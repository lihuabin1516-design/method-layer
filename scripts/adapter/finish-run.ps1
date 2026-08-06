[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RunPath,
    [Parameter(Mandatory)]
    [string]$TaskBindingPath,
    [string]$EvidencePath,
    [switch]$SummaryOnly,
    [string]$ExpectedRunSha256
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MethodLayer.Adapter.psm1') -Force

if (($EvidencePath -and $SummaryOnly) -or (-not $EvidencePath -and -not $SummaryOnly)) {
    throw 'Specify exactly one of -EvidencePath or -SummaryOnly.'
}

$run = Read-MethodArtifact -Path $RunPath -ArtifactType run
$runHash = Get-FileSha256 -Path $RunPath
if ($ExpectedRunSha256 -and $runHash -ne $ExpectedRunSha256.ToUpperInvariant()) {
    throw "Run SHA-256 conflict: expected $ExpectedRunSha256, found $runHash."
}

Assert-JsonSchema -Path $TaskBindingPath -SchemaPath (Get-InternalSchemaPath -Name taskBinding) | Out-Null
$binding = Read-JsonFile -Path $TaskBindingPath
$projectPath = [System.IO.Path]::GetFullPath([string]$run.workspace.projectPath)
if ([System.IO.Path]::GetFullPath([string]$binding.projectPath) -ne $projectPath) {
    throw 'TaskBinding projectPath does not match run.workspace.projectPath.'
}
if (
    $binding.PSObject.Properties.Name -contains 'sessionId' -and
    [string]$binding.sessionId -ne [string]$run.runner.session.sessionId
) {
    throw 'TaskBinding sessionId does not match run.runner.session.sessionId.'
}
if (-not ($run.taskRef.PSObject.Properties.Name -contains 'artifactPath')) {
    throw 'run.taskRef.artifactPath is required by the reference adapter.'
}

$artifactRootReference = Get-ArtifactRootReferenceFromTaskPath -TaskArtifactPath ([string]$run.taskRef.artifactPath)
$artifactRoot = Resolve-ArtifactRoot -ProjectPath $projectPath -ArtifactRoot $artifactRootReference
$taskPath = Resolve-ContainedPath -Root $projectPath -ChildPath ([string]$run.taskRef.artifactPath)
$task = Read-MethodArtifact -Path $taskPath -ArtifactType task
$git = Get-GitBaseline -ProjectPath $projectPath
$runReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $RunPath

if ($EvidencePath) {
    $evidence = Read-MethodArtifact -Path $EvidencePath -ArtifactType evidence
}
else {
    $evidence = New-SummaryOnlyEvidence -Run $run -TaskBinding $binding -GitBaseline $git -RunReferencePath $runReference
}

if ([string]$evidence.taskId -ne [string]$run.taskRef.taskId -or [string]$evidence.runId -ne [string]$run.runId) {
    throw 'Evidence identity does not match the run.'
}

$taskKey = ConvertTo-ArtifactKey -Identity ([string]$run.taskRef.taskId)
$runKey = ConvertTo-ArtifactKey -Identity ([string]$run.runId)
$evidenceKey = ConvertTo-ArtifactKey -Identity ([string]$evidence.evidenceId)
$evidenceTarget = Resolve-ContainedPath `
    -Root $artifactRoot `
    -ChildPath "tasks/$taskKey/runs/$runKey/evidence/$evidenceKey.json"

$taskDirectory = Resolve-ContainedPath -Root $artifactRoot -ChildPath "tasks/$taskKey"
$lock = Enter-TaskLock -TaskDirectory $taskDirectory -Operation 'finish-run'

try {
    # Evidence is intentionally published before run/TaskBinding/leader state envelopes.
    $evidenceWrite = Write-CreateOnceJson `
        -Path $evidenceTarget `
        -Value $evidence `
        -SchemaPath (Get-MethodSchemaPath -ArtifactType evidence)
    $evidenceReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $evidenceTarget

    $completed = Test-EvidenceFinishGate -Task $task -Run $run -Evidence $evidence -GitBaseline $git
    $methodOutcome = if ($completed) {
        'completed'
    }
    elseif ([string]$evidence.outcome -eq 'failed' -or [string]$binding.status -eq 'failed') {
        'failed'
    }
    elseif ([string]$evidence.outcome -eq 'blocked') {
        'blocked'
    }
    else {
        'partial'
    }

    $updatedRun = $run | Select-Object *
    if ($updatedRun.PSObject.Properties.Name -contains 'endedAt') {
        $updatedRun.endedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
    else {
        $updatedRun | Add-Member -NotePropertyName endedAt -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o'))
    }
    $updatedRun.status = switch ($methodOutcome) {
        'completed' { 'completed' }
        'failed' { 'failed' }
        default { 'blocked' }
    }
    $runWrite = Write-CompareAndSwapJson `
        -Path $RunPath `
        -Value $updatedRun `
        -SchemaPath (Get-MethodSchemaPath -ArtifactType run) `
        -ExpectedSha256 $runHash

    $metadataPatch = New-MethodLayerMetadataPatch `
        -TaskId ([string]$run.taskRef.taskId) `
        -RunId ([string]$run.runId) `
        -ArtifactRoot $artifactRootReference `
        -TaskPath ([string]$run.taskRef.artifactPath) `
        -RunPath $runReference `
        -LatestEvidencePath $evidenceReference

    $patch = [ordered]@{
        status = [string]$binding.status
        progress = [int]$binding.progress
        completionSummary = [string]$evidence.summary
        metadata = $metadataPatch.metadata
    }
    if ($binding.PSObject.Properties.Name -contains 'exitCode') {
        $patch.exitCode = [int]$binding.exitCode
    }

    $leaderReport = [pscustomobject][ordered]@{
        workerId = [string]$binding.id
        status = [string]$binding.status
        summary = [string]$evidence.summary
        dispatchPolicy = 'if-not-auto-notified'
    }

    $result = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        envelopeType = 'finish-run-envelope'
        operation = 'finish-run'
        methodOutcome = $methodOutcome
        evidencePath = $evidenceReference
        evidenceSha256 = $evidenceWrite.Sha256
        runPath = $runReference
        runSha256 = $runWrite.Sha256
        taskBindingLookup = [pscustomobject][ordered]@{
            operation = 'find_task_binding_by_session'
            sessionId = [string]$run.runner.session.sessionId
            fallback = 'manual-review'
        }
        taskBindingPatch = [pscustomobject]$patch
        leaderReport = $leaderReport
    }
    ConvertTo-ValidatedEnvelopeJson -Value $result -Name finishRunEnvelope
}
finally {
    Exit-TaskLock -Lock $lock
}
