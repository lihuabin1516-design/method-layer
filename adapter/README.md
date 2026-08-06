# File-First Adapter v0.1

This directory contains internal contracts for the dependency-free PowerShell reference adapter.

## Boundary

- Protocol artifacts remain `task`, `run`, `evidence`, and `handoff`.
- `adapter/schemas/*.internal.schema.json` describe local operation inputs and recovery state; they are not additional protocol artifact types.
- Adapter commands emit JSON envelopes for a CC-Panes transport caller.
- Every stdout envelope carries `schemaVersion` and `envelopeType`, and is validated against its command-specific internal schema before stdout is written.
- Runtime calls, UI changes, database migrations, profile changes, and user-global configuration remain outside this reference adapter.

## Source contract pin

The internal launch response and TaskBinding snapshots were mapped from:

```text
D:\cc-pane\.source\cc-pane
e63d0889c52b6f8dc1109266563327da59eb080e
```

Relevant source files:

- `src-tauri/src/services/orchestrator_service.rs`
- `cc-panes-core/src/models/task_binding.rs`
- `cc-panes-core/src/services/task_binding_service.rs`
- `web/types/orchestrator.ts`

## Intended command flow

```text
prepare-launch
  -> transport invokes launch_task
  -> bind-launch
  -> transport resolves TaskBinding with find_task_binding_by_session(sessionId)
  -> transport applies taskBindingPatch

finish-run
  -> transport applies taskBindingPatch
  -> transport sends leaderReport

new-handoff
  -> transport applies taskBindingPatch
```

`recover-launch` inspects a launch attempt and returns a deterministic recovery action. Missing method metadata can produce `repair-metadata`; an existing methodLayer with conflicting task, run, path, project, or session identity produces `manual-review`.

The controller-mediated MCP mapping, metadata merge rule, readback gates, and recovery action table are defined in:

- `docs/ccpanes-mcp-transport-runbook.md`

A dependency-free dry-run consumer of those envelopes is documented in:

- `controller/README.md`

## Commands

Prepare a launch envelope:

```powershell
pwsh -NoProfile -File scripts/adapter/prepare-launch.ps1 `
  -TaskPath PATH_TO_TASK `
  -CliTool codex `
  -Profile PROFILE_ID `
  -RuntimeKind local
```

After the transport returns the `launch_task` response:

```powershell
pwsh -NoProfile -File scripts/adapter/bind-launch.ps1 `
  -AttemptPath PATH_TO_ATTEMPT `
  -LaunchResponsePath PATH_TO_RESPONSE
```

Finish with a complete evidence artifact:

```powershell
pwsh -NoProfile -File scripts/adapter/finish-run.ps1 `
  -RunPath PATH_TO_RUN `
  -TaskBindingPath PATH_TO_BINDING `
  -EvidencePath PATH_TO_EVIDENCE
```

Finish from a summary-only TaskBinding snapshot:

```powershell
pwsh -NoProfile -File scripts/adapter/finish-run.ps1 `
  -RunPath PATH_TO_RUN `
  -TaskBindingPath PATH_TO_BINDING `
  -SummaryOnly
```

Generate a handoff:

```powershell
pwsh -NoProfile -File scripts/adapter/new-handoff.ps1 `
  -TaskPath PATH_TO_TASK `
  -RunPath PATH_TO_RUN `
  -EvidencePath PATH_TO_EVIDENCE `
  -ContextPath PATH_TO_HANDOFF_CONTEXT
```

Inspect launch recovery:

```powershell
pwsh -NoProfile -File scripts/adapter/recover-launch.ps1 `
  -AttemptPath PATH_TO_ATTEMPT
```

Every command writes one JSON envelope to stdout. The transport applies the returned CC-Panes request, patch, or leader report.

`launch_task.taskId` identifies the orchestrator launch-status record. TaskBinding identity is resolved separately through `sessionId`; the adapter never aliases these two identifiers.

MCP `update_task_binding` receives a complete `metadata` value rather than the adapter's merge patch semantics. A controller must read the current TaskBinding, preserve sibling metadata keys, replace only `metadata.methodLayer`, update, and then read back before advancing.

`leaderReport.dispatchPolicy` is `if-not-auto-notified`: a controller does not manually call `report_to_leader` when its preceding `update_task_binding` already caused a non-terminal worker to enter `completed` or `failed`, because the CC-Panes MCP path auto-notifies that transition.

## Execution and method status

- TaskBinding `pending/running/waiting/completed/failed` describes the execution binding.
- Evidence `completed/partial/blocked/failed` describes method outcome.
- `completionSummary` supplies summary text; required checks and aligned drift still control method completion.
- Summary-only finish produces blocked or failed evidence with explicit missing-proof records.
- `finish-run` preserves the input TaskBinding `status` and `progress`; runtime/transport owns execution-state transitions.
- Every `task.requiredEvidence` item must have an exact-name `evidence.checks[]` entry marked `required: true` and `status: pass` before method completion.

## Project artifact policy

Each consuming project selects one explicit policy for `.ccpanes-method/`:

- track artifacts when repository history should retain method evidence;
- ignore artifacts when execution state is local and ephemeral.

The reference adapter leaves the consuming project’s `.gitignore` unchanged.

## Validation

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
```

The main validator checks protocol examples, internal schemas, PowerShell syntax, command-specific stdout envelope contracts, and the complete adapter test suite.
