[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AttemptPath,
    [string]$LaunchResponsePath,
    [string]$TaskBindingPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MethodLayer.Adapter.psm1') -Force

Assert-JsonSchema -Path $AttemptPath -SchemaPath (Get-InternalSchemaPath -Name launchAttempt) | Out-Null
$attempt = Read-JsonFile -Path $AttemptPath
$projectPath = [System.IO.Path]::GetFullPath([string]$attempt.launch.projectPath)

if ($LaunchResponsePath) {
    $bindOutput = & (Join-Path $PSScriptRoot 'bind-launch.ps1') -AttemptPath $AttemptPath -LaunchResponsePath $LaunchResponsePath
    $bindResult = (($bindOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json
    $result = [pscustomobject][ordered]@{
        schemaVersion = '0.1-internal'
        envelopeType = 'recovery-envelope'
        operation = 'recover-launch'
        attemptState = [string]$attempt.state
        recoveryAction = 'bind-response'
        bindResult = $bindResult
    }
    ConvertTo-ValidatedEnvelopeJson -Value $result -Name recoveryEnvelope
    return
}

if (
    [string]$attempt.state -eq 'launched' -and
    $attempt.PSObject.Properties.Name -contains 'response'
) {
    $attemptDirectory = Split-Path -Parent $AttemptPath
    $responseTemp = Join-Path $attemptDirectory ('.recovery-response-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        Write-CreateOnceJson `
            -Path $responseTemp `
            -Value $attempt.response `
            -SchemaPath (Get-InternalSchemaPath -Name launchResponse) | Out-Null
        $bindOutput = & (Join-Path $PSScriptRoot 'bind-launch.ps1') -AttemptPath $AttemptPath -LaunchResponsePath $responseTemp
        $bindResult = (($bindOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) | ConvertFrom-Json
        $result = [pscustomobject][ordered]@{
            schemaVersion = '0.1-internal'
            envelopeType = 'recovery-envelope'
            operation = 'recover-launch'
            attemptState = 'launched'
            recoveryAction = 'bind-response'
            bindResult = $bindResult
        }
        ConvertTo-ValidatedEnvelopeJson -Value $result -Name recoveryEnvelope
        return
    }
    finally {
        if (Test-Path -LiteralPath $responseTemp) {
            Remove-Item -LiteralPath $responseTemp -Force
        }
    }
}

$runExists = $false
$runPath = $null
if ($attempt.PSObject.Properties.Name -contains 'runPath') {
    $runPath = [string]$attempt.runPath
    $absoluteRunPath = Resolve-ContainedPath -Root $projectPath -ChildPath $runPath
    $runExists = Test-Path -LiteralPath $absoluteRunPath -PathType Leaf
}

$action = switch ([string]$attempt.state) {
    'prepared' { 'retry-launch' }
    'launched' { 'manual-review' }
    'bound' {
        if (-not $runExists) {
            'manual-review'
        }
        elseif ($TaskBindingPath) {
            Assert-JsonSchema -Path $TaskBindingPath -SchemaPath (Get-InternalSchemaPath -Name taskBinding) | Out-Null
            $binding = Read-JsonFile -Path $TaskBindingPath
            $bindingProjectPath = [System.IO.Path]::GetFullPath([string]$binding.projectPath)
            $expectedSessionId = if ($attempt.PSObject.Properties.Name -contains 'response') {
                [string]$attempt.response.sessionId
            }
            else {
                $null
            }
            $method = $null
            if (
                $binding.PSObject.Properties.Name -contains 'metadata' -and
                $null -ne $binding.metadata -and
                $binding.metadata.PSObject.Properties.Name -contains 'methodLayer'
            ) {
                $method = $binding.metadata.methodLayer
            }
            if (
                $bindingProjectPath -ne $projectPath -or
                [string]::IsNullOrWhiteSpace($expectedSessionId) -or
                -not ($binding.PSObject.Properties.Name -contains 'sessionId') -or
                [string]$binding.sessionId -ne $expectedSessionId
            ) {
                'manual-review'
            }
            elseif ($null -eq $method) {
                'repair-metadata'
            }
            else {
                $requiredMethodProperties = @(
                    'protocolVersion',
                    'taskId',
                    'runId',
                    'artifactRoot',
                    'taskPath',
                    'runPath'
                )
                $methodProperties = @($method.PSObject.Properties.Name)
                $missingMethodProperty = @(
                    $requiredMethodProperties | Where-Object { $_ -notin $methodProperties }
                ).Count -gt 0
                $methodConflict = $missingMethodProperty -or
                    [string]$method.protocolVersion -ne '0.1' -or
                    [string]$method.taskId -ne [string]$attempt.taskId -or
                    [string]$method.runId -ne [string]$attempt.runId -or
                    ([string]$method.artifactRoot -replace '\\', '/') -ne ([string]$attempt.artifactRoot -replace '\\', '/') -or
                    ([string]$method.taskPath -replace '\\', '/') -ne ([string]$attempt.taskPath -replace '\\', '/') -or
                    ([string]$method.runPath -replace '\\', '/') -ne ($runPath -replace '\\', '/')
                if ($methodConflict) {
                    'manual-review'
                }
                else {
                    'already-bound'
                }
            }
        }
        else {
            'already-bound'
        }
    }
    default { 'manual-review' }
}

$result = [pscustomobject][ordered]@{
    schemaVersion = '0.1-internal'
    envelopeType = 'recovery-envelope'
    operation = 'recover-launch'
    attemptState = [string]$attempt.state
    recoveryAction = $action
    taskId = [string]$attempt.taskId
    runId = [string]$attempt.runId
}
if ($runPath) {
    $result | Add-Member -NotePropertyName runPath -NotePropertyValue $runPath
}
if ($attempt.PSObject.Properties.Name -contains 'response') {
    $result | Add-Member -NotePropertyName launchTaskId -NotePropertyValue ([string]$attempt.response.taskId)
    $result | Add-Member -NotePropertyName sessionId -NotePropertyValue ([string]$attempt.response.sessionId)
}
if ($action -eq 'repair-metadata' -and $runPath) {
    $patch = New-MethodLayerMetadataPatch `
        -TaskId ([string]$attempt.taskId) `
        -RunId ([string]$attempt.runId) `
        -ArtifactRoot ([string]$attempt.artifactRoot) `
        -TaskPath ([string]$attempt.taskPath) `
        -RunPath $runPath
    $result | Add-Member -NotePropertyName taskBindingPatch -NotePropertyValue $patch
}
ConvertTo-ValidatedEnvelopeJson -Value $result -Name recoveryEnvelope
