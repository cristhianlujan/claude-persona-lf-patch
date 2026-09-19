from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
C = json.loads((ROOT / "contracts/runtime_update_operation_disposition_v1.json").read_text())
P = C["pre_repair_state"]
D = C["decision"]
A = C["candidate_after_migration"]
G = C["promotion_gate"]
B = C["deployment_boundary"]

checks = {
    "exact_operation": C["operation_code"] == "ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF",
    "v2_contract": C["contract_code"] == "RUNTIME_UPDATE_OPERATION_DISPOSITION_V2",
    "candidate_pre_state": P["registry_status"] == "CANDIDATO_READ_ONLY" and P["lifecycle_state"] == "OP_CANDIDATE",
    "pre_steps_14": P["total_steps"] == 14 and P["active_steps"] == 0 and P["active_step_contracts"] == 14,
    "pre_bindings_zero": P["active_bindings"] == 0,
    "legacy_runs_disposed": P["open_legacy_executions"] == 0,
    "reenable_classification": D["classification"] == "REENABLE_WITH_DEDICATED_PER_STEP_ENFORCEMENT",
    "retain_distinct": D["retain_as_distinct_operation"] is True,
    "per_step_topology": D["judge_topology"] == "14_DISTINCT_RUNTIME_STEP_JUDGES",
    "server_validation_bound": D["server_validation"] == "public.lf_runtime_update_trust_validation_v1",
    "recorder_bound": D["recorder"] == "public.lf_record_runtime_update_operation_step_v1",
    "begin_bound": D["begin"] == "public.lf_runtime_update_begin_v1",
    "no_profile_judge_clone": D["clone_profile_judges"] is False,
    "candidate_active_steps_14": A["active_steps"] == 14,
    "candidate_bindings_14": A["active_bindings"] == 14,
    "candidate_distinct_judges_14": A["distinct_judges"] == 14,
    "native_model_runtime": A["resolver_mode"] == "NATIVE_MODEL_RUNTIME_WITH_SUPABASE_CONTEXT",
    "step60_revision_precondition": {"bound_revision", "execution_bound_to_target_before_change"}.issubset(set(A["prewrite_required"])),
    "qualification_suite": A["qualification_suite"] == "TS-RUNTIME-OP-UPDATE-V1",
    "qualification_binding": A["qualification_binding"] == "BIND-OP-RUNTIME-UPDATE-V1",
    "still_candidate_before_qualification": A["lifecycle_state"] == "OP_CANDIDATE",
    "candidate_router_not_active": A["router_binding_status"] == "CANDIDATO_READ_ONLY",
    "qualification_required": G["requires_qualification"] is True and G["qualification_currentness"] == "EXACT_REVISION",
    "router_activation_after_promotion": G["router_activation_after_promotion"] is True,
    "promotion_transition": G["transition_action"] == "PROMOTE_OPERATION" and G["target_lifecycle"] == "OP_OPERATIONAL",
    "positive_canary_required": G["positive_governed_canary_required"] is True,
    "deployment_separate": B["runtime_host_deployment_separate"] is True,
    "no_auto_promotion": B["automatic_promotion"] is False,
    "profile_files_forbidden": B["profile_files_change_allowed"] is False,
    "adapter_contract_forbidden": B["adapter_contract_change_allowed"] is False,
    "production_promotion_forbidden": B["production_promotion_allowed"] is False,
}

failed = [k for k, v in checks.items() if not v]
if failed:
    raise SystemExit("FAIL_RUNTIME_UPDATE_OPERATION_DISPOSITION:" + ",".join(failed))

print(f"PASS_RUNTIME_UPDATE_OPERATION_DISPOSITION={sum(checks.values())}/{len(checks)}")
print("REENABLE_TOPOLOGY=14_DISTINCT_RUNTIME_STEP_JUDGES")
print("QUALIFICATION_REQUIRED=true")
print("AUTOMATIC_PROMOTION=false")
print("RUNTIME_HOST_DEPLOYMENT_SEPARATE=true")
