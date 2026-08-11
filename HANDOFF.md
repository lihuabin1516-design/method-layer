# CC-Panes Method Layer Handoff

## 1. Role, task id, current result

- Role: next `ccpanes-method-layer` maintenance controller.
- Task ID: `ccpanes-official-exe-external-companion`.
- Current result: the published `java-enterprise` Prompt Pack `0.1.0` is now exposed through a repository-local, file-first Official CC-Panes external Companion. The Companion validates caller-supplied task context, selects Prompt metadata deterministically, reports missing project facts or authorization expansion, and emits metadata-only guidance for manual copy or separately approved transport into official `cc-panes.exe`. It does not launch official CC-Panes, write official/user configuration, mutate host files, execute or compose Prompts, or persist Prompt bodies.

## 2. Required reading

1. `AGENTS.md`
2. `README.md`
3. `HANDOFF.md`
4. `docs/charter.md`
5. `docs/architecture/repository-structure.md`
6. `docs/architecture/adr-2026-08-10-prompt-pack-repository-boundary.md`
7. `docs/integration-map.md`
8. `docs/upstreams/ai-coding-prompt-java.md`
9. `docs/specs/2026-08-10-prompt-pack-v0.1-design.md`
10. `docs/specs/2026-08-11-official-ccpanes-companion-design.md`
11. `docs/plans/2026-08-10-ai-coding-prompt-java-absorption.md`
12. `docs/plans/2026-08-11-official-ccpanes-companion.md`
13. `prompt-packs/java-enterprise/README.md`
14. `prompt-packs/java-enterprise/pack.json`
15. `schemas/prompt-pack.internal.schema.json`
16. `companion/README.md`
17. `companion/schemas/official-companion-request.internal.schema.json`
18. `companion/schemas/official-companion-guidance.internal.schema.json`
19. `scripts/companion/MethodLayer.Companion.psm1`
20. `scripts/companion/new-guidance.ps1`
21. `tests/prompt-pack/run.ps1`
22. `tests/companion/run.ps1`

## 3. Current baseline, facts, and evidence

- Repository: `D:\ccpanes-method-layer`
- Branch: `codex/official-ccpanes-companion`
- Baseline HEAD: `921725ec19930687e247841fdfa90bbbf3bf704b`
- Remote: `origin -> https://github.com/lihuabin1516-design/ccpanes-method-layer.git`
- Current task has no commit, push, merge, cleanup, or official runtime mutation authorization.
- The previous Prompt Pack branch `codex/prompt-pack-java-intake` is published at `921725ec19930687e247841fdfa90bbbf3bf704b`.
- Donor repository: `https://github.com/jwangkun/ai-coding-prompt-java.git`
- Donor branch and locked commit: `main` at `1959b508696c7d92d550c152c735f49ed6dafbe2`
- Donor commit date: `2025-11-25`
- License evidence: README claims MIT, but the locked tree has no license file and no recognized SPDX record.
- Public v0.1 artifacts remain `task`, `run`, `evidence`, and `handoff`; their schemas were not changed by this Companion slice.
- `.gitattributes` still marks all ten Prompt Pack source-locked artifacts `-text`.
- Companion focused RED was observed because `companion/schemas/*` and `scripts/companion/new-guidance.ps1` were absent.
- Companion focused GREEN reports 6 tests.
- Fast validation passed after adding Companion schemas/fixtures to JSON syntax checks and running Prompt Pack + Companion suites.
- Full validation passed after adding Companion to the gate; Full includes Prompt Pack 11, Companion 6, adapter 23, controller planner 16, and controller executor 16.
- `python -m json.tool` passed for public schemas, Prompt Pack internal schema, and both Companion schemas.
- Sample guidance for `tests\companion\fixtures\design-request.json` returned `decision=ready-to-copy`, selected `requirement-review,solution-design`, and kept `launchesOfficialExe=false`, `writesOfficialConfig=false`, `mutatesHost=false`.
- `git diff --check` passed; latest status has only intended Companion/documentation/validator changes and untracked new Companion artifacts.
- External Companion artifacts:
  - Request schema: `companion/schemas/official-companion-request.internal.schema.json`
  - Guidance schema: `companion/schemas/official-companion-guidance.internal.schema.json`
  - Command: `scripts/companion/new-guidance.ps1`
  - Module: `scripts/companion/MethodLayer.Companion.psm1`
  - Tests/fixtures: `tests/companion/**`
- External Companion behavior:
  - Reads caller-supplied request JSON.
  - Reads Prompt Pack manifest/profile metadata from this repository.
  - Selects Prompt IDs via stage/changeType/risk rules.
  - Blocks requested actions outside authorization.
  - Blocks missing required project facts.
  - Emits metadata-only guidance with no Prompt bodies.
- External Companion boundaries:
  - no official executable launch;
  - no official/user config write;
  - no profile, hook, plugin, MCP, or host mutation;
  - no Prompt execution;
  - no runtime Prompt composition;
  - no Prompt Pack source mutation;
  - no Prompt body persistence.

## 4. Single objective for the next round

Finish validating the Official CC-Panes external Companion as a local method-layer sidecar, then decide whether to commit/push this branch. Any direct official CC-Panes runtime integration remains a separate task with explicit target surface and mutation authorization.

## 5. Authorization, forbidden items, conditional authorization

Current repository maintenance may:

- modify only `D:\ccpanes-method-layer` files required by the Companion task;
- read and validate Prompt Pack source artifacts;
- read and validate Companion request/guidance schemas and fixtures;
- run local schema, Prompt Pack, Companion, adapter, planner, and executor checks.

Without a new explicit task:

- do not modify `D:\cc-pane`, PaneForge, official CC-Panes source, or any user-global configuration;
- do not launch or mutate official `cc-panes.exe` from this repository;
- do not install dependencies;
- do not publish generated Skills;
- do not merge, push, commit, clean worktrees, or change remote state;
- do not change public v0.1 artifact semantics;
- do not vendor donor Prompt files or substantial donor text.

The earlier `2026-08-11` commit/push authorization applied only to publishing `codex/prompt-pack-java-intake`. It does not apply to `codex/official-ccpanes-companion`.

## 6. Execution order and agent boundaries

For future Prompt Pack or Companion maintenance:

1. record authoritative Git/worktree status;
2. read the source lock, design, ADR, manifest, profile, evals, and Companion schemas;
3. update deterministic fixtures before changing composition, guidance, or validation;
4. change the internal owner contract before consumers or projections;
5. run focused Prompt Pack and Companion tests when either surface is touched;
6. run Fast and Full validation;
7. inspect the complete diff and status;
8. update this handoff only with fresh evidence.

Read-only workers may review donor diffs, schema compatibility, Prompt content, eval coverage, or Companion output shape. Writing workers need disjoint file scopes inside the task worktree. The controller retains schema/version decisions and final validation.

## 7. Required checks and acceptance assertions

Required:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\prompt-pack\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\companion\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Full
python -m json.tool schemas\task.schema.json > $null
python -m json.tool schemas\run.schema.json > $null
python -m json.tool schemas\evidence.schema.json > $null
python -m json.tool schemas\handoff.schema.json > $null
python -m json.tool schemas\prompt-pack.internal.schema.json > $null
python -m json.tool companion\schemas\official-companion-request.internal.schema.json > $null
python -m json.tool companion\schemas\official-companion-guidance.internal.schema.json > $null
git diff --check
git status --short --branch
```

Assertions:

- Prompt Pack manifest, profile, and eval suite satisfy the internal schema.
- Prompt identity/version pairs are unique.
- Required inputs, output contracts, and acceptance assertions are non-empty.
- Declared input markers match Prompt metadata.
- Provenance points to the locked donor commit.
- Donor-specific fixed implementation assumptions are absent from local Prompts.
- Thirteen eval scenarios have exact expected results.
- Companion request/guidance schemas and fixtures remain schema-valid.
- Companion output keeps official target mutation fields false and contains no Prompt bodies.
- Public v0.1 schemas and artifact semantics remain unchanged.
- No unexplained out-of-scope tracked or untracked changes exist.

## 8. Audit, fuse, and stop conditions

- Inspect task diff and status after write batches.
- Treat missing source lock, duplicate Prompt identity, undeclared marker, invalid schema, missing project fact, authorization expansion, or host-mutation field as fail-closed.
- Preserve historical donor and validation evidence.
- Stop before public schema change, other-repository write, official/user-configuration write, Skill publication, PaneForge change, any remote Git action, official runtime mutation, or large donor-copy requirement.
- Stop after three repair cycles for the same Full-validation root cause.

## 9. Artifacts, delivery, and next order

Primary artifacts:

- `docs/upstreams/ai-coding-prompt-java.md`
- `docs/specs/2026-08-10-prompt-pack-v0.1-design.md`
- `docs/specs/2026-08-11-official-ccpanes-companion-design.md`
- `docs/plans/2026-08-10-ai-coding-prompt-java-absorption.md`
- `docs/plans/2026-08-11-official-ccpanes-companion.md`
- `docs/architecture/adr-2026-08-10-prompt-pack-repository-boundary.md`
- `schemas/prompt-pack.internal.schema.json`
- `prompt-packs/java-enterprise/**`
- `tests/prompt-pack/run.ps1`
- `companion/README.md`
- `companion/schemas/official-companion-request.internal.schema.json`
- `companion/schemas/official-companion-guidance.internal.schema.json`
- `scripts/companion/MethodLayer.Companion.psm1`
- `scripts/companion/new-guidance.ps1`
- `tests/companion/**`

Validation owner:

- `scripts/validate.ps1`

Next order:

> After local validation, ask whether to commit/push `codex/official-ccpanes-companion`. A later task may add an already-approved transport surface, but the current Companion remains manual-copy / metadata-only.

Do not execute remote publishing or official runtime integration as part of the current task.
