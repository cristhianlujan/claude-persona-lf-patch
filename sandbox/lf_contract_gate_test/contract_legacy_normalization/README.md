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

All nine keys are mandatory. A change to any of them changes the source digest and invalidates the old translation. Audit/transport fields such as timestamps and execution ids are deliberately excluded.

### Explicit grouped source mappings

A mapping may bind either one legacy leaf atom or an explicitly selected parent node such as an array/object. The selected node must remain inside the declared contractual section and its `expected_source` must match the complete node exactly.

When a parent node is selected, every descendant leaf atom is counted as covered by that one mapping. This allows one semantic unit such as an allowed-value array to become one `IN`, `ALL`, `ANY`, or other explicitly authored predicate instead of splitting it mechanically.

Grouping is never inferred by the normalizer. Overlapping mappings, source drift, cross-section mappings, missing coverage, and duplicate coverage fail closed. `coverage_mode=FULL` requires every leaf atom in all four contract sections to be covered exactly once.

## Exact live translation templates

`legacy_translation_templates_v1.json` is the first explicit live-authoring batch. A template is reusable only when the four legacy contract sections match exactly. `legacy_translation_template_v1.py` performs exact structural matching and then materializes a normal translation bound to the exact operation, contract identity, and semantic-source SHA-256.

It does not select a template by names, regex, semantic similarity, or model judgment.

Latest read-only authority census used for this batch:

- 40 active contracts;
- 32 distinct semantic definitions;
- 3 exact semantic definitions explicitly authored in this batch;
- 11/40 active contracts covered by those three repeated definitions;
- 29 semantic definitions / 29 contracts still require explicit authoring.

The first three templates cover:

- `RULE_MUTATION_V1`: create/update rule contracts (2 live contracts);
- `APP_SHELL_MUTATION_V1`: create/update app-shell contracts (2 live contracts);
- `PRE_EKB_GATE_V1`: the shared PRE-EKB contract definition (7 live contracts).

This is translation coverage only. It does not mutate live contract rows, switch any contract to `TYPED`, authorize runtime, or perform Contract Check cutover.

## Evidence

- `PASS_LEGACY_CONTRACT_NORMALIZATION_V1=15/15`
- `PASS_LEGACY_CONTRACT_SOURCE_PROJECTION_V1=8/8`
- `PASS_LEGACY_CONTRACT_GROUPED_SOURCE_MAPPING_V1=9/9`
- `PASS_LEGACY_TRANSLATION_TEMPLATE_V1=13/13`

The template regression proves exact reuse across different operation/contract identities, source-bound translation hashes, FULL normalization coverage, source-drift rejection, transport-metadata tolerance, and explicit grouped PRE-EKB semantics.

No live contract, production workflow, runtime state, or automatic-impact state is modified by this candidate.
