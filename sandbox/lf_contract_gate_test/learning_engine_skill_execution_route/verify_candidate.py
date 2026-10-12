#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
candidate = json.loads((ROOT / "candidate_contract.json").read_text(encoding="utf-8"))
run = json.loads((ROOT / "aud018_full_route.json").read_text(encoding="utf-8"))
reg = json.loads((ROOT / "cross_family_regression.json").read_text(encoding="utf-8"))

assert candidate["operation_code"] == "EJECUCION_SKILL_LF"
assert candidate["persistent_status"] == "CANDIDATO_READ_ONLY"
assert candidate["structural_readback"]["persistent_router_action_count"] == 0
assert candidate["structural_readback"]["missing_judge_bindings"] == 0
assert candidate["structural_readback"]["evidence_key_drift"] == 0
assert candidate["structural_readback"]["required_policies"] == candidate["structural_readback"]["resolved_required_policies"] == 4
assert candidate["allowed"]["read_only"] is True
assert candidate["allowed"]["github_write"] is False
assert candidate["allowed"]["runtime_change"] is False
assert candidate["allowed"]["automatic_impact"] is False

assert run["router_before"]["status"] == "BLOCKED"
assert run["router_before"]["blocking_code"] == "BLOCK_OPERATION_NOT_REGISTERED"
assert run["router_during_sandbox"]["status"] == "READY_TO_EXECUTE"
assert run["router_during_sandbox"]["operation_code"] == "EJECUCION_SKILL_LF"
assert run["router_during_sandbox"]["required_policy_count"] == run["router_during_sandbox"]["resolved_policy_count"] == 4
assert run["skill_output"]["score"]["total"] == sum(v for k, v in run["skill_output"]["score"].items() if k not in {"total", "scale"})
assert run["execution_steps"]["semantic_judge"] == "NOT_EXECUTED_INDEPENDENTLY"
assert run["result"] == "PATCH_CANDIDATE_READY_WITH_OPEN_GATES"
assert "INDEPENDENT_SEMANTIC_REVIEW_PENDING" in run["skill_output"]["blocking_codes"]
assert "ACT0046_SOURCE_PARITY_DRIFT" in run["skill_output"]["blocking_codes"]
assert run["runtime_change"] is False and run["production_change"] is False and run["automatic_impact"] is False

assert reg["case_count"] == len(reg["target_change_cases"]) + len(reg["non_target_cases"]) == 23
assert reg["observed"]["non_target_changed_count"] == 0
assert reg["observed"]["target_existing_skill_before"] == "BLOCKED/BLOCK_OPERATION_NOT_REGISTERED"
assert reg["observed"]["target_existing_skill_after"] == "READY_TO_EXECUTE/EJECUCION_SKILL_LF"
assert reg["observed"]["target_missing_skill_after"] == "BLOCKED/BLOCK_ASSET_NOT_FOUND"
assert reg["persistent_postcondition"]["SKILL_EXECUTE_active_router_mapping"] is False
assert reg["result"] == "PASS_NO_NON_TARGET_ROUTER_REGRESSION"

print("MOTOR_SKILL_EXECUTION_ROUTE_CANDIDATE_VERIFY_PASS 23/23_ROUTER_CASES")
print("CLAIM_CEILING SANDBOX_CANDIDATE_ONLY_NO_INDEPENDENT_SEMANTIC_PASS")
