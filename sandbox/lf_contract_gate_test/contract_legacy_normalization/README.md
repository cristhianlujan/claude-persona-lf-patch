# Legacy Contract Normalization V1

Status: `SHADOW_CANDIDATE`

## Purpose

Provide a deterministic compatibility boundary between heterogeneous legacy contract payloads and the typed predicate schema consumed by the single Contract Check capability.

This component does **not** infer contract meaning. Every translation must be explicit, source-bound, and fail closed on drift.

```text
resolved legacy contract
        |
        v
explicit translation spec
  - exact operation + contract
  - exact source contract SHA-256
  - exact source pointer/value
  - explicit typed predicate
        |
        v
Legacy Contract Normalization V1
        |
        +-- PARTIAL_SHADOW -> never eligible for Contract Check
        |
        `-- FULL + exact coverage -> typed contract
                                      |
                                      v
                         Contract Predicate Semantics
                                      |
                                      v
                             Contract Check Core
```

## Boundary

V1 MUST NOT:

- decide whether Contract Check applies;
- resolve or rank contracts;
- infer `operation_code` or `contract_code`;
- translate free-form strings by naming convention, regex, LLM judgment, or heuristics;
- reinterpret a changed source contract under an old translation;
- mutate `lf_operation_contracts` or any live Supabase authority;
- activate runtime or change workflow cutover behavior;
- emit a partial translation as ready for Contract Check.

## Translation integrity

A translation is bound to the canonical SHA-256 of the complete source contract. Every mapping also binds one atomic legacy JSON pointer to its exact expected JSON value and to one explicit typed term.

The normalizer deterministically enumerates legacy source atoms only for coverage accounting. That enumeration does not assign semantics.

`coverage_mode=FULL` requires every atom in all four contract sections to be explicitly mapped. Missing coverage blocks normalization. `coverage_mode=PARTIAL_SHADOW` may be used for investigation, but `normalized_contract` remains `null` and `ready_for_contract_check=false`.

## Why this exists

The active contract authority is heterogeneous. A read-only census on 2026-09-28 found 39 `ACTIVE_ENFORCEMENT` contracts across four top-level section-shape families:

- 26: array / object / array / array
- 8: object / object / object / object
- 4: array / object / object / array
- 1: object / object / array / object

Those shapes cannot be sent directly to `Contract Predicate Semantics V1`, which intentionally accepts typed term arrays only.

The tests use four representative shadow fixtures matching those shape families. They prove normalization mechanics and fail-closed behavior; they do **not** claim that any live contract has already been semantically migrated.

## Evidence

Candidate self-test marker:

`PASS_LEGACY_CONTRACT_NORMALIZATION_V1=15/15`

The self-test includes an end-to-end shadow path:

`legacy fixture -> FULL explicit translation -> typed predicate semantics -> Contract Check Core -> PASS`

No live contract, Supabase row, production workflow, or runtime state is modified by this candidate.
