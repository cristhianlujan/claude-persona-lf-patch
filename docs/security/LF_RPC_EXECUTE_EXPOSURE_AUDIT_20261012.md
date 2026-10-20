# LF Supabase API SECURITY DEFINER exposure — read-only audit (2026-10-12)

Status: **DRAFT, NOT APPLIED**. Project `mhwmirqcgxxukpctffuv`. Supabase connector lacks Dashboard API settings, backups, billing usage and API exposed schemas. Never infer exposed schemas solely from pg_catalog.

## Verified
- Org subscription Pro, project ACTIVE_HEALTHY, DB 486681747 bytes (464 MiB), session transaction_read_only off.
- 8 target functions: SECURITY DEFINER and VOLATILE; `has_function_privilege('anon'/'authenticated',oid,'EXECUTE')=true` for each.
- `has_schema_privilege('anon'/'authenticated','programacion','USAGE')=false`. **These 7 are not directly callable through normal role-based SQL in that schema**, though effective REST schema exposure still needs Dashboard readback. `public` has USAGE granted to anon/authenticated.
- None of the eight definitions contains a direct `auth.uid()` or role identity check. Other business-logic / token gates do exist; they are not caller authentication.
- `public.fn_lf_decision_context_asof_record_v1(jsonb,text)` directly INSERTs into `private.lf_decision_context_asof_v1` and accepts `p_actor_execution_id` as caller-supplied text; body checks nonempty and governance metadata, but not caller identity. This is a **potential anonymous RPC write path** if `public` is an exposed schema; do not assert exploitation without a non-writing exposure verification.
- `programacion.fn_ig_causal_lineage_receipts_emit_v1` and `fn_ig_timing_receipts_emit_v1` and `fn_ig_validator_timing_receipt_emit_v1` call `programacion.issue_provenance_receipt` to write `programacion.provenance_receipts`, after reading Vault verifier token; no caller identity check.
- `programacion.fn_input_archive_source_observation_v1` calls `public.fn_lf_evidence_ledger_anchor_v1` for indirect evidence-ledger write; check callee tables before revocation.
- `programacion.fn_input_build_source_manifest_safe_v1` builds JSON from SELECT and helper calls, no direct DML found; nested calls require inspection.
- `programacion.fn_input_governance_release_bundle_receipt_v1` calls `programacion.issue_provenance_receipt`, which records in `programacion.provenance_receipts`; no caller identity check.
- `programacion.fn_input_stage_gate_summary_known_current_v1` aggregates readiness and contract status; no direct write in inspected definition; called helpers may require audit.
- Auth rights and API exposure are distinct. A function with EXECUTE permission is not thereby proven callable over PostgREST.

## Functions and recommendation
| Function | Direct / indirect writing | Caller auth | API classification |
|---|---|---|---|
| programacion.fn_ig_causal_lineage_receipts_emit_v1 | Indirect provenance_receipts via issue_provenance_receipt | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| programacion.fn_ig_timing_receipts_emit_v1 | Indirect provenance_receipts | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| programacion.fn_ig_validator_timing_receipt_emit_v1 | Indirect provenance_receipts | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| programacion.fn_input_archive_source_observation_v1 | Indirect evidence ledger anchor; write target pending callee audit | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| programacion.fn_input_build_source_manifest_safe_v1 | No direct DML detected; helpers pending | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| programacion.fn_input_governance_release_bundle_receipt_v1 | Indirect provenance_receipts | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| programacion.fn_input_stage_gate_summary_known_current_v1 | No direct DML detected; helper review pending | none | NO_EXPUESTA through anon SQL privileges; Dashboard confirmation pending |
| public.fn_lf_decision_context_asof_record_v1 | **Direct INSERT private.lf_decision_context_asof_v1** | no auth.uid()/role | **POTENTIAL EXPLOTABLE_VIA_ANON** contingent on public exposed schema; no non-writing exploit probe performed |

## Legitimate call sites (GitHub code search, bounded / non-exhaustive)
For public.fn_lf_decision_context_asof_record_v1: `sandbox/lf_contract_gate_test/transversal_assets/decision_context_asof/test_decision_context_asof_v1.sql`, `sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/validate_wave1_boundary_contracts_v1.py`, and corresponding contract/docs; review their execution roles before revoking. Other seven functions: direct search returned no indexed non-migration hits in a bounded search; **not proof of absence**. Search all .sql, .py and Edge Functions before merge.

## Manual-only dashboard dependencies
1. Settings → API → Exposed schemas (record exact list and compare to public/programacion).
2. Database → Backups: last successful backup UTC, daily/PITR and retention.
3. Organization → Usage: DB/egress/log ingestion/log query and billing period reset; check restrictions.
4. Review function EXECUTE default ACL and direct grants; ensure explicit revoke covers PUBLIC, anon and authenticated; test in an isolated approved development project first.

## Safety
SQL lives at `docs/security/DRAFT_revoke_risky_rpc_execute.sql`, not `supabase/migrations/**`. It is a proposal, not an executable workflow. Do not apply/merge without Cristhian approval and verified caller impact. This PR makes no schema, secret, configuration or runtime changes.
