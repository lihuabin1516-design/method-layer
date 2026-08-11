# CC-Panes Method Layer Handoff

## 1. Role, task id, current result

- Role: next `ccpanes-method-layer` maintenance controller.
- Task ID: `ccpanes-prompt-pack-ai-coding-java-intake`.
- Current result: the locked `ai-coding-prompt-java` donor has been recorded and independently rewritten into the first `java-enterprise` Prompt Pack `0.1.0`, with internal schema, technology profile, five Prompts, thirteen deterministic eval fixtures, donor-window fingerprints, validation integration, and repository-boundary ADR. PaneForge `PF-FUSION-007` has also implemented a disabled-by-default, read-only metadata review consumer for these hash-bound artifacts in its separate task worktree.

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
10. `docs/plans/2026-08-10-ai-coding-prompt-java-absorption.md`
11. `prompt-packs/java-enterprise/README.md`
12. `prompt-packs/java-enterprise/pack.json`
13. `schemas/prompt-pack.internal.schema.json`
14. `tests/prompt-pack/run.ps1`

## 3. Current baseline, facts, and evidence

- Main repository: `D:\ccpanes-method-layer`
- Task worktree: `D:\ccpanes-method-layer-worktrees\prompt-pack-java-intake`
- Branch: `codex/prompt-pack-java-intake`
- Baseline HEAD: `d9abbb8b0f5cfa68448a3d7bf673bbd00ab72d47`
- Remote: `origin -> https://github.com/lihuabin1516-design/ccpanes-method-layer.git`
- On `2026-08-11`, the user explicitly authorized committing and pushing this task to `origin`. Merge to `main` and worktree cleanup remain outside the authorization.
- Pre-change Full validation passed:
  - adapter: 23
  - controller planner: 16
  - controller executor: 16
- Prompt Pack focused RED was observed because the internal schema did not exist.
- Focused GREEN currently reports 11 Prompt Pack tests.
- Current Fast and Full validation pass; Full includes Prompt Pack 11, adapter 23, controller planner 16, and controller executor 16.
- Task hook phase `verify` was recorded before removing the transient untracked hook files from both worktrees.
- Donor repository: `https://github.com/jwangkun/ai-coding-prompt-java.git`
- Donor branch and locked commit: `main` at `1959b508696c7d92d550c152c735f49ed6dafbe2`
- Donor commit date: `2025-11-25`
- Query date: `2026-08-10`
- Donor tree: 28 Markdown files.
- License evidence: README claims MIT, but the locked tree has no license file and no recognized SPDX record.
- Public v0.1 artifacts remain `task`, `run`, `evidence`, and `handoff`; their schemas were not changed.
- `.gitattributes` marks all ten PaneForge source-locked artifacts `-text`, preventing Git from normalizing mixed LF/CRLF bytes and changing their reviewed SHA-256 values during commit or checkout.
- Downstream preview evidence:
  - PaneForge branch: `codex/pf-fusion-007-readonly-review-seam`
  - Feature flag: `PANEFORGE_PROMPT_PACK_REVIEW_ENABLED`
  - Input: caller-supplied source-lock JSON and sanitized catalog JSON only
  - Behavior: exact source-lock UTF-8 byte hash plus manifest/profile/eval/five-Prompt reference checks
  - Boundaries: no Prompt execution/composition, Skill generation/install, method-layer write, persistence, filesystem path read, or host-config mutation
  - Current source-state caveat: the PaneForge lock still classifies this pack as `local-uncommitted-reviewed` above base commit `d9abbb8b0f5cfa68448a3d7bf673bbd00ab72d47`.

## 4. Single objective for the next round

After this Prompt Pack is committed and pushed, replace PaneForge's `local-uncommitted-reviewed` source state with an explicit method-layer commit lock, preserving the same ten reviewed artifact byte/hash records, then rerun the PF-FUSION-007 review gates.

This order is a separate task and does not authorize work from this handoff.

## 5. Authorization, forbidden items, conditional authorization

Current repository maintenance may:

- read and validate the Prompt Pack source artifacts;
- update this repository under a new explicit task;
- run local schema, Prompt Pack, adapter, planner, and executor checks.

Without a new explicit task:

- do not modify `D:\cc-pane`, `D:\codex-cc-pane`, `D:\cc-pane\tool\skills`, PaneForge, or user configuration;
- do not install dependencies;
- do not publish generated Skills;
- do not merge, push, commit, clean worktrees, or change remote state;
- do not change public v0.1 artifact semantics;
- do not vendor donor Prompt files or substantial donor text.

The `2026-08-11` commit/push authorization applies only to publishing the current `codex/prompt-pack-java-intake` task branch. Future remote actions require a new explicit task.

## 6. Execution order and agent boundaries

For future Prompt Pack maintenance:

1. record authoritative Git/worktree status;
2. read the source lock, design, ADR, manifest, profile, and evals;
3. update deterministic fixtures before changing composition or validation;
4. change the internal owner contract before consumers or projections;
5. run focused Prompt Pack tests;
6. run Fast and Full validation;
7. inspect the complete diff and status;
8. update this handoff only with fresh evidence.

Read-only workers may review donor diffs, schema compatibility, Prompt content, or eval coverage. Writing workers need disjoint file scopes inside the task worktree. The controller retains schema/version decisions and final validation.

## 7. Required checks and acceptance assertions

Required:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\prompt-pack\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Full
python -m json.tool schemas\task.schema.json > $null
python -m json.tool schemas\run.schema.json > $null
python -m json.tool schemas\evidence.schema.json > $null
python -m json.tool schemas\handoff.schema.json > $null
python -m json.tool schemas\prompt-pack.internal.schema.json > $null
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
- Public v0.1 schemas and artifact semantics remain unchanged.
- No unexplained out-of-scope tracked or untracked changes exist.

## 8. Audit, fuse, and stop conditions

- Inspect task diff and status after write batches.
- Treat missing source lock, duplicate Prompt identity, undeclared marker, invalid schema, missing project fact, or authorization expansion as fail-closed.
- Preserve historical donor and validation evidence.
- Stop before public schema change, other-repository write, user-configuration write, Skill publication, PaneForge change, any remote Git action outside the current branch publication, or large donor-copy requirement.
- Stop after three repair cycles for the same Full-validation root cause.

## 9. Artifacts, delivery, and next order

Primary new artifacts:

- `docs/upstreams/ai-coding-prompt-java.md`
- `docs/specs/2026-08-10-prompt-pack-v0.1-design.md`
- `docs/plans/2026-08-10-ai-coding-prompt-java-absorption.md`
- `docs/architecture/adr-2026-08-10-prompt-pack-repository-boundary.md`
- `schemas/prompt-pack.internal.schema.json`
- `prompt-packs/java-enterprise/**`
- `tests/prompt-pack/run.ps1`

Validation owner:

- `scripts/validate.ps1`

Next order:

> Replace PaneForge's `local-uncommitted-reviewed` Prompt Pack source state with an explicit commit lock for the published method-layer artifacts, preserve the reviewed byte/hash set, and rerun PF-FUSION-007 verification without adding execution, composition, persistence, source mutation, or host mutation authority.

Do not execute that order as part of the current task.
