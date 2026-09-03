from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "contracts/profile_operation_common_recorder_v1.sql").read_text(encoding="utf-8")
RUNTIME = (ROOT.parents[1] / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8")

checks = {
    "common_rpc_only": "lf_record_profile_operation_step_v1" in SQL,
    "no_parallel_update_rpc": "lf_record_actualizacion_perfil_step_v1" not in SQL and "lf_record_actualizacion_perfil_step_v1" not in RUNTIME,
    "create_update_exact_scope": "v_execution.operation_code not in ('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF')" in SQL,
    "target_profile_required": "v_execution.target_type <> 'PERFIL'" in SQL,
    "execution_lock": "for update;" in SQL.lower(),
    "active_step_required": "and active is true" in SQL,
    "active_contract_required": "and status = 'ACTIVE'" in SQL,
    "active_binding_required": "and status = 'ACTIVE_ENFORCEMENT'" in SQL,
    "prior_step_order_enforced": "PRIOR_REQUIRED_STEP_NOT_CLEAN" in SQL,
    "required_evidence_enforced": "REQUIRED_EVIDENCE_MISSING" in SQL,
    "blocking_codes_enforced": "BLOCKING_CODES_INVALID" in SQL and "jsonb_array_length(v_blocking_codes) > 0" in SQL,
    "update_prewrite_trust_chain_required": "PROFILE_UPDATE_PREWRITE_TRUST_CHAIN_REQUIRED" in SQL,
    "trusted_resolver_required": "GITHUB_PUBLIC_API_EXACT_REF_V1" in SQL,
    "bound_revision_object_required": "jsonb_typeof(p_evidence_payload->'bound_revision') <> 'object'" in SQL,
    "execution_binding_required": "execution_bound_to_target_before_change" in SQL,
    "declared_current_ignored_required": "declared_current_revision_ignored" in SQL,
    "transactional_insert": "insert into public.lf_operation_execution_steps" in SQL.lower(),
    "source_only_marker": "SOURCE_ONLY / NOT_DEPLOYED / NO_RUNTIME_ENABLEMENT" in SQL,
    "create_compatibility_preserved": "lf_record_creacion_perfil_step_v1 entrypoint" in SQL,
    "runtime_update_still_disabled": "UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED" in RUNTIME,
}

# Source-level positive/negative matrix: each fail-closed guard must be independently represented.
matrix = {
    "POS_CREATE_COMMON_SCOPE": checks["create_update_exact_scope"] and checks["create_compatibility_preserved"],
    "POS_UPDATE_PREWRITE_TRUSTED": checks["update_prewrite_trust_chain_required"] and checks["trusted_resolver_required"],
    "NEG_WRONG_OPERATION": "EXECUTION_IDENTITY_INVALID" in SQL,
    "NEG_WRONG_TARGET_TYPE": checks["target_profile_required"],
    "NEG_MISSING_BINDING": "STEP_JUDGE_BINDING_MISSING" in SQL,
    "NEG_PRIOR_STEP_NOT_CLEAN": checks["prior_step_order_enforced"],
    "NEG_REQUIRED_EVIDENCE_MISSING": checks["required_evidence_enforced"],
    "NEG_UPDATE_UNBOUND": checks["execution_binding_required"],
    "NEG_UPDATE_NO_TRUSTED_RESOLVER": checks["trusted_resolver_required"],
    "NEG_UPDATE_DECLARED_CURRENT_NOT_IGNORED": checks["declared_current_ignored_required"],
}

failed = [k for k,v in checks.items() if not v] + [f"MATRIX::{k}" for k,v in matrix.items() if not v]
if failed:
    raise SystemExit("FAIL_PROFILE_OPERATION_COMMON_RECORDER:" + ",".join(failed))
print(f"PASS_PROFILE_OPERATION_COMMON_RECORDER_CHECKS={sum(checks.values())}/{len(checks)}")
print(f"PASS_PROFILE_OPERATION_COMMON_RECORDER_MATRIX={sum(matrix.values())}/{len(matrix)}")
print("COMMON_RECORDER_SOURCE_ONLY=true")
print("UPDATE_WRITE_ENABLED=false")
