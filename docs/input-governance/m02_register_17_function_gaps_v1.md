# M0.2 — Register 17 unrepresented IG functions

Plan: `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
Rule prerequisite: `R16`  
Scope: registry only; no runtime change.

## Preflight

Current live M0.2 proper IG universe: **113 functions**.

Current unrepresented functions: **17**.

Gap-set SHA-256:

`6be620fe2dcf02350e4a7f7970281d1556296b20599e202f7c6d578c2a5e4691`

The 17 functions are:

- 12 `programacion.fn_guard_input_*` trigger guards;
- 4 public wrappers:
  - `public.fn_input_governance_curator_materialize_v1`
  - `public.fn_input_governance_execute`
  - `public.fn_input_governance_safe_autofix_v1`
  - `public.fn_input_governance_validator_validate_v1`
- `programacion.fn_input_source_inventory_lookup_l1_v1`.

`programacion.fn_lf_router_input_governance_resolve_v1` is already represented by the dedicated asset `PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1`; it is not part of the 17.

## Capability-first registration

No new asset or relation is created.

- Guard set expands 1 → 13 members.
- Curation set expands 7 → 8 with its public wrapper.
- Execution set expands 4 → 5 with its public wrapper.
- Remediation set expands 1 → 2 with its public wrapper.
- Validation set expands 6 → 7 with its public wrapper.
- Candidate source inventory asset adds the lookup function as its single function member.

The source-inventory asset remains:
- `CANDIDATO`
- `READ_ONLY`
- `CANDIDATE_READ_ONLY`
- `NOT_APPROVED`
- L2 note: `decidir en L2 si lo absorbe T-SOURCE`.

## New membership fingerprints

| Asset | Count | SHA-256 |
|---|---:|---|
| Curation | 8 | `99a1192ddc1cb17420317a159b26127e184eb87d88750ae95f66ff52a41925ba` |
| Execution | 5 | `2fad0d188cc5011661eb8697e5c5e109e34f049dd0cdb3123e2dc54d98fcbaf5` |
| Guard | 13 | `e2e7b9954003bc6547efa5ef1c7df676bbf5aedf77065c53c5db803031d16c7e` |
| Remediation | 2 | `8c9cf35f768169820ce44998650083954dada340a590d8c7a2a8b4824f3f133b` |
| Validation | 7 | `4532074de481760ec0f801f27b7e2379a873fc4a2b41a9ed878c0dfcc163d729` |
| Source Inventory L1 | 1 | `4d1bb266643b9ad1c849a7a6a1dd3e6ac6d89a461616929062f10c79701578ce` |

## Postflight

Expected registry gap count after migration: **0**.

This does not mark M0.2 DONE by itself; liveness/classification and #1312 still require the separate review already identified.
