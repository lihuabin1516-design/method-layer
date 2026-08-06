[CmdletBinding()]
param(
    [ValidateSet('all', 'core', 'recovery', 'transport')]
    [string]$Group = 'all'
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'adapter/TestHarness.ps1')

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executorModule = Join-Path $root 'scripts/controller/MethodLayer.Executor.psm1'
$controllerModule = Join-Path $root 'scripts/controller/MethodLayer.Controller.psm1'
$adapterModule = Join-Path $root 'scripts/adapter/MethodLayer.Adapter.psm1'
$transportModule = Join-Path $root 'scripts/controller/CcPanesMcp.Transport.psm1'
$fixtures = Join-Path $root 'tests/controller/fixtures'
$resultSchema = Join-Path $root 'controller/schemas/execution-result.internal.schema.json'
$journalSchema = Join-Path $root 'controller/schemas/execution-journal-entry.internal.schema.json'

function Test-ExecutorGroup {
    param([string]$Name)
    return $Group -eq 'all' -or $Group -eq $Name
}

function Import-ExecutorModules {
    Import-Module $executorModule -Force
    Import-Module $controllerModule -Force
    Import-Module $adapterModule -Force
}

function New-TestProject {
    $path = Join-Path (Get-TestTempRoot) ('controller-executor-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function New-TestPlan {
    param(
        [string]$EnvelopeName = 'bind-envelope.json',
        [string]$TaskBindingName = 'task-binding-running.json'
    )

    Import-ExecutorModules
    $envelope = Read-ControllerEnvelope -Path (Join-Path $fixtures $EnvelopeName)
    $binding = if ($TaskBindingName) {
        Read-ControllerTaskBinding -Path (Join-Path $fixtures $TaskBindingName)
    }
    else {
        $null
    }
    $plan = New-ControllerTransportPlan -Envelope $envelope -TaskBinding $binding
    $plan.planId = 'controller-plan-executor-fixture'
    Assert-ControllerTransportPlan -Plan $plan | Out-Null
    return $plan
}

function Write-TestPlan {
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$ProjectPath
    )

    $path = Join-Path $ProjectPath 'plan.json'
    ConvertTo-StableJson -Value $Plan | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    return $path
}

function Assert-ExecutionSchema {
    param([Parameter(Mandatory)]$Result)
    Assert-JsonValueMatchesSchema -Value $Result -SchemaPath $resultSchema
}

function Assert-JournalSchema {
    param([Parameter(Mandatory)][string]$Path)
    $entries = Get-Content -LiteralPath $Path | ForEach-Object { $_ | ConvertFrom-Json }
    foreach ($entry in $entries) {
        Assert-JsonValueMatchesSchema -Value $entry -SchemaPath $journalSchema
    }
    return @($entries)
}

function Copy-JsonValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    return ($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json
}

if (Test-ExecutorGroup 'core') {
    Invoke-TestCase 'planner update step contains binding drift preconditions' {
        $plan = New-TestPlan
        $update = @($plan.steps | Where-Object tool -eq 'update_task_binding')[0]
        Assert-Equal 'ccpanes-binding-controller' $update.preconditions.bindingId
        Assert-Equal 'session-controller-fixture' $update.preconditions.sessionId
        Assert-Equal 'worker' $update.preconditions.role
        Assert-Equal 'running' $update.preconditions.status
        Assert-True ($update.preconditions.metadataSha256 -match '^[A-F0-9]{64}$')
    }

    Invoke-TestCase 'dry-run validates without invoking transport or creating journal' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $planPath = Write-TestPlan -Plan (New-TestPlan) -ProjectPath $project
            $state = [pscustomobject]@{ calls = 0 }
            $result = Invoke-ControllerExecution `
                -PlanPath $planPath `
                -ProjectPath $project `
                -Mode dry-run `
                -TransportInvoker { $state.calls++; throw 'transport must not run' }
            Assert-ExecutionSchema $result
            Assert-Equal 'dry-run' $result.status
            Assert-Equal 0 $state.calls
            Assert-Equal $null $result.journalPath
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'live bind executes lookup update readback and persists journal responses' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $running = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $updated = Copy-JsonValue $running
            $updated.metadata = Copy-JsonValue $plan.steps[1].request.metadata
            $calls = [System.Collections.Generic.List[string]]::new()
            $invoker = {
                param($Tool, $Request)
                $calls.Add($Tool)
                if ($Tool -eq 'find_task_binding_by_session' -and $calls.Count -eq 1) { return $running }
                if ($Tool -eq 'update_task_binding') { return $updated }
                return $updated
            }
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker $invoker
            Assert-ExecutionSchema $result
            Assert-Equal 'completed' $result.status
            Assert-Equal 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session' ($calls -join '|')
            $journal = Join-Path $project $result.journalPath
            $entries = Assert-JournalSchema -Path $journal
            Assert-True (@($entries | Where-Object eventType -eq 'step-succeeded').Count -eq 3)
            foreach ($stepResult in @($result.steps | Where-Object status -eq 'succeeded')) {
                Assert-True (Test-Path -LiteralPath (Join-Path $project $stepResult.responsePath) -PathType Leaf)
            }
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'metadata drift stops before update' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $planPath = Write-TestPlan -Plan (New-TestPlan) -ProjectPath $project
            $drifted = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $drifted.metadata | Add-Member -NotePropertyName concurrent -NotePropertyValue $true
            $calls = [System.Collections.Generic.List[string]]::new()
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $calls.Add($Tool)
                return $drifted
            }
            Assert-ExecutionSchema $result
            Assert-Equal 'manual-review' $result.status
            Assert-False ('update_task_binding' -in @($calls))
            Assert-Contains ($result.notes -join ' ') 'metadata'
            $entries = Assert-JournalSchema -Path (Join-Path $project $result.journalPath)
            Assert-True (@($entries | Where-Object {
                $_.eventType -eq 'step-failed' -and $_.tool -eq 'update_task_binding'
            }).Count -eq 1)
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'readback assertion mismatch stops execution' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $running = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $updated = Copy-JsonValue $running
            $updated.metadata = Copy-JsonValue $plan.steps[1].request.metadata
            $wrong = Copy-JsonValue $updated
            $wrong.metadata.methodLayer.runId = 'run-wrong-readback'
            $state = [pscustomobject]@{ count = 0 }
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $state.count++
                if ($state.count -eq 1) { return $running }
                if ($Tool -eq 'update_task_binding') { return $updated }
                return $wrong
            }
            Assert-ExecutionSchema $result
            Assert-Equal 'manual-review' $result.status
            Assert-Contains ($result.notes -join ' ') 'assertion'
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'executor rejects an envelope-incompatible tool sequence' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan -EnvelopeName 'prepare-envelope.json' -TaskBindingName ''
            $plan.sourceEnvelopeType = 'bind-launch-envelope'
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            Assert-Throws {
                Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode dry-run -TransportTargetProjectPath 'D:/fixture/project'
            } 'sequence|invalid|sourceEnvelopeType'
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }
}

if (Test-ExecutorGroup 'recovery') {
    Invoke-TestCase 'transient lookup retries at most three attempts and then succeeds' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan -EnvelopeName 'recovery-bound-envelope.json' -TaskBindingName ''
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $binding = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $binding.metadata | Add-Member -NotePropertyName methodLayer -NotePropertyValue ([pscustomobject]@{
                taskId = 'team:task-001'
                runId = 'run-controller-fixture'
            })
            $state = [pscustomobject]@{ attempt = 0 }
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $state.attempt++
                if ($state.attempt -lt 3) {
                    $exception = [System.Exception]::new('fixture transient')
                    $exception.Data['ControllerTransportCategory'] = 'transient'
                    $exception.Data['ControllerDelivery'] = 'not-sent'
                    throw $exception
                }
                return $binding
            }
            Assert-ExecutionSchema $result
            Assert-Equal 'completed' $result.status
            Assert-Equal 3 $state.attempt
            Assert-Equal 3 $result.steps[0].attempts
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'ambiguous launch is never retried automatically' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan -EnvelopeName 'prepare-envelope.json' -TaskBindingName ''
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $state = [pscustomobject]@{ attempt = 0 }
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $state.attempt++
                $exception = [System.Exception]::new('fixture ambiguous launch')
                $exception.Data['ControllerTransportCategory'] = 'transient'
                $exception.Data['ControllerDelivery'] = 'ambiguous'
                throw $exception
            }
            Assert-ExecutionSchema $result
            Assert-Equal 'manual-review' $result.status
            Assert-Equal 1 $state.attempt
            $second = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $state.attempt++
                throw 'replay transport must not run'
            }
            Assert-Equal 'manual-review' $second.status
            Assert-Equal 1 $state.attempt
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'report response must be sent or queued' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan -EnvelopeName 'finish-envelope.json' -TaskBindingName 'task-binding-completed.json'
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $binding = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-completed.json')
            $updated = Copy-JsonValue $binding
            $updated.metadata = Copy-JsonValue $plan.steps[1].request.metadata
            foreach ($property in @('status', 'progress', 'completionSummary', 'exitCode')) {
                if ($plan.steps[1].request.PSObject.Properties.Name -contains $property) {
                    $updated.$property = $plan.steps[1].request.$property
                }
            }
            $state = [pscustomobject]@{ finds = 0 }
            $invoker = {
                param($Tool, $Request)
                if ($Tool -eq 'report_to_leader') {
                    return [pscustomobject]@{ sent = $false; queued = $false; skipReason = 'leader not found' }
                }
                if ($Tool -eq 'find_task_binding_by_session') {
                    $state.finds++
                    if ($state.finds -eq 1) { return $binding }
                }
                return $updated
            }.GetNewClosure()
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker $invoker
            Assert-Equal 'manual-review' $result.status
            Assert-Contains ($result.notes -join ' ') 'neither sent nor queued'
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'launch response must satisfy the pinned adapter response schema' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan -EnvelopeName 'prepare-envelope.json' -TaskBindingName ''
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $result = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                return [pscustomobject]@{ taskId = 'launch-only-missing-session' }
            }
            Assert-ExecutionSchema $result
            Assert-Equal 'manual-review' $result.status
            Assert-Contains ($result.notes -join ' ') 'schema'
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'replay skips successful update and repeats readback' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $running = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $updated = Copy-JsonValue $running
            $updated.metadata = Copy-JsonValue $plan.steps[1].request.metadata
            $firstCalls = [System.Collections.Generic.List[string]]::new()
            $first = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $firstCalls.Add($Tool)
                if ($Tool -eq 'find_task_binding_by_session' -and $firstCalls.Count -eq 1) { return $running }
                if ($Tool -eq 'update_task_binding') { return $updated }
                $exception = [System.Exception]::new('fixture readback unavailable')
                $exception.Data['ControllerTransportCategory'] = 'permanent'
                $exception.Data['ControllerDelivery'] = 'rejected'
                throw $exception
            }
            Assert-Equal 'failed' $first.status

            $secondCalls = [System.Collections.Generic.List[string]]::new()
            $second = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $secondCalls.Add($Tool)
                return $updated
            }
            Assert-ExecutionSchema $second
            Assert-Equal 'completed' $second.status
            Assert-False ('update_task_binding' -in @($secondCalls))
            Assert-Equal 2 @($secondCalls | Where-Object { $_ -eq 'find_task_binding_by_session' }).Count
            Assert-Equal 'skipped' $second.steps[1].status
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'journal plan hash mismatch fails closed' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan -EnvelopeName 'recovery-bound-envelope.json' -TaskBindingName ''
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $binding = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $binding.metadata | Add-Member -NotePropertyName methodLayer -NotePropertyValue ([pscustomobject]@{
                taskId = 'team:task-001'
                runId = 'run-controller-fixture'
            })
            $first = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                return $binding
            }
            Assert-Equal 'completed' $first.status
            $changed = Get-Content -Raw -LiteralPath $planPath | ConvertFrom-Json
            $changed.notes = @('changed with same plan id')
            ConvertTo-StableJson -Value $changed | Set-Content -LiteralPath $planPath -Encoding utf8NoBOM
            Assert-Throws {
                Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                    param($Tool, $Request)
                    return $binding
                }
            } 'hash|journal|plan'
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }

    Invoke-TestCase 'replay rejects a missing successful mutation response artifact' {
        Import-ExecutorModules
        $project = New-TestProject
        try {
            $plan = New-TestPlan
            $planPath = Write-TestPlan -Plan $plan -ProjectPath $project
            $running = Read-ControllerTaskBinding -Path (Join-Path $fixtures 'task-binding-running.json')
            $updated = Copy-JsonValue $running
            $updated.metadata = Copy-JsonValue $plan.steps[1].request.metadata
            $calls = [System.Collections.Generic.List[string]]::new()
            $first = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                $calls.Add($Tool)
                if ($Tool -eq 'find_task_binding_by_session' -and $calls.Count -eq 1) { return $running }
                return $updated
            }
            Assert-Equal 'completed' $first.status
            [System.IO.File]::Delete((Join-Path $project $first.steps[1].responsePath))
            $second = Invoke-ControllerExecution -PlanPath $planPath -ProjectPath $project -Mode live -TransportTargetProjectPath 'D:/fixture/project' -AllowNonAtomicTaskBindingUpdate -TransportInvoker {
                param($Tool, $Request)
                return $updated
            }
            Assert-ExecutionSchema $second
            Assert-Equal 'manual-review' $second.status
            Assert-Contains ($second.notes -join ' ') 'response'
        }
        finally {
            Remove-Item -LiteralPath $project -Recurse -Force
        }
    }
}

if (Test-ExecutorGroup 'transport') {
    Invoke-TestCase 'MCP SSE parser unwraps JSON text tool result' {
        Import-Module $transportModule -Force
        $payload = @'
data:
id: 0
retry: 3000

data: {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"id\":\"binding-1\",\"status\":\"running\"}"}],"isError":false}}

'@
        $value = ConvertFrom-CcPanesMcpResponse -Content $payload
        Assert-Equal 'binding-1' $value.id
        Assert-Equal 'running' $value.status
    }

    Invoke-TestCase 'MCP tool error is normalized as a contract exception' {
        Import-Module $transportModule -Force
        $payload = @'
data: {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"tool rejected fixture"}],"isError":true}}

'@
        Assert-Throws {
            ConvertFrom-CcPanesMcpResponse -Content $payload
        } 'tool rejected fixture|MCP'
    }

    Invoke-TestCase 'MCP parser accepts JSON and selects response before trailing notification' {
        Import-Module $transportModule -Force
        $json = '{"jsonrpc":"2.0","id":7,"result":{"content":[{"type":"text","text":"null"}],"isError":false}}'
        Assert-Equal $null (ConvertFrom-CcPanesMcpResponse -Content $json -ExpectedId 7)
        $sse = @'
data: {"jsonrpc":"2.0","id":8,"result":{"content":[{"type":"text","text":"{\"ok\":true}"}],"isError":false}}

data: {"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info"}}

'@
        $value = ConvertFrom-CcPanesMcpResponse -Content $sse -ExpectedId 8
        Assert-True ([bool]$value.ok)
    }
}

Complete-TestRun -Label 'Controller executor'
