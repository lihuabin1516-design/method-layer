Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:AdapterModule = Join-Path $script:RepositoryRoot 'scripts/adapter/MethodLayer.Adapter.psm1'
$script:PlanSchema = Join-Path $script:RepositoryRoot 'controller/schemas/transport-plan.internal.schema.json'

Import-Module $script:AdapterModule -Force

function Copy-ControllerJsonValue {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json
}

function Get-ControllerEnvelopeSchemaPath {
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'prepare-launch-envelope',
            'bind-launch-envelope',
            'finish-run-envelope',
            'handoff-envelope',
            'recovery-envelope'
        )]
        [string]$EnvelopeType
    )

    $name = switch ($EnvelopeType) {
        'prepare-launch-envelope' { 'prepareLaunchEnvelope' }
        'bind-launch-envelope' { 'bindLaunchEnvelope' }
        'finish-run-envelope' { 'finishRunEnvelope' }
        'handoff-envelope' { 'handoffEnvelope' }
        'recovery-envelope' { 'recoveryEnvelope' }
    }
    return Get-InternalSchemaPath -Name $name
}

function Read-ControllerEnvelope {
    param([Parameter(Mandatory)][string]$Path)

    $value = Read-JsonFile -Path $Path
    if (-not ($value.PSObject.Properties.Name -contains 'envelopeType')) {
        throw 'Controller envelope is missing envelopeType.'
    }
    $schemaPath = Get-ControllerEnvelopeSchemaPath -EnvelopeType ([string]$value.envelopeType)
    Assert-JsonSchema -Path $Path -SchemaPath $schemaPath | Out-Null
    return $value
}

function Read-ControllerTaskBinding {
    param([Parameter(Mandatory)][string]$Path)

    Assert-JsonSchema -Path $Path -SchemaPath (Get-InternalSchemaPath -Name taskBinding) | Out-Null
    return Read-JsonFile -Path $Path
}

function Merge-ControllerMetadata {
    param(
        [Parameter(Mandatory)]$TaskBinding,
        [Parameter(Mandatory)]$TaskBindingPatch
    )

    $metadata = if (
        $TaskBinding.PSObject.Properties.Name -contains 'metadata' -and
        $null -ne $TaskBinding.metadata
    ) {
        Copy-ControllerJsonValue -Value $TaskBinding.metadata
    }
    else {
        [pscustomobject]@{}
    }
    $methodLayer = Copy-ControllerJsonValue -Value $TaskBindingPatch.metadata.methodLayer
    if ($metadata.PSObject.Properties.Name -contains 'methodLayer') {
        $metadata.methodLayer = $methodLayer
    }
    else {
        $metadata | Add-Member -NotePropertyName methodLayer -NotePropertyValue $methodLayer
    }
    return $metadata
}

function New-ControllerStep {
    param(
        [Parameter(Mandatory)][int]$Sequence,
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$Purpose,
        [string[]]$ReadbackAssertions,
        $Preconditions
    )

    $step = [pscustomobject][ordered]@{
        sequence = $Sequence
        tool = $Tool
        request = $Request
        purpose = $Purpose
    }
    if ($ReadbackAssertions -and @($ReadbackAssertions).Count -gt 0) {
        $step | Add-Member -NotePropertyName readbackAssertions -NotePropertyValue @($ReadbackAssertions)
    }
    if ($null -ne $Preconditions) {
        $step | Add-Member -NotePropertyName preconditions -NotePropertyValue $Preconditions
    }
    return $step
}

function Get-ControllerValueSha256 {
    param($Value)

    $json = if ($null -eq $Value) { 'null' } else { ConvertTo-StableJson -Value $Value -Compress }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash)
}

function New-ControllerPlanObject {
    param(
        [Parameter(Mandatory)][string]$SourceEnvelopeType,
        [Parameter(Mandatory)][string]$Decision,
        [Parameter(Mandatory)][string]$LeaderNotification,
        [Parameter(Mandatory)]$Correlation,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Steps,
        [Parameter(Mandatory)][string[]]$Notes
    )

    return [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        artifactType = 'controller-transport-plan'
        planId = 'controller-plan-' + [guid]::NewGuid().ToString('N')
        createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        sourceEnvelopeType = $SourceEnvelopeType
        mode = 'dry-run'
        decision = $Decision
        leaderNotification = $LeaderNotification
        correlation = $Correlation
        steps = @($Steps)
        notes = @($Notes)
    }
}

function Get-ControllerCorrelation {
    param([Parameter(Mandatory)]$Envelope)

    $correlation = [ordered]@{}
    $method = $null
    if (
        $Envelope.PSObject.Properties.Name -contains 'taskBindingPatch' -and
        $null -ne $Envelope.taskBindingPatch -and
        $Envelope.taskBindingPatch.PSObject.Properties.Name -contains 'metadata' -and
        $Envelope.taskBindingPatch.metadata.PSObject.Properties.Name -contains 'methodLayer'
    ) {
        $method = $Envelope.taskBindingPatch.metadata.methodLayer
    }
    if ($null -ne $method) {
        if ($method.PSObject.Properties.Name -contains 'taskId') {
            $correlation.taskId = [string]$method.taskId
        }
        if ($method.PSObject.Properties.Name -contains 'runId') {
            $correlation.runId = [string]$method.runId
        }
    }
    foreach ($property in @('taskId', 'runId', 'launchTaskId', 'sessionId')) {
        if (
            -not $correlation.Contains($property) -and
            $Envelope.PSObject.Properties.Name -contains $property
        ) {
            $correlation[$property] = [string]$Envelope.$property
        }
    }
    if (
        -not $correlation.Contains('sessionId') -and
        $Envelope.PSObject.Properties.Name -contains 'taskBindingLookup'
    ) {
        $correlation.sessionId = [string]$Envelope.taskBindingLookup.sessionId
    }
    return [pscustomobject]$correlation
}

function New-FindBindingStep {
    param(
        [Parameter(Mandatory)][int]$Sequence,
        [Parameter(Mandatory)][string]$SessionId,
        [string]$Purpose = 'Resolve the current TaskBinding by PTY session identity.',
        [string[]]$Assertions
    )

    return New-ControllerStep `
        -Sequence $Sequence `
        -Tool 'find_task_binding_by_session' `
        -Request ([pscustomobject][ordered]@{ sessionId = $SessionId }) `
        -Purpose $Purpose `
        -ReadbackAssertions $Assertions
}

function Test-ControllerBindingIdentity {
    param(
        [Parameter(Mandatory)]$TaskBinding,
        [Parameter(Mandatory)][string]$SessionId,
        [string]$ExpectedBindingId
    )

    if (
        -not ($TaskBinding.PSObject.Properties.Name -contains 'sessionId') -or
        [string]$TaskBinding.sessionId -ne $SessionId
    ) {
        return 'TaskBinding sessionId differs from the envelope lookup identity.'
    }
    if ($ExpectedBindingId -and [string]$TaskBinding.id -ne $ExpectedBindingId) {
        return 'TaskBinding id differs from the envelope worker identity.'
    }
    return $null
}

function New-BindingMutationPlan {
    param(
        [Parameter(Mandatory)]$Envelope,
        $TaskBinding,
        [switch]$IncludeLeaderReport
    )

    $sourceType = [string]$Envelope.envelopeType
    $correlation = Get-ControllerCorrelation -Envelope $Envelope
    $sessionId = if ($Envelope.PSObject.Properties.Name -contains 'taskBindingLookup') {
        [string]$Envelope.taskBindingLookup.sessionId
    }
    else {
        [string]$Envelope.sessionId
    }
    $findStep = New-FindBindingStep -Sequence 1 -SessionId $sessionId

    if ($null -eq $TaskBinding) {
        return New-ControllerPlanObject `
            -SourceEnvelopeType $sourceType `
            -Decision 'requires-binding' `
            -LeaderNotification 'not-applicable' `
            -Correlation $correlation `
            -Steps @($findStep) `
            -Notes @('Supply a fresh TaskBinding snapshot returned for the envelope sessionId before planning mutation.')
    }

    $expectedBindingId = if ($IncludeLeaderReport) {
        [string]$Envelope.leaderReport.workerId
    }
    else {
        $null
    }
    $identityConflict = Test-ControllerBindingIdentity `
        -TaskBinding $TaskBinding `
        -SessionId $sessionId `
        -ExpectedBindingId $expectedBindingId
    if ($identityConflict) {
        return New-ControllerPlanObject `
            -SourceEnvelopeType $sourceType `
            -Decision 'manual-review' `
            -LeaderNotification 'not-applicable' `
            -Correlation $correlation `
            -Steps @($findStep) `
            -Notes @($identityConflict)
    }

    $mergedMetadata = Merge-ControllerMetadata `
        -TaskBinding $TaskBinding `
        -TaskBindingPatch $Envelope.taskBindingPatch
    $updateRequest = [ordered]@{
        id = [string]$TaskBinding.id
    }
    foreach ($property in @('status', 'progress', 'completionSummary', 'exitCode')) {
        if ($Envelope.taskBindingPatch.PSObject.Properties.Name -contains $property) {
            $updateRequest[$property] = $Envelope.taskBindingPatch.$property
        }
    }
    $updateRequest.metadata = $mergedMetadata
    $updateRequestBytes = [System.Text.Encoding]::UTF8.GetByteCount(
        (([pscustomobject]$updateRequest) | ConvertTo-Json -Depth 100 -Compress)
    )
    if ($updateRequestBytes -gt 64KB) {
        return New-ControllerPlanObject `
            -SourceEnvelopeType $sourceType `
            -Decision 'manual-review' `
            -LeaderNotification 'not-applicable' `
            -Correlation $correlation `
            -Steps @($findStep) `
            -Notes @("Merged update_task_binding request is $updateRequestBytes bytes; controller limit is 65536 bytes.")
    }

    $steps = [System.Collections.Generic.List[object]]::new()
    $steps.Add($findStep)
    $steps.Add((New-ControllerStep `
        -Sequence 2 `
        -Tool 'update_task_binding' `
        -Request ([pscustomobject]$updateRequest) `
        -Purpose 'Apply the envelope patch while preserving existing TaskBinding metadata siblings.' `
        -Preconditions ([pscustomobject][ordered]@{
            bindingId = [string]$TaskBinding.id
            sessionId = [string]$TaskBinding.sessionId
            role = [string]$TaskBinding.role
            status = [string]$TaskBinding.status
            projectPath = [string]$TaskBinding.projectPath
            metadataSha256 = Get-ControllerValueSha256 -Value $TaskBinding.metadata
        })))

    $method = $Envelope.taskBindingPatch.metadata.methodLayer
    $assertions = @(
        "binding.id == $([string]$TaskBinding.id)",
        "metadata.methodLayer.taskId == $([string]$method.taskId)",
        "metadata.methodLayer.runId == $([string]$method.runId)"
    )
    if ($method.PSObject.Properties.Name -contains 'latestEvidencePath') {
        $assertions += "metadata.methodLayer.latestEvidencePath == $([string]$method.latestEvidencePath)"
    }
    if ($method.PSObject.Properties.Name -contains 'latestHandoffPath') {
        $assertions += "metadata.methodLayer.latestHandoffPath == $([string]$method.latestHandoffPath)"
    }
    foreach ($property in @('status', 'progress', 'completionSummary', 'exitCode')) {
        if ($Envelope.taskBindingPatch.PSObject.Properties.Name -contains $property) {
            $assertions += "$property == $([string]$Envelope.taskBindingPatch.$property)"
        }
    }
    $steps.Add((New-FindBindingStep `
        -Sequence 3 `
        -SessionId $sessionId `
        -Purpose 'Read back the persisted TaskBinding before advancing transport.' `
        -Assertions $assertions))

    $leaderNotification = 'not-applicable'
    $notes = @('This plan is descriptive only and executes no MCP call.')
    if ($IncludeLeaderReport) {
        $terminalStatuses = @('completed', 'failed')
        $autoNotify = [string]$TaskBinding.role -eq 'worker' -and
            [string]$TaskBinding.status -notin $terminalStatuses -and
            [string]$Envelope.taskBindingPatch.status -in $terminalStatuses
        if ($autoNotify) {
            $leaderNotification = 'auto-notify-expected'
            $notes += 'The planned update crosses into a terminal worker status, so CC-Panes automatic leader notification is expected.'
        }
        else {
            $leaderNotification = 'manual-report-planned'
            $steps.Add((New-ControllerStep `
                -Sequence 4 `
                -Tool 'report_to_leader' `
                -Request ([pscustomobject][ordered]@{
                    workerId = [string]$Envelope.leaderReport.workerId
                    status = [string]$Envelope.leaderReport.status
                    summary = [string]$Envelope.leaderReport.summary
                }) `
                -Purpose 'Manually report only when the preceding update is not expected to auto-notify.'))
        }
    }

    return New-ControllerPlanObject `
        -SourceEnvelopeType $sourceType `
        -Decision 'ready' `
        -LeaderNotification $leaderNotification `
        -Correlation $correlation `
        -Steps $steps.ToArray() `
        -Notes $notes
}

function New-ControllerTransportPlan {
    param(
        [Parameter(Mandatory)]$Envelope,
        $TaskBinding,
        $PrepareEnvelope
    )

    switch ([string]$Envelope.envelopeType) {
        'prepare-launch-envelope' {
            return New-ControllerPlanObject `
                -SourceEnvelopeType 'prepare-launch-envelope' `
                -Decision 'ready' `
                -LeaderNotification 'not-applicable' `
                -Correlation (Get-ControllerCorrelation -Envelope $Envelope) `
                -Steps @(
                    New-ControllerStep `
                        -Sequence 1 `
                        -Tool 'launch_task' `
                        -Request (Copy-ControllerJsonValue -Value $Envelope.launchTaskRequest) `
                        -Purpose 'Launch the validated method task through CC-Panes MCP.'
                ) `
                -Notes @('The controller must persist the launch response before invoking bind-launch.')
        }
        'bind-launch-envelope' {
            return New-BindingMutationPlan -Envelope $Envelope -TaskBinding $TaskBinding
        }
        'finish-run-envelope' {
            return New-BindingMutationPlan `
                -Envelope $Envelope `
                -TaskBinding $TaskBinding `
                -IncludeLeaderReport
        }
        'handoff-envelope' {
            return New-BindingMutationPlan -Envelope $Envelope -TaskBinding $TaskBinding
        }
        'recovery-envelope' {
            $correlation = Get-ControllerCorrelation -Envelope $Envelope
            switch ([string]$Envelope.recoveryAction) {
                'retry-launch' {
                    if ($null -eq $PrepareEnvelope) {
                        return New-ControllerPlanObject `
                            -SourceEnvelopeType 'recovery-envelope' `
                            -Decision 'requires-journal' `
                            -LeaderNotification 'not-applicable' `
                            -Correlation $correlation `
                            -Steps @() `
                            -Notes @('The launch attempt omits prompt body; supply the original prepare-launch envelope from the controller journal.')
                    }
                    if (
                        [string]$PrepareEnvelope.envelopeType -ne 'prepare-launch-envelope' -or
                        [string]$PrepareEnvelope.runId -ne [string]$Envelope.runId
                    ) {
                        return New-ControllerPlanObject `
                            -SourceEnvelopeType 'recovery-envelope' `
                            -Decision 'manual-review' `
                            -LeaderNotification 'not-applicable' `
                            -Correlation $correlation `
                            -Steps @() `
                            -Notes @('The supplied prepare envelope does not match the recovery runId.')
                    }
                    return New-ControllerPlanObject `
                        -SourceEnvelopeType 'recovery-envelope' `
                        -Decision 'ready' `
                        -LeaderNotification 'not-applicable' `
                        -Correlation $correlation `
                        -Steps @(
                            New-ControllerStep `
                                -Sequence 1 `
                                -Tool 'launch_task' `
                                -Request (Copy-ControllerJsonValue -Value $PrepareEnvelope.launchTaskRequest) `
                                -Purpose 'Retry launch from the original validated controller journal envelope.'
                        ) `
                        -Notes @('Do not reconstruct or expand the prompt from environment state.')
                }
                'bind-response' {
                    $nested = New-BindingMutationPlan -Envelope $Envelope.bindResult -TaskBinding $TaskBinding
                    $nested.sourceEnvelopeType = 'recovery-envelope'
                    $nested.notes = @($nested.notes) + @('The call sequence derives from recovery.bindResult; no second launch is planned.')
                    return $nested
                }
                'repair-metadata' {
                    return New-BindingMutationPlan -Envelope $Envelope -TaskBinding $TaskBinding
                }
                'already-bound' {
                    if (
                        -not ($Envelope.PSObject.Properties.Name -contains 'sessionId') -or
                        [string]::IsNullOrWhiteSpace([string]$Envelope.sessionId)
                    ) {
                        return New-ControllerPlanObject `
                            -SourceEnvelopeType 'recovery-envelope' `
                            -Decision 'manual-review' `
                            -LeaderNotification 'not-applicable' `
                            -Correlation $correlation `
                            -Steps @() `
                            -Notes @('already-bound recovery lacks sessionId for readback.')
                    }
                    return New-ControllerPlanObject `
                        -SourceEnvelopeType 'recovery-envelope' `
                        -Decision 'already-satisfied' `
                        -LeaderNotification 'not-applicable' `
                        -Correlation $correlation `
                        -Steps @(
                            New-FindBindingStep `
                                -Sequence 1 `
                                -SessionId ([string]$Envelope.sessionId) `
                                -Purpose 'Read back the already-bound TaskBinding without mutation.' `
                                -Assertions @(
                                    "metadata.methodLayer.taskId == $([string]$Envelope.taskId)",
                                    "metadata.methodLayer.runId == $([string]$Envelope.runId)"
                                )
                        ) `
                        -Notes @('No update or launch is planned for already-bound recovery.')
                }
                'manual-review' {
                    return New-ControllerPlanObject `
                        -SourceEnvelopeType 'recovery-envelope' `
                        -Decision 'manual-review' `
                        -LeaderNotification 'not-applicable' `
                        -Correlation $correlation `
                        -Steps @() `
                        -Notes @('The recovery envelope explicitly requires manual review.')
                }
            }
        }
    }
}

function Assert-ControllerTransportPlan {
    param([Parameter(Mandatory)]$Plan)
    return Assert-JsonValueSchema -Value $Plan -SchemaPath $script:PlanSchema
}

Export-ModuleMember -Function @(
    'Read-ControllerEnvelope',
    'Read-ControllerTaskBinding',
    'Merge-ControllerMetadata',
    'New-ControllerTransportPlan',
    'Assert-ControllerTransportPlan'
)
