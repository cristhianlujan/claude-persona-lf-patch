from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = json.loads((ROOT / "contracts/update_server_trust_context_contract.json").read_text(encoding="utf-8"))
RUNTIME = (ROOT.parents[1] / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8")
RECORDER = (ROOT / "contracts/profile_operation_common_recorder_v1.sql").read_text(encoding="utf-8")

matrix = {row["case"]: row for row in CONTRACT["decision_matrix"]}
checks = {
    "update_scope": CONTRACT.get("operation_code") == "ACTUALIZACION_PERFIL_LF",
    "prewrite_scope": CONTRACT.get("step_id") == "pre_write_execution_binding_gate",
    "no_new_layer": CONTRACT["architecture"]["new_layer"] is False,
    "no_new_table": CONTRACT["architecture"]["new_table"] is False,
    "no_new_operation": CONTRACT["architecture"]["new_operation"] is False,
    "no_new_step": CONTRACT["architecture"]["new_step"] is False,
    "existing_runtime_authority": CONTRACT["architecture"]["authority_location"] == "existing run-creacion-perfil-lf runtime",
    "existing_jsonb_persistence": CONTRACT["architecture"]["persistence_location"] == "existing lf_operation_execution_steps.evidence_payload",
    "no_parallel_update_recorder": CONTRACT["architecture"]["parallel_update_recorder"] is False,
    "caller_input_only": CONTRACT["trust_boundary"]["caller_role"] == "REQUEST_AND_EVIDENCE_INPUT_ONLY",
    "runtime_authority": CONTRACT["trust_boundary"]["runtime_role"] == "SERVER_DERIVED_CURRENTNESS_AUTHORITY",
    "recorder_structural_only": CONTRACT["trust_boundary"]["recorder_role"] == "TRANSACTIONAL_STRUCTURAL_PERSISTENCE",
    "caller_cannot_authorize_server_context": all(x in CONTRACT["trust_boundary"]["caller_must_not_authorize"] for x in ["trusted_current_revision","server_trust_context_valid","server_trust_context_source"]),
    "runtime_derives_core": all(x in CONTRACT["trust_boundary"]["runtime_must_derive"] for x in ["persisted_baseline_revision","github_main_revision_sha","github_target_blob_sha","bound_revision_match","continuity_result"]),
    "exact_github_resolver": CONTRACT["server_context"]["resolver"] == "GITHUB_PUBLIC_API_EXACT_REF_V1" and CONTRACT["server_context"]["base_ref"] == "main",
    "not_request_payload": CONTRACT["server_context"]["must_not_be_taken_from_request_payload"] is True,
    "after_current_step_check": CONTRACT["server_context"]["must_be_computed_after_current_step_check"] is True,
    "before_recorder": CONTRACT["server_context"]["must_be_computed_before_recorder_call"] is True,
    "matrix_size": len(matrix) == 12,
    "pos_current_bound": matrix["POS_CURRENT_BOUND"]["result"] == "CURRENT_BOUND",
    "pos_stale_rebound": matrix["POS_STALE_REBOUND_CURRENT"]["result"] == "STALE_REBOUND_CURRENT",
    "neg_missing_baseline": matrix["NEG_MISSING_BASELINE"]["result"] == "PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED",
    "neg_missing_current": matrix["NEG_MISSING_CURRENT"]["result"] == "PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED",
    "neg_target_blob": matrix["NEG_TARGET_BLOB_UNRESOLVED"]["result"] == "PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED",
    "neg_bound_unstructured": matrix["NEG_BOUND_UNSTRUCTURED"]["result"] == "PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED",
    "neg_execution_unbound": matrix["NEG_EXECUTION_NOT_BOUND"]["result"] == "PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED",
    "neg_stale_no_reread": matrix["NEG_STALE_NO_REREAD"]["result"] == "PROFILE_UPDATE_STALE_REREAD_REQUIRED",
    "neg_stale_no_rebind": matrix["NEG_STALE_NO_REBIND"]["result"] == "PROFILE_UPDATE_STALE_REBIND_REQUIRED",
    "neg_wrong_rebound": matrix["NEG_REBOUND_FROM_WRONG_REV"]["result"] == "PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH",
    "neg_bound_not_current": matrix["NEG_BOUND_NOT_CURRENT"]["result"] == "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH",
    "neg_caller_override": matrix["NEG_CALLER_TRUST_FLAGS_CANNOT_OVERRIDE"]["result"] == "PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH",
    "runtime_update_still_blocked": "UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED" in RUNTIME,
    "recorder_server_context_still_blocked": "PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED" in RECORDER,
    "activation_runtime_false": CONTRACT["activation_gate"]["runtime_source_implemented"] is False,
    "activation_write_false": CONTRACT["activation_gate"]["update_write_enabled"] is False,
    "activation_deploy_false": CONTRACT["activation_gate"]["runtime_deployment_authorized"] is False,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL_UPDATE_SERVER_TRUST_CONTEXT:" + ",".join(failed))
print(f"PASS_UPDATE_SERVER_TRUST_CONTEXT={sum(checks.values())}/{len(checks)}")
print(f"PASS_UPDATE_SERVER_TRUST_MATRIX={len(matrix)}/{len(matrix)}")
print("SERVER_AUTHORITY_SOURCE_IMPLEMENTED=false")
print("COMMON_RECORDER_MATERIALIZED=false")
print("UPDATE_WRITE_ENABLED=false")
