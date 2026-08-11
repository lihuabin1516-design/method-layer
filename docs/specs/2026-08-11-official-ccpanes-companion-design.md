# Official CC-Panes External Companion Design

**Status:** accepted and implemented locally
**Date:** 2026-08-11
**Owner:** `ccpanes-method-layer`

## Goal

Expose the `java-enterprise` Prompt Pack as an external assistant for the
official `cc-panes.exe` without changing official CC-Panes runtime, source,
profile, hook, plugin, MCP, or user configuration.

## Architecture

The companion is a file-first sidecar inside this repository:

```text
caller context JSON
  -> companion request schema
  -> Prompt Pack manifest/profile metadata
  -> deterministic prompt selection and stop gates
  -> companion guidance JSON
  -> manual copy or separately approved existing CC-Panes surface
```

Official CC-Panes remains the owner of panes, sessions, PTY, and runtime
execution. The method layer owns Prompt Pack metadata and guidance envelopes
only.

## Boundaries

- The companion does not start `cc-panes.exe`.
- The companion does not write official user config, profiles, hooks, plugins,
  MCP server entries, or host runtime files.
- The companion does not execute or compose Prompts.
- The companion output contains Prompt IDs, versions, output contracts, missing
  facts, authorization gaps, and copy instructions, but not Prompt bodies.

## Failure behavior

- Invalid request schema: reject before guidance.
- Requested actions outside authorization: return `blocked-authorization`.
- Missing required project facts: return `blocked-input-gap`.
- Otherwise return `ready-to-copy`.

## Acceptance

1. Request and guidance schemas reject unknown host mutation fields.
2. Java design context selects `requirement-review` and `solution-design`.
3. Missing technology facts block before copy guidance.
4. Authorization expansion blocks before copy guidance.
5. Output remains metadata-only and names official CC-Panes as an external target.
