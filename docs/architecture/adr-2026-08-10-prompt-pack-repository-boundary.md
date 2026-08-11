# ADR: Prompt Pack Repository Boundary

**Status:** accepted
**Date:** 2026-08-10

## Context

Prompt semantics, versions, composition rules, technology profiles, source locks, and evals need one canonical owner. Current consumers and release behavior are not mature enough to justify an independent repository.

## Decision

`ccpanes-method-layer` owns Prompt Pack source artifacts. `java-enterprise` is internal configuration and knowledge input, not a public method artifact.

`D:\cc-pane\tool\skills` may receive a generated, versioned projection in a later task. It does not own source semantics. Runtime transport and PaneForge catalog/review surfaces remain separate consumers.

## Rejected alternatives

### Create `ccpanes-prompt-layer` now

Rejected because there is one local pack, no stable multi-consumer release contract, and no sustained independent eval/release cadence. Immediate separation would add synchronization and version-coordination cost without reducing current coupling.

### Make `tool/skills` canonical

Rejected because Skills are runtime-facing projections. Making projections authoritative would mix method semantics with installation and transport concerns.

### Treat Prompt Pack as a fifth public method artifact

Rejected because Prompt configuration does not represent task intent, a run binding, execution evidence, or a controller handoff. Adding it would change the frozen public v0.1 protocol.

## Consequences

- Prompt changes and method protocol changes share one repository gate.
- Internal schema and evals can evolve without changing public artifact versions.
- Consumers must reference pack identity/version and must not silently fork semantics.
- Full Prompt bodies should not be copied into long-lived launch, journal, or evidence artifacts.
- A future repository split must preserve provenance, history, schema ownership, and generated-projection direction.
- PaneForge `PF-FUSION-007` is the first read-only metadata review consumer. It validates a hash-bound projection but does not own Prompt semantics and does not yet satisfy the stable multi-consumer split gate.

## Split review gates

Reassess an independent `ccpanes-prompt-layer` only when all of these conditions have evidence:

1. At least two independent consumers use Prompt Packs stably.
2. Prompt Packs have an independent schema, SemVer policy, and compatibility policy.
3. A sustainable eval suite runs continuously.
4. Packs cover multiple languages or technical domains.
5. Prompt release cadence clearly diverges from method-artifact protocol cadence.
6. License, provenance, and maintenance ownership are explicit.
7. Separation benefit exceeds repository synchronization and version-coordination cost.

Meeting the gates triggers review, not automatic migration.

## Verification

- Internal schema validates pack/profile/eval artifacts.
- Repository tests assert the public artifact list remains unchanged.
- Repository tests resolve manifest references and reject large normalized passages matching locked donor fingerprints.
- Documentation identifies `ccpanes-method-layer` as owner and `tool/skills` as derived.

## Reversal

Before stable external consumers exist, remove the pack, internal schema, tests, and documentation entries. After consumers exist, use a versioned migration plan with source-history transfer, consumer cutover, projection regeneration, and explicit retirement of the old owner.
