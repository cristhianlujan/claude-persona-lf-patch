# M0.14 — Spec traversal checklist v1

**Plan:** `IG_CURATOR_VALIDATOR_REFACTOR_V2`  
**Unit:** `M0.14` / `PAULO-107` / L3  
**Contract:** `INPUT_READINESS_CONTRACT`, id `37`, revision `5.13`  
**DB spec MD5:** `1d9709b94d20ee8036ad985edffaaf01`  
**Run contract snapshot SHA256:** `125e73215036c76f79847d6821e97942b38f80e3ca46206786d8f96dae1c6c38`  
**M0.11 merge:** `c716d142bb5e92757616b4f31901c226fa58ef20`  
**M0.11 classification SHA256:** `2104c02aaa2828cfc0476ca9307c9eacb88db0e1090d9641c1d9971a692fe118`  
**M0.11 detailed snapshot SHA256:** `c22492d0b7d4f3873b3cd595a12106683bcfd546947bd410c436b2338931e59f`  
**Checklist canonical SHA256:** `54d5153e00026ad8361e722ee035567b816870501e02d8ae53c9abdab4372ad8`

## Purpose

This is the manual predecessor of M1.A8. Every Input Governance run report produced after approval of this checklist must enumerate the exact 60 top-level clauses below and assign exactly one status to each: `APPLIED`, `N/A`, or `BLOCKED`.

This checklist does not decide semantic correctness by itself. It proves traversal completeness and forces an explicit disposition for every clause.

## Required row schema

Each report row MUST contain:

- `clause`: one of the 60 exact keys below;
- `status`: exactly one of `APPLIED`, `N/A`, `BLOCKED`;
- `evidence_refs`: non-empty evidence references for the disposition;
- `reason`: mandatory for `N/A` and `BLOCKED`; optional for `APPLIED`.

A report is invalid when any of the following is true:

1. row count is not exactly 60;
2. any canonical clause is missing;
3. any clause is duplicated or unknown;
4. any status is outside the allowlist;
5. `evidence_refs` is empty;
6. an `N/A` or `BLOCKED` row has no non-empty `reason`.

## Contract identity

The checklist binds two distinct identities and MUST NOT treat them as interchangeable:

- DB textual identity: spec MD5 `1d9709b94d20ee8036ad985edffaaf01`;
- persisted run binding: `contract_snapshot_sha256=125e73215036c76f79847d6821e97942b38f80e3ca46206786d8f96dae1c6c38` for revision 5.13.

The checklist is aligned to M0.11's exact 60-key snapshot. M1.A8 must consume the same key set when it replaces the manual report with an automated traversal receipt.

## Closed clause list

| # | Clause | Status | Evidence | Reason when N/A/BLOCKED |
|---:|---|---|---|---|
| 1 | `api_data_contract_readiness` | | | |
| 2 | `applicability_source_grounding` | | | |
| 3 | `applicability_status_invariants` | | | |
| 4 | `assertion_contract` | | | |
| 5 | `assertion_relevance_policy` | | | |
| 6 | `assertion_required_fields` | | | |
| 7 | `assertion_truth_evaluated` | | | |
| 8 | `audit_remediation` | | | |
| 9 | `auto_promotion` | | | |
| 10 | `builder_regression_v2` | | | |
| 11 | `builder_regression_v3` | | | |
| 12 | `candidate_as_own_authority` | | | |
| 13 | `canon_vs_proposal_separation` | | | |
| 14 | `canonical_universe_rule` | | | |
| 15 | `consumer` | | | |
| 16 | `contract_revision` | | | |
| 17 | `curator_fields_immutable_after_insert` | | | |
| 18 | `data_placement` | | | |
| 19 | `design_system_readiness` | | | |
| 20 | `deterministic_stage_summary` | | | |
| 21 | `direct_source_readback_required` | | | |
| 22 | `empty_collection_semantics` | | | |
| 23 | `family_stage_requirements` | | | |
| 24 | `family_universe_source` | | | |
| 25 | `freshness_gate` | | | |
| 26 | `governance_authority_policy` | | | |
| 27 | `legacy_contract_v1_authoritative` | | | |
| 28 | `legacy_contract_v2_authoritative` | | | |
| 29 | `llm_as_sole_gate` | | | |
| 30 | `negative_tests` | | | |
| 31 | `not_applicable_positive_authority_contract` | | | |
| 32 | `not_applicable_requires_reason` | | | |
| 33 | `parameterization_contract` | | | |
| 34 | `production_activation` | | | |
| 35 | `proposal_contract` | | | |
| 36 | `readiness_levels` | | | |
| 37 | `readiness_stage_hierarchy` | | | |
| 38 | `remediation_revision` | | | |
| 39 | `revision_lineage` | | | |
| 40 | `schema_version` | | | |
| 41 | `screen_graph_contract` | | | |
| 42 | `screen_graph_scoping` | | | |
| 43 | `semantic_coherence_contract` | | | |
| 44 | `semantic_component_sufficiency` | | | |
| 45 | `semantic_depth_contract` | | | |
| 46 | `semantic_fail_closed` | | | |
| 47 | `source_manifest` | | | |
| 48 | `source_precedence` | | | |
| 49 | `source_ref_contract` | | | |
| 50 | `source_refs_required_per_family` | | | |
| 51 | `source_snapshot_binding` | | | |
| 52 | `stage_authority_policy` | | | |
| 53 | `stage_boundary_contract` | | | |
| 54 | `statuses` | | | |
| 55 | `story_ready_rule` | | | |
| 56 | `validator_component_binding` | | | |
| 57 | `validator_evidence_required_fields` | | | |
| 58 | `validator_identity_must_differ_from_curator` | | | |
| 59 | `validator_independence_required` | | | |
| 60 | `validator_requires_run_status` | | | |

## First-use rule

The first post-merge run report must persist, in `public.lf_eventos`, all 60 rows plus the checklist Git path, checklist Git blob SHA, checklist canonical SHA256, contract revision 5.13, DB spec MD5 and run contract snapshot SHA256.

For documentation-only units, a clause may be `N/A` when the unit does not exercise that runtime/product concern, but the row still requires evidence of unit scope and a reason. `N/A` never means “not inspected.”

## Negative desk tests

The checklist validator must reject at least:

- a 59-row report missing one canonical clause;
- a 60-row report where any `N/A` lacks a reason.

These are structural completeness tests only; they do not replace semantic validation.

## Upgrade path

M1.A8 / `PAULO-055` supersedes this manual checklist with an automated `spec traversal receipt`. The automated receipt must preserve these exact clause keys and completeness rules.
