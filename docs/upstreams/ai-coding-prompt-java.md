# Upstream Evidence: ai-coding-prompt-java

## Source lock

- Repository: `https://github.com/jwangkun/ai-coding-prompt-java.git`
- Default branch: `main`
- Locked commit: `1959b508696c7d92d550c152c735f49ed6dafbe2`
- Commit date: `2025-11-25`
- Query date: `2026-08-10`
- Query commands:
  - `git ls-remote --symref https://github.com/jwangkun/ai-coding-prompt-java.git HEAD refs/heads/main`
  - detached checkout of the locked commit in a temporary directory
  - `git ls-tree -r --name-only HEAD`

On the query date, remote `main` and `HEAD` both resolved to the locked commit. The commit remained readable.

## Directly observed facts

- The tree contains 28 Markdown files.
- The content is grouped into rules, business, application, technical solution, data, project structure, frontend, and mobile categories.
- Java-related material includes requirement review, new and modified feature design, business logic, API definition and implementation, database design, persistence, service dependencies, tests, performance, and security.
- Frontend material assumes Vue-oriented tooling; mobile material assumes uni-app. Those categories are recorded but are outside the first local pack.
- README states that the project uses MIT and links to `LICENSE`.
- The locked tree contains no `LICENSE`, `LICENCE`, `COPYING`, or SPDX-recognized license file.
- Several donor Prompts contain fixed examples or defaults such as a specific Spring generation, database engine version, ORM choices, table names, entity names, security APIs, cache choices, and performance numbers.
- Some donor files are long mixed-purpose documents containing guidance, complete code examples, configuration, deployment commands, and output templates in one Prompt.

## Ideas adopted

- Organize Prompt knowledge by work stage and concern instead of one monolithic role Prompt.
- Compose requirement review, solution design, persistence, security, and testing concerns.
- Make inputs, output shape, checks, and quality assertions explicit.
- Keep Java enterprise applicability while separating framework-family guidance from project-specific versions.
- Treat Prompt content as versioned, reviewable knowledge with provenance and deterministic validation.

## Local rewrites

- Role-heavy instructions became bounded task contracts with required inputs, output contracts, and acceptance assertions.
- Fixed class names, table names, framework versions, database products, cache products, and performance thresholds were removed.
- Project facts and task authorization are external inputs; the pack does not infer or widen them.
- Generic examples were replaced by repository-first analysis and explicit stop conditions.
- Complete implementation generation became design, impact, verification, and risk output.
- Security guidance now requires actual trust boundaries, allowed and denied paths, and repository-confirmed framework semantics.
- Test guidance now separates proposed tests from fresh execution evidence.
- Prompt source text uses declared `input` markers. The validator rejects undeclared or unresolved rendered markers.

## Content not absorbed

- Frontend and mobile Prompt bodies: outside the Java enterprise v0.1 scope.
- Full project scaffolding, deployment configuration, and infrastructure recipes: too broad and project-specific.
- Performance Prompt as a first-pack Prompt: useful measurement principles were retained in acceptance guidance, but a separate performance Prompt needs evidence-driven fixtures first.
- Complete donor code, SQL, YAML, and configuration examples: license evidence is incomplete and the examples embed unsupported assumptions.
- Claimed productivity percentages: no supporting dataset or evaluation method was present in the locked tree.
- Automatic coding, deployment, remote Git, or production actions: outside method-layer Prompt authority.

## Local mapping

| Donor category | Local destination | Result |
| --- | --- | --- |
| Requirement implementation review | `requirement-review` | Evidence-first review contract |
| New and modified technical solution | `solution-design` | One bounded design Prompt |
| Table and persistence guidance | `persistence-design` | Ownership, migration, consistency, recovery |
| Security checklist | `security-review` | Trust-boundary and denied-path review |
| Test generation | `test-generation` | Acceptance-linked test design |
| Fixed Java/Spring assumptions | `profiles/spring-enterprise.json` | Exact versions required from project facts |
| Prompt selection workflow | `pack.json` composition rules | Deterministic stage/change/risk selection |

## License assessment

The repository's README claim is not sufficient license evidence because the referenced license file is absent and GitHub does not expose a recognized SPDX license for the locked tree. Local use is therefore limited to ideas, categorization, and independently written contracts. No donor directory, complete Prompt, or substantial code/configuration passage is vendored.

## Schema and compatibility impact

- Added one internal schema for Prompt Pack, profile, and eval configuration.
- Public `task`, `run`, `evidence`, and `handoff` schemas remain unchanged at protocol version `0.1`.
- Adapter and controller runtime contracts remain unchanged.

## Verification and rollback

- Deterministic validation checks the source commit, local rewrite boundaries, declared inputs, Prompt identities, cross-file references, composition, eval expectations, and SHA-256 fingerprints of normalized donor windows.
- Rollback is removal of the internal schema, `prompt-packs/java-enterprise`, Prompt Pack tests, and the corresponding validation/documentation entries. Public v0.1 artifacts require no migration.

## Future synchronization

Upstream changes do not flow automatically. A future intake must:

1. record the then-current branch and commit;
2. compare changed donor categories with this source lock;
3. reassess license evidence;
4. update provenance only for independently reviewed local rewrites;
5. add or update deterministic fixtures before changing composition or Prompt contracts.
