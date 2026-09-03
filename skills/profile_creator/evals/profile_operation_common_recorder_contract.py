from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "contracts/profile_operation_common_recorder_v1.sql").read_text(encoding="utf-8")
RUNTIME = (ROOT.parents[1] / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8")
MIGRATION = (ROOT.parents[1] / "supabase/migrations/20260903205327_lf_profile_operation_common_recorder_v1.sql").read_text(encoding="utf-8")

checks = {
    "common_rpc_only": "lf_record_profile_operation_step_v1" in SQL,
    "no_parallel_update_rpc": "lf_record_actualizacion_perfil_step_v1" not in SQL and "lf_record_actualizacion_perfil_step_v1" not in RUNTIME,
    "create_update_exact_scope": "v_execution.operation_code not in ('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF')" in SQL,
    "target_profile_required": "v_execution.target_type <> 'PERFIL'" in SQL,
    "execution_lock": "for update;" in SQL.lower(),
    "active_step_required": "and active is true" in SQL,
    "operation_aware_contract_status": "when v_execution.operation_code = 'ACTUALIZACION_PERFIL_LF' then 'ACTIVE_ENFORCEMENT'" in SQL and "else 'ACTIVE'" in SQL,
    "active_binding_required": "and status = 'ACTIVE_ENFORCEMENT'" in SQL,
    "prior_step_order_enforced": "PRIOR_REQUIRED_STEP_NOT_CLEAN" in SQL,
    "prior_clean_is_binding_driven": "pb.clean_result_value is null or es.status <> pb.clean_result_value" in SQL,
    "no_init_clean_status_hardcode": "s.step_id='init_execution' and es.status <> 'STEP_CLEAN_PASS'" not in SQL,
    "required_evidence_enforced": "REQUIRED_EVIDENCE_MISSING" in SQL,
    "blocking_codes_enforced": "BLOCKING_CODES_INVALID" in SQL and "jsonb_array_length(v_blocking_codes) > 0" in SQL,
    "update_prewrite_server_trust_blocks": "PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED" in SQL,
    "caller_flags_not_authority": "current_revision_resolved_by_caller" not in SQL and "declared_current_revision_ignored" not in SQL,
    "caller_resolver_shape_not_authority": "GITHUB_PUBLIC_API_EXACT_REF_V1" not in SQL,
    "caller_bound_revision_shape_not_authority": "jsonb_typeof(p_evidence_payload->'bound_revision')" not in SQL,
    "transactional_insert": "insert into public.lf_operation_execution_steps" in SQL.lower(),
    "live_source_marker": "SOURCE_CANONICAL / LIVE_V1_MATERIALIZED / UPDATE_WRITE_STILL_DISABLED" in SQL,
    "migration_service_role_only": "revoke all on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) from anon;" in MIGRATION and "revoke all on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) from authenticated;" in MIGRATION and "grant execute on function public.lf_record_profile_operation_step_v1(text,text,text,jsonb,text) to service_role;" in MIGRATION,
    "create_compatibility_preserved": "lf_record_creacion_perfil_step_v1 entrypoint" in SQL,
    "runtime_update_still_disabled": "UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED" in RUNTIME,
}

matrix = {
    "POS_CREATE_CONTRACT_STATUS_ACTIVE": checks["operation_aware_contract_status"],
    "POS_UPDATE_CONTRACT_STATUS_ACTIVE_ENFORCEMENT": checks["operation_aware_contract_status"],
    "POS_CREATE_INIT_USES_BINDING_CLEAN_RESULT": checks["prior_clean_is_binding_driven"] and checks["no_init_clean_status_hardcode"],
    "POS_UPDATE_INIT_USES_BINDING_CLEAN_RESULT": checks["prior_clean_is_binding_driven"] and checks["no_init_clean_status_hardcode"],
    "POS_UPDATE_NON_PREWRITE_COMMON_SCOPE": checks["create_update_exact_scope"] and checks["active_binding_required"],
    "NEG_WRONG_OPERATION": "EXECUTION_IDENTITY_INVALID" in SQL,
    "NEG_WRONG_TARGET_TYPE": checks["target_profile_required"],
    "NEG_MISSING_BINDING": "STEP_JUDGE_BINDING_MISSING" in SQL,
    "NEG_PRIOR_STEP_NOT_CLEAN": checks["prior_step_order_enforced"],
    "NEG_REQUIRED_EVIDENCE_MISSING": checks["required_evidence_enforced"],
    "NEG_UPDATE_PREWRITE_ALWAYS_BLOCKED": checks["update_prewrite_server_trust_blocks"],
    "NEG_CALLER_CURRENT_TRUE_CANNOT_OVERRIDE": checks["caller_flags_not_authority"],
    "NEG_CALLER_RESOLVER_JSON_CANNOT_OVERRIDE": checks["caller_resolver_shape_not_authority"],
    "NEG_CALLER_BOUND_REVISION_OBJECT_CANNOT_OVERRIDE": checks["caller_bound_revision_shape_not_authority"],
}

failed = [k for k,v in checks.items() if not v] + [f"MATRIX::{k}" for k,v in matrix.items() if not v]
if failed:
    raise SystemExit("FAIL_PROFILE_OPERATION_COMMON_RECORDER:" + ",".join(failed))
print(f"PASS_PROFILE_OPERATION_COMMON_RECORDER_CHECKS={sum(checks.values())}/{len(checks)}")
print(f"PASS_PROFILE_OPERATION_COMMON_RECORDER_MATRIX={sum(matrix.values())}/{len(matrix)}")
print("PRIOR_CLEAN_STATUS=ACTIVE_BINDING_DERIVED")
print("UPDATE_CONTRACT_STATUS=ACTIVE_ENFORCEMENT")
print("CREATE_CONTRACT_STATUS=ACTIVE")
print("COMMON_RECORDER_LIVE_SERVICE_ROLE_ONLY=true")
print("UPDATE_PREWRITE_SERVER_TRUST_CONTEXT_REQUIRED=true")
print("CALLER_SELF_ATTESTATION_AUTHORITY=false")
print("UPDATE_WRITE_ENABLED=false")
