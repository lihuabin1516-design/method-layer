# Prompt Pack v0.1 Design

**Status:** accepted and implemented locally
**Date:** 2026-08-10
**Owner:** `ccpanes-method-layer`
**Initial pack:** `java-enterprise` `0.1.0`

## Goal and invariant

Create a versioned, composable, provenance-aware Prompt Pack for Java enterprise engineering without adding a fifth public method artifact or transferring authorization into Prompt content.

The governing invariant is:

> Prompt Pack configuration may select and render method guidance, but task/project context remains the authority for facts, permissions, stop conditions, and acceptance.

## Boundaries and ownership

### Prompt Pack owner

- Owns Prompt semantics, Prompt IDs and versions, composition rules, technology profiles, provenance, and deterministic evals.
- Does not own task authorization, project facts, runtime launch, evidence, or CC-Panes UI.

### Providers and consumers

- Provider: `ccpanes-method-layer`.
- Future consumers: CC-Panes task/prompt transport and generated Skill projections.
- Donor repositories: read-only reference inputs at locked commits.
- `tool/skills`: derived projection only.

### Public protocol

Public method artifacts remain exactly:

```text
task
run
evidence
handoff
```

Prompt Pack files are internal configuration and knowledge inputs. They do not use `protocolVersion: "0.1"` and do not change the meaning of the public schemas.

## Component model

| Component | Owns | Does not own |
| --- | --- | --- |
| `schemas/prompt-pack.internal.schema.json` | Internal manifest, profile, and eval shapes | Public method protocol |
| `prompt-packs/java-enterprise/pack.json` | Pack version, Prompt metadata, composition, source lock | Runtime selection authority |
| `profiles/spring-enterprise.json` | Required technology facts and version policy | Concrete project versions |
| `prompts/*.md` | Independently written method instructions | Task policy or runtime evidence |
| `evals/cases.json` | Deterministic fixtures and expected decisions | Model-quality judgment |
| `evals/donor-fingerprints.json` | Irreversible hashes of normalized donor windows | Donor text or runtime content |
| `tests/prompt-pack/run.ps1` | Structural and composition verification | Prompt execution against an LLM |

## Composition flow

```text
task stage
  + change type
  + risk tags
  + technology profile
  + project facts
  + task authorization
  -> stop gates
  -> select Prompt IDs
  -> de-duplicate
  -> filter by Prompt applicable stage
  -> stable pack order
  -> render declared input markers
  -> derive required project facts from Prompt/profile
  -> validate the union of selected Prompt output contracts
```

Stage, change-type, and risk rules only nominate Prompt IDs. The composer then removes Prompts that do not declare the active stage. A requested action outside authorization or an absent fact derived from selected Prompt inputs and referenced technology profiles returns a blocked decision before rendering.

## Prompt contract

Every Prompt manifest entry contains:

- `id`
- `version`
- `title`
- `purpose`
- `applicableStages`
- `requiredInputs`
- `optionalInputs`
- `outputContract`
- `acceptanceAssertions`
- `sourceProvenance`
- `knownLimitations`
- `contentPath`

Prompt Markdown uses `{{input.<name>}}` markers. Every marker must be declared by the manifest. Rendering must supply all required inputs and leave no marker in candidate output. For a composed result, required output sections are the stable de-duplicated union of the selected Prompt contracts.

## Layering

The pack separates:

1. common engineering principles in the Prompt bodies;
2. work-stage and risk composition in `pack.json`;
3. Java/Spring family guidance in the technology profile;
4. project facts supplied at composition time;
5. output contracts in Prompt metadata;
6. acceptance assertions in Prompt metadata and rendered output.

Policy and authorization remain external. Runtime journal, launch attempt, and evidence artifacts should store Prompt identity/version and compact references rather than full Prompt bodies.

## Initial Prompt set

1. `requirement-review`
2. `solution-design`
3. `persistence-design`
4. `security-review`
5. `test-generation`

The donor's performance material is not a separate v0.1 Prompt because concrete optimization advice requires measured baselines and representative workloads.

## Technology profile

`spring-enterprise` names the Java/Spring family but sets `versionPolicy` to `project-fact-required`. Required facts include Java version, Spring version, build tool, and persistence technology. Missing values block concrete implementation advice.

## Deterministic evals

Required gates do not depend on an LLM judge. Thirteen fixtures cover:

- normal new feature;
- existing feature modification;
- missing facts;
- database change;
- authentication or authorization;
- read-only audit;
- unresolved input marker;
- authorization expansion;
- missing acceptance assertions;
- fixed framework-version assumption.
- stage applicability filtering;
- an omitted composed output-contract section;
- a missing technology-profile required fact.

Each case has an exact expected decision, ordered Prompt IDs, and violation list.

## Failure behavior

- Invalid JSON/schema: fail before composition.
- Duplicate Prompt identity/version: fail.
- Missing referenced content: fail.
- Missing profile, eval, fingerprint, or Prompt reference: fail.
- Undeclared source marker: fail.
- Missing required project fact: blocked.
- Authorization expansion: blocked.
- Unresolved rendered marker: fail.
- Missing acceptance assertions: fail.
- Unsupported fixed framework version: fail.
- A normalized local Prompt window matching the locked donor fingerprints: fail.

## Provenance and license

The donor is locked to `1959b508696c7d92d550c152c735f49ed6dafbe2`. README claims MIT, but no license file or recognized SPDX record exists in the tree. Local artifacts are independent, compact rewrites. The repository stores only SHA-256 fingerprints of normalized 256-character donor windows at stride 128; donor text is never a runtime dependency or vendored artifact.

## Compatibility and recovery

This is an internal `0.1-internal` contract. Changes to the internal schema or Prompt metadata require fixture updates. The ten artifacts consumed by the PaneForge source lock are marked `-text` in `.gitattributes` so Git stores their reviewed bytes without line-ending normalization. Removal requires deleting the pack, internal schema, tests, attributes, and documentation entries; no public artifact migration is needed.

## Acceptance assertions

1. Public v0.1 artifact schemas and semantics remain unchanged.
2. Prompt IDs and versions are unique.
3. Required inputs, output contracts, and acceptance assertions are non-empty.
4. All declared content paths remain inside the pack root.
5. Provenance points to the locked donor commit.
6. Donor-specific fixed implementation assumptions are absent.
7. All thirteen deterministic eval cases match exact expected results.
8. Fast and Full repository validation include Prompt Pack gates.
9. Manifest cross-file references resolve inside the pack root.
10. No local Prompt contains a locked donor fingerprint window.
11. Git preserves the exact bytes of all ten source-locked artifacts.
