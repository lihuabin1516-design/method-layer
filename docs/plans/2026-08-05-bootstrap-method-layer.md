# Bootstrap Method Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a maintainable local repository for CC-Panes Method Layer design, schemas, templates, and handoff artifacts.

**Architecture:** The repository stays independent from `D:\cc-pane` and stores method-layer documents as plain Markdown plus JSON Schemas. Upstream projects remain references, while CC-Panes-specific adapters and contracts are defined locally.

**Tech Stack:** Markdown, JSON Schema draft 2020-12, Git, PowerShell validation commands.

---

### Task 1: Repository Bootstrap

**Files:**
- Create: `README.md`
- Create: `AGENTS.md`
- Create: `.gitignore`
- Create: `docs/charter.md`
- Create: `docs/integration-map.md`
- Create: `docs/workflow.md`

- [x] **Step 1: Initialize repository**

Run:

```powershell
New-Item -ItemType Directory -Path D:\ccpanes-method-layer
git -C D:\ccpanes-method-layer init -b main
```

Expected: a new independent local Git repository exists at `D:\ccpanes-method-layer`.

- [x] **Step 2: Write core documents**

Create the files listed above with the current charter, mapping, and workflow draft.

- [x] **Step 3: Verify repository state**

Run:

```powershell
git -C D:\ccpanes-method-layer status --short
```

Expected: new untracked files are visible; no commit is made without explicit approval.

### Task 2: Schemas and Templates

**Files:**
- Create: `schemas/task.schema.json`
- Create: `schemas/run.schema.json`
- Create: `schemas/evidence.schema.json`
- Create: `schemas/handoff.schema.json`
- Create: `templates/task.md`
- Create: `templates/run-evidence.json`
- Create: `templates/controller-handoff.md`

- [x] **Step 1: Write JSON schemas**

Define minimal stable fields for task identity, run metadata, evidence, and handoff.

- [x] **Step 2: Write templates**

Create human-readable templates for task, evidence, and controller handoff.

- [x] **Step 3: Validate JSON syntax**

Run:

```powershell
python -m json.tool schemas/task.schema.json > $null
python -m json.tool schemas/run.schema.json > $null
python -m json.tool schemas/evidence.schema.json > $null
python -m json.tool schemas/handoff.schema.json > $null
```

Expected: each command exits 0.

### Task 3: Handoff

**Files:**
- Create: `HANDOFF.md`
- Create: `docs/upstreams/lattice.md`
- Create: `docs/upstreams/aegis.md`

- [x] **Step 1: Record upstream adoption boundaries**

Write what is adopted, rewritten, and left aside from Lattice and Aegis.

- [x] **Step 2: Write next-controller handoff**

Create `HANDOFF.md` with role, baseline, target, authorization, execution order, checks, stop conditions, and artifacts.

- [x] **Step 3: Final status check**

Run:

```powershell
git -C D:\ccpanes-method-layer status --short
git -C D:\ccpanes-method-layer rev-parse --show-toplevel
```

Expected: repository is initialized and files are ready for review.
