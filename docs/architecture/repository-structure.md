# Repository Structure

本文档是 `D:\ccpanes-method-layer` 的长期维护目录架构说明。它描述每个目录的职责、允许的变更类型和维护注意事项。

## 总览

```text
D:\ccpanes-method-layer
├── AGENTS.md
├── HANDOFF.md
├── README.md
├── tsc.md
├── schemas/
├── prompt-packs/
├── examples/
├── templates/
├── companion/
├── adapter/
├── controller/
├── scripts/
│   ├── companion/
│   ├── adapter/
│   └── controller/
├── tests/
│   ├── adapter/
│   ├── prompt-pack/
│   ├── companion/
│   ├── controller/
│   └── controller-executor/
└── docs/
    ├── architecture/
    ├── maintenance/
    ├── plans/
    ├── specs/
    └── upstreams/
```

Ignored local/runtime paths:

```text
.ccpanes/
.ccpanes-method/
artifacts/local/
tests/.tmp/
CLAUDE.md
```

## Root files

| Path | Responsibility | Maintenance notes |
| --- | --- | --- |
| `README.md` | Human entrypoint and quick validation guide | Keep reading order and command list aligned with actual files. |
| `HANDOFF.md` | Current top-level handoff for the next controller | Update at major baseline changes, push/release events, or integration milestones. |
| `AGENTS.md` | Project operating rules | Keep concise; do not duplicate every long-form runbook. |
| `tsc.md` | Original task / prompt context | Treat as historical context unless a later task explicitly updates it. |
| `.gitignore` | Runtime and local scratch exclusions | Keep `.ccpanes/`, `.ccpanes-method/`, `artifacts/local/`, `tests/.tmp/` ignored. |
| `.gitattributes` | Exact-byte preservation for source-locked Prompt Pack artifacts | Keep the ten reviewed schema/manifest/profile/eval/Prompt paths marked `-text`; changing this requires source-lock regeneration and downstream review. |

## Public protocol layer

```text
schemas/
├── task.schema.json
├── run.schema.json
├── evidence.schema.json
└── handoff.schema.json
```

These four files are the v0.1 public protocol surface.

Rules:

- Preserve `protocolVersion: "0.1"` semantics.
- Preserve artifact boundaries: `task`, `run`, `evidence`, `handoff`.
- Any required-field or meaning change needs a plan in `docs/plans/`.
- Add valid and invalid examples for every schema behavior change.
- Keep `additionalProperties: false` intentional and reviewed.

Internal Prompt Pack contracts live beside the public schemas:

```text
schemas/
└── prompt-pack.internal.schema.json
```

The internal schema validates Prompt Pack manifests, technology profiles, and deterministic eval suites. It does not add a public artifact type or change `protocolVersion: "0.1"`.

## Prompt Packs

```text
prompt-packs/
└── java-enterprise/
    ├── pack.json
    ├── README.md
    ├── profiles/
    ├── prompts/
    └── evals/
```

Purpose:

- Own versioned Prompt semantics, composition, source provenance, and eval fixtures.
- Separate common engineering guidance, work-stage rules, technology profiles, project facts, output contracts, and acceptance assertions.
- Provide source artifacts for later generated Skill projections.
- Keep the locked donor comparison as hashes only; do not vendor donor Prompt text.

Maintenance:

- Keep task authorization and project facts outside the pack.
- Require exact source commit and idea-level rewrite records.
- Add deterministic fixtures before changing composition or validation behavior.
- Preserve the exact committed bytes of source-locked artifacts; Git line-ending normalization must not change reviewed SHA-256 values.
- Do not persist full Prompt bodies in launch attempts, journals, or evidence.
- Reassess an independent repository only through `docs/architecture/adr-2026-08-10-prompt-pack-repository-boundary.md`.

## Examples

```text
examples/
├── README.md
├── valid/
└── invalid/
```

Purpose:

- Demonstrate accepted v0.1 artifact shapes.
- Pin known rejected cases.
- Serve as regression coverage for public schemas.

Maintenance:

- Every new protocol feature needs at least one focused valid example or fixture.
- Every fixed schema bug should gain one invalid example when practical.
- Examples should stay small and readable; integration-scale data belongs in tests.

## Templates

```text
templates/
├── controller-handoff.md
├── run-evidence.json
└── task.md
```

Purpose:

- Provide human-startable task / evidence / handoff scaffolds.
- Avoid requiring users to remember the full schema by hand.

Maintenance:

- Template JSON must remain schema-valid.
- Markdown templates should match current terminology in `docs/workflow.md`.

## Official CC-Panes external companion

```text
companion/
├── README.md
└── schemas/
    ├── official-companion-request.internal.schema.json
    └── official-companion-guidance.internal.schema.json
```

Purpose:

- Let `ccpanes-method-layer` assist the official `cc-panes.exe` from outside the runtime.
- Validate caller-supplied task context and return metadata-only Prompt Pack guidance.
- Keep official CC-Panes executable, profiles, hooks, plugins, MCP registration, user configuration, and host runtime untouched.

Maintenance:

- Companion schemas are internal contracts, not public v0.1 artifacts.
- Output must keep `launchesOfficialExe`, `writesOfficialConfig`, and `mutatesHost` false.
- Output may include Prompt identity/version/output-contract metadata, but not Prompt bodies.
- Changes to selection behavior require fixtures in `tests/companion/`.

## Adapter contract layer

```text
adapter/
├── README.md
└── schemas/
    ├── launch-attempt.internal.schema.json
    ├── launch-response.internal.schema.json
    ├── task-binding.internal.schema.json
    ├── prepare-launch-envelope.internal.schema.json
    ├── bind-launch-envelope.internal.schema.json
    ├── finish-run-envelope.internal.schema.json
    ├── handoff-envelope.internal.schema.json
    ├── handoff-context.internal.schema.json
    └── recovery-envelope.internal.schema.json
```

Purpose:

- Define internal adapter/controller envelopes.
- Keep runtime transport separate from public method artifacts.

Maintenance:

- Internal schema changes should keep controller planner/executor tests aligned.
- `launch_task.taskId`, PTY `sessionId`, TaskBinding `id`, method `taskId`, and `runId` stay distinct.
- Do not put full prompt bodies into long-lived recovery artifacts unless a plan explicitly accepts that tradeoff.

## Controller contract layer

```text
controller/
├── README.md
└── schemas/
    ├── transport-plan.internal.schema.json
    ├── execution-journal-entry.internal.schema.json
    └── execution-result.internal.schema.json
```

Purpose:

- Plan MCP transport from validated adapter envelopes.
- Execute plans with project-local journal and response evidence.

Maintenance:

- Planner output must stay deterministic enough for review.
- Executor must validate plan semantics beyond JSON Schema.
- Journal entries must stay append-only and hash-verifiable.
- Non-idempotent operations (`launch_task`, `report_to_leader`) require strict replay gates.

## Scripts

```text
scripts/
├── validate.ps1
├── companion/
│   ├── MethodLayer.Companion.psm1
│   └── new-guidance.ps1
├── adapter/
│   ├── MethodLayer.Adapter.psm1
│   ├── prepare-launch.ps1
│   ├── bind-launch.ps1
│   ├── finish-run.ps1
│   ├── new-handoff.ps1
│   └── recover-launch.ps1
└── controller/
    ├── MethodLayer.Controller.psm1
    ├── MethodLayer.Executor.psm1
    ├── CcPanesMcp.Transport.psm1
    ├── plan-transport.ps1
    └── execute-transport.ps1
```

### `scripts/validate.ps1`

Main local gate. It checks:

- JSON syntax.
- protocol examples.
- templates.
- PowerShell parser.
- Prompt Pack tests.
- Official CC-Panes external companion tests.
- adapter tests.
- controller planner tests.
- controller executor tests.

### `scripts/adapter/*`

File-first artifact and envelope generation.

Core invariants:

- path containment;
- reparse/junction rejection;
- create-once and CAS writes;
- task lock;
- evidence-first finish;
- command-specific stdout schema validation.

### `scripts/controller/*`

Plan and execute transport.

Core invariants:

- validated envelope -> ordered plan;
- metadata sibling preservation;
- TaskBinding preconditions;
- readback assertions;
- response hash;
- replay safety;
- loopback-only MCP endpoint.

### `scripts/companion/*`

External guidance for the official `cc-panes.exe`.

Core invariants:

- request and guidance schema validation;
- read-only Prompt Pack metadata consumption;
- no official executable launch;
- no official/user configuration mutation;
- no Prompt execution or runtime composition;
- metadata-only guidance output.

## Tests

```text
tests/
├── adapter/
│   ├── TestHarness.ps1
│   ├── run.ps1
│   └── fixtures/
├── prompt-pack/
│   └── run.ps1
├── companion/
│   ├── run.ps1
│   └── fixtures/
├── controller/
│   ├── run.ps1
│   └── fixtures/
└── controller-executor/
    └── run.ps1
```

Current expected counts:

| Suite | Command | Expected |
| --- | --- | --- |
| Adapter | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\adapter\run.ps1` | 23 pass |
| Prompt Pack | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\prompt-pack\run.ps1` | 11 pass |
| Official Companion | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\companion\run.ps1` | 6 pass |
| Controller planner | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\controller\run.ps1` | 16 pass |
| Controller executor | `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\controller-executor\run.ps1` | 16 pass |

Maintenance:

- Add tests before changing behavior.
- Keep Prompt Pack fixtures deterministic; LLM judging is optional and non-gating.
- Keep Companion fixtures synthetic and metadata-only.
- Keep fixture identities obvious and synthetic.
- Keep `tests/.tmp` empty after successful runs.
- Use injected transport for mutation tests; live MCP checks should be read-only unless the task states otherwise.

## Docs

```text
docs/
├── charter.md
├── workflow.md
├── integration-map.md
├── ccpanes-mcp-transport-runbook.md
├── architecture/
├── maintenance/
├── plans/
├── specs/
└── upstreams/
```

### Stable docs

| Path | Role |
| --- | --- |
| `docs/charter.md` | Purpose, boundaries, non-goals |
| `docs/workflow.md` | Artifact lifecycle |
| `docs/integration-map.md` | Mapping from upstream ideas and CC-Panes primitives |
| `docs/ccpanes-mcp-transport-runbook.md` | Transport ordering and failure rules |

### `docs/architecture/`

Repository architecture and ownership map. Keep this directory up to date when directories or core roles change.

### `docs/maintenance/`

Long-lived handoffs, governance baseline, license/provenance decision, maintenance playbooks, release checklists, absorption procedure. This is the first place a new long-term maintenance conversation should read after `HANDOFF.md`.

### `docs/plans/`

Historical and proposed implementation plans.

Rules:

- Use dated filenames.
- State objective, scope, excluded items, validation, and rollback.
- Do not delete old plans just because implementation finished; they are audit history.

### `docs/specs/`

Detailed designs. Use for durable architecture decisions and version proposals.

### `docs/upstreams/`

External method-layer sources.

For each source, record:

- URL;
- read date;
- version/commit/tag;
- capabilities to absorb;
- mappings to current artifacts;
- discarded assumptions;
- required tests.

## Upstream absorption workflow

When absorbing another project's method-layer ideas:

1. Create or update `docs/upstreams/<source>.md`.
2. Add a dated plan under `docs/plans/`.
3. Map concepts into one of:
   - existing v0.1 field;
   - adapter/controller internal behavior;
   - documentation-only guidance;
   - future candidate.
4. Add examples/tests before implementation changes.
5. Keep public schema changes smallest-first.
6. Run full validation.
7. Update `docs/integration-map.md`.
8. Update `HANDOFF.md` with the new baseline.

## Release / push checklist

Before commit or push:

```powershell
git status --branch --short
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
git diff --check
git log --oneline --decorate --max-count=3
```

After push:

```powershell
git status --branch --short
git ls-remote origin refs/heads/main
```

Expected clean state:

```text
## main...origin/main
```
