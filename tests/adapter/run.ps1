[CmdletBinding()]
param(
    [ValidateSet('all', 'path', 'validation', 'storage', 'prepare-launch', 'bind-launch', 'recovery', 'finish', 'handoff', 'envelope')]
    [string]$Group = 'all'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $root 'scripts/adapter/MethodLayer.Adapter.psm1'
$prepareScript = Join-Path $root 'scripts/adapter/prepare-launch.ps1'
$bindScript = Join-Path $root 'scripts/adapter/bind-launch.ps1'
$recoverScript = Join-Path $root 'scripts/adapter/recover-launch.ps1'
$finishScript = Join-Path $root 'scripts/adapter/finish-run.ps1'
$handoffScript = Join-Path $root 'scripts/adapter/new-handoff.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures'

function Test-Group {
    param([string]$Name)
    return $Group -eq 'all' -or $Group -eq $Name
}

function Import-AdapterModule {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

function New-PreparedFixture {
    $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
    try {
        $prepared = Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
            TaskPath = $project.TaskPath
            CliTool = 'codex'
            Profile = 'codex-gpt55-heavy'
            RuntimeKind = 'local'
        }
        return [pscustomobject]@{
            Project = $project
            Prepared = $prepared
            AttemptPath = Join-Path $project.ProjectPath ($prepared.attemptPath -replace '/', '\')
        }
    }
    catch {
        Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        throw
    }
}

function New-BoundFixture {
    $fixture = New-PreparedFixture
    try {
        $responsePath = Join-Path $fixture.Project.ProjectPath 'input/launch-response.json'
        Copy-Item -LiteralPath (Join-Path $fixtures 'launch-response.json') -Destination $responsePath
        $bound = Invoke-AdapterScript -ScriptPath $bindScript -Parameters @{
            AttemptPath = $fixture.AttemptPath
            LaunchResponsePath = $responsePath
        }
        return [pscustomobject]@{
            Project = $fixture.Project
            Prepared = $fixture.Prepared
            AttemptPath = $fixture.AttemptPath
            Bound = $bound
            RunPath = Join-Path $fixture.Project.ProjectPath ($bound.runPath -replace '/', '\')
            ResponsePath = $responsePath
        }
    }
    catch {
        Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        throw
    }
}

function Write-EvidenceFixture {
    param(
        [Parameter(Mandatory)]$BoundFixture,
        [Parameter(Mandatory)][string]$FixtureName
    )

    $evidence = Get-Content -Raw -LiteralPath (Join-Path $fixtures $FixtureName) | ConvertFrom-Json
    $run = Get-Content -Raw -LiteralPath $BoundFixture.RunPath | ConvertFrom-Json
    $evidence.runId = $run.runId
    $evidence.taskId = $run.taskRef.taskId
    $evidence.touchedFiles[0].path = $BoundFixture.Bound.runPath
    $path = Join-Path $BoundFixture.Project.ProjectPath "input/$FixtureName"
    $evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    return $path
}

if (Test-Group 'path') {
    Invoke-TestCase 'identity encoding is Windows-safe and reversible' {
        Import-AdapterModule
        $encoded = ConvertTo-ArtifactKey -Identity 'team:task-001'
        Assert-Equal 'team%3Atask-001' $encoded
        Assert-Equal 'team:task-001' (ConvertFrom-ArtifactKey -Key $encoded)
    }

    Invoke-TestCase 'contained-path guard rejects traversal and rooted injection' {
        Import-AdapterModule
        $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        try {
            New-Item -ItemType Directory -Path $project.ArtifactRoot -Force | Out-Null
            Assert-Throws { Resolve-ContainedPath -Root $project.ArtifactRoot -ChildPath '..\outside.json' } 'outside|escape|contained'
            Assert-Throws { Resolve-ContainedPath -Root $project.ArtifactRoot -ChildPath 'C:\outside.json' } 'rooted|absolute|contained'
            Assert-Throws { Resolve-ContainedPath -Root $project.ArtifactRoot -ChildPath '\\server\share\outside.json' } 'rooted|absolute|contained'
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        }
    }

    Invoke-TestCase 'contained-path guard rejects junction escape' {
        Import-AdapterModule
        $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        $outside = Join-Path (Get-TestTempRoot) ([guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $project.ArtifactRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            $junction = Join-Path $project.ArtifactRoot 'junction'
            New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
            Assert-Throws { Resolve-ContainedPath -Root $project.ArtifactRoot -ChildPath 'junction\escape.json' } 'reparse|junction|escape'
        }
        finally {
            if (Test-Path -LiteralPath $outside) {
                Remove-Item -LiteralPath $outside -Recurse -Force
            }
            Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        }
    }
}

if (Test-Group 'validation') {
    Invoke-TestCase 'unknown protocol version fails before attempt creation' {
        $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        try {
            $task = Get-Content -Raw -LiteralPath $project.TaskPath | ConvertFrom-Json
            $task.protocolVersion = '9.9'
            $task | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $project.TaskPath -Encoding utf8NoBOM
            Assert-Throws {
                Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
                    TaskPath = $project.TaskPath
                    CliTool = 'codex'
                    Profile = 'codex-gpt55-heavy'
                    RuntimeKind = 'local'
                }
            } 'protocol|schema|0.1'
            Assert-False (Test-Path -LiteralPath $project.ArtifactRoot) 'Artifact root appeared after invalid task.'
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        }
    }

    Invoke-TestCase 'conditional task action requires and records approval evidence' {
        $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        try {
            $task = Get-Content -Raw -LiteralPath $project.TaskPath | ConvertFrom-Json
            $task.authorization | Add-Member -NotePropertyName conditionalActions -NotePropertyValue @('Use the local adapter after explicit confirmation.')
            $task | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $project.TaskPath -Encoding utf8NoBOM
            Assert-Throws {
                Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
                    TaskPath = $project.TaskPath
                    CliTool = 'codex'
                    Profile = 'codex-gpt55-heavy'
                    RuntimeKind = 'local'
                }
            } 'approval'
            $prepared = Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
                TaskPath = $project.TaskPath
                CliTool = 'codex'
                Profile = 'codex-gpt55-heavy'
                RuntimeKind = 'local'
                ConditionalApproval = @('User confirmed adapter execution on 2026-08-05.')
            }
            Assert-Contains $prepared.launchTaskRequest.prompt 'User confirmed adapter execution on 2026-08-05.'
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        }
    }
}

if (Test-Group 'storage') {
    Invoke-TestCase 'create-once write is idempotent and detects divergent content' {
        Import-AdapterModule
        $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        try {
            $target = Join-Path $project.ProjectPath 'launch-response.json'
            $schema = Join-Path $root 'adapter/schemas/launch-response.internal.schema.json'
            $value = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'launch-response.json') | ConvertFrom-Json
            $first = Write-CreateOnceJson -Path $target -Value $value -SchemaPath $schema
            $second = Write-CreateOnceJson -Path $target -Value $value -SchemaPath $schema
            Assert-Equal $first.Sha256 $second.Sha256
            $value.status = 'completed'
            Assert-Throws { Write-CreateOnceJson -Path $target -Value $value -SchemaPath $schema } 'conflict'
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        }
    }
}

if (Test-Group 'prepare-launch') {
    Invoke-TestCase 'prepare launch writes attempt and renders complete prompt' {
        $fixture = New-PreparedFixture
        try {
            Assert-True (Test-Path -LiteralPath $fixture.AttemptPath)
            Assert-Equal 'codex-gpt55-heavy' $fixture.Prepared.launchTaskRequest.profileId
            Assert-Equal 'local' $fixture.Prepared.launchTaskRequest.runtimeKind
            foreach ($fragment in @('Objective', 'Authorization', 'Acceptance', 'Required Evidence', 'Stop Conditions', 'report_to_leader')) {
                Assert-Contains $fixture.Prepared.launchTaskRequest.prompt $fragment
            }
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'riskMode does not select profile or runtime' {
        $standardProject = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        $deepProject = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        try {
            $first = Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
                TaskPath = $standardProject.TaskPath
                CliTool = 'codex'
                Profile = 'explicit-profile'
                RuntimeKind = 'local'
            }
            $task = Get-Content -Raw -LiteralPath $deepProject.TaskPath | ConvertFrom-Json
            $task.riskMode = 'deep'
            $task | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $deepProject.TaskPath -Encoding utf8NoBOM
            $second = Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
                TaskPath = $deepProject.TaskPath
                CliTool = 'codex'
                Profile = 'explicit-profile'
                RuntimeKind = 'local'
            }
            Assert-Equal $first.launchTaskRequest.profileId $second.launchTaskRequest.profileId
            Assert-Equal $first.launchTaskRequest.runtimeKind $second.launchTaskRequest.runtimeKind
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $standardProject.ProjectPath
            Remove-AdapterTestProject -ProjectPath $deepProject.ProjectPath
        }
    }
}

if (Test-Group 'bind-launch') {
    Invoke-TestCase 'bind launch publishes valid run and reference-only metadata' {
        $fixture = New-BoundFixture
        try {
            Assert-True (Test-Path -LiteralPath $fixture.RunPath)
            $runSchema = Join-Path $root 'schemas/run.schema.json'
            Assert-True (Test-Json -LiteralPath $fixture.RunPath -SchemaFile $runSchema)
            $run = Get-Content -Raw -LiteralPath $fixture.RunPath | ConvertFrom-Json
            $task = Get-Content -Raw -LiteralPath $fixture.Project.TaskPath | ConvertFrom-Json
            Assert-Equal $task.objective $run.contract.objective
            Assert-Equal ($task.acceptance -join '|') ($run.contract.acceptance -join '|')
            $patchJson = $fixture.Bound.taskBindingPatch | ConvertTo-Json -Depth 100 -Compress
            Assert-True ([Text.Encoding]::UTF8.GetByteCount($patchJson) -lt 8192) 'Metadata patch exceeds 8 KiB.'
            Assert-False $patchJson.Contains($task.objective) 'Metadata contains task body.'
            Assert-Equal 'launch-task-001' $fixture.Bound.launchTaskId
            Assert-Equal 'session-001' $fixture.Bound.taskBindingLookup.sessionId
            Assert-False ($fixture.Bound.PSObject.Properties.Name -contains 'taskBindingId') 'launch taskId was exposed as TaskBinding identity.'
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'bound retry rejects a different launch response identity' {
        $fixture = New-BoundFixture
        try {
            $changedResponsePath = Join-Path $fixture.Project.ProjectPath 'input/launch-response-changed.json'
            $response = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'launch-response.json') | ConvertFrom-Json
            $response.sessionId = 'session-different'
            $response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $changedResponsePath -Encoding utf8NoBOM
            Assert-Throws {
                Invoke-AdapterScript -ScriptPath $bindScript -Parameters @{
                    AttemptPath = $fixture.AttemptPath
                    LaunchResponsePath = $changedResponsePath
                }
            } 'conflict|session|response'
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }
}

if (Test-Group 'recovery') {
    Invoke-TestCase 'recovery classifies prepared and bound attempts' {
        $fixture = New-PreparedFixture
        try {
            $preparedRecovery = Invoke-AdapterScript -ScriptPath $recoverScript -Parameters @{
                AttemptPath = $fixture.AttemptPath
            }
            Assert-Equal 'retry-launch' $preparedRecovery.recoveryAction

            $responsePath = Join-Path $fixture.Project.ProjectPath 'input/launch-response.json'
            Copy-Item -LiteralPath (Join-Path $fixtures 'launch-response.json') -Destination $responsePath
            $bound = Invoke-AdapterScript -ScriptPath $bindScript -Parameters @{
                AttemptPath = $fixture.AttemptPath
                LaunchResponsePath = $responsePath
            }
            $boundRecovery = Invoke-AdapterScript -ScriptPath $recoverScript -Parameters @{
                AttemptPath = $fixture.AttemptPath
            }
            Assert-Equal 'already-bound' $boundRecovery.recoveryAction
            Assert-Equal $bound.runPath $boundRecovery.runPath
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'recovery rebuilds launched run and emits metadata repair patch' {
        Import-AdapterModule
        $launchedFixture = New-PreparedFixture
        try {
            $attempt = Read-JsonFile -Path $launchedFixture.AttemptPath
            $attemptHash = Get-FileSha256 -Path $launchedFixture.AttemptPath
            $response = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'launch-response.json') | ConvertFrom-Json
            $attempt.state = 'launched'
            $attempt.updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
            $attempt | Add-Member -NotePropertyName response -NotePropertyValue $response
            Write-CompareAndSwapJson `
                -Path $launchedFixture.AttemptPath `
                -Value $attempt `
                -SchemaPath (Get-InternalSchemaPath -Name launchAttempt) `
                -ExpectedSha256 $attemptHash | Out-Null

            $recovered = Invoke-AdapterScript -ScriptPath $recoverScript -Parameters @{
                AttemptPath = $launchedFixture.AttemptPath
            }
            Assert-Equal 'bind-response' $recovered.recoveryAction
            $recoveredRun = Join-Path $launchedFixture.Project.ProjectPath ($recovered.bindResult.runPath -replace '/', '\')
            Assert-True (Test-Path -LiteralPath $recoveredRun)

            $bindingPath = Join-Path $launchedFixture.Project.ProjectPath 'input/task-binding-running.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-running.json') -OutputPath $bindingPath -ProjectPath $launchedFixture.Project.ProjectPath
            $repair = Invoke-AdapterScript -ScriptPath $recoverScript -Parameters @{
                AttemptPath = $launchedFixture.AttemptPath
                TaskBindingPath = $bindingPath
            }
            Assert-Equal 'repair-metadata' $repair.recoveryAction
            Assert-Equal $attempt.runId $repair.taskBindingPatch.metadata.methodLayer.runId
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $launchedFixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'recovery sends conflicting TaskBinding identity to manual review' {
        $fixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $fixture.Project.ProjectPath 'input/task-binding-conflict.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-running.json') -OutputPath $bindingPath -ProjectPath $fixture.Project.ProjectPath
            $binding = Get-Content -Raw -LiteralPath $bindingPath | ConvertFrom-Json
            $binding.metadata = [pscustomobject]@{
                kept = $true
                methodLayer = [pscustomobject]@{
                    protocolVersion = '0.1'
                    taskId = 'team:task-001'
                    runId = 'run-conflicting-identity'
                    artifactRoot = '.ccpanes-method/v0.1'
                    taskPath = '.ccpanes-method/v0.1/tasks/team%3Atask-001/task.json'
                    runPath = '.ccpanes-method/v0.1/tasks/team%3Atask-001/runs/run-conflicting-identity/run.json'
                }
            }
            $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bindingPath -Encoding utf8NoBOM

            $recovery = Invoke-AdapterScript -ScriptPath $recoverScript -Parameters @{
                AttemptPath = $fixture.AttemptPath
                TaskBindingPath = $bindingPath
            }
            Assert-Equal 'manual-review' $recovery.recoveryAction
            Assert-False ($recovery.PSObject.Properties.Name -contains 'taskBindingPatch')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }
}

if (Test-Group 'finish') {
    Invoke-TestCase 'summary-only finish creates truthful incomplete evidence' {
        $fixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $fixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $fixture.Project.ProjectPath
            $finished = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $fixture.RunPath
                TaskBindingPath = $bindingPath
                SummaryOnly = $true
            }
            $evidencePath = Join-Path $fixture.Project.ProjectPath ($finished.evidencePath -replace '/', '\')
            $evidence = Get-Content -Raw -LiteralPath $evidencePath | ConvertFrom-Json
            Assert-False ($evidence.outcome -eq 'completed')
            Assert-False (@($evidence.checks | Where-Object status -eq 'pass').Count -gt 0)
            Assert-Equal 'needs-review' $evidence.driftCheck.acceptance
            Assert-Equal 'completed' $finished.taskBindingPatch.status
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'aligned evidence passes and drifted evidence remains incomplete' {
        $completeFixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $completeFixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $completeFixture.Project.ProjectPath
            $completeEvidence = Write-EvidenceFixture -BoundFixture $completeFixture -FixtureName 'evidence-completed.json'
            $complete = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $completeFixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $completeEvidence
            }
            Assert-Equal 'completed' $complete.methodOutcome
            Assert-Equal 'completed' $complete.taskBindingPatch.status
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $completeFixture.Project.ProjectPath
        }

        $driftFixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $driftFixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $driftFixture.Project.ProjectPath
            $driftEvidence = Write-EvidenceFixture -BoundFixture $driftFixture -FixtureName 'evidence-drifted.json'
            $drift = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $driftFixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $driftEvidence
            }
            Assert-False ($drift.methodOutcome -eq 'completed')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $driftFixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'contract or Git evidence drift blocks completed outcome' {
        Import-AdapterModule
        $contractFixture = New-BoundFixture
        try {
            $run = Read-JsonFile -Path $contractFixture.RunPath
            $runHash = Get-FileSha256 -Path $contractFixture.RunPath
            $run.contract.acceptance = @('Changed after launch.')
            Write-CompareAndSwapJson `
                -Path $contractFixture.RunPath `
                -Value $run `
                -SchemaPath (Get-MethodSchemaPath -ArtifactType run) `
                -ExpectedSha256 $runHash | Out-Null
            $bindingPath = Join-Path $contractFixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $contractFixture.Project.ProjectPath
            $evidencePath = Write-EvidenceFixture -BoundFixture $contractFixture -FixtureName 'evidence-completed.json'
            $result = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $contractFixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidencePath
            }
            Assert-False ($result.methodOutcome -eq 'completed')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $contractFixture.Project.ProjectPath
        }

        $gitFixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $gitFixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $gitFixture.Project.ProjectPath
            $evidencePath = Write-EvidenceFixture -BoundFixture $gitFixture -FixtureName 'evidence-completed.json'
            $evidence = Read-JsonFile -Path $evidencePath
            $evidence.gitStatus.branch = 'different-branch'
            $evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM
            $result = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $gitFixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidencePath
            }
            Assert-False ($result.methodOutcome -eq 'completed')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $gitFixture.Project.ProjectPath
        }

        $coverageFixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $coverageFixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $coverageFixture.Project.ProjectPath
            $evidencePath = Write-EvidenceFixture -BoundFixture $coverageFixture -FixtureName 'evidence-completed.json'
            $evidence = Read-JsonFile -Path $evidencePath
            $evidence.checks = @(
                [pscustomobject]@{
                    name = 'Unrelated passing check'
                    command = 'unrelated-check'
                    required = $true
                    status = 'pass'
                }
            )
            $evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $evidencePath -Encoding utf8NoBOM
            $result = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $coverageFixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidencePath
            }
            Assert-False ($result.methodOutcome -eq 'completed')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $coverageFixture.Project.ProjectPath
        }

        $statusFixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $statusFixture.Project.ProjectPath 'input/task-binding-running.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-running.json') -OutputPath $bindingPath -ProjectPath $statusFixture.Project.ProjectPath
            $evidencePath = Write-EvidenceFixture -BoundFixture $statusFixture -FixtureName 'evidence-completed.json'
            $result = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $statusFixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidencePath
            }
            Assert-Equal 'completed' $result.methodOutcome
            Assert-Equal 'running' $result.taskBindingPatch.status
            Assert-Equal 'running' $result.leaderReport.status
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $statusFixture.Project.ProjectPath
        }
    }
}

if (Test-Group 'handoff') {
    Invoke-TestCase 'handoff validates nine sections and creates no launch attempt' {
        $fixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $fixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $fixture.Project.ProjectPath
            $evidencePath = Write-EvidenceFixture -BoundFixture $fixture -FixtureName 'evidence-completed.json'
            $finished = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $fixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidencePath
            }
            $publishedEvidence = Join-Path $fixture.Project.ProjectPath ($finished.evidencePath -replace '/', '\')
            $attemptCountBefore = @(Get-ChildItem -LiteralPath (Split-Path -Parent $fixture.AttemptPath) -Filter '*.json' -File).Count
            $handoff = Invoke-AdapterScript -ScriptPath $handoffScript -Parameters @{
                TaskPath = $fixture.Project.TaskPath
                RunPath = $fixture.RunPath
                EvidencePath = $publishedEvidence
                ContextPath = (Join-Path $fixtures 'handoff-context.json')
            }
            $handoffPath = Join-Path $fixture.Project.ProjectPath ($handoff.handoffPath -replace '/', '\')
            Assert-True (Test-Json -LiteralPath $handoffPath -SchemaFile (Join-Path $root 'schemas/handoff.schema.json'))
            $attemptCountAfter = @(Get-ChildItem -LiteralPath (Split-Path -Parent $fixture.AttemptPath) -Filter '*.json' -File).Count
            Assert-Equal $attemptCountBefore $attemptCountAfter
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'custom artifact root is preserved through bind finish and handoff' {
        $project = New-AdapterTestProject -TaskFixture (Join-Path $fixtures 'task-with-colon.json')
        try {
            $prepared = Invoke-AdapterScript -ScriptPath $prepareScript -Parameters @{
                TaskPath = $project.TaskPath
                CliTool = 'codex'
                Profile = 'codex-gpt55-heavy'
                RuntimeKind = 'local'
                ArtifactRoot = '.method-custom/v0.1'
            }
            $attemptPath = Join-Path $project.ProjectPath ($prepared.attemptPath -replace '/', '\')
            $responsePath = Join-Path $project.ProjectPath 'input/launch-response.json'
            Copy-Item -LiteralPath (Join-Path $fixtures 'launch-response.json') -Destination $responsePath
            $bound = Invoke-AdapterScript -ScriptPath $bindScript -Parameters @{
                AttemptPath = $attemptPath
                LaunchResponsePath = $responsePath
            }
            $runPath = Join-Path $project.ProjectPath ($bound.runPath -replace '/', '\')
            $bindingPath = Join-Path $project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $project.ProjectPath
            $boundFixture = [pscustomobject]@{
                Project = $project
                Bound = $bound
                RunPath = $runPath
            }
            $evidenceInput = Write-EvidenceFixture -BoundFixture $boundFixture -FixtureName 'evidence-completed.json'
            $finished = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $runPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidenceInput
            }
            $evidencePath = Join-Path $project.ProjectPath ($finished.evidencePath -replace '/', '\')
            $handoff = Invoke-AdapterScript -ScriptPath $handoffScript -Parameters @{
                TaskPath = $project.TaskPath
                RunPath = $runPath
                EvidencePath = $evidencePath
                ContextPath = (Join-Path $fixtures 'handoff-context.json')
            }
            Assert-True $bound.runPath.StartsWith('.method-custom/v0.1/')
            Assert-True $finished.evidencePath.StartsWith('.method-custom/v0.1/')
            Assert-True $handoff.handoffPath.StartsWith('.method-custom/v0.1/')
            Assert-Equal '.method-custom/v0.1' $finished.taskBindingPatch.metadata.methodLayer.artifactRoot
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $project.ProjectPath
        }
    }
}

if (Test-Group 'envelope') {
    Invoke-TestCase 'prepare-launch stdout matches its internal envelope contract' {
        $fixture = New-PreparedFixture
        try {
            Assert-JsonValueMatchesSchema `
                -Value $fixture.Prepared `
                -SchemaPath (Join-Path $root 'adapter/schemas/prepare-launch-envelope.internal.schema.json')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'bind-launch stdout matches its internal envelope contract' {
        $fixture = New-BoundFixture
        try {
            Assert-JsonValueMatchesSchema `
                -Value $fixture.Bound `
                -SchemaPath (Join-Path $root 'adapter/schemas/bind-launch-envelope.internal.schema.json')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'finish-run stdout matches its internal envelope contract' {
        $fixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $fixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $fixture.Project.ProjectPath
            $evidencePath = Write-EvidenceFixture -BoundFixture $fixture -FixtureName 'evidence-completed.json'
            $finished = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $fixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidencePath
            }
            Assert-Equal 'find_task_binding_by_session' $finished.taskBindingLookup.operation
            Assert-Equal 'session-001' $finished.taskBindingLookup.sessionId
            Assert-Equal 'if-not-auto-notified' $finished.leaderReport.dispatchPolicy
            Assert-JsonValueMatchesSchema `
                -Value $finished `
                -SchemaPath (Join-Path $root 'adapter/schemas/finish-run-envelope.internal.schema.json')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'new-handoff stdout matches its internal envelope contract' {
        $fixture = New-BoundFixture
        try {
            $bindingPath = Join-Path $fixture.Project.ProjectPath 'input/task-binding-completed.json'
            Set-FixtureProjectPath -FixturePath (Join-Path $fixtures 'task-binding-completed.json') -OutputPath $bindingPath -ProjectPath $fixture.Project.ProjectPath
            $evidenceInput = Write-EvidenceFixture -BoundFixture $fixture -FixtureName 'evidence-completed.json'
            $finished = Invoke-AdapterScript -ScriptPath $finishScript -Parameters @{
                RunPath = $fixture.RunPath
                TaskBindingPath = $bindingPath
                EvidencePath = $evidenceInput
            }
            $publishedEvidence = Join-Path $fixture.Project.ProjectPath ($finished.evidencePath -replace '/', '\')
            $handoff = Invoke-AdapterScript -ScriptPath $handoffScript -Parameters @{
                TaskPath = $fixture.Project.TaskPath
                RunPath = $fixture.RunPath
                EvidencePath = $publishedEvidence
                ContextPath = (Join-Path $fixtures 'handoff-context.json')
            }
            Assert-Equal 'find_task_binding_by_session' $handoff.taskBindingLookup.operation
            Assert-Equal 'session-001' $handoff.taskBindingLookup.sessionId
            Assert-JsonValueMatchesSchema `
                -Value $handoff `
                -SchemaPath (Join-Path $root 'adapter/schemas/handoff-envelope.internal.schema.json')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }

    Invoke-TestCase 'recover-launch stdout matches its internal envelope contract' {
        $fixture = New-PreparedFixture
        try {
            $recovery = Invoke-AdapterScript -ScriptPath $recoverScript -Parameters @{
                AttemptPath = $fixture.AttemptPath
            }
            Assert-JsonValueMatchesSchema `
                -Value $recovery `
                -SchemaPath (Join-Path $root 'adapter/schemas/recovery-envelope.internal.schema.json')
        }
        finally {
            Remove-AdapterTestProject -ProjectPath $fixture.Project.ProjectPath
        }
    }
}

Complete-TestRun
