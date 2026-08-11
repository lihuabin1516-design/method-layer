# ai-coding-prompt-java Absorption Implementation Plan

> **For agentic workers:** Execute only in the linked task worktree. Commit, push, merge, cleanup, other-repository writes, user configuration, and runtime integration are outside this plan.

**Goal:** Intake the locked donor as an external corpus and deliver `java-enterprise` Prompt Pack `0.1.0` with internal contracts and deterministic validation.

**Architecture:** Keep Prompt Pack semantics in `ccpanes-method-layer`. Use one internal JSON Schema for manifest, technology profile, and eval suite; store independently written Prompt bodies under the pack; compose by stage, change type, and risk without changing task authorization.

**Tech Stack:** Markdown, JSON Schema draft 2020-12, PowerShell 7 `Test-Json`, Python standard-library `json.tool`, Git read-only donor inspection.

---

### Task 1: Rebuild baselines and lock donor evidence

**Files:**
- Create: `docs/upstreams/ai-coding-prompt-java.md`

- [x] Record repository root, branch, HEAD, status, and remotes.
- [x] Create `codex/prompt-pack-java-intake` in a linked worktree.
- [x] Run the pre-change Full validation.
- [x] Verify donor `main`, locked commit, tree, Java-related categories, and license-file absence.
- [x] Classify observed facts, adopted ideas, rewrites, discarded content, and synchronization policy.

### Task 2: Add the failing Prompt Pack gate

**Files:**
- Create: `tests/prompt-pack/run.ps1`

- [x] Add a focused test runner that requires the internal schema, pack, profile, and eval suite.
- [x] Run it before implementation.
- [x] Confirm RED because `schemas/prompt-pack.internal.schema.json` is absent.

Expected RED evidence:

```text
Missing artifact: schemas\prompt-pack.internal.schema.json
```

### Task 3: Implement internal contracts and pack metadata

**Files:**
- Create: `schemas/prompt-pack.internal.schema.json`
- Create: `prompt-packs/java-enterprise/pack.json`
- Create: `prompt-packs/java-enterprise/profiles/spring-enterprise.json`

- [x] Define strict discriminated schemas for pack, profile, and eval artifacts.
- [x] Keep `task`, `run`, `evidence`, and `handoff` as the exact public artifact list.
- [x] Define Prompt identity, SemVer, source provenance, required inputs, output contract, and acceptance assertions.
- [x] Define deterministic stage/change/risk composition and stop rules.
- [x] Require concrete Java/Spring versions from project facts.

### Task 4: Add five independently written Prompts

**Files:**
- Create: `prompt-packs/java-enterprise/prompts/requirement-review.md`
- Create: `prompt-packs/java-enterprise/prompts/solution-design.md`
- Create: `prompt-packs/java-enterprise/prompts/persistence-design.md`
- Create: `prompt-packs/java-enterprise/prompts/security-review.md`
- Create: `prompt-packs/java-enterprise/prompts/test-generation.md`

- [x] Replace donor role narratives with bounded inputs, method, output, and evidence requirements.
- [x] Use declared input markers and reject undeclared markers.
- [x] Remove fixed names, versions, products, deployment recipes, and unsupported performance targets.
- [x] Keep implementation generation outside the default output contract.

### Task 5: Add deterministic eval fixtures

**Files:**
- Create: `prompt-packs/java-enterprise/evals/cases.json`
- Create: `prompt-packs/java-enterprise/evals/README.md`
- Create: `prompt-packs/java-enterprise/README.md`

- [x] Add all ten required scenarios plus stage, output-contract, and profile-fact regressions with exact expected decisions.
- [x] Verify Prompt selection order and violations.
- [x] Verify unresolved rendered markers, authorization expansion, missing assertions, and fixed-version assumptions.
- [x] Run the focused suite and confirm GREEN with eleven tests.

### Task 6: Integrate repository validation

**Files:**
- Modify: `scripts/validate.ps1`

- [x] Include all Prompt Pack JSON in syntax validation.
- [x] Run Prompt Pack tests in both Fast and Full modes.
- [x] Keep Fast limited to structural/schema/Prompt Pack/parser checks.
- [x] Keep Full as Fast plus adapter, planner, and executor suites.

### Task 7: Record architecture and repository boundaries

**Files:**
- Create: `docs/specs/2026-08-10-prompt-pack-v0.1-design.md`
- Create: `docs/architecture/adr-2026-08-10-prompt-pack-repository-boundary.md`
- Modify: `docs/architecture/repository-structure.md`
- Modify: `docs/integration-map.md`
- Modify: `README.md`
- Modify: `HANDOFF.md`

- [x] Document canonical ownership, components, flows, failure behavior, and recovery.
- [x] Record the independent-repository split gates and rejected alternatives.
- [x] Add Prompt Pack reading and validation entry points.
- [x] Record the linked worktree baseline and the single follow-up task.

### Task 8: Verify and audit

**Files:**
- Inspect the complete task diff and status.

- [x] Run `scripts\validate.ps1 -Mode Fast`.
- [x] Run `scripts\validate.ps1 -Mode Full`.
- [x] Run JSON syntax and schema checks for the new internal artifacts.
- [x] Run the four required public-schema syntax checks.
- [x] Run `git diff --check`.
- [x] Confirm no public v0.1 schema changed.
- [x] Confirm the main worktree has no tracked changes.
- [x] Set task hook phase to `verify` and record final status.
