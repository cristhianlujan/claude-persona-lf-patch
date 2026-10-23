import json
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "sandbox/lf_contract_gate_test/skill_orchestration_runtime/orquestacion_skill_lf_v1.json"
JUDGE = ROOT / "sandbox/lf_contract_gate_test/skill_orchestration_runtime/judges/orquestacion_skill_lf.yaml"
MIGRATION = ROOT / "supabase/migrations/20261002031000_skill_orchestration_operation_candidate_v1.sql"

EXPECTED_STEPS = [
    "init_execution",
    "bind_parent_skill_execution",
    "load_next_step_contract",
    "resolve_worker",
    "resolve_task_runtime_binding",
    "build_task_packet_seed",
    "reserve_child_execution",
    "issue_dispatch_receipt",
    "entry_guard_readback",
    "finalize_task_packet",
    "dispatch_worker",
    "collect_worker_result",
    "step_judge_handoff",
    "checkpoint_or_close",
]

REQUIRED_REUSE = {
    "ACT-0001",
    "CURRENTNESS_AUTHORITY",
    "SKILL_WORKER_RESOLVER_V1",
    "PROFILE_TASK_RUNTIME_BINDING_V1",
    "PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1",
    "PROFILE_EXECUTION_RUNTIME",
    "EJECUCION_PERFIL_LF",
    "CAPABILITY_EXECUTION_CONTRACT_V1",
    "ORCHESTRATOR_EXECUTION_GUARD_V1",
}


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    judge = yaml.safe_load(JUDGE.read_text(encoding="utf-8"))
    sql = MIGRATION.read_text(encoding="utf-8")
    checks = 0

    assert contract["operation_code"] == "ORQUESTACION_SKILL_LF"
    assert contract["operation_family"] == "ORCHESTRATION"
    assert contract["operation_domain"] == "SKILL_RUNTIME_CONTROL"
    assert contract["operation_type"] == "CHILD_DISPATCH_SUPERVISED"
    assert contract["applies_to_asset_type"] == "SKILL"
    assert contract["lifecycle_state_code"] == "OP_CANDIDATE"
    assert contract["status"] == "CANDIDATO_READ_ONLY"
    assert contract["parent_contract"]["required_parent_operation"] == "EJECUCION_SKILL_LF"
    assert contract["parent_contract"]["parent_status"] == "IN_PROGRESS"
    checks += 9

    steps = contract["steps"]
    assert len(steps) == 14
    assert [item["step_id"] for item in steps] == EXPECTED_STEPS
    assert [item["order"] for item in steps] == list(range(0, 140, 10))
    assert all(item["required_evidence"] for item in steps)
    checks += 4

    assert REQUIRED_REUSE.issubset(set(contract["reused_components"]))
    assert contract["boundaries"]["executes_models"] is False
    assert contract["boundaries"]["owns_profile_runtime"] is False
    assert contract["boundaries"]["owns_skill_runtime"] is False
    assert contract["boundaries"]["owns_router"] is False
    assert contract["boundaries"]["owns_currentness"] is False
    assert contract["boundaries"]["creates_new_queue"] is False
    assert contract["boundaries"]["production_enabled"] is False
    assert contract["boundaries"]["runtime_activation_by_registration"] is False
    assert contract["boundaries"]["pase_modified"] is False
    assert contract["boundaries"]["post_pase_modified"] is False
    checks += 11

    assert judge["judge_code"] == "JUDGE-ORQUESTACION-SKILL-LF-v0.1"
    assert judge["scope"] == "ORQUESTACION_SKILL_LF"
    assert judge["status"] == "CANDIDATO_READ_ONLY"
    assert judge["independent_from_worker"] is True
    assert "self_judging" in judge["fail_if"]
    assert "dispatch_receipt_is_real_and_cross_bound" in judge["pass_if"]
    checks += 6

    assert "'ORQUESTACION_SKILL_LF'" in sql
    assert "'ORCHESTRATION'" in sql
    assert "'OP_CANDIDATE'" in sql
    assert "'CANDIDATO_READ_ONLY'" in sql
    assert "insert into public.lf_operation_registry" in sql.lower()
    assert "insert into public.lf_operation_steps" in sql.lower()
    assert "insert into public.lf_operation_step_contracts" in sql.lower()
    assert "insert into public.lf_operation_judges" in sql.lower()
    assert "insert into public.lf_operation_step_judge_bindings" in sql.lower()
    assert "v_steps<>14 or v_contracts<>14 or v_bindings<>14" in sql
    checks += 10

    for step_id in EXPECTED_STEPS:
        assert step_id in sql
        checks += 1

    forbidden = (
        "'ORQUESTACION_PIPELINE_LF'",
        "'OP_OPERATIONAL'",
        "APROBADO_PRODUCCION_CONTROLADA",
        "create table",
        "create trigger",
        "create or replace function",
        "runtime_enabled',true",
    )
    lowered = sql.lower()
    for token in forbidden:
        assert token.lower() not in lowered
        checks += 1

    assert checks == 61
    print("PASS_SKILL_ORCHESTRATION_OPERATION_V1 checks=61")


if __name__ == "__main__":
    main()
