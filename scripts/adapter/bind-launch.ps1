[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AttemptPath,
    [Parameter(Mandatory)]
    [string]$LaunchResponsePath,
    [string]$ExpectedAttemptSha256
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MethodLayer.Adapter.psm1') -Force

Assert-JsonSchema -Path $AttemptPath -SchemaPath (Get-InternalSchemaPath -Name launchAttempt) | Out-Null
$attempt = Read-JsonFile -Path $AttemptPath
$attemptHash = Get-FileSha256 -Path $AttemptPath
if ($ExpectedAttemptSha256 -and $attemptHash -ne $ExpectedAttemptSha256.ToUpperInvariant()) {
    throw "Attempt SHA-256 conflict: expected $ExpectedAttemptSha256, found $attemptHash."
}
if ($attempt.state -notin @('prepared', 'launched', 'bound')) {
    throw "Attempt state '$($attempt.state)' is not bindable."
}

Assert-JsonSchema -Path $LaunchResponsePath -SchemaPath (Get-InternalSchemaPath -Name launchResponse) | Out-Null
$response = Read-JsonFile -Path $LaunchResponsePath
$projectPath = [System.IO.Path]::GetFullPath([string]$attempt.launch.projectPath)
$artifactRoot = Resolve-ArtifactRoot -ProjectPath $projectPath -ArtifactRoot ([string]$attempt.artifactRoot)
$taskPath = Resolve-ContainedPath -Root $projectPath -ChildPath ([string]$attempt.taskPath)
$task = Read-MethodArtifact -Path $taskPath -ArtifactType task
if ((Get-FileSha256 -Path $taskPath) -ne [string]$attempt.taskSha256) {
    throw 'Task SHA-256 differs from the prepared launch attempt.'
}

$taskKey = ConvertTo-ArtifactKey -Identity ([string]$attempt.taskId)
$taskDirectory = Resolve-ContainedPath -Root $artifactRoot -ChildPath "tasks/$taskKey"
$lock = Enter-TaskLock -TaskDirectory $taskDirectory -Operation 'bind-launch'

try {
    if ($attempt.PSObject.Properties.Name -contains 'response') {
        if (
            [string]$attempt.response.taskId -ne [string]$response.taskId -or
            [string]$attempt.response.sessionId -ne [string]$response.sessionId -or
            [string]$attempt.response.runtimeKind -ne [string]$response.runtimeKind -or
            [string]$attempt.response.profileId -ne [string]$response.profileId
        ) {
            throw 'Launch response conflict: TaskBinding, session, or runtime identity differs.'
        }
    }
    if ($attempt.state -eq 'bound' -and $attempt.PSObject.Properties.Name -contains 'runPath') {
        if (-not ($attempt.PSObject.Properties.Name -contains 'response')) {
            throw 'Bound launch attempt is missing its persisted response.'
        }
        $existingRunPath = Resolve-ContainedPath -Root $projectPath -ChildPath ([string]$attempt.runPath)
        if (Test-Path -LiteralPath $existingRunPath -PathType Leaf) {
            $existingPatch = New-MethodLayerMetadataPatch `
                -TaskId ([string]$attempt.taskId) `
                -RunId ([string]$attempt.runId) `
                -ArtifactRoot ([string]$attempt.artifactRoot) `
                -TaskPath ([string]$attempt.taskPath) `
                -RunPath ([string]$attempt.runPath)
            $existingResult = [pscustomobject][ordered]@{
                schemaVersion = '0.1-internal'
                envelopeType = 'bind-launch-envelope'
                operation = 'bind-launch'
                runPath = [string]$attempt.runPath
                runSha256 = Get-FileSha256 -Path $existingRunPath
                launchTaskId = [string]$response.taskId
                sessionId = [string]$response.sessionId
                taskBindingLookup = [pscustomobject][ordered]@{
                    operation = 'find_task_binding_by_session'
                    sessionId = [string]$response.sessionId
                    fallback = 'create_or_register_task_binding'
                }
                taskBindingPatch = $existingPatch
                idempotent = $true
            }
            ConvertTo-ValidatedEnvelopeJson -Value $existingResult -Name bindLaunchEnvelope
            return
        }
    }

    $launchedAttempt = $attempt | Select-Object *
    $launchedAttempt.state = 'launched'
    $launchedAttempt.updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    if ($launchedAttempt.PSObject.Properties.Name -contains 'response') {
        $launchedAttempt.response = $response
    }
    else {
        $launchedAttempt | Add-Member -NotePropertyName response -NotePropertyValue $response
    }
    $launchedWrite = Write-CompareAndSwapJson `
        -Path $AttemptPath `
        -Value $launchedAttempt `
        -SchemaPath (Get-InternalSchemaPath -Name launchAttempt) `
        -ExpectedSha256 $attemptHash

    $git = Get-GitBaseline -ProjectPath $projectPath
    $runner = [ordered]@{
        cliTool = [string]$attempt.launch.cliTool
        profile = if (
            $response.PSObject.Properties.Name -contains 'profileId' -and
            -not [string]::IsNullOrWhiteSpace([string]$response.profileId)
        ) {
            [string]$response.profileId
        }
        else {
            [string]$attempt.launch.profile
        }
        runtimeKind = [string]$response.runtimeKind
        session = [pscustomobject][ordered]@{
            sessionId = [string]$response.sessionId
        }
    }
    if ($attempt.launch.PSObject.Properties.Name -contains 'resumeId') {
        $runner.session | Add-Member -NotePropertyName resumeSessionId -NotePropertyValue ([string]$attempt.launch.resumeId)
    }

    $workspace = [ordered]@{
        projectPath = $projectPath
        worktreePath = $git.repoRoot
        branch = $git.branch
    }
    if ($attempt.launch.PSObject.Properties.Name -contains 'workspaceName') {
        $workspace.workspaceName = [string]$attempt.launch.workspaceName
    }

    $run = [pscustomobject][ordered]@{
        protocolVersion = '0.1'
        artifactType = 'run'
        runId = [string]$attempt.runId
        taskRef = [pscustomobject][ordered]@{
            taskId = [string]$attempt.taskId
            protocolVersion = '0.1'
            artifactPath = [string]$attempt.taskPath
        }
        startedAt = [string]$attempt.createdAt
        status = if ([string]$response.status -match 'fail|error') { 'failed' } else { 'running' }
        runner = [pscustomobject]$runner
        workspace = [pscustomobject]$workspace
        contract = New-RunContract -Task $task -CapturedAt ([string]$attempt.createdAt)
    }

    $runKey = ConvertTo-ArtifactKey -Identity ([string]$attempt.runId)
    $runPath = Resolve-ContainedPath -Root $artifactRoot -ChildPath "tasks/$taskKey/runs/$runKey/run.json"
    $runWrite = Write-CreateOnceJson -Path $runPath -Value $run -SchemaPath (Get-MethodSchemaPath -ArtifactType run)
    $runReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $runPath

    $boundAttempt = $launchedAttempt | Select-Object *
    $boundAttempt.state = 'bound'
    $boundAttempt.updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    foreach ($property in @{
        runPath = $runReference
        runSha256 = $runWrite.Sha256
    }.GetEnumerator()) {
        if ($boundAttempt.PSObject.Properties.Name -contains $property.Key) {
            $boundAttempt.($property.Key) = $property.Value
        }
        else {
            $boundAttempt | Add-Member -NotePropertyName $property.Key -NotePropertyValue $property.Value
        }
    }
    $boundWrite = Write-CompareAndSwapJson `
        -Path $AttemptPath `
        -Value $boundAttempt `
        -SchemaPath (Get-InternalSchemaPath -Name launchAttempt) `
        -ExpectedSha256 $launchedWrite.Sha256

    $patch = New-MethodLayerMetadataPatch `
        -TaskId ([string]$attempt.taskId) `
        -RunId ([string]$attempt.runId) `
        -ArtifactRoot ([string]$attempt.artifactRoot) `
        -TaskPath ([string]$attempt.taskPath) `
        -RunPath $runReference

    $result = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        envelopeType = 'bind-launch-envelope'
        operation = 'bind-launch'
        attemptPath = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $AttemptPath
        attemptSha256 = $boundWrite.Sha256
        runPath = $runReference
        runSha256 = $runWrite.Sha256
        launchTaskId = [string]$response.taskId
        sessionId = [string]$response.sessionId
        taskBindingLookup = [pscustomobject][ordered]@{
            operation = 'find_task_binding_by_session'
            sessionId = [string]$response.sessionId
            fallback = 'create_or_register_task_binding'
        }
        taskBindingPatch = $patch
        idempotent = [bool]$runWrite.Idempotent
    }
    ConvertTo-ValidatedEnvelopeJson -Value $result -Name bindLaunchEnvelope
}
finally {
    Exit-TaskLock -Lock $lock
}
