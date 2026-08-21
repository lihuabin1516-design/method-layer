# License / Provenance Decision Record

## Scope

- Repository: `D:\ccpanes-method-layer`
- Effective date: `2026-08-21`
- Status: provisional; license decision pending review

## Current facts

- No `LICENSE` file exists in the repository tree.
- `README.md` still treats license information as pending final decision.
- `docs/upstreams/lattice.md` and `docs/upstreams/aegis.md` record upstream branch, commit, query date, adopted ideas, and discarded ideas.
- `docs/upstreams/ai-coding-prompt-java.md` records the locked donor commit, the missing donor license file, and the local rewrite boundary.
- Source-locked Prompt Pack artifacts remain byte-preserved through `.gitattributes` and validation.

## Decision

- The repository does not yet declare a final distribution license.
- Provenance is recorded for local rewrite, comparison, and validation only.
- No donor directory, no substantial donor Prompt text, and no unreviewed SPDX claim are treated as repository facts.
- Any future release, redistribution, or public-facing license claim requires an explicit reviewed license decision record.

## Operational implications

- Keep the repository in pending-license state until a reviewed `LICENSE` or SPDX decision is added.
- Keep upstream provenance entries current when new ideas or material are absorbed.
- Keep `README.md`, `HANDOFF.md`, and the maintenance baseline linked to this record.

## Review trigger

- New upstream absorption.
- Public release, tag, or push.
- Addition or change of repository license text.
- Any attempt to present the repository as having a final license status.
