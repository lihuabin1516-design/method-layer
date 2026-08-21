# Official CC-Panes External Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local, file-first Companion that lets the method-layer Prompt Pack assist official `cc-panes.exe` from the outside.

**Architecture:** Keep official CC-Panes as the runtime owner. Add internal Companion schemas, one PowerShell command, and deterministic tests that return metadata-only guidance without launching or mutating official CC-Panes.

**Tech Stack:** PowerShell 7, JSON Schema via `Test-Json`, existing Prompt Pack JSON.

---

### Task 1: RED companion tests

**Files:**
- Create: `tests/companion/run.ps1`
- Create: `tests/companion/fixtures/*.json`

- [x] Write focused tests for schema presence, Java design selection, missing facts, authorization expansion, host mutation rejection, and metadata-only output.
- [x] Run `pwsh -NoProfile -ExecutionPolicy Bypass -File tests\companion\run.ps1`.
- [x] Observe RED because `companion/schemas/*` and `scripts/companion/new-guidance.ps1` are absent.

### Task 2: Companion contract and implementation

**Files:**
- Create: `companion/schemas/official-companion-request.internal.schema.json`
- Create: `companion/schemas/official-companion-guidance.internal.schema.json`
- Create: `scripts/companion/MethodLayer.Companion.psm1`
- Create: `scripts/companion/new-guidance.ps1`

- [x] Add request schema with official target fixed to `official-cc-panes` / `cc-panes.exe` / `external-companion` and `additionalProperties: false`.
- [x] Add guidance schema with fixed no-launch/no-config/no-host-mutation target fields.
- [x] Implement deterministic Prompt selection from `prompt-packs/java-enterprise/pack.json`.
- [x] Return `blocked-authorization`, `blocked-input-gap`, or `ready-to-copy`.
- [x] Validate output against the guidance schema before stdout.

### Task 3: Documentation and validation integration

**Files:**
- Create: `companion/README.md`
- Modify: `scripts/validate.ps1`
- Modify: `README.md`
- Modify: `docs/integration-map.md`
- Modify: `docs/architecture/repository-structure.md`
- Modify: `HANDOFF.md`

- [x] Add Companion schemas and fixtures to JSON syntax validation.
- [x] Run Companion tests from `scripts/validate.ps1`.
- [x] Document the external sidecar boundary and command.
- [x] Run focused Companion tests, Fast validation, Full validation, and final Git status.
