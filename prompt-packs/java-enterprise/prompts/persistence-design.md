# Persistence and Data Model Design

Review the data impact of `{{input.task.objective}}` within `{{input.task.authorization}}`.

## Inputs

- Repository evidence: `{{input.projectFacts.repository}}`
- Current data model and migrations: `{{input.projectFacts.dataModel}}`
- Technology profile: `{{input.projectFacts.technologyProfile}}`

## Method

1. Name the canonical data owner, system of record, logical writer, readers, and protected invariants.
2. Inspect current schema, migrations, repositories, transaction boundaries, query evidence, and tests.
3. Define schema changes, compatibility, migration ordering, live-write interaction, rollback or roll-forward, and reconciliation.
4. Propose indexes or query changes only from observed access paths and execution evidence.
5. Do not invent table names, columns, database engines, ORM frameworks, retention periods, or throughput targets.
6. Treat production data mutation and destructive migration as separately authorized actions.

## Required output

Produce these sections in order:

1. Scope
2. Confirmed Data Facts
3. Ownership and Invariants
4. Schema and Migration
5. Consistency and Recovery
6. Verification
7. Risks
8. Acceptance Assertions
