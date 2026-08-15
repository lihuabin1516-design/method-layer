# Method Layer v0.1 task → run → evidence → handoff lifecycle brief

状态：**Derived / renderer-neutral brief**

生成日期：2026-08-15

本文件是 `task → run → evidence → handoff` 生命周期的图形 brief 与 receipt。它从
本仓库 public schema、workflow 文档、adapter/controller 边界生成，只作为派生解释视图。
它不是 schema、协议权威、CC-Panes runtime 状态、完成许可或交接本体。

```yaml
derived: true
authoritative: false
renderStatus: not-run
```

## Diagram brief

- **Title**: CC-Panes Method Layer v0.1 lifecycle: task → run → evidence → handoff
- **Question**: v0.1 中哪个 artifact 拥有目标/授权、launch-time snapshot、验证事实与下一任
  主控控制契约；reference adapter 和 controller 如何消费这些 artifact 但不改变其语义？
- **Reader**: `ccpanes-method-layer` 维护者、adapter/controller reviewer、后续 renderer。
- **Diagram type**: lifecycle flow + authority-boundary overlay.
- **Intended consumer path**: `docs/architecture/` 的派生图形 brief；可被后续 renderer 转为
  Mermaid/SVG/PNG，但 render output 必须继续附带本 receipt。

## Canonical sources

| Source | Commit / version | Referenced section | Load-bearing fact |
|---|---|---|---|
| `AGENTS.md` | `7710065da960b92c52ade1875740f97e4d93209e` | 范围、安全与授权、验收 | 本仓库只维护方法层协议、schema、模板、映射和本地脚本；不接入主仓库或用户配置 |
| `README.md` | `7710065da960b92c52ade1875740f97e4d93209e` | v0.1 协议边界、File-first reference adapter、Controller planner 与 executor | 四类 public JSON artifact 及验证入口 |
| `docs/workflow.md` | `7710065da960b92c52ade1875740f97e4d93209e` | 标准路径、Reference adapter 路径、Task/Run/Evidence/Finish Gate/Handoff | 生命周期顺序和 finish gate 检查 |
| `docs/integration-map.md` | `7710065da960b92c52ade1875740f97e4d93209e` | 稳定边界、CC-Panes 原生能力映射 | task/run/evidence/handoff 的 authority 与 CC-Panes 运行时边界 |
| `schemas/task.schema.json` | `7710065da960b92c52ade1875740f97e4d93209e` | title/description/required/properties | task 是目标、授权、baseline、acceptance、evidence contract 权威 |
| `schemas/run.schema.json` | `7710065da960b92c52ade1875740f97e4d93209e` | title/description/contract | run 是 task contract 与具体 runner session 的 launch-time binding |
| `schemas/evidence.schema.json` | `7710065da960b92c52ade1875740f97e4d93209e` | title/description/checks/driftCheck/gitStatus | evidence 记录 fresh verification、触达文件、检查、drift 和残余风险 |
| `schemas/handoff.schema.json` | `7710065da960b92c52ade1875740f97e4d93209e` | title/description/required sections | handoff 是九段式下一任主控控制契约 |
| `adapter/README.md` | `7710065da960b92c52ade1875740f97e4d93209e` | Intended command flow、Execution and method status | Adapter 命令产出 internal envelopes，不新增 public artifact type |
| `controller/README.md` | `7710065da960b92c52ade1875740f97e4d93209e` | Boundary、Execution gates | Controller plan/journal/result 是 internal transport artifacts |

## Authority map

| Concept | Canonical owner | Provider | Consumer | Source of truth | Diagram role |
|---|---|---|---|---|---|
| Task intent / authorization / baseline / acceptance / required evidence / stop conditions | `task` artifact + `schemas/task.schema.json` | Main controller | Adapter, run creator, finish gate, handoff creator | `task` JSON | Lifecycle start and authority contract |
| Run binding / runner session / workspace / launch-time contract snapshot | `run` artifact + `schemas/run.schema.json` | `prepare-launch` + `bind-launch` flow | Worker, finish-run, evidence/handoff creation | `run` JSON | Concrete execution binding |
| Fresh verification and drift facts | `evidence` artifact + `schemas/evidence.schema.json` | Worker or `finish-run` | Finish gate, leader report, handoff | `evidence` JSON | Proof bundle and drift record |
| Next controller control contract | `handoff` artifact + `schemas/handoff.schema.json` | `new-handoff` / current controller | Next controller | `handoff` JSON | Continuation boundary |
| Adapter envelopes | `adapter/schemas/*.internal.schema.json` | Reference adapter commands | Controller transport caller | Internal stdout envelope | Translation layer, not public protocol |
| Controller transport plan / journal / execution result | `controller/schemas/*.internal.schema.json` | Controller planner/executor | Explicit caller | Internal artifacts under project artifact root | Runtime bridge, not method protocol |
| CC-Panes `launch_task` and TaskBinding | Official CC-Panes runtime / caller transport | CC-Panes MCP | Adapter/controller | CC-Panes runtime state | External runtime boundary |
| Diagram artifact | This file only | Markdown brief | Maintainers / renderer | Canonical sources above | Derived explanatory projection |

## Lifecycle nodes for renderer

1. `Task intake`
   - owned by: main controller and `task` schema.
   - carries: objective, allowed paths, forbidden/conditional actions, Git baseline, acceptance,
     required evidence, stop conditions, lineage, `riskMode`.
   - invariant: `riskMode` is advisory-only and never grants permission.
2. `prepare-launch`
   - owned by: reference adapter.
   - consumes: validated `task`.
   - outputs: internal `launch_task` envelope and launch attempt.
   - invariant: file artifact lands before transport action.
3. `bind-launch`
   - owned by: reference adapter.
   - consumes: launch attempt + transport response.
   - outputs: `run` artifact and TaskBinding metadata patch.
   - invariant: `launch_task.taskId` and TaskBinding identity resolved by `sessionId` are distinct.
4. `Run execution`
   - owned by: runner/session side, while method contract is the `run` artifact.
   - carries: `run.contract`, the immutable launch-time snapshot.
   - invariant: task later changing must not silently rewrite existing `run.contract`.
5. `finish-run / evidence`
   - owned by: evidence schema plus adapter finish command.
   - consumes: `run`, TaskBinding snapshot, worker evidence or summary-only proof gaps.
   - outputs: `evidence`, TaskBinding patch and leader report envelope.
   - invariant: checks are actual pass/fail/blocked/not-run records; summary alone does not prove completion.
6. `Finish gate`
   - owned by: main controller policy described in `docs/workflow.md`.
   - checks: task objective vs run.contract, scope/files/acceptance drift, required checks, Git status,
     and integration authorization.
   - invariant: evidence does not authorize commit, merge, push, cleanup or completion by itself.
7. `new-handoff`
   - owned by: handoff schema and current controller.
   - consumes: task, run, evidence and handoff context.
   - outputs: nine-section `handoff`.
   - invariant: `nextOrder` describes gate dependency only; it does not expand current authorization.

## Edges for renderer

| Source | Destination | Flow type | Label | Meaning | Source reference |
|---|---|---|---|---|---|
| Main controller | `Task intake` | command/data | create task | Establish objective, authorization, baseline, acceptance and evidence contract | `schemas/task.schema.json`; `docs/workflow.md` §1 |
| `Task intake` | `prepare-launch` | data | validated task | Adapter validates task before producing launch envelope | `docs/workflow.md` Reference adapter path |
| `prepare-launch` | CC-Panes transport caller | command | launch envelope | stdout internal envelope; caller performs `launch_task` separately | `adapter/README.md` intended command flow |
| CC-Panes transport caller | `bind-launch` | data | launch response | Bind runtime launch response to method run | `adapter/README.md` commands |
| `bind-launch` | `Run execution` | data | run artifact | Concrete runner/session/workspace plus `run.contract` snapshot | `schemas/run.schema.json` |
| `Run execution` | `finish-run / evidence` | data | worker proof | Worker or finish command records outcome, files, checks, drift, Git status and risk | `schemas/evidence.schema.json` |
| `finish-run / evidence` | `Finish gate` | data | evidence artifact | Controller evaluates objective alignment, drift, required checks and authorized Git state | `docs/workflow.md` §4 |
| `Finish gate` | `new-handoff` | command/data | continuation needed | Handoff is generated only when the next controller needs a control contract | `docs/workflow.md` §5 |
| `new-handoff` | Next controller | data | nine-section handoff | Next controller receives required reading, facts, objective, auth, checks and stop conditions | `schemas/handoff.schema.json` |
| Adapter/controller | CC-Panes runtime | command/query | transport requests | Runtime effects occur only through explicit caller/live mode; method artifacts remain separate | `controller/README.md`; `docs/integration-map.md` |

## Success path

1. Main controller creates a schema-valid `task` with non-empty objective, authorization, acceptance,
   required evidence and stop conditions.
2. `prepare-launch` validates `task`, records launch attempt and emits a command-specific envelope.
3. The caller invokes `launch_task`; `bind-launch` consumes the response and writes a schema-valid `run`.
4. Worker executes against `run.contract`, not an unstated later task mutation.
5. `finish-run` writes `evidence` with required check entries and drift status.
6. Finish gate confirms objective/run alignment, scope/files/acceptance alignment, required checks, Git status,
   and whether commit/merge/push/cleanup still require user approval.
7. If continuation is needed, `new-handoff` emits a schema-valid nine-section `handoff`.

## Blocked / recovery path

1. If launch was prepared but not bound, `recover-launch` reads the launch attempt and returns a deterministic
   recovery action.
2. If TaskBinding method metadata is missing, recovery can be `repair-metadata`.
3. If methodLayer metadata conflicts on task, run, path, project or session identity, recovery becomes
   `manual-review`.
4. Controller live execution uses journal/readback gates; ambiguous `launch_task` or `report_to_leader`
   is not retried automatically.
5. Summary-only finish records blocked/failed evidence with explicit missing-proof records instead of treating
   a worker summary as a complete proof bundle.

## Trust and authority boundaries

- Boundary 1: public method artifacts (`task`, `run`, `evidence`, `handoff`) ↔ internal adapter envelopes.
- Boundary 2: internal adapter/controller artifacts ↔ CC-Panes MCP/runtime transport.
- Boundary 3: method artifact facts ↔ TaskBinding metadata projection.
- Boundary 4: evidence facts ↔ human or leader completion decision.
- Boundary 5: handoff nextOrder ↔ future task authorization.

## Unresolved assumptions and source gaps

- This brief does not execute adapter/controller commands and does not inspect live CC-Panes runtime.
- This brief does not change public v0.1 schema, runtime transport behavior, TaskBinding state, user config
  or project `.ccpanes-method/` policy.
- If future protocol versions add `closure`, `changeDisposition`, UI projection, automatic profile selection,
  merge/push/cleanup or a fifth public artifact, regenerate this brief from the new accepted sources.

## Forbidden claims

- Do not claim this diagram is a public schema.
- Do not claim `riskMode` grants authority or selects a profile automatically.
- Do not claim `evidence.outcome=completed` alone authorizes merge, push, cleanup or task closure.
- Do not claim controller plans, journals or adapter envelopes are public method artifacts.
- Do not claim this brief proves live CC-Panes launch, TaskBinding mutation or leader notification.

## Sensitive-data exclusions

- CC-Panes API base URL and token values.
- Plaintext Session IDs, TaskBinding IDs, prompt bodies, worker output, user project content and private paths
  beyond source-backed repository-relative examples.

## Receipt

### Identity

- Diagram title: `CC-Panes Method Layer v0.1 lifecycle: task → run → evidence → handoff`
- Artifact id: `ccpanes-method-layer-diagram-lifecycle-pilot-20260815`
- Consumer repository/path: `D:\ccpanes-method-layer\docs\architecture\diagram-v0.1-lifecycle.md`
- Diagram question: v0.1 artifact 生命周期和 adapter/controller 边界如何分工？
- Diagram type: lifecycle flow + authority boundary overlay
- Generated date: 2026-08-15
- Reviewed date: 2026-08-15

### Renderer / provider

- Provider: none
- Provider URL: none
- Provider HEAD: none
- Provider version: none
- Render status: not-run
- Check status: pass
- Render notes: Renderer-neutral Markdown brief only; no PNG/SVG/HTML output produced and no renderer installed.

### Brief and output

- Brief/input reference: this file
- Output path: none
- Output SHA-256: none
- Derived: `true`
- Authoritative: `false`

### Reviewer / check notes

- Reviewer: Codex main controller
- Source check notes:
  - Re-read `AGENTS.md`, `README.md`, `docs/workflow.md`, `docs/integration-map.md`,
    public schemas, `adapter/README.md` and `controller/README.md` before writing this brief.
- Diagram quality notes:
  - The brief separates public artifacts from internal envelopes and runtime transport, and keeps evidence/handoff
    from becoming completion or authorization shortcuts.
- Residual risk:
  - Documentation-only projection can become stale if v0.1 schemas, adapter/controller contracts or future protocol
    versions change.

### Regeneration instructions

1. Re-read the canonical source references above.
2. Rebuild lifecycle nodes and edges from the current public schema and workflow docs.
3. Preserve `derived: true` and `authoritative: false`.
4. Render only with an already-approved provider; otherwise keep `renderStatus: not-run`.
5. Recompute any output SHA-256 if a rendered file is produced later.

