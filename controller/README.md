# Controller Planner and Journaled Executor v0.1

## Boundary

The controller layer consumes validated adapter envelopes, produces an ordered
MCP request plan, and can execute an explicitly supplied plan through the
current CC-Panes MCP endpoint.

The four method artifacts remain authoritative. Controller plans, journal
entries, execution results, and response files are internal transport
artifacts.

This repository does not modify the CC-Panes source tree, user configuration,
profiles, hooks, plugins, UI, Git remotes, or dependencies.

## Plan

```powershell
pwsh -NoProfile -File scripts/controller/plan-transport.ps1 `
  -EnvelopePath PATH_TO_ENVELOPE `
  -TaskBindingPath PATH_TO_CURRENT_BINDING `
  -PrepareEnvelopePath PATH_TO_ORIGINAL_PREPARE_ENVELOPE
```

`TaskBindingPath` is required before planning a mutation.
`PrepareEnvelopePath` is required for `retry-launch`.

The planner validates against
`controller/schemas/transport-plan.internal.schema.json` and returns one of:

- `ready`
- `requires-binding`
- `requires-journal`
- `manual-review`
- `already-satisfied`

Every update step carries preconditions for binding id, session id, role,
status, and the canonical SHA-256 of the metadata snapshot used for the merge.

## Execute

Dry-run validation:

```powershell
pwsh -NoProfile -File scripts/controller/execute-transport.ps1 `
  -PlanPath PATH_TO_PLAN `
  -ProjectPath TARGET_PROJECT `
  -Mode dry-run
```

Explicit live execution:

```powershell
pwsh -NoProfile -File scripts/controller/execute-transport.ps1 `
  -PlanPath PATH_TO_PLAN `
  -ProjectPath TARGET_PROJECT `
  -Mode live
```

Because the current CC-Panes `update_task_binding` API has no server-side CAS,
plans containing metadata replacement stop at `manual-review` unless the caller
also supplies `-AllowNonAtomicTaskBindingUpdate`. That switch is an explicit
risk acceptance; precondition lookup and readback reduce but do not eliminate
the server-side TOCTOU window.

Live mode reads `CC_PANES_API_BASE_URL` and `CC_PANES_API_TOKEN`, initializes
an MCP Streamable HTTP session, and invokes `tools/call`. Credentials are not
persisted.

Default execution state:

```text
TARGET_PROJECT/.ccpanes-method/v0.1/controller/executions/<planId>/
  execution.lock
  journal.jsonl
  responses/*.json
```

Use `-ArtifactRoot` to select another contained project-local root.

## Execution gates

- plan and journal schema validation;
- append-only contiguous journal sequence;
- plan id/hash and deterministic execution id verification;
- project containment and reparse-point checks;
- exclusive execution file lock;
- TaskBinding drift preconditions before update;
- response file SHA-256 and create-once conflict detection;
- update readback assertions before advancement;
- transient read/update retries, maximum three per invocation;
- no automatic retry for ambiguous `launch_task` or `report_to_leader`;
- replay skips only a matching previously successful mutation;
- credentials and full requests are absent from journal lines.

`manual-review` exits with code `2`; transport failure exits with code `1`;
`dry-run` and `completed` exit with code `0`.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/controller/run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests/controller-executor/run.ps1
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
```

The automated suite uses injected deterministic transport. A live acceptance
probe must remain read-only unless a separate task explicitly authorizes
runtime mutation.
