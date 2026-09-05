from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "contracts/profile_operation_common_recorder_v1.sql").read_text(encoding="utf-8")
RUNTIME = (ROOT.parents[1] / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8")
MIGRATION = (ROOT.parents[1] / "supabase/migrations/20260903205327_lf_profile_operation_common_recorder_v1.sql").read_text(encoding="utf-8")
checks = {
 "common_rpc_only":"lf_record_profile_operation_step_v1" in SQL,
 "no_parallel_update_rpc":"lf_record_actualizacion_perfil_step_v1" not in SQL and "lf_record_actualizacion_perfil_step_v1" not in RUNTIME,
 "create_update_exact_scope":"v_execution.operation_code not in ('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF')" in SQL,
 "execution_lock":"for update;" in SQL.lower(),
 "operation_aware_contract_status":"ACTIVE_ENFORCEMENT" in SQL and "else 'ACTIVE'" in SQL,
 "active_binding_required":"status='ACTIVE_ENFORCEMENT'" in SQL or "status = 'ACTIVE_ENFORCEMENT'" in SQL,
 "prior_step_order_enforced":"PRIOR_REQUIRED_STEP_NOT_CLEAN" in SQL,
 "prior_clean_binding_driven":"pb.clean_result_value is null or es.status<>pb.clean_result_value" in SQL or "pb.clean_result_value is null or es.status <> pb.clean_result_value" in SQL,
 "required_evidence_enforced":"REQUIRED_EVIDENCE_MISSING" in SQL,
 "server_trust_required":"server_trust_context_valid" in SQL and "server_trust_context_source" in SQL,
 "server_resolver_required":"GITHUB_PUBLIC_API_EXACT_REF_V1" in SQL,
 "server_identity_bound":"v_trust->>'repository'<>coalesce(v_execution.target_repo,'')" in SQL and "v_trust->>'target_path'<>coalesce(v_execution.target_path,'')" in SQL,
 "server_revision_shapes":"revision_sha" in SQL and "target_blob_sha" in SQL and "baseline_revision" in SQL,
 "fail_closed_code_preserved":"PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED" in SQL,
 "transactional_insert":"insert into public.lf_operation_execution_steps" in SQL.lower(),
 "live_source_marker":"UPDATE_PREWRITE_SERVER_TRUST_ENABLED" in SQL,
 "migration_service_role_only":"grant execute on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) to service_role;" in MIGRATION,
 "runtime_v22":"v22-profile-update-server-trust-context" in RUNTIME,
 "runtime_strips_trust":"stripCallerTrust" in RUNTIME,
 "runtime_calls_common":"lf_record_profile_operation_step_v1" in RUNTIME,
 "runtime_old_block_removed":"UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED" not in RUNTIME,
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit("FAIL_PROFILE_OPERATION_COMMON_RECORDER:"+",".join(failed))
print(f"PASS_PROFILE_OPERATION_COMMON_RECORDER_CHECKS={sum(checks.values())}/{len(checks)}")
print("COMMON_RECORDER_LIVE_SERVICE_ROLE_ONLY=true")
print("UPDATE_PREWRITE_SERVER_TRUST_CONTEXT_REQUIRED=true")
print("CALLER_SELF_ATTESTATION_AUTHORITY=false")
print("UPDATE_PREWRITE_SOURCE_ENABLED=true")
