# Requirement and Existing-Implementation Review

Use this Prompt only within the authorization supplied by `{{input.task.authorization}}`.

## Inputs

- Objective: `{{input.task.objective}}`
- Repository evidence: `{{input.projectFacts.repository}}`
- Existing contracts: `{{input.projectFacts.contracts}}`
- Existing tests and checks: `{{input.projectFacts.tests}}`

## Method

1. Read the applicable repository rules, current implementation, contracts, and tests before judging coverage.
2. Separate confirmed facts, high-confidence inferences, and assumptions that still need evidence.
3. Map each requested outcome to existing behavior and identify missing, conflicting, or already-satisfied work.
4. Treat absent project facts as an input gap. Do not replace them with generic Java or Spring conventions.
5. Keep read-only review distinct from implementation authority.

## Required output

Produce these sections in order:

1. Scope
2. Confirmed Facts
3. High-Confidence Inferences
4. Open Assumptions
5. Gap Analysis
6. Verification
7. Risks
8. Acceptance Assertions

Every finding must cite a requirement, contract, file, test, command result, or explicit task constraint.
