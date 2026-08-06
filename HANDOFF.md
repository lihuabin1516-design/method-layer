# CC-Panes Method Layer v0.1 Production Baseline Handoff

## 1. Role, task id, current result

- Role: 下一任 CC-Panes Method Layer 主控。
- Task ID: `ccp-method-v01-production-baseline-20260805`
- Current result: v0.1 四类方法 artifact、file-first adapter、transport planner、
  journaled executor 和 MCP Streamable HTTP driver 已形成可本机验证基线。

## 2. Required reading

- `AGENTS.md`
- `tsc.md`
- `README.md`
- `docs/charter.md`
- `docs/integration-map.md`
- `docs/workflow.md`
- `docs/ccpanes-mcp-transport-runbook.md`
- `docs/plans/2026-08-05-v0.1-controller-executor.md`
- `controller/README.md`
- `schemas/*.schema.json`
- `adapter/schemas/*.json`
- `controller/schemas/*.json`
- `scripts/adapter/*`
- `scripts/controller/*`
- `tests/adapter/*`
- `tests/controller/*`
- `tests/controller-executor/*`

## 3. Current baseline, facts, evidence

- Repository: `D:\ccpanes-method-layer`
- Branch: `main`
- HEAD: `unborn`
- Remote count: `0`
- Repository content remains untracked because commit was not authorized.
- No dependency install, commit, push, remote, UI, hook, plugin, profile, global
  configuration, or `D:\cc-pane` write was performed.
- Four public schemas remain `task`, `run`, `evidence`, and `handoff` v0.1.
- Adapter commands remain file-first and emit command-specific validated envelopes.
- Planner emits ordered requests and update preconditions containing binding identity,
  status, role, and metadata SHA-256.
- Executor supports `dry-run` and explicit `live`; live state is project-local.
- Journal is append-only JSONL; responses are separate create-once JSON artifacts.
- Read/update transient failures retry at most three times per invocation.
- Ambiguous `launch_task` and `report_to_leader` stop after one attempt.
- Replay skips only a matching successful mutation and repeats readback.
- Production driver completed a real read-only MCP
  `find_task_binding_by_session` execution through `/mcp`; the synthetic session
  lookup returned `null`, and the journaled execution completed successfully.
- Live probe evidence is under ignored `artifacts/local/live-probe/`.
- RED evidence: executor suite initially reported 11 failures / 0 passes.
- GREEN evidence: executor suite reports 16 passes.
- Existing adapter suite reports 23 passes.
- Existing planner suite reports 16 passes.

## 4. Single objective for the next round

Consume this v0.1 baseline from a separately authorized CC-Panes adapter integration
without changing the four public artifact contracts.

## 5. Authorization, forbidden items, conditional authorization

Authorized baseline maintenance:

- Modify only `D:\ccpanes-method-layer` files required by the active task.
- Run local schema, parser, fixture, and read-only MCP checks.

Forbidden without a new explicit task:

- Modify `D:\cc-pane`.
- Write user global configuration.
- Install dependencies.
- Commit, merge, push, create remotes, or clean unrelated worktree content.
- Add UI, hook, plugin, profile, or automatic runtime wiring.
- Run live mutation plans against non-synthetic TaskBindings.

Conditional:

- CC-Panes main-repository adapter integration requires exact target paths and
  mutation authorization.

## 6. Execution order and agent dispatch boundary

1. Re-run `scripts/validate.ps1`.
2. Read planner/executor schemas and `controller/README.md`.
3. Generate a plan from a validated adapter envelope.
4. Run `execute-transport.ps1 -Mode dry-run`.
5. Only with explicit runtime mutation authorization, run `-Mode live`.
6. Inspect journal, response hashes, TaskBinding readback, and full Git status.

Read-only workers may review schemas or transport sequencing. Writing workers must
have disjoint file scopes inside this repository and report touched files, commands,
outcome, and residual risk.

## 7. Required checks and acceptance assertions

Required:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
python -m json.tool schemas/task.schema.json > $null
python -m json.tool schemas/run.schema.json > $null
python -m json.tool schemas/evidence.schema.json > $null
python -m json.tool schemas/handoff.schema.json > $null
git status --short
```

Assertions:

- all valid examples pass and focused invalid examples are rejected;
- adapter 23, planner 16, and executor 16 tests pass;
- every PowerShell file parses;
- no runtime token appears in repository files or journal evidence;
- no unexplained repository-external write exists.

## 8. Audit, fuse, and stop conditions

- Inspect task diff/status after each write batch.
- Treat plan hash, journal sequence, response hash, TaskBinding precondition, or
  readback mismatch as fail-closed.
- Same root cause gets at most three autonomous repair rounds.
- Stop before any unapproved CC-Panes source/config/runtime mutation.
- Do not report completion while a required check is failing.

## 9. Artifacts, delivery, and next order

Primary artifacts:

- `schemas/**`
- `adapter/**`
- `controller/**`
- `scripts/adapter/**`
- `scripts/controller/**`
- `tests/adapter/**`
- `tests/controller/**`
- `tests/controller-executor/**`
- `docs/**`
- `templates/**`
- `README.md`
- `HANDOFF.md`

Delivery remains a local uncommitted repository baseline. The next dependency is a
separately authorized CC-Panes adapter consumption task; it does not expand this
handoff's permissions automatically.
