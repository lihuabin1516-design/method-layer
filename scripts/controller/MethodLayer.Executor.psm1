Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:AdapterModule = Join-Path $script:RepositoryRoot 'scripts/adapter/MethodLayer.Adapter.psm1'
$script:ControllerModule = Join-Path $script:RepositoryRoot 'scripts/controller/MethodLayer.Controller.psm1'
$script:PlanSchema = Join-Path $script:RepositoryRoot 'controller/schemas/transport-plan.internal.schema.json'
$script:JournalSchema = Join-Path $script:RepositoryRoot 'controller/schemas/execution-journal-entry.internal.schema.json'
$script:ResultSchema = Join-Path $script:RepositoryRoot 'controller/schemas/execution-result.internal.schema.json'
$script:LaunchResponseSchema = Join-Path $script:RepositoryRoot 'adapter/schemas/launch-response.internal.schema.json'
$script:TaskBindingSchema = Join-Path $script:RepositoryRoot 'adapter/schemas/task-binding.internal.schema.json'

Import-Module $script:AdapterModule -Force
Import-Module $script:ControllerModule -Force

function Get-ControllerTextSha256 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
    return [Convert]::ToHexString($hash)
}

function Get-ControllerJsonText {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    return ConvertTo-StableJson -Value $Value -Compress
}

function Get-ControllerJsonSha256 {
    param($Value)
    return Get-ControllerTextSha256 -Text (Get-ControllerJsonText -Value $Value)
}

function Get-ControllerExecutionId {
    param([Parameter(Mandatory)][string]$PlanSha256)
    return 'execution-' + $PlanSha256.Substring(0, 32).ToLowerInvariant()
}

function New-ControllerResult {
    param(
        $Plan,
        [string]$PlanSha256,
        [string]$ExecutionId,
        [string]$Mode,
        [string]$Status,
        [string]$StartedAt,
        $JournalPath,
        [object[]]$Steps,
        [string[]]$Notes
    )
    $result = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        artifactType = 'controller-execution-result'
        executionId = $ExecutionId
        planId = [string]$Plan.planId
        planSha256 = $PlanSha256
        mode = $Mode
        status = $Status
        startedAt = $StartedAt
        completedAt = [DateTimeOffset]::UtcNow.ToString('o')
        journalPath = $JournalPath
        leaderNotification = [string]$Plan.leaderNotification
        steps = @($Steps)
        notes = @($Notes)
    }
    Assert-JsonValueSchema -Value $result -SchemaPath $script:ResultSchema | Out-Null
    return $result
}

function Get-ControllerExecutionPaths {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$ArtifactRoot,
        [Parameter(Mandatory)][string]$PlanId
    )
    $root = Resolve-ArtifactRoot -ProjectPath $ProjectPath -ArtifactRoot $ArtifactRoot -Create
    $relative = Join-Path 'controller/executions' $PlanId
    $directory = Resolve-ContainedPath -Root $root -ChildPath $relative
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Assert-NoReparsePointEscape -Root $root -Candidate $directory
    $responses = Join-Path $directory 'responses'
    New-Item -ItemType Directory -Path $responses -Force | Out-Null
    return [pscustomobject]@{
        Root = $root
        Directory = $directory
        Responses = $responses
        Journal = Join-Path $directory 'journal.jsonl'
        Lock = Join-Path $directory 'execution.lock'
    }
}

function Enter-ControllerExecutionLock {
    param([Parameter(Mandatory)][string]$Path)
    try {
        return [System.IO.File]::Open($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    }
    catch {
        throw "Controller execution lock conflict at '$Path'."
    }
}

function Read-ControllerJournal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$PlanId,
        [Parameter(Mandatory)][string]$PlanSha256,
        [Parameter(Mandatory)][string]$ExecutionId
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $entries = [System.Collections.Generic.List[object]]::new()
    $expected = 1
    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { throw 'Controller journal contains an empty or partial line.' }
        try { $entry = $line | ConvertFrom-Json } catch { throw "Controller journal contains invalid JSON: $($_.Exception.Message)" }
        Assert-JsonValueSchema -Value $entry -SchemaPath $script:JournalSchema | Out-Null
        if ([string]$entry.planId -ne $PlanId -or [string]$entry.planSha256 -ne $PlanSha256 -or [string]$entry.executionId -ne $ExecutionId) {
            throw 'Controller journal plan identity or hash mismatch.'
        }
        if ([int]$entry.entrySequence -ne $expected) { throw 'Controller journal sequence is not contiguous.' }
        $entries.Add($entry)
        $expected++
    }
    return $entries.ToArray()
}

function Add-ControllerJournalEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Entries,
        [Parameter(Mandatory)]$Base,
        [Parameter(Mandatory)][string]$EventType,
        [hashtable]$Fields
    )
    $entry = [ordered]@{
        schemaVersion = '0.1-internal'
        artifactType = 'controller-execution-journal-entry'
        executionId = $Base.executionId
        planId = $Base.planId
        planSha256 = $Base.planSha256
        entrySequence = $Entries.Count + 1
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        eventType = $EventType
        mode = 'live'
    }
    if ($Fields) { foreach ($key in $Fields.Keys) { $entry[$key] = $Fields[$key] } }
    $value = [pscustomobject]$entry
    Assert-JsonValueSchema -Value $value -SchemaPath $script:JournalSchema | Out-Null
    $line = (ConvertTo-StableJson -Value $value -Compress) + [Environment]::NewLine
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    $Entries.Add($value)
    return $value
}

function Write-ControllerResponse {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][int]$StepSequence,
        [Parameter(Mandatory)][int]$Attempt,
        $Response
    )
    $name = 'step-{0:D3}-attempt-{1:D3}.json' -f $StepSequence, $Attempt
    $path = Join-Path $Directory $name
    $json = Get-ControllerJsonText -Value $Response
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally { $stream.Dispose() }
    }
    catch {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileSha256 -Path $path) -ne (Get-ControllerTextSha256 -Text $json)) {
            throw "Controller response artifact conflict at '$path'."
        }
    }
    return [pscustomobject]@{ Path = $path; Sha256 = Get-FileSha256 -Path $path }
}

function Get-ControllerPropertyValue {
    param($Value, [string]$Path)
    if ($Path.StartsWith('binding.')) { $Path = $Path.Substring(8) }
    $current = $Value
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $current -or -not ($current.PSObject.Properties.Name -contains $part)) {
            throw "Readback assertion path '$Path' does not exist."
        }
        $current = $current.$part
    }
    return $current
}

function Assert-ControllerReadback {
    param($Response, [string[]]$Assertions)
    foreach ($assertion in @($Assertions)) {
        $parts = $assertion -split '\s+==\s+', 2
        if ($parts.Count -ne 2) { throw "Unsupported readback assertion '$assertion'." }
        $actual = Get-ControllerPropertyValue -Value $Response -Path $parts[0]
        if ([string]$actual -ne [string]$parts[1]) {
            throw "Readback assertion failed: $assertion; actual='$actual'."
        }
    }
}

function Assert-ControllerToolResponse {
    param(
        [Parameter(Mandatory)][string]$Tool,
        $Response
    )
    switch ($Tool) {
        'launch_task' {
            Assert-JsonValueSchema -Value $Response -SchemaPath $script:LaunchResponseSchema | Out-Null
        }
        'find_task_binding_by_session' {
            if ($null -ne $Response) {
                Assert-JsonValueSchema -Value $Response -SchemaPath $script:TaskBindingSchema | Out-Null
            }
        }
        'update_task_binding' {
            Assert-JsonValueSchema -Value $Response -SchemaPath $script:TaskBindingSchema | Out-Null
        }
        'report_to_leader' {
            if ($null -eq $Response -or -not ($Response.PSObject.Properties.Name -contains 'sent')) {
                throw 'report_to_leader response contract is missing sent.'
            }
            $queued = $Response.PSObject.Properties.Name -contains 'queued' -and [bool]$Response.queued
            if (-not [bool]$Response.sent -and -not $queued) {
                $reason = if ($Response.PSObject.Properties.Name -contains 'skipReason') { [string]$Response.skipReason } else { 'unspecified' }
                throw "report_to_leader was neither sent nor queued: $reason"
            }
        }
    }
}

function Assert-ControllerUpdatePreconditions {
    param($Binding, $Preconditions, [string]$TransportTargetProjectPath)
    if ($null -eq $Binding) { throw 'TaskBinding precondition failed: lookup returned null.' }
    foreach ($property in @('id', 'sessionId', 'role', 'status')) {
        $expectedName = if ($property -eq 'id') { 'bindingId' } else { $property }
        if ([string]$Binding.$property -ne [string]$Preconditions.$expectedName) {
            throw "TaskBinding precondition failed for $property."
        }
    }
    $metadata = if ($Binding.PSObject.Properties.Name -contains 'metadata') { $Binding.metadata } else { $null }
    if ((Get-ControllerJsonSha256 -Value $metadata) -ne [string]$Preconditions.metadataSha256) {
        throw 'TaskBinding metadata precondition hash differs from the planned snapshot.'
    }
    if ([string]$Binding.projectPath -ne [string]$Preconditions.projectPath) {
        throw 'TaskBinding projectPath differs from the planned snapshot.'
    }
    $expectedProject = [System.IO.Path]::GetFullPath($TransportTargetProjectPath).TrimEnd('\', '/')
    $bindingProject = [System.IO.Path]::GetFullPath([string]$Binding.projectPath).TrimEnd('\', '/')
    if (-not $bindingProject.Equals($expectedProject, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'TaskBinding projectPath differs from the authorized transport target project.'
    }
}

function Assert-ControllerPlanSemantics {
    param($Plan, [string]$TransportTargetProjectPath)
    $steps = @($Plan.steps)
    for ($index = 0; $index -lt $steps.Count; $index++) {
        if ([int]$steps[$index].sequence -ne ($index + 1)) {
            throw 'Controller plan step sequence must be unique, ordered, and contiguous.'
        }
    }
    $tools = @($steps.tool) -join '|'
    $allowed = switch ([string]$Plan.sourceEnvelopeType) {
        'prepare-launch-envelope' { @('launch_task') }
        'bind-launch-envelope' { @('find_task_binding_by_session', 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session') }
        'handoff-envelope' { @('find_task_binding_by_session', 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session') }
        'finish-run-envelope' { @('find_task_binding_by_session', 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session', 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session|report_to_leader') }
        'recovery-envelope' { @('', 'launch_task', 'find_task_binding_by_session', 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session') }
    }
    if ($tools -notin $allowed) {
        throw "Controller plan tool sequence '$tools' is invalid for sourceEnvelopeType '$($Plan.sourceEnvelopeType)'."
    }
    foreach ($step in $steps | Where-Object tool -eq 'launch_task') {
        $planned = [System.IO.Path]::GetFullPath([string]$step.request.projectPath).TrimEnd('\', '/')
        $authorized = [System.IO.Path]::GetFullPath($TransportTargetProjectPath).TrimEnd('\', '/')
        if (-not $planned.Equals($authorized, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'launch_task projectPath differs from the authorized transport target project.'
        }
    }
}

function Get-ControllerNormalizedError {
    param([Parameter(Mandatory)]$Exception)
    $category = if ($Exception.Data['ControllerTransportCategory']) { [string]$Exception.Data['ControllerTransportCategory'] } else { 'contract' }
    $delivery = if ($Exception.Data['ControllerDelivery']) { [string]$Exception.Data['ControllerDelivery'] } else { 'unknown' }
    $message = [string]$Exception.Message
    if ($env:CC_PANES_API_TOKEN) { $message = $message.Replace($env:CC_PANES_API_TOKEN, '***') }
    return [pscustomobject]@{ category = $category; delivery = $delivery; message = $message }
}

function New-StepResult {
    param($Step)
    return [pscustomobject][ordered]@{
        sequence = [int]$Step.sequence
        tool = [string]$Step.tool
        status = 'pending'
        attempts = 0
    }
}

function Invoke-ControllerExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$ProjectPath,
        [ValidateSet('dry-run', 'live')][string]$Mode = 'dry-run',
        [string]$ArtifactRoot,
        [scriptblock]$TransportInvoker,
        [string]$TransportTargetProjectPath,
        [switch]$AllowNonAtomicTaskBindingUpdate,
        [ValidateRange(1, 3)][int]$MaxAttempts = 3
    )

    Assert-JsonSchema -Path $PlanPath -SchemaPath $script:PlanSchema | Out-Null
    $plan = Read-JsonFile -Path $PlanPath
    $planSha = Get-FileSha256 -Path $PlanPath
    $executionId = Get-ControllerExecutionId -PlanSha256 $planSha
    $startedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $stepResults = @($plan.steps | ForEach-Object { New-StepResult -Step $_ })
    if ([string]::IsNullOrWhiteSpace($TransportTargetProjectPath)) { $TransportTargetProjectPath = $ProjectPath }
    Assert-ControllerPlanSemantics -Plan $plan -TransportTargetProjectPath $TransportTargetProjectPath

    if ($Mode -eq 'dry-run') {
        return New-ControllerResult -Plan $plan -PlanSha256 $planSha -ExecutionId $executionId -Mode dry-run -Status dry-run -StartedAt $startedAt -JournalPath $null -Steps $stepResults -Notes @('Plan validated; transport was not invoked.')
    }
    if ($null -eq $TransportInvoker) { throw 'Live mode requires a transport invoker.' }

    $paths = Get-ControllerExecutionPaths -ProjectPath $ProjectPath -ArtifactRoot $ArtifactRoot -PlanId ([string]$plan.planId)
    $journalRelative = ConvertTo-ProjectRelativePath -ProjectPath $ProjectPath -Path $paths.Journal
    $lock = Enter-ControllerExecutionLock -Path $paths.Lock
    try {
        $existing = @(Read-ControllerJournal -Path $paths.Journal -PlanId $plan.planId -PlanSha256 $planSha -ExecutionId $executionId)
        $entries = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $existing) { $entries.Add($entry) }
        $base = @{ executionId = $executionId; planId = [string]$plan.planId; planSha256 = $planSha }
        [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType execution-started -Fields @{ note = 'Controller execution invocation started.' })

        if ([string]$plan.decision -in @('manual-review', 'requires-binding', 'requires-journal')) {
            $note = "Plan decision '$($plan.decision)' does not permit live execution."
            [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType execution-finished -Fields @{ executionStatus = 'manual-review'; note = $note })
            return New-ControllerResult -Plan $plan -PlanSha256 $planSha -ExecutionId $executionId -Mode live -Status manual-review -StartedAt $startedAt -JournalPath $journalRelative -Steps $stepResults -Notes @($note)
        }

        $lastBinding = $null
        $finalStatus = 'completed'
        $notes = [System.Collections.Generic.List[string]]::new()
        foreach ($step in @($plan.steps)) {
            $result = @($stepResults | Where-Object sequence -eq ([int]$step.sequence))[0]
            $requestSha = Get-ControllerJsonSha256 -Value $step.request
            $priorSuccess = @($entries | Where-Object {
                $_.eventType -eq 'step-succeeded' -and
                [int]$_.stepSequence -eq [int]$step.sequence -and
                [string]$_.requestSha256 -eq $requestSha
            }) | Select-Object -Last 1
            $repeatableRead = [string]$step.tool -eq 'find_task_binding_by_session'
            if ($priorSuccess -and -not $repeatableRead) {
                try {
                    if (-not ($priorSuccess.PSObject.Properties.Name -contains 'responsePath') -or -not ($priorSuccess.PSObject.Properties.Name -contains 'responseSha256')) {
                        throw 'Successful mutation journal entry is missing response evidence.'
                    }
                    $priorResponse = Resolve-ContainedPath -Root $ProjectPath -ChildPath ([string]$priorSuccess.responsePath)
                    if (-not (Test-Path -LiteralPath $priorResponse -PathType Leaf)) { throw 'Successful mutation response artifact is missing.' }
                    if ((Get-FileSha256 -Path $priorResponse) -ne [string]$priorSuccess.responseSha256) { throw 'Successful mutation response artifact hash differs.' }
                }
                catch {
                    $finalStatus = 'manual-review'
                    $result.status = 'failed'
                    $result | Add-Member error $_.Exception.Message
                    $notes.Add($_.Exception.Message)
                    break
                }
                $result.status = 'skipped'
                $result.attempts = 0
                if ($priorSuccess.PSObject.Properties.Name -contains 'responsePath') {
                    $result | Add-Member responsePath $priorSuccess.responsePath
                    $result | Add-Member responseSha256 $priorSuccess.responseSha256
                }
                [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType step-skipped -Fields @{
                    stepSequence = [int]$step.sequence; tool = [string]$step.tool; requestSha256 = $requestSha
                    stepStatus = 'skipped'; note = 'Matching successful mutation already exists in the journal.'
                })
                continue
            }

            if ([string]$step.tool -in @('launch_task', 'report_to_leader')) {
                $priorAttempt = @($entries | Where-Object {
                    $_.eventType -eq 'step-attempted' -and [int]$_.stepSequence -eq [int]$step.sequence -and [string]$_.requestSha256 -eq $requestSha
                }).Count -gt 0
                if ($priorAttempt) {
                    $message = "Non-idempotent step '$($step.tool)' has a prior attempt without durable success; replay requires manual review."
                    $finalStatus = 'manual-review'
                    $result.status = 'failed'
                    $result | Add-Member error $message
                    $notes.Add($message)
                    break
                }
            }

            if ([string]$step.tool -eq 'update_task_binding') {
                if (-not $AllowNonAtomicTaskBindingUpdate) {
                    $message = 'update_task_binding metadata replacement has no server-side CAS; explicit AllowNonAtomicTaskBindingUpdate is required.'
                    $finalStatus = 'manual-review'
                    $result.status = 'failed'
                    $result | Add-Member error $message
                    $notes.Add($message)
                    break
                }
                try { Assert-ControllerUpdatePreconditions -Binding $lastBinding -Preconditions $step.preconditions -TransportTargetProjectPath $TransportTargetProjectPath }
                catch {
                    $finalStatus = 'manual-review'
                    $result.status = 'failed'
                    $result | Add-Member error $_.Exception.Message
                    $notes.Add($_.Exception.Message)
                    [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType step-failed -Fields @{
                        stepSequence = [int]$step.sequence
                        tool = [string]$step.tool
                        requestSha256 = $requestSha
                        stepStatus = 'failed'
                        error = [pscustomobject]@{
                            category = 'contract'
                            delivery = 'rejected'
                            message = $_.Exception.Message
                        }
                    })
                    break
                }
            }

            $maxForStep = if ([string]$step.tool -in @('launch_task', 'report_to_leader')) { 1 } else { $MaxAttempts }
            $priorAttempts = @(
                $entries |
                    Where-Object {
                        $_.eventType -eq 'step-attempted' -and
                        [int]$_.stepSequence -eq [int]$step.sequence -and
                        [string]$_.requestSha256 -eq $requestSha
                    } |
                    ForEach-Object { [int]$_.attempt }
            )
            $attemptBase = if ($priorAttempts.Count -gt 0) {
                ($priorAttempts | Measure-Object -Maximum).Maximum
            }
            else { 0 }
            for ($attempt = 1; $attempt -le $maxForStep; $attempt++) {
                $journalAttempt = $attemptBase + $attempt
                $result.attempts = $attempt
                [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType step-attempted -Fields @{
                    stepSequence = [int]$step.sequence; tool = [string]$step.tool; attempt = $journalAttempt; requestSha256 = $requestSha
                })
                try {
                    $response = & $TransportInvoker ([string]$step.tool) $step.request
                    Assert-ControllerToolResponse -Tool ([string]$step.tool) -Response $response
                    if ($step.PSObject.Properties.Name -contains 'readbackAssertions') {
                        Assert-ControllerReadback -Response $response -Assertions @($step.readbackAssertions)
                    }
                    $saved = Write-ControllerResponse -Directory $paths.Responses -StepSequence $step.sequence -Attempt $journalAttempt -Response $response
                    $relative = ConvertTo-ProjectRelativePath -ProjectPath $ProjectPath -Path $saved.Path
                    [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType step-succeeded -Fields @{
                        stepSequence = [int]$step.sequence; tool = [string]$step.tool; attempt = $journalAttempt
                        requestSha256 = $requestSha; responsePath = $relative; responseSha256 = $saved.Sha256; stepStatus = 'succeeded'
                    })
                    $result.status = 'succeeded'
                    $result | Add-Member responsePath $relative
                    $result | Add-Member responseSha256 $saved.Sha256
                    if ([string]$step.tool -eq 'find_task_binding_by_session') { $lastBinding = $response }
                    break
                }
                catch {
                    $error = Get-ControllerNormalizedError -Exception $_.Exception
                    [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType step-failed -Fields @{
                        stepSequence = [int]$step.sequence; tool = [string]$step.tool; attempt = $journalAttempt
                        requestSha256 = $requestSha; stepStatus = 'failed'; error = $error
                    })
                    $retry = $error.category -eq 'transient' -and $attempt -lt $maxForStep
                    if ($retry) { continue }
                    $result.status = 'failed'
                    $result | Add-Member error $error.message
                    $ambiguousNonIdempotent = [string]$step.tool -in @('launch_task', 'report_to_leader') -and $error.delivery -in @('ambiguous', 'unknown')
                    $contractConflict = $error.category -eq 'contract' -and $error.message -match 'assertion|precondition|journal|response artifact|schema'
                    $finalStatus = if ($ambiguousNonIdempotent -or $contractConflict) { 'manual-review' } else { 'failed' }
                    $notes.Add($error.message)
                    break
                }
            }
            if ($result.status -eq 'failed') { break }
        }
        if ($notes.Count -eq 0) { $notes.Add('All executable plan steps reached a durable successful or replay-safe state.') }
        [void](Add-ControllerJournalEntry -Path $paths.Journal -Entries $entries -Base $base -EventType execution-finished -Fields @{ executionStatus = $finalStatus; note = $notes[0] })
        return New-ControllerResult -Plan $plan -PlanSha256 $planSha -ExecutionId $executionId -Mode live -Status $finalStatus -StartedAt $startedAt -JournalPath $journalRelative -Steps $stepResults -Notes $notes.ToArray()
    }
    finally { $lock.Dispose() }
}

Export-ModuleMember -Function @(
    'Invoke-ControllerExecution',
    'Get-ControllerJsonSha256'
)
