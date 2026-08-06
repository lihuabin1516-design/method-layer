[CmdletBinding()]
param(
    [ValidateSet('all', 'core', 'recovery')]
    [string]$Group = 'all'
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'adapter/TestHarness.ps1')

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$plannerScript = Join-Path $root 'scripts/controller/plan-transport.ps1'
$planSchema = Join-Path $root 'controller/schemas/transport-plan.internal.schema.json'
$fixtures = Join-Path $PSScriptRoot 'fixtures'

function Test-ControllerGroup {
    param([string]$Name)
    return $Group -eq 'all' -or $Group -eq $Name
}

function Invoke-ControllerPlanner {
    param(
        [Parameter(Mandatory)]
        [string]$EnvelopeName,
        [string]$TaskBindingName,
        [string]$PrepareEnvelopeName
    )

    $parameters = @{
        EnvelopePath = Join-Path $fixtures $EnvelopeName
    }
    if ($TaskBindingName) {
        $parameters.TaskBindingPath = Join-Path $fixtures $TaskBindingName
    }
    if ($PrepareEnvelopeName) {
        $parameters.PrepareEnvelopePath = Join-Path $fixtures $PrepareEnvelopeName
    }
    return Invoke-AdapterScript -ScriptPath $plannerScript -Parameters $parameters
}

function Assert-PlanSchema {
    param([Parameter(Mandatory)]$Plan)
    Assert-JsonValueMatchesSchema -Value $Plan -SchemaPath $planSchema
}

if (Test-ControllerGroup 'core') {
    Invoke-TestCase 'prepare envelope maps to one dry-run launch_task request' {
        $plan = Invoke-ControllerPlanner -EnvelopeName 'prepare-envelope.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'ready' $plan.decision
        Assert-Equal 'not-applicable' $plan.leaderNotification
        Assert-Equal 1 @($plan.steps).Count
        Assert-Equal 'launch_task' $plan.steps[0].tool
        Assert-Equal 'codex-gpt55-heavy' $plan.steps[0].request.profileId
        Assert-Equal 'silent' $plan.steps[0].request.placement
    }

    Invoke-TestCase 'bind envelope without TaskBinding stops after lookup' {
        $plan = Invoke-ControllerPlanner -EnvelopeName 'bind-envelope.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'requires-binding' $plan.decision
        Assert-Equal 1 @($plan.steps).Count
        Assert-Equal 'find_task_binding_by_session' $plan.steps[0].tool
    }

    Invoke-TestCase 'bind plan preserves sibling metadata and schedules readback' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'bind-envelope.json' `
            -TaskBindingName 'task-binding-running.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'ready' $plan.decision
        Assert-Equal 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session' (@($plan.steps.tool) -join '|')
        Assert-True ([bool]$plan.steps[1].request.metadata.kept)
        Assert-Equal 'fixture' $plan.steps[1].request.metadata.owner.kind
        Assert-Equal 'run-controller-fixture' $plan.steps[1].request.metadata.methodLayer.runId
    }

    Invoke-TestCase 'finish transition relies on automatic terminal notification' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'finish-envelope.json' `
            -TaskBindingName 'task-binding-running.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'ready' $plan.decision
        Assert-Equal 'auto-notify-expected' $plan.leaderNotification
        Assert-False ('report_to_leader' -in @($plan.steps.tool))
        Assert-Contains ($plan.steps[2].readbackAssertions -join '|') 'status == completed'
        Assert-Contains ($plan.steps[2].readbackAssertions -join '|') 'progress == 100'
    }

    Invoke-TestCase 'finish without terminal transition plans manual leader report' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'finish-envelope.json' `
            -TaskBindingName 'task-binding-completed.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'manual-report-planned' $plan.leaderNotification
        Assert-Equal 'report_to_leader' $plan.steps[-1].tool
        Assert-Equal 'ccpanes-binding-controller' $plan.steps[-1].request.workerId
    }

    Invoke-TestCase 'handoff plan preserves metadata and updates latest handoff path' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'handoff-envelope.json' `
            -TaskBindingName 'task-binding-completed.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'ready' $plan.decision
        Assert-True ([bool]$plan.steps[1].request.metadata.kept)
        Assert-Contains $plan.steps[1].request.metadata.methodLayer.latestHandoffPath 'handoff-controller.json'
    }

    Invoke-TestCase 'TaskBinding session mismatch produces manual review with no update' {
        $bindingPath = Join-Path $fixtures 'task-binding-mismatch.json'
        $binding = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'task-binding-running.json') | ConvertFrom-Json
        $binding.sessionId = 'session-different'
        $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bindingPath -Encoding utf8NoBOM
        try {
            $plan = Invoke-ControllerPlanner `
                -EnvelopeName 'bind-envelope.json' `
                -TaskBindingName 'task-binding-mismatch.json'
            Assert-PlanSchema -Plan $plan
            Assert-Equal 'manual-review' $plan.decision
            Assert-False ('update_task_binding' -in @($plan.steps.tool))
        }
        finally {
            Remove-Item -LiteralPath $bindingPath -Force
        }
    }

    Invoke-TestCase 'invalid envelope is rejected before a transport plan is emitted' {
        $tempRoot = Get-TestTempRoot
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $invalidPath = Join-Path $tempRoot ('invalid-controller-envelope-' + [guid]::NewGuid().ToString('N') + '.json')
        $value = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'prepare-envelope.json') | ConvertFrom-Json
        $value | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
        $value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $invalidPath -Encoding utf8NoBOM
        try {
            Assert-Throws {
                Invoke-AdapterScript -ScriptPath $plannerScript -Parameters @{
                    EnvelopePath = $invalidPath
                }
            } 'schema|valid|unexpected'
        }
        finally {
            Remove-Item -LiteralPath $invalidPath -Force
        }
    }

    Invoke-TestCase 'oversized merged TaskBinding metadata is sent to manual review' {
        $bindingPath = Join-Path $fixtures 'task-binding-oversized.json'
        $binding = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'task-binding-running.json') | ConvertFrom-Json
        $binding.metadata | Add-Member -NotePropertyName oversized -NotePropertyValue ('x' * 70000)
        $binding | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bindingPath -Encoding utf8NoBOM
        try {
            $plan = Invoke-ControllerPlanner `
                -EnvelopeName 'bind-envelope.json' `
                -TaskBindingName 'task-binding-oversized.json'
            Assert-PlanSchema -Plan $plan
            Assert-Equal 'manual-review' $plan.decision
            Assert-False ('update_task_binding' -in @($plan.steps.tool))
        }
        finally {
            Remove-Item -LiteralPath $bindingPath -Force
        }
    }
}

if (Test-ControllerGroup 'recovery') {
    Invoke-TestCase 'retry recovery requires original prepare journal' {
        $plan = Invoke-ControllerPlanner -EnvelopeName 'recovery-retry-envelope.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'requires-journal' $plan.decision
        Assert-Equal 0 @($plan.steps).Count
    }

    Invoke-TestCase 'retry recovery reuses matching prepare launch request' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'recovery-retry-envelope.json' `
            -PrepareEnvelopeName 'prepare-envelope.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'ready' $plan.decision
        Assert-Equal 'launch_task' $plan.steps[0].tool
        Assert-Equal 'run-controller-fixture' $plan.correlation.runId
    }

    Invoke-TestCase 'manual-review recovery emits no MCP calls' {
        $plan = Invoke-ControllerPlanner -EnvelopeName 'recovery-manual-envelope.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'manual-review' $plan.decision
        Assert-Equal 0 @($plan.steps).Count
    }

    Invoke-TestCase 'bind-response recovery maps nested bind result without relaunch' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'recovery-bind-envelope.json' `
            -TaskBindingName 'task-binding-running.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'recovery-envelope' $plan.sourceEnvelopeType
        Assert-Equal 'ready' $plan.decision
        Assert-False ('launch_task' -in @($plan.steps.tool))
        Assert-Equal 'find_task_binding_by_session|update_task_binding|find_task_binding_by_session' (@($plan.steps.tool) -join '|')
    }

    Invoke-TestCase 'repair recovery preserves sibling metadata' {
        $plan = Invoke-ControllerPlanner `
            -EnvelopeName 'recovery-repair-envelope.json' `
            -TaskBindingName 'task-binding-running.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'ready' $plan.decision
        Assert-True ([bool]$plan.steps[1].request.metadata.kept)
        Assert-Equal 'run-controller-fixture' $plan.steps[1].request.metadata.methodLayer.runId
    }

    Invoke-TestCase 'already-bound recovery plans readback only' {
        $plan = Invoke-ControllerPlanner -EnvelopeName 'recovery-bound-envelope.json'
        Assert-PlanSchema -Plan $plan
        Assert-Equal 'already-satisfied' $plan.decision
        Assert-Equal 1 @($plan.steps).Count
        Assert-Equal 'find_task_binding_by_session' $plan.steps[0].tool
    }

    Invoke-TestCase 'retry recovery rejects a mismatched prepare journal' {
        $tempPath = Join-Path $fixtures 'prepare-envelope-mismatch.json'
        $prepare = Get-Content -Raw -LiteralPath (Join-Path $fixtures 'prepare-envelope.json') | ConvertFrom-Json
        $prepare.runId = 'run-controller-mismatch'
        $prepare | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tempPath -Encoding utf8NoBOM
        try {
            $plan = Invoke-ControllerPlanner `
                -EnvelopeName 'recovery-retry-envelope.json' `
                -PrepareEnvelopeName 'prepare-envelope-mismatch.json'
            Assert-PlanSchema -Plan $plan
            Assert-Equal 'manual-review' $plan.decision
            Assert-Equal 0 @($plan.steps).Count
        }
        finally {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

Complete-TestRun -Label 'Controller'
