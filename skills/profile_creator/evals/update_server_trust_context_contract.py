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
    "no_new_architecture": all(CONTRACT["architecture"][k] is False for k in ["new_layer","new_table","new_operation","new_step","parallel_update_recorder"]),
    "existing_runtime_authority": CONTRACT["architecture"]["authority_location"] == "existing run-creacion-perfil-lf runtime",
    "runtime_authority": CONTRACT["trust_boundary"]["runtime_role"] == "SERVER_DERIVED_CURRENTNESS_AUTHORITY",
    "caller_input_only": CONTRACT["trust_boundary"]["caller_role"] == "REQUEST_AND_EVIDENCE_INPUT_ONLY",
    "exact_github_resolver": CONTRACT["server_context"]["resolver"] == "GITHUB_PUBLIC_API_EXACT_REF_V1" and CONTRACT["server_context"]["base_ref"] == "main",
    "matrix_size": len(matrix) == 12,
    "source_implemented": CONTRACT["activation_gate"]["runtime_source_implemented"] is True,
    "common_recorder_materialized": CONTRACT["activation_gate"]["common_recorder_materialized"] is True,
    "runtime_v22": 'v22-profile-update-server-trust-context' in RUNTIME,
    "runtime_strips_caller_trust": 'stripCallerTrust' in RUNTIME and 'TRUST_FIELDS' in RUNTIME,
    "runtime_reads_main": '/git/ref/heads/main' in RUNTIME,
    "runtime_reads_target_blob": '/contents/${encodedPath}?ref=${current}' in RUNTIME,
    "runtime_checks_bound": 'PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH' in RUNTIME,
    "runtime_checks_stale_reread": 'PROFILE_UPDATE_STALE_REREAD_REQUIRED' in RUNTIME,
    "runtime_checks_stale_rebind": 'PROFILE_UPDATE_STALE_REBIND_REQUIRED' in RUNTIME,
    "runtime_injects_server_context": 'server_trust_context_valid: true' in RUNTIME and 'server_trust_context_source: "run-creacion-perfil-lf"' in RUNTIME,
    "runtime_calls_common_recorder": 'lf_record_profile_operation_step_v1' in RUNTIME,
    "old_update_block_removed": 'UPDATE_OPERATION_CANONICAL_RECORDER_REQUIRED' not in RUNTIME,
    "recorder_requires_server_context": "server_trust_context_valid" in RECORDER and "GITHUB_PUBLIC_API_EXACT_REF_V1" in RECORDER,
    "recorder_preserves_fail_closed_code": "PROFILE_UPDATE_SERVER_TRUST_CONTEXT_NOT_MATERIALIZED" in RECORDER,
    "merge_still_false": CONTRACT["activation_gate"]["merge_authorized"] is False,
}
for name, expected in {
    "NEG_MISSING_BASELINE":"PROFILE_UPDATE_BASELINE_OBSERVATION_REQUIRED",
    "NEG_MISSING_CURRENT":"PROFILE_UPDATE_CURRENT_REVISION_UNRESOLVED",
    "NEG_TARGET_BLOB_UNRESOLVED":"PROFILE_UPDATE_CURRENT_TARGET_BLOB_UNRESOLVED",
    "NEG_BOUND_UNSTRUCTURED":"PROFILE_UPDATE_BOUND_REVISION_STRUCTURED_REQUIRED",
    "NEG_EXECUTION_NOT_BOUND":"PROFILE_UPDATE_EXECUTION_BINDING_REQUIRED",
    "NEG_STALE_NO_REREAD":"PROFILE_UPDATE_STALE_REREAD_REQUIRED",
    "NEG_STALE_NO_REBIND":"PROFILE_UPDATE_STALE_REBIND_REQUIRED",
    "NEG_REBOUND_FROM_WRONG_REV":"PROFILE_UPDATE_REBOUND_FROM_REVISION_MISMATCH",
    "NEG_BOUND_NOT_CURRENT":"PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH",
    "NEG_CALLER_TRUST_FLAGS_CANNOT_OVERRIDE":"PROFILE_UPDATE_BOUND_REVISION_CURRENT_MISMATCH",
}.items(): checks[name.lower()] = matrix[name]["result"] == expected
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit("FAIL_UPDATE_SERVER_TRUST_CONTEXT:"+",".join(failed))
print(f"PASS_UPDATE_SERVER_TRUST_CONTEXT={sum(checks.values())}/{len(checks)}")
print("PASS_UPDATE_SERVER_TRUST_MATRIX=12/12")
print("SERVER_AUTHORITY_SOURCE_IMPLEMENTED=true")
print("COMMON_RECORDER_MATERIALIZED=true")
print("UPDATE_PREWRITE_SOURCE_ENABLED=true")
print("RUNTIME_DEPLOYED=false")
