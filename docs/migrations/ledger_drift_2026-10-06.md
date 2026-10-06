# Migration ledger drift — 2026-10-06

Read-only snapshot for reconciliation. These ledger versions were present in sandbox on 2026-10-06 but no exact `<version>_<name>.sql` existed on `main` at the snapshot. They are **remote_only drift external to the migration-train pilot** and must not be confused with the pilot migration's exact parity result.

| version | name | created_by |
|---|---|---|
| 20261006010757 | engineering_effective_dependency_semantics_v1 | xcrisrhian191080@gmail.com |
| 20261006010940 | engineering_effective_dependency_semantics_ekb_v1 | xcrisrhian191080@gmail.com |
| 20261006020117 | engineering_transversal_explicit_routing_pilot_v1 | xcrisrhian191080@gmail.com |
| 20261006020235 | engineering_transversal_explicit_routing_ekb_v1 | xcrisrhian191080@gmail.com |
| 20261006020610 | engineering_transversal_multi_probe_v1 | xcrisrhian191080@gmail.com |
| 20261006020733 | engineering_transversal_multi_probe_restore_v1 | xcrisrhian191080@gmail.com |
| 20261006021239 | engineering_transversal_multi_capability_probe_evidence_v1 | xcrisrhian191080@gmail.com |
| 20261006022215 | engineering_transversal_sequential_array_v1 | xcrisrhian191080@gmail.com |
| 20261006022241 | engineering_transversal_sequence_three_step_probe_v1 | xcrisrhian191080@gmail.com |
| 20261006022406 | engineering_transversal_sequence_eight_step_compile_probe_v1 | xcrisrhian191080@gmail.com |
| 20261006022443 | engineering_transversal_sequence_probe_restore_and_ekb_v1 | xcrisrhian191080@gmail.com |
| 20261006023342 | ig_plan_transversal_execution_metadata_v1 | xcrisrhian191080@gmail.com |
| 20261006023410 | ig_plan_transversal_execution_metadata_declared_only_fix_v1 | xcrisrhian191080@gmail.com |
| 20261006023441 | ig_plan_transversal_execution_m810_two_checkpoints_fix_v1 | xcrisrhian191080@gmail.com |
| 20261006023520 | ig_plan_transversal_execution_metadata_ekb_v1 | xcrisrhian191080@gmail.com |
| 20261006032612 | input_governance_shadow_v2_reuse_semantic_result_v1 | xcrisrhian191080@gmail.com |
| 20261006033232 | input_governance_shadow_v2_reuse_canonical_graph_context_v1 | xcrisrhian191080@gmail.com |
| 20261006033600 | input_governance_shadow_v2_reuse_semantic_graph_context_v1 | xcrisrhian191080@gmail.com |
| 20261006035054 | ig_dynamic_selection_existing_work_integration_v1 | xcrisrhian191080@gmail.com |
| 20261006090926 | engineering_parallel_bootstrap_pilot_v1 | xcrisrhian191080@gmail.com |
| 20261006091128 | engineering_parallel_bootstrap_pilot_search_path_v1 | xcrisrhian191080@gmail.com |
| 20261006113037 | engineering_exact_write_packet_overlay_v1 | xcrisrhian191080@gmail.com |
| 20261006113050 | engineering_exact_write_packet_hook_v1 | xcrisrhian191080@gmail.com |
| 20261006113459 | rollback_engineering_exact_write_packet_overlay_v1 | xcrisrhian191080@gmail.com |
| 20261006115937 | ig_m411_require_bound_independent_oracle_receipt_v2 | xcrisrhian191080@gmail.com |
| 20261006121620 | ig_n6_independence_cross_schema_guard_v1 | xcrisrhian191080@gmail.com |
| 20261006121636 | ekb_independence_cross_schema_closure_v1 | xcrisrhian191080@gmail.com |
| 20261006121727 | ig_n6_cross_schema_sourcepack_block_v1 | xcrisrhian191080@gmail.com |
| 20261006122745 | independent_assurance_qualified_cross_schema_closure_v1 | xcrisrhian191080@gmail.com |
| 20261006122950 | ig_n6_bind_qualified_independent_assurance_inputs_v1 | xcrisrhian191080@gmail.com |
| 20261006130352 | independent_assurance_1_0_1_candidate_registry_v1 | xcrisrhian191080@gmail.com |
| 20261006131353 | independent_assurance_callers_candidate_versions_v1 | xcrisrhian191080@gmail.com |
| 20261006131756 | independent_assurance_qualified_cross_schema_v1_canonical | xcrisrhian191080@gmail.com |
| 20261006135957 | engineering_parallel_pilot_checkpoint_accounting_v1 | xcrisrhian191080@gmail.com |

| 20261006150831 | enable_rls_input_governance_tables | xcrisrhian191080@gmail.com |
| 20261006154819 | engineering_parallel_executor_governance_report_cleanup | xcrisrhian191080@gmail.com |

Count: **36 remote_only**.

## Changes since the first snapshot

- `20261006142429 engineering_parallel_executor_v1` is no longer remote_only: the exact file is now present on `main`.
- `20261006150831 enable_rls_input_governance_tables` is new remote_only drift and is flagged as a **security change** because it enables RLS on Input Governance tables. It requires reconciliation/provenance review before being treated as source-parity-clean.
- `20261006154819 engineering_parallel_executor_governance_report_cleanup` is remote_only because `main` currently carries `20261006154800_engineering_parallel_executor_governance_report_cleanup.sql`, not the ledger's exact version.


## Source-only reconciliation candidate

- Draft PR #1799 reconstructs all **36/36** remote-only sources directly from `supabase_migrations.schema_migrations.statements[1]`.
- `NO_RECONSTRUIBLE = 0`: every listed ledger row has exactly one non-null statement.
- No DDL/apply is performed by #1799.
- `20261006154800_engineering_parallel_executor_governance_report_cleanup.sql` is proposed as a pure rename to ledger identity `20261006154819_...`; the source blob is identical, so no duplicate is introduced.
- Reverified after IG-1 #1797 merged: the drift count remains **36**; IG-1 itself is exact on both main and ledger and is not part of this set.
