# RW1-04_C1 erratum — semantic handoff site count

**Plan:** `LF_ROUTER_ARCHITECTURE_WAVE_V1`  
**Unit:** `RW1-04`  
**Affects:** C1 evidence count only; architecture and C1 DONE state remain unchanged.

## Correction

The frozen C1 baseline states that current `public.lf_router_resolve_v1` has five semantic-gap emission sites using `public.lf_router_intent_handoff_v1`.

Exact-source reinspection before C2 implementation found **six** occurrences.

The omitted site is the repository-artifact consumer handoff that emits candidates from `v_artifact_discovery->'matches'` with reference kind `REPOSITORY_ARTIFACT` and participates in the artifact-consumer unresolved/ambiguous path.

## Exact six V1 emission sites to preserve and dual-emit in C2

1. Multiple exact targets need scope — `v_exact_asset_candidates / CANONICAL_ASSET`.
2. Repository artifact consumer unresolved/ambiguous — `v_artifact_discovery->'matches' / REPOSITORY_ARTIFACT`.
3. Explicit target intent attestation required — current asset candidate / `CANONICAL_ASSET`.
4. Screen subject / executor-role separation — `v_screen_subjects / CANONICAL_SCREEN`.
5. Negative/exclusion scope semantics — current asset candidate / `CANONICAL_ASSET`.
6. Unstructured mutation intent — current asset candidate / `CANONICAL_ASSET`.

## Effect on implementation

C2 must patch **all six** sites to emit V2 alongside V1.

This is not an architecture change:
- D1 handoff V2 remains unchanged.
- D2 resume validator remains unchanged.
- D3 is corrected from five to six existing call sites.
- D4 shadow/disabled transition remains unchanged.
- Discovery, derivation, operation selection, effect authority, Input Governance and Merge Train remain out of scope.

## Evidence

Current Router source before C2:
- main: `3a2bae4deb53f8ab9e7ea661708fcbe0cf6ddeb2`
- pre-C2 Router md5: `d45f5bddb693791b6459bbe3acfd4ed3`
- source migration blob: `23acf59f2afcee2cf81d10e05c6d31ec4c23ebf2`

**Disposition:** C1 historical evidence is preserved; C2 consumes this erratum and uses six as the exact implementation/readback count.
