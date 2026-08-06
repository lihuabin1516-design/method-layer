# CC-Panes Method Layer Long-Term Maintenance Handoff

## 1. Role, task id, current result

- Role: 下一任 CC-Panes Method Layer 长期维护主控。
- Task ID: `ccp-method-layer-long-term-maintenance-20260806`
- Current result: v0.1 四类方法 artifact、file-first adapter、transport planner、
  journaled executor、MCP Streamable HTTP driver、长期维护交接和仓库目录架构已形成可持续维护基线。

## 2. Required reading

- `AGENTS.md`
- `tsc.md`
- `README.md`
- `docs/maintenance/2026-08-06-long-term-maintenance-handoff.md`
- `docs/maintenance/long-term-maintenance-agent-prompt.md`
- `docs/architecture/repository-structure.md`
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
- Current pushed baseline commit: `d75cf50be269009cc53f6e984fc70981c55cee31`
- Remote: `https://github.com/lihuabin1516-design/ccpanes-method-layer.git`
- Remote `main` matched local HEAD after push.
- Current follow-up maintenance docs are local working-tree changes on top of the pushed v0.1 baseline.
- No dependency install, UI, hook, plugin, profile, global configuration, or `D:\cc-pane` write was performed.
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
- Long-term maintenance handoff added under `docs/maintenance/`.
- Standalone long-term Agent prompt added under `docs/maintenance/`.
- Repository directory architecture added under `docs/architecture/`.

## 4. Single objective for the next round

Maintain this repository as the long-term CC-Panes method-layer baseline and absorb
future method-layer ideas from other projects through documented, tested, reversible
plans.

## 5. Authorization, forbidden items, conditional authorization

Authorized baseline maintenance:

- Modify only `D:\ccpanes-method-layer` files required by the active task.
- Run local schema, parser, fixture, and read-only MCP checks.
- Read upstream public repositories and record findings under `docs/upstreams/`.
- Add plans under `docs/plans/` before changing public protocol semantics.

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
2. Read `docs/maintenance/2026-08-06-long-term-maintenance-handoff.md`.
3. Read `docs/architecture/repository-structure.md`.
4. Classify the next task as protocol, upstream absorption, adapter, controller,
   documentation, or CC-Panes integration preparation.
5. Write or update a focused plan under `docs/plans/`.
6. Add tests/examples before behavior changes.
7. Run validation and inspect full Git status.

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
- `docs/maintenance/**`
- `docs/architecture/**`
- `templates/**`
- `README.md`
- `HANDOFF.md`

Next order:

1. Use `docs/maintenance/2026-08-06-long-term-maintenance-handoff.md` as the
   starting state for the new long-term maintenance conversation.
2. Keep `docs/architecture/repository-structure.md` aligned with directory changes.
3. When absorbing another project, first create/update `docs/upstreams/<source>.md`,
   then create a dated plan, tests, implementation, validation, and handoff update.
