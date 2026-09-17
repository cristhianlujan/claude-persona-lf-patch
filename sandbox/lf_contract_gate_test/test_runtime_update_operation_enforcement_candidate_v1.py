from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent / "profile_execution_runtime"
SQL = (ROOT / "runtime_update_operation_enforcement_candidate_v1.sql").read_text(encoding="utf-8")
STRUCT = json.loads((ROOT / "runtime_update_judge_structural_source_v1.json").read_text(encoding="utf-8"))
PREWRITE = json.loads((ROOT / "runtime_update_prewrite_judge_semantics_v1.json").read_text(encoding="utf-8"))

OP = "ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF"
GENERIC = "JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-v1"
PREWRITE_JUDGE = "JUDGE-ACTUALIZACION-RUNTIME-EJECUCION-PERFIL-LF-PREWRITE-v1"

assert STRUCT["operation_code"] == OP
assert STRUCT["judge_code"] == GENERIC
assert STRUCT["constraints"]["target_type"] == "OPERATION_CODE"
assert STRUCT["constraints"]["target_code"] == "EJECUCION_PERFIL_LF"
assert STRUCT["constraints"]["no_runtime_activation"] is True
assert STRUCT["constraints"]["no_auto_promotion"] is True

assert PREWRITE["operation_code"] == OP
assert PREWRITE["judge_code"] == PREWRITE_JUDGE
assert PREWRITE["constraints"]["server_assertions_required"] is True
assert PREWRITE["constraints"]["caller_assertions_are_not_authority"] is True
required_pass = {
    "execution_id_matches_current_execution",
    "target_type_is_operation_code",
    "target_code_is_ejecucion_perfil_lf",
    "target_path_matches_execution_target",
    "execution_bound_to_target_before_change_is_true",
    "bound_revision_is_structured",
    "bound_revision_matches_current_resolved_revision",
}
assert set(PREWRITE["pass_if"]) == required_pass

sql_lower = SQL.lower()
assert "source only / not applied" in sql_lower
assert "begin;" in sql_lower
assert "rollback;" in sql_lower
assert OP.lower() in sql_lower
assert "runtime_update" in sql_lower
assert "candidato_read_only" in sql_lower
assert "op_candidate" in sql_lower
assert "v_steps_total<>14" in sql_lower
assert "v_steps_active<>0" in sql_lower
assert "v_contracts_total<>14" in sql_lower
assert "v_judges<>0" in sql_lower
assert "v_bindings<>0" in sql_lower
assert "v_active_steps<>14" in sql_lower
assert "v_bindings<>14" in sql_lower
assert "v_generic<>13" in sql_lower
assert "v_prewrite<>1" in sql_lower
assert PREWRITE_JUDGE.lower() in sql_lower
assert GENERIC.lower() in sql_lower
assert "bound_revision" in sql_lower
assert "execution_bound_to_target_before_change" in sql_lower
assert "required_evidence_missing" in sql_lower
assert "step_recorded" in sql_lower
assert "lf_record_operation_step_core_v1" in sql_lower

# Fail closed against the defect we found: runtime-update contracts must not keep the Profile Update judge.
assert "mini_judge_code like 'judge-actualizacion-perfil-lf%'" in sql_lower
assert "v_wrong_judge<>0" in sql_lower

# This candidate repairs only enforcement topology. It must not activate/promote the operation or modify Router.
for forbidden in (
    "update public.lf_operation_registry",
    "insert into public.lf_router_action_registry",
    "update public.lf_router_action_registry",
    "delete from public.lf_router_action_registry",
    "lifecycle_state_code='op_operational'",
    "status='produccion_controlada'",
):
    assert forbidden not in sql_lower, forbidden

print("PASS_RUNTIME_UPDATE_OPERATION_ENFORCEMENT_CANDIDATE_V1")
