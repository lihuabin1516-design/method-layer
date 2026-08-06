[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TaskPath,
    [Parameter(Mandatory)]
    [string]$RunPath,
    [Parameter(Mandatory)]
    [string]$EvidencePath,
    [Parameter(Mandatory)]
    [string]$ContextPath,
    [string]$ExpectedTaskSha256,
    [string]$ExpectedRunSha256,
    [string]$ExpectedEvidenceSha256
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MethodLayer.Adapter.psm1') -Force

$task = Read-MethodArtifact -Path $TaskPath -ArtifactType task
$run = Read-MethodArtifact -Path $RunPath -ArtifactType run
$evidence = Read-MethodArtifact -Path $EvidencePath -ArtifactType evidence
Assert-JsonSchema -Path $ContextPath -SchemaPath (Get-InternalSchemaPath -Name handoffContext) | Out-Null
$context = Read-JsonFile -Path $ContextPath

foreach ($check in @(
    @{ Name = 'task'; Path = $TaskPath; Expected = $ExpectedTaskSha256 },
    @{ Name = 'run'; Path = $RunPath; Expected = $ExpectedRunSha256 },
    @{ Name = 'evidence'; Path = $EvidencePath; Expected = $ExpectedEvidenceSha256 }
)) {
    if ($check.Expected) {
        $actualHash = Get-FileSha256 -Path $check.Path
        if ($actualHash -ne $check.Expected.ToUpperInvariant()) {
            throw "$($check.Name) SHA-256 conflict: expected $($check.Expected), found $actualHash."
        }
    }
}

if ([string]$task.taskId -ne [string]$run.taskRef.taskId) {
    throw 'Task and run identities differ.'
}
if ([string]$evidence.taskId -ne [string]$task.taskId -or [string]$evidence.runId -ne [string]$run.runId) {
    throw 'Evidence lineage differs from task/run.'
}

$projectPath = [System.IO.Path]::GetFullPath([string]$run.workspace.projectPath)
$artifactRootReference = Get-ArtifactRootReferenceFromTaskPath -TaskArtifactPath ([string]$run.taskRef.artifactPath)
$artifactRoot = Resolve-ArtifactRoot -ProjectPath $projectPath -ArtifactRoot $artifactRootReference
$git = Get-GitBaseline -ProjectPath $projectPath
$taskKey = ConvertTo-ArtifactKey -Identity ([string]$task.taskId)
$taskDirectory = Resolve-ContainedPath -Root $artifactRoot -ChildPath "tasks/$taskKey"
$lock = Enter-TaskLock -TaskDirectory $taskDirectory -Operation 'new-handoff'

try {
    $taskReference = if ($run.taskRef.PSObject.Properties.Name -contains 'artifactPath') {
        [string]$run.taskRef.artifactPath
    }
    else {
        ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $TaskPath
    }
    $runReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $RunPath
    $evidenceReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $EvidencePath
    $baseline = [ordered]@{
        projectPath = $projectPath
        repoRoot = [string]$git.repoRoot
        git = [pscustomobject][ordered]@{
            branch = [string]$git.branch
            head = [string]$git.head
            status = [pscustomobject][ordered]@{
                state = [string]$git.state
                summary = [string]$git.summary
            }
        }
        relevantRules = @($task.baseline.relevantRules)
    }
    if ($task.baseline.PSObject.Properties.Name -contains 'workspaceName') {
        $baseline.workspaceName = [string]$task.baseline.workspaceName
    }

    $conditional = if ($task.authorization.PSObject.Properties.Name -contains 'conditionalActions') {
        @($task.authorization.conditionalActions)
    }
    else {
        @('No conditional actions are declared in the task artifact.')
    }

    $handoff = [pscustomobject][ordered]@{
        protocolVersion = '0.1'
        artifactType = 'handoff'
        handoffId = New-AdapterId -Prefix 'handoff'
        createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        role = [string]$context.role
        taskId = [string]$task.taskId
        currentResult = [string]$evidence.summary
        requiredReading = @($context.requiredReading)
        baseline = [pscustomobject]$baseline
        facts = @($context.facts)
        evidence = @(
            "Evidence $($evidence.evidenceId): $($evidence.summary)",
            "$evidenceReference sha256=$(Get-FileSha256 -Path $EvidencePath)"
        )
        objective = [string]$task.objective
        authorization = @($task.authorization.allowedPaths)
        forbidden = @($task.authorization.forbiddenActions)
        conditionalAuthorization = @($conditional)
        executionOrder = @($context.executionOrder)
        agentDispatchBoundary = $context.agentDispatchBoundary
        requiredChecks = @($context.requiredChecks)
        acceptanceAssertions = @($task.acceptance)
        audit = @($context.audit)
        fuse = @($context.fuse)
        stopConditions = @($task.stopConditions)
        artifacts = @($taskReference, $runReference, $evidenceReference)
        delivery = $context.delivery
        nextOrder = @($context.nextOrder)
    }

    $handoffKey = ConvertTo-ArtifactKey -Identity ([string]$handoff.handoffId)
    $handoffPath = Resolve-ContainedPath -Root $artifactRoot -ChildPath "tasks/$taskKey/handoffs/$handoffKey.json"
    $handoffWrite = Write-CreateOnceJson `
        -Path $handoffPath `
        -Value $handoff `
        -SchemaPath (Get-MethodSchemaPath -ArtifactType handoff)
    $handoffReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $handoffPath

    $patch = New-MethodLayerMetadataPatch `
        -TaskId ([string]$task.taskId) `
        -RunId ([string]$run.runId) `
        -ArtifactRoot $artifactRootReference `
        -TaskPath $taskReference `
        -RunPath $runReference `
        -LatestEvidencePath $evidenceReference `
        -LatestHandoffPath $handoffReference

    $result = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        envelopeType = 'handoff-envelope'
        operation = 'new-handoff'
        handoffPath = $handoffReference
        handoffSha256 = $handoffWrite.Sha256
        taskBindingLookup = [pscustomobject][ordered]@{
            operation = 'find_task_binding_by_session'
            sessionId = [string]$run.runner.session.sessionId
            fallback = 'manual-review'
        }
        taskBindingPatch = $patch
    }
    ConvertTo-ValidatedEnvelopeJson -Value $result -Name handoffEnvelope
}
finally {
    Exit-TaskLock -Lock $lock
}
