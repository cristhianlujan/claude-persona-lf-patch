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

The template catalogs are authoring shards of the single `LF_CONTRACT_CHECK` capability, not separate capabilities or parallel engines. A template is reusable only when the four legacy contract sections match exactly. `legacy_translation_template_v1.py` materializes a normal translation bound to exact operation, contract identity, and semantic-source SHA-256.

No template is selected by names, regex, semantic similarity, or model judgment.

### Batch 1

`legacy_translation_templates_v1.json` covers the three repeated semantic definitions:

- `RULE_MUTATION_V1`: create/update rule contracts (2 live contracts);
- `APP_SHELL_MUTATION_V1`: create/update app-shell contracts (2 live contracts);
- `PRE_EKB_GATE_V1`: shared PRE-EKB definition (7 live contracts).

Coverage after Batch 1: 11/40 active contracts and 3/32 semantic definitions.

### Batch 2

`legacy_translation_templates_batch2_v1.json` explicitly authors nine additional live definitions:

- adapter depth;
- adapter examples depth;
- card examples depth;
- profile general depth;
- skill general depth;
- Card no-close enforcement;
- Skill no-close enforcement;
- DS build no-close enforcement;
- Profile no-close enforcement.

The no-close templates use explicit closure applicability where the legacy field is closure-only, and blocked condition arrays become one explicit `ANY` predicate. Depth contract requirement arrays become explicit `ALL` predicates. This grouping is authored in the catalog; the normalizer does not infer it.

Coverage after Batch 2: 20/40 active contracts and 12/32 semantic definitions.

### Batch 3

`legacy_translation_templates_batch3_v1.json` explicitly authors ten additional definitions:

- adapter update;
- profile update;
- skill update;
- router update;
- profile-runtime update;
- Input Governance execution;
- profile execution;
- skill execution;
- Learning Bridge governance gate;
- vulnerability coverage repair.

Update contracts encode pre-write requirements as explicit `ALL`, prohibited states/actions as `FALSE`/blocking `ANY`, and closure evidence as `ALL`. Execution contracts preserve exact identity/config fields with `EQ`, bounded enumerations with `IN`, output-presence requirements with `EXISTS`, and no-write/runtime/production constraints explicitly.

The vulnerability-coverage conditional is represented as an explicit implication: when a coverage claim is attempted, `regression_suite_pass` must be true. No condition is inferred from names.

Cumulative read-only authority coverage after Batch 3:

- 40 active contracts;
- 32 distinct semantic definitions;
- 30/40 active contracts explicitly covered;
- 22/32 semantic definitions explicitly authored;
- 10 contracts / 10 semantic definitions still pending.

This remains translation-authoring coverage only. No `lf_operation_contracts` row is changed to `TYPED`, and no runtime, production, carrier, or automatic-impact cutover is authorized.

## Evidence

- `PASS_LEGACY_CONTRACT_NORMALIZATION_V1=15/15`
- `PASS_LEGACY_CONTRACT_SOURCE_PROJECTION_V1=8/8`
- `PASS_LEGACY_CONTRACT_GROUPED_SOURCE_MAPPING_V1=9/9`
- `PASS_LEGACY_TRANSLATION_TEMPLATE_V1=13/13`
- candidate Batch 2 regression: `PASS_LEGACY_TRANSLATION_TEMPLATES_BATCH2_V1=10/10`
- candidate Batch 3 regression: `PASS_LEGACY_TRANSLATION_TEMPLATES_BATCH3_V1=11/11`

Batch regressions are designed to instantiate every exact template in their shard, normalize with FULL coverage, generate evidence-backed satisfying/clear facts, evaluate Predicate Semantics at CLOSURE, require Contract Check Core `PASS`, and reject semantic drift. These markers are candidate self-test markers; PASE remains plan-only and does not itself execute these Python regressions.

No live contract, production workflow, runtime state, or automatic-impact state is modified by these authoring catalogs.
