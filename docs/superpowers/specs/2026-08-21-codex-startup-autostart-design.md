# Codex Startup Autostart Design

**Goal:** When Codex App or Codex CLI opens this repository, the session should immediately enter the external method-layer workflow: task intake, baseline readback, Companion guidance, run creation, evidence, finish gate, and handoff. Users must still be able to stop the bootstrap locally.

## Why this path

We need the workflow to start automatically in both Codex App and Codex CLI without changing official CC-Panes runtime surfaces. The safest place to do that is a project-local startup hook plus a small ignored stop switch. The repo already has a stable method-layer artifact root and AGENTS.md, so startup bootstrap can be additive instead of invasive.

## Recommended approach

1. Add a project-local `.codex/config.toml` with a `SessionStart` hook.
2. Make the hook run a tiny repository-local bootstrap script.
3. Have the script emit a concise startup context only when autostart is enabled.
4. Use an ignored sentinel file and an environment variable as manual stop controls.

This keeps the behavior:
- automatic on startup when hooks are trusted;
- visible and local;
- reversible without editing official runtime settings;
- shared by App and CLI.

## Manual stop

Use either control:
- create `.ccpanes-method/v0.1/runtime/autostart.disabled`
- or set `CCPANES_METHOD_LAYER_AUTOSTART=0`

The hook should check both and emit no bootstrap context when either stop is active.

## Validation

- Parse the `.codex/config.toml` file.
- Run the hook script directly with autostart on/off.
- Verify the disabled sentinel suppresses startup context.
- Confirm the repository docs describe the startup path and stop switch.

## Constraints

- No change to official CC-Panes executable, profiles, hooks, plugins, or host runtime.
- No hidden network call or prompt execution in the bootstrap layer.
- No automatic task creation; the hook only seeds the session with workflow context.
- The startup hook must degrade safely if trust is not granted.

