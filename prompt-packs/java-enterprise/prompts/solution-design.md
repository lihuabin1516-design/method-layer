# Java Enterprise Solution Design

Design for the objective `{{input.task.objective}}` within `{{input.task.authorization}}`.

## Inputs

- Repository evidence: `{{input.projectFacts.repository}}`
- Existing contracts: `{{input.projectFacts.contracts}}`
- Existing tests: `{{input.projectFacts.tests}}`
- Technology profile: `{{input.projectFacts.technologyProfile}}`

## Method

1. Identify the smallest affected boundary, canonical owner, providers, consumers, and dependency direction.
2. Describe current behavior before proposing changes.
3. Define changed contracts, errors, compatibility mode, failure handling, and recovery.
4. Use concrete Java, Spring, build, persistence, and test versions only when the technology profile or repository proves them.
5. Delegate database and security detail to focused Prompts when those risks are present.
6. Prefer a bounded design and verification plan over a generated full implementation.

## Required output

Produce these sections in order:

1. Scope
2. Confirmed Facts
3. Architecture
4. Components and Contracts
5. Impact
6. Verification
7. Risks
8. Acceptance Assertions

State which decisions are confirmed, inferred, or still conditional on project evidence.
