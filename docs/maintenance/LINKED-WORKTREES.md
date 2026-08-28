# CC-Panes Method Layer Linked Worktrees Registry

**Registry date:** 2026-08-28
**Repository:** `D:\ccpanes-method-layer`
**Authority:** Git worktree metadata, queried with `git worktree list --porcelain`

This registry makes the linked worktrees discoverable after the controlling
Codex conversation ends. Git worktree metadata is the source of truth and
remains on disk independently of the conversation.

## Registered worktrees

| Path | Branch / state | Baseline | Use |
|---|---|---|---|
| `D:\ccpanes-method-layer` | `codex/official-ccpanes-companion` | `f245d9b` | primary checkout; contains pre-existing local changes |
| `C:\Users\AI001\.codex\worktrees\f461\ccpanes-method-layer` | detached | `f245d9b` | historical detached review worktree |
| `D:\cc-pane\.worktrees\method-layer-production-runtime-20260828` | `codex/method-layer-production-runtime-20260828` | `f245d9b` | clean execution entry for the production-runtime task |
| `D:\cc-pane\tool\worktrees\ccpanes-method-layer\spec-kit-method-contract-20260815` | `codex/spec-kit-method-contract-20260815` | `532a230` | historical method-contract worktree |
| `D:\cc-pane\worktrees\ccpanes-method-layer\scheme-b-contracts-20260827` | `codex/scheme-b-contracts-20260827` | `f245d9b` | historical Scheme B worktree; contains local changes |
| `D:\ccpanes-method-layer-worktrees\diagram-lifecycle-pilot` | `codex/diagram-lifecycle-pilot` | `42f3011` | historical lifecycle worktree |
| `D:\ccpanes-method-layer-worktrees\prompt-pack-java-intake` | `codex/prompt-pack-java-intake` | `921725e` | published prompt-pack intake worktree |

## Recovery

```powershell
git -C D:\ccpanes-method-layer worktree list --porcelain
git -C D:\ccpanes-method-layer worktree repair
git -C D:\cc-pane\.worktrees\method-layer-production-runtime-20260828 status --short --branch
```

Use Git status and worktree metadata before cleanup, branch deletion, or
integration. Existing local changes remain outside this registry's scope.
