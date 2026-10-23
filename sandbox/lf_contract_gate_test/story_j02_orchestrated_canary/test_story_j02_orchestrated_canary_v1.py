import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
CONTRACT = HERE / "story_j02_orchestrated_canary_v1.json"

REQUIRED_SEQUENCE = [
    "PARENT_SKILL_EXECUTION_IN_PROGRESS",
    "ORCHESTRATOR_EXECUTION_IN_PROGRESS",
    "CURRENT_STEP_CONTRACT_READBACK",
    "WORKER_RESOLUTION",
    "TASK_RUNTIME_BINDING_RESOLUTION",
    "TASK_PACKET_SEED",
    "CHILD_PROFILE_EXECUTION_RESERVATION",
    "REAL_DISPATCH_RECEIPT",
    "ENTRY_GUARD_ACCEPTED",
    "FINAL_TASK_PACKET",
    "PROFILE_RUNTIME_ATTACH_EXISTING_CHILD",
    "PROFILE_RUNTIME_COMPLETION",
    "PROFILE_CONTRACT_VALIDATION",
    "J02_INDEPENDENT_JUDGE",
    "DOWNSTREAM_J02_OUTPUT_CONSUMPTION_READBACK",
]


def main() -> None:
    payload = json.loads(CONTRACT.read_text(encoding="utf-8"))
    checks = 0

    assert payload["schema_version"] == "LF_STORY_J02_ORCHESTRATED_CANARY_V1"
    assert payload["status"] == "CANDIDATE_READ_ONLY"
    scope = payload["scope"]
    assert scope["skill_code"] == "SKILL-CREATING-INTEGRAL-USER-STORIES"
    assert scope["parent_operation"] == "EJECUCION_SKILL_LF"
    assert scope["orchestrator_operation"] == "ORQUESTACION_SKILL_LF"
    assert scope["step_id"] == "SCREEN_DECOMPOSITION"
    assert scope["worker_role"] == "SCREEN_DECOMPOSER"
    assert scope["worker_kind"] == "PROFILE"
    assert scope["profile_code"] == "PERFIL-SCREEN-DECOMPOSER-LF"
    assert scope["judge_code"] == "J02_SCREEN_DECOMPOSITION"
    assert scope["validator_path"].endswith("validate_screen_decomposition_visual.py")
    checks += 11

    assert payload["required_sequence"] == REQUIRED_SEQUENCE
    components = payload["required_components"]
    assert components["worker_role_contract"] == "STORY_WORKER_ROLE_CONTRACT_V1"
    assert components["worker_resolver"] == "SKILL_WORKER_RESOLVER_V1"
    assert components["task_runtime_binding"] == "PROFILE_TASK_RUNTIME_BINDING_V1"
    assert components["profile_bridge"] == "PROFILE_EXECUTION_ORCHESTRATED_BRIDGE_V1"
    assert components["profile_capability"] == "PROFILE_EXECUTION_RUNTIME"
    assert components["profile_attach"] == "PROFILE_RUNTIME_ORCHESTRATED_ATTACH_V1"
    assert components["profile_operation"] == "EJECUCION_PERFIL_LF"
    assert components["entry_guard"] == "ORCHESTRATOR_EXECUTION_GUARD_V1"
    checks += 9

    close = payload["positive_close"]
    assert close["runtime_completion"] == "PASS"
    assert close["profile_contract_valid"] == "PASS"
    assert close["j02_result"] == "PASS_WITH_EVIDENCE"
    assert close["j02_version"] == "v0.8"
    assert close["downstream_consumption_observed"] is True
    assert close["receipt_and_guard_real"] is True
    assert close["worker_judge_independence"] is True
    assert close["source_and_head_exact"] is True
    checks += 8

    negatives = set(payload["mandatory_negative_controls"])
    required_negatives = {
        "UNRESOLVED_PROFILE_BINDING_BLOCKS_WITH_ZERO_DURABLE_QUEUE_EFFECT",
        "STALE_J02_CURRENTNESS_BLOCKS_BEFORE_CHILD_DISPATCH",
        "AMBIGUOUS_WORKER_BLOCKS_BEFORE_CHILD_DISPATCH",
        "FABRICATED_GUARD_OR_RECEIPT_BLOCKS",
        "STATIC_TASK_PACKET_DRIFT_AFTER_RECEIPT_BLOCKS",
        "J02_SOURCE_OMISSION_RETURNS_TO_WORKER",
        "WORKER_CANNOT_EXECUTE_OWN_JUDGE",
    }
    assert required_negatives.issubset(negatives)
    checks += 1

    refs = payload["evidence_contract"]["required_refs"]
    assert len(refs) == len(set(refs))
    assert "dispatch_receipt_ref" in refs
    assert "j02_judge_result_ref" in refs
    assert "downstream_consumption_ref" in refs
    dims = payload["evidence_contract"]["crossbind_dimensions"]
    for required in ("source_revision", "orchestrator_execution_id", "child_execution_id", "task_packet_work_digest", "dispatch_receipt_id", "output_digest"):
        assert required in dims
        checks += 1
    checks += 4

    non_goals = set(payload["non_goals"])
    assert "production activation" in non_goals
    assert "new queue or new model runtime" in non_goals
    assert "PASE or POST-PASE modification" in non_goals
    checks += 3

    assert checks == 42
    print("PASS_STORY_J02_ORCHESTRATED_CANARY_V1 checks=42")


if __name__ == "__main__":
    main()
