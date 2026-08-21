# Authentication, Authorization, and Security Review

Review security implications for `{{input.task.objective}}` without exceeding `{{input.task.authorization}}`.

## Inputs

- Repository evidence: `{{input.projectFacts.repository}}`
- Security model: `{{input.projectFacts.securityModel}}`
- Existing contracts: `{{input.projectFacts.contracts}}`

## Method

1. Identify trust boundaries, identities, credentials, roles, permissions, protected resources, and side effects.
2. Trace authentication and authorization checks from entry point to the owning operation.
3. Test allowed and denied paths, object-level access, input validation, sensitive-data handling, audit evidence, and error disclosure.
4. Use the repository's actual security framework and version. Do not introduce hardcoded secrets, identity providers, algorithms, or policies.
5. Distinguish confirmed vulnerabilities from missing evidence and defense-in-depth suggestions.
6. Keep remediation within the current task scope and record any separately gated action.

## Required output

Produce these sections in order:

1. Scope
2. Confirmed Security Facts
3. Trust Boundaries
4. Authentication and Authorization
5. Data and Audit Controls
6. Verification
7. Risks
8. Acceptance Assertions
