[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TaskPath,
    [Parameter(Mandatory)]
    [string]$CliTool,
    [Parameter(Mandatory)]
    [string]$Profile,
    [Parameter(Mandatory)]
    [string]$RuntimeKind,
    [string]$ProviderId,
    [string]$ProviderSelection,
    [string]$WorkspaceName,
    [string]$PaneId,
    [string]$LayoutId,
    [string]$LayoutName,
    [string]$Placement,
    [string]$ResumeId,
    [string]$ArtifactRoot,
    [string[]]$ConditionalApproval
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MethodLayer.Adapter.psm1') -Force

$task = Read-MethodArtifact -Path $TaskPath -ArtifactType task
$projectPath = [System.IO.Path]::GetFullPath([string]$task.baseline.projectPath)
$sourceTaskPath = [System.IO.Path]::GetFullPath($TaskPath)
if (-not (Test-PathContained -Root $projectPath -Candidate $sourceTaskPath)) {
    throw "Task source path must remain within projectPath: $sourceTaskPath"
}
Assert-NoReparsePointEscape -Root $projectPath -Candidate $sourceTaskPath

$actualBaseline = Get-GitBaseline -ProjectPath $projectPath
Compare-TaskBaseline -Task $task -Actual $actualBaseline | Out-Null
Assert-LaunchAuthorization -Task $task -ProjectPath $projectPath -ConditionalApproval $ConditionalApproval | Out-Null

$resolvedArtifactRoot = Resolve-ArtifactRoot -ProjectPath $projectPath -ArtifactRoot $ArtifactRoot -Create
$taskKey = ConvertTo-ArtifactKey -Identity ([string]$task.taskId)
$taskDirectory = Resolve-ContainedPath -Root $resolvedArtifactRoot -ChildPath "tasks/$taskKey"
$lock = Enter-TaskLock -TaskDirectory $taskDirectory -Operation 'prepare-launch'

try {
    $canonicalTaskPath = Resolve-ContainedPath -Root $resolvedArtifactRoot -ChildPath "tasks/$taskKey/task.json"
    $taskWrite = Write-CreateOnceJson -Path $canonicalTaskPath -Value $task -SchemaPath (Get-MethodSchemaPath -ArtifactType task)
    $taskReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $canonicalTaskPath
    $artifactRootReference = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $resolvedArtifactRoot

    $runId = New-AdapterId -Prefix 'run'
    $attemptId = New-AdapterId -Prefix 'attempt'
    $now = [DateTimeOffset]::UtcNow.ToString('o')

    $launch = [ordered]@{
        projectPath = $projectPath
        cliTool = $CliTool
        profile = $Profile
        runtimeKind = $RuntimeKind
    }
    foreach ($optional in @{
        providerId = $ProviderId
        providerSelection = $ProviderSelection
        workspaceName = $WorkspaceName
        paneId = $PaneId
        layoutId = $LayoutId
        layoutName = $LayoutName
        placement = $Placement
        resumeId = $ResumeId
    }.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace([string]$optional.Value)) {
            $launch[$optional.Key] = [string]$optional.Value
        }
    }
    if ($null -ne $ConditionalApproval -and @($ConditionalApproval).Count -gt 0) {
        $launch.conditionalApproval = @($ConditionalApproval)
    }

    $attempt = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        artifactType = 'launch-attempt'
        attemptId = $attemptId
        taskId = [string]$task.taskId
        runId = $runId
        taskPath = $taskReference
        taskSha256 = $taskWrite.Sha256
        artifactRoot = $artifactRootReference
        state = 'prepared'
        launch = [pscustomobject]$launch
        createdAt = $now
        updatedAt = $now
    }

    $attemptKey = ConvertTo-ArtifactKey -Identity $attemptId
    $attemptPath = Resolve-ContainedPath -Root $resolvedArtifactRoot -ChildPath "adapter/launch-attempts/$attemptKey.json"
    $attemptWrite = Write-CreateOnceJson -Path $attemptPath -Value $attempt -SchemaPath (Get-InternalSchemaPath -Name launchAttempt)

    $launchRequest = [ordered]@{
        projectPath = $projectPath
        cliTool = $CliTool
        profileId = $Profile
        runtimeKind = $RuntimeKind
    }
    if ($ResumeId) {
        $launchRequest.resumeId = $ResumeId
    }
    else {
        $launchRequest.prompt = New-LaunchPrompt `
            -Task $task `
            -TaskPath $taskReference `
            -RunId $runId `
            -ConditionalApproval $ConditionalApproval
    }
    foreach ($mapping in @{
        providerId = $ProviderId
        providerSelection = $ProviderSelection
        workspaceName = $WorkspaceName
        paneId = $PaneId
        layoutId = $LayoutId
        layoutName = $LayoutName
        placement = $Placement
    }.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace([string]$mapping.Value)) {
            $launchRequest[$mapping.Key] = [string]$mapping.Value
        }
    }

    $result = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        envelopeType = 'prepare-launch-envelope'
        operation = 'prepare-launch'
        attemptPath = ConvertTo-ProjectRelativePath -ProjectPath $projectPath -Path $attemptPath
        attemptSha256 = $attemptWrite.Sha256
        taskPath = $taskReference
        taskSha256 = $taskWrite.Sha256
        runId = $runId
        launchTaskRequest = [pscustomobject]$launchRequest
    }
    ConvertTo-ValidatedEnvelopeJson -Value $result -Name prepareLaunchEnvelope
}
finally {
    Exit-TaskLock -Lock $lock
}
