# Codex Startup Autostart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex App and Codex CLI enter the external method-layer workflow automatically on repository startup, with a local ignored stop switch.

**Architecture:** Keep the bootstrap entirely project-local. A `.codex` SessionStart hook loads a tiny script that emits workflow entry context, while an ignored `.ccpanes-method/v0.1/runtime/autostart.disabled` file or `CCPANES_METHOD_LAYER_AUTOSTART=0` suppresses it. Update docs and validation so the startup behavior is visible and testable.

**Tech Stack:** TOML config, Python bootstrap script, PowerShell helper and tests, existing repo validation.

---

### Task 1: Add the startup hook surface

**Files:**
- Create: `.codex/config.toml`
- Create: `.codex/hooks/session-start.py`

- [ ] **Step 1: Define the SessionStart hook in `.codex/config.toml`**

Use a project-local hook that runs the bootstrap script from the repository root on `startup`, `resume`, and `compact`.

- [ ] **Step 2: Implement the bootstrap script**

Make the script:
- resolve the repository root from its own path,
- read `CCPANES_METHOD_LAYER_AUTOSTART`,
- check `.ccpanes-method/v0.1/runtime/autostart.disabled`,
- print startup context only when autostart is enabled.

### Task 2: Add a manual stop helper and tests

**Files:**
- Create: `scripts/bootstrap/set-autostart.ps1`
- Create: `tests/bootstrap/run.ps1`

- [ ] **Step 1: Add a helper that toggles the sentinel file**

The helper should create or delete `.ccpanes-method/v0.1/runtime/autostart.disabled` and print the resulting state.

- [ ] **Step 2: Add a focused test runner**

Test the hook script in both states:
- enabled -> startup context is emitted;
- disabled -> no startup context is emitted.

- [ ] **Step 3: Wire the new test into repository validation**

Add the startup test runner to `scripts/validate.ps1` so Fast and Full both cover the new bootstrap seam.

### Task 3: Update docs and structure

**Files:**
- Modify: `README.md`
- Modify: `docs/workflow.md`
- Modify: `docs/architecture/repository-structure.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Document the new startup behavior in the human entrypoints**

Explain that Codex App / CLI now auto-enter the method-layer workflow when the hook is trusted.

- [ ] **Step 2: Document the stop switch**

Describe the sentinel file and environment variable as manual stop controls.

- [ ] **Step 3: Record the new directory and helper paths**

Add the `.codex/` startup layer and `scripts/bootstrap/` helper to the repository structure map.

### Task 4: Verify the autostart seam end-to-end

**Files:**
- None

- [ ] **Step 1: Run repository validation**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Full
```

- [ ] **Step 2: Create a fresh Codex thread in this repo**

Confirm the new session starts with the workflow bootstrap context and that the first turn reflects the method-layer entry path.

- [ ] **Step 3: Check diff hygiene**

Run:

```powershell
git diff --check
git status --short --branch
```

