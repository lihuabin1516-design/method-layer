# Java Enterprise Deterministic Evals

`cases.json` contains thirteen dependency-free fixtures. Each fixture declares input facts, authorization, requested actions, candidate output shape, and the exact expected decision, Prompt order, and violation list.

The suite covers:

- normal new-feature design;
- modification of existing behavior;
- missing project facts;
- database change;
- authentication or authorization;
- read-only audit;
- unresolved rendered input markers;
- authorization expansion;
- missing acceptance assertions;
- unsupported fixed framework versions;
- stage applicability filtering;
- a missing composed output-contract section;
- a missing technology-profile required fact.

`donor-fingerprints.json` contains only SHA-256 hashes of normalized 256-character windows from the locked 28-file donor tree, sampled at stride 128. The runner scans local Prompts at stride 1, so a sufficiently large verbatim normalized passage is rejected without storing donor text.

The required gate uses deterministic PowerShell assertions. LLM judging may be added later only as an optional signal.
