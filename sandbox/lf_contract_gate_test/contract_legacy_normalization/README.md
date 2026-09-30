# Legacy Contract Normalization V1

Status: `SHADOW_CANDIDATE`

## Purpose

Provide a deterministic compatibility boundary between heterogeneous legacy contract payloads and the typed predicate schema consumed by the single Contract Check capability.

This component does **not** infer contract meaning. Every translation must be explicit, source-bound, and fail closed on semantic drift.

```text
resolved legacy contract
        |
        v
canonical semantic source projection
        |
        v
explicit translation spec
  - exact operation + contract
  - exact semantic-source SHA-256
  - exact source node/value
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
- reinterpret a changed semantic source under an old translation;
- mutate `lf_operation_contracts` or any live Supabase authority;
- activate runtime or change workflow cutover behavior;
- emit a partial translation as ready for Contract Check.

## Translation integrity

A translation is bound to the SHA-256 of one fixed semantic/identity projection of the source contract:

- `operation_code`;
- `contract_code`;
- `contract_path`;
- `contract_sha`;
- `required_before_write`;
- `allowed`;
- `blocked`;
- `required_after_write`;
- `status`.

All nine keys are mandatory. A change to any of them changes the source digest and invalidates the old translation.

Authority snapshots may also carry transport/audit fields such as `created_at`, `updated_at`, `created_by_execution_id`, `updated_by_execution_id`, or future snapshot metadata. Those fields are deliberately excluded from the translation digest because they are not contractual semantics.

### Explicit grouped source mappings

A mapping may bind either one legacy leaf atom or an explicitly selected parent node such as an array/object. The selected node must remain inside the declared contractual section and its `expected_source` must match the complete node exactly.

When a parent node is selected, every descendant leaf atom is counted as covered by that one mapping. This permits a semantic unit such as:

```text
/allowed/execution_modes = [READ_ONLY, SANDBOX]
```

to become one explicit typed predicate:

```text
execution.mode IN [READ_ONLY, SANDBOX]
```

instead of incorrectly requiring separate mutually exclusive typed terms for each array element.

Grouping is never inferred by the normalizer: the translation author chooses the exact source node and exact typed predicate. Overlapping mappings are rejected because descendant atoms would be covered more than once. Cross-section mappings are rejected.

`coverage_mode=FULL` still requires every leaf atom in all four contract sections to be covered exactly once. Missing or duplicate coverage blocks normalization. `coverage_mode=PARTIAL_SHADOW` may be used for investigation, but `normalized_contract` remains `null` and `ready_for_contract_check=false`.

## Why this exists

The active contract authority is heterogeneous. A read-only census on 2026-09-28 found 39 `ACTIVE_ENFORCEMENT` contracts across four top-level section-shape families:

- 26: array / object / array / array
- 8: object / object / object / object
- 4: array / object / object / array
- 1: object / object / array / object

Those shapes cannot be sent directly to `Contract Predicate Semantics V1`, which intentionally accepts typed term arrays only.

The tests use representative shadow fixtures matching those shape families. They prove normalization mechanics and fail-closed behavior; they do **not** claim that any live contract has already been semantically migrated.

## Evidence

Existing candidate self-test marker:

`PASS_LEGACY_CONTRACT_NORMALIZATION_V1=15/15`

Source-projection regression marker:

`PASS_LEGACY_CONTRACT_SOURCE_PROJECTION_V1=8/8`

Grouped-source regression marker:

`PASS_LEGACY_CONTRACT_GROUPED_SOURCE_MAPPING_V1=9/9`

The grouped-source regression proves that an explicitly selected array node can produce one `IN` predicate while preserving exact descendant coverage; overlapping, mismatched, and cross-section mappings fail closed.

The existing self-test includes an end-to-end shadow path:

`legacy fixture -> FULL explicit translation -> typed predicate semantics -> Contract Check Core -> PASS`

No live contract, Supabase row, production workflow, or runtime state is modified by this candidate.
