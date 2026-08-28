# External Method Layer Workflow Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repository's external method layer the canonical workflow path for Codex App and codex cli, using `task` / `run` / `evidence` / `handoff` artifacts plus Companion and Adapter/Controller seams without touching official CC-Panes runtime surfaces.

**Architecture:** Keep official CC-Panes as the runtime owner. Update the user-facing workflow docs so every task starts with task intake and baseline readback, flows through Companion guidance and run artifact creation, and ends with evidence, finish gate, and handoff. No official runtime, profile, hook, plugin, or user-config mutation is introduced.

**Tech Stack:** Markdown docs, existing JSON schemas in `schemas/` and `companion/schemas/`, PowerShell validation scripts, and the current task/run/evidence/handoff templates.

---

### Task 1: Make the README describe the shared workflow entry

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a workflow section that names Codex App, codex cli, and official CC-Panes**

The new section should state that Codex App and codex cli share the same repository-local artifact flow, and that official CC-Panes remains runtime owner only.

- [ ] **Step 2: Add the canonical artifact order**

Document the sequence `task -> baseline readback -> companion guidance -> run -> evidence -> drift/finish gate -> handoff`.

- [ ] **Step 3: Point readers to the workflow doc and templates**

Link to `docs/workflow.md`, `templates/task.md`, and the companion / adapter / controller command entry points already present in the repository.

### Task 2: Make `docs/workflow.md` the canonical operating sequence

**Files:**
- Modify: `docs/workflow.md`

- [ ] **Step 1: Add a short entry-surface section above the standard path**

State which steps are typically done in Codex App versus codex cli / local scripts, and keep official CC-Panes outside the mutation boundary.

- [ ] **Step 2: Keep the standard path as the shared workflow**

Preserve the existing nine-step order and make it explicit that this is the canonical loop for external method-layer usage.

- [ ] **Step 3: Tie the finish gate to evidence and handoff**

Reinforce that the workflow ends only after evidence validation, drift review, and either a handoff or a local completion decision.

### Task 3: Verify the docs-only change set

**Files:**
- None

- [ ] **Step 1: Run schema syntax checks**

Run:

```powershell
python -m json.tool schemas\task.schema.json > $null
python -m json.tool schemas\run.schema.json > $null
python -m json.tool schemas\evidence.schema.json > $null
python -m json.tool schemas\handoff.schema.json > $null
```

- [ ] **Step 2: Run repository validation**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Full
```

- [ ] **Step 3: Check diff hygiene**

Run:

```powershell
git diff --check
git status --short --branch
```

