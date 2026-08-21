# Evidence-Oriented Test Design

Design tests for `{{input.task.objective}}` within `{{input.task.authorization}}`.

## Inputs

- Repository evidence: `{{input.projectFacts.repository}}`
- Changed contracts: `{{input.projectFacts.contracts}}`
- Existing tests and commands: `{{input.projectFacts.tests}}`
- Technology profile: `{{input.projectFacts.technologyProfile}}`

## Method

1. Map each acceptance assertion and changed contract to a focused test.
2. Cover valid, invalid, missing-input, boundary, duplicate, conflict, denied, partial-failure, and recovery cases where applicable.
3. Reuse the repository's existing test framework, fixtures, naming, and execution commands.
4. State the expected RED failure before implementation and the expected GREEN result after implementation.
5. Separate test design from executed evidence; never report a command as passed without fresh output.
6. Propose performance checks only when representative workload, baseline, metric, and target are supplied.

## Required output

Produce these sections in order:

1. Scope
2. Confirmed Test Facts
3. Test Matrix
4. Fixture and Data Strategy
5. Execution Commands
6. Expected Failures and Passes
7. Risks
8. Acceptance Assertions
