# M0.11 — INPUT_READINESS_CONTRACT 5.13 preliminary enforcement matrix

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M0.11` / `PAULO-112` / L3  
**Contract:** `programacion.contratos.id=37`, revision `5.13`  
**Contract spec MD5:** `1d9709b94d20ee8036ad985edffaaf01`  
**Current Git baseline:** `cb7c6186253af5c5e208f363effd65609e32f809`  
**Classification SHA256:** `2104c02aaa2828cfc0476ca9307c9eacb88db0e1090d9641c1d9971a692fe118`  
**Detailed snapshot SHA256:** `c22492d0b7d4f3873b3cd595a12106683bcfd546947bd410c436b2338931e59f`

## Scope and method

This is a preliminary AS-IS matrix. It does not change runtime and it does not claim that a textual reference alone proves semantic enforcement.

For each of the 60 top-level contract clauses:

1. Direct SQL readers were located in `programacion.*`, scoped to Input Governance functions (`fn_input_%` plus `fn_lf_router_input_governance_resolve_v1`).
2. Curator and Validator reachability was calculated by a static call walk to depth 8 from their live roots. This is a locator, not a proof of runtime execution for every branch.
3. Trigger enforcement was checked on `programacion.input_readiness_runs`, `input_family_assessments`, and `input_gap_proposals`.
4. The three Edge functions were read at the exact Git baseline. They transport parameters/identity and call RPCs; none reads the contract JSON or a top-level contract clause directly.
5. `UNREAD` means no direct Input-Governance SQL reader, relevant trigger reader, or Edge contract reader was found by this method. It does **not** mean the behavior is necessarily absent; literals may reimplement the rule outside the contract.

Edge evidence at baseline:

- Agent blob `2140c07b67a36cb93c89d056f8180f4736de2eca`
- Curator blob `6e5ccf8f817d575183bc619b312016b7e653aeab`
- Validator blob `5b53db7633da386770a0b9dd6ed5bc12bfcf0bd3`
- Direct contract-key reads in Edge: `0`

## Current counts

| Metric | Current |
|---|---:|
| Contract clauses | 60 |
| Clauses with direct IG function reader | 17 |
| Clauses without direct IG function reader | 43 |
| Clauses with relevant trigger reader | 5 |
| Clauses with no SQL-function/trigger direct reader | 42 |
| Curator-path clauses | 6 |
| Validator-path clauses | 5 |
| Curator+Validator shared | 5 |
| OTHER_IG | 11 |
| Edge direct contract reads | 0 |

Classification distribution:

- `UNREAD`: 42
- `OTHER_IG`: 11
- `TRIGGER`: 1
- `CURATOR_TRIGGER_SHARED`: 1
- `CURATOR_VALIDATOR_SHARED`: 2
- `CURATOR_VALIDATOR_TRIGGER_SHARED`: 3

## Reconciliation with the original plan claim

Event `lf_eventos#19195` stated `44/60` clauses not read by an Input Governance function and `3` shared by Curator and Validator. Current readback is `43/60` without a direct IG function reader and `5` Curator+Validator shared. After including trigger-only enforcement, `42/60` have no direct SQL/trigger reader.

The old event persisted only aggregate counts, not its clause-level matrix or query snapshot. Therefore M0.11 records the delta but does **not** attribute it to a specific code change without evidence. Future count claims must persist the clause-level matrix and digest used to derive them.

## 60/60 preliminary matrix

| Clause | Classification | Direct evidence |
|---|---|---|
| `api_data_contract_readiness` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `applicability_source_grounding` | UNREAD | no direct reader found |
| `applicability_status_invariants` | UNREAD | no direct reader found |
| `assertion_contract` | UNREAD | no direct reader found |
| `assertion_relevance_policy` | UNREAD | no direct reader found |
| `assertion_required_fields` | UNREAD | no direct reader found |
| `assertion_truth_evaluated` | UNREAD | no direct reader found |
| `audit_remediation` | UNREAD | no direct reader found |
| `auto_promotion` | UNREAD | no direct reader found |
| `builder_regression_v2` | UNREAD | no direct reader found |
| `builder_regression_v3` | UNREAD | no direct reader found |
| `candidate_as_own_authority` | OTHER_IG | `fn_input_governance_worker_spec*` |
| `canon_vs_proposal_separation` | UNREAD | no direct reader found |
| `canonical_universe_rule` | UNREAD | no direct reader found |
| `consumer` | CURATOR_VALIDATOR_SHARED | Curator materialize/recurate/rebind paths plus shared orchestration/worker-spec references |
| `contract_revision` | CURATOR_VALIDATOR_TRIGGER_SHARED | Curator + Validator paths and 11 relevant trigger bindings |
| `curator_fields_immutable_after_insert` | UNREAD | no direct reader found |
| `data_placement` | UNREAD | no direct reader found |
| `design_system_readiness` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `deterministic_stage_summary` | UNREAD | no direct reader found |
| `direct_source_readback_required` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `empty_collection_semantics` | UNREAD | no direct reader found |
| `family_stage_requirements` | CURATOR_VALIDATOR_TRIGGER_SHARED | classify/stage helpers on both paths + 2 relevant triggers |
| `family_universe_source` | UNREAD | no direct reader found |
| `freshness_gate` | UNREAD | no direct reader found |
| `governance_authority_policy` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `legacy_contract_v1_authoritative` | UNREAD | no direct reader found |
| `legacy_contract_v2_authoritative` | UNREAD | no direct reader found |
| `llm_as_sole_gate` | UNREAD | no direct reader found |
| `negative_tests` | OTHER_IG | `fn_input_governance_module_health` |
| `not_applicable_positive_authority_contract` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `not_applicable_requires_reason` | UNREAD | no direct reader found |
| `parameterization_contract` | UNREAD | no direct reader found |
| `production_activation` | UNREAD | no direct reader found |
| `proposal_contract` | UNREAD | no direct reader found |
| `readiness_levels` | UNREAD | no direct reader found |
| `readiness_stage_hierarchy` | UNREAD | no direct reader found |
| `remediation_revision` | UNREAD | no direct reader found |
| `revision_lineage` | UNREAD | no direct reader found |
| `schema_version` | CURATOR_VALIDATOR_TRIGGER_SHARED | Curator + Validator reachable code and 3 relevant trigger bindings |
| `screen_graph_contract` | UNREAD | no direct reader found |
| `screen_graph_scoping` | UNREAD | no direct reader found |
| `semantic_coherence_contract` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `semantic_component_sufficiency` | UNREAD | no direct reader found |
| `semantic_depth_contract` | TRIGGER | semantic-depth guards on assessment insert/update |
| `semantic_fail_closed` | UNREAD | no direct reader found |
| `source_manifest` | CURATOR_TRIGGER_SHARED | context/currentness path + run/assessment/proposal guards |
| `source_precedence` | OTHER_IG | context-manifest and worker-spec helpers |
| `source_ref_contract` | UNREAD | no direct reader found |
| `source_refs_required_per_family` | OTHER_IG | `fn_input_governance_shadow_family_spec_v2` |
| `source_snapshot_binding` | UNREAD | no direct reader found |
| `stage_authority_policy` | UNREAD | no direct reader found |
| `stage_boundary_contract` | UNREAD | no direct reader found |
| `statuses` | CURATOR_VALIDATOR_SHARED | `bootstrap_classify_v2` / `semantic_probe_v3` reachable from both paths |
| `story_ready_rule` | OTHER_IG | context-manifest helpers |
| `validator_component_binding` | UNREAD | no direct reader found |
| `validator_evidence_required_fields` | UNREAD | no direct reader found |
| `validator_identity_must_differ_from_curator` | UNREAD | no direct reader found |
| `validator_independence_required` | UNREAD | no direct reader found |
| `validator_requires_run_status` | UNREAD | no direct reader found |

## Important interpretation

The most material result is not only the count `42`. Several critical Validator clauses remain `UNREAD`, including:

- `validator_independence_required`
- `validator_identity_must_differ_from_curator`
- `validator_evidence_required_fields`
- `validator_component_binding`
- `validator_requires_run_status`
- `assertion_contract`
- `llm_as_sole_gate`

Some behaviors corresponding to those clauses exist as hard-coded checks elsewhere. M0.11 deliberately does not relabel that as “spec read”. M1.A6/A7/A8/A9 are responsible for converting this preliminary inventory into explicit ownership, enforcement, tests, traversal receipts, and executable/versioned spec behavior.

## R16 / R17

This unit produces documentation/readback only. No runtime function, Edge function, contract, migration, deploy, promotion, or production state is changed. R17 is therefore not applicable.
