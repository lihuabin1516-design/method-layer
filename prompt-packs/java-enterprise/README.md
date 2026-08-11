# Java Enterprise Prompt Pack

`java-enterprise` v0.1 is an internal method-layer configuration package. It composes focused Prompts from task stage, change type, risk tags, project facts, and the current task authorization.

## Boundaries

- Canonical owner: `ccpanes-method-layer`.
- Public method artifacts remain `task`, `run`, `evidence`, and `handoff`.
- The pack selects and renders guidance; it does not grant permissions or record runtime evidence.
- Concrete Java, Spring, persistence, security, and test versions come from `profiles/spring-enterprise.json` plus repository facts.
- `tool/skills` may later receive a generated projection, but is not a source of truth.

## Composition

The manifest applies rules in this order:

1. stage rules;
2. change-type rules;
3. risk rules;
4. de-duplication by Prompt ID;
5. filtering by each Prompt's `applicableStages`;
6. stable ordering from `composition.order`;
7. project-fact derivation from selected Prompt inputs and referenced profiles;
8. stop gates for missing facts or authorization expansion.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File tests\prompt-pack\run.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\validate.ps1 -Mode Fast
```

The deterministic suite validates schema conformance, bounded cross-file references, Prompt identity and version uniqueness, declared inputs, composed output contracts, acceptance assertions, profile-derived facts, source locks, donor-window fingerprints, composition, and negative output cases.
