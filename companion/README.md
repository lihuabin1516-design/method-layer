# Official CC-Panes External Companion v0.1

This companion is a method-layer sidecar for the official `cc-panes.exe`.

It does **not** modify the official CC-Panes executable, source tree, user
configuration, profiles, hooks, plugins, MCP registration, or host runtime.
It reads caller-supplied context plus this repository's Prompt Pack metadata and
returns copyable guidance for a human or an already-approved transport surface.

## Boundary

| Surface | Owner |
| --- | --- |
| Official panes, sessions, PTY, existing runtime | official CC-Panes |
| Prompt Pack metadata and composition rules | `ccpanes-method-layer` |
| Companion guidance envelope | `companion/schemas/*` |
| Task authorization and project facts | caller / target project |

The companion output contains Prompt identities, versions, output contracts, and
missing facts. It does not emit Prompt bodies or execute/compose Prompts.

## Command

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\companion\new-guidance.ps1 `
  -ContextPath tests\companion\fixtures\design-request.json
```

The command writes one JSON document to stdout:

- `artifactType: official-ccpanes-companion-guidance`
- `decision: ready-to-copy | blocked-input-gap | blocked-authorization`
- `target.launchesOfficialExe: false`
- `target.writesOfficialConfig: false`
- `target.mutatesHost: false`

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\companion\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
```
