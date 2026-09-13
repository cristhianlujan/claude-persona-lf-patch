#!/usr/bin/env python3
from pathlib import Path
import copy
import importlib.util
import json

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("matrix_engine_v1", HERE / "matrix_engine_v1.py")
M = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(M)

snapshot = json.loads((HERE / "live_snapshot_20260913_v1.json").read_text(encoding="utf-8"))

# Missing any reservation guard must fail closed independently. Router provenance is
# deliberately distinct from policy/registry trigger protections.
all_missing = {
    "router_provenance_required": False,
    "policy_snapshot_on_insert": False,
    "required_policy_resolution_guard": False,
    "policy_snapshot_immutable_and_currentness_guard": False,
    "registered_operation_required": False,
}
assert set(M.reservation_findings(all_missing)) == {
    "DIRECT_OPERATION_RESERVATION_ROUTER_PROVENANCE_NOT_REQUIRED",
    "DIRECT_OPERATION_RESERVATION_POLICY_SNAPSHOT_NOT_ENFORCED",
    "DIRECT_OPERATION_RESERVATION_REQUIRED_POLICY_GUARD_NOT_ENFORCED",
    "DIRECT_OPERATION_RESERVATION_POLICY_CURRENTNESS_GUARD_NOT_ENFORCED",
    "DIRECT_OPERATION_RESERVATION_REGISTRY_GUARD_NOT_ENFORCED",
}

# Historical evidence and a declarative router_read clause are evidence, not structural
# entry binding. They must continue to block closure until mandatory provenance exists.
for status in (
    "HISTORICAL_CHAIN_ONLY",
    "CONTRACT_REQUIRES_ROUTER_READ_BUT_ENTRY_NOT_BOUND",
    "NO_EXECUTION_EVIDENCE",
):
    findings = M.unrouted_operation_findings({
        "operation_code": "SYNTHETIC_INTERNAL",
        "status": "APROBADO_PRODUCCION_CONTROLADA",
        "operation_family": "CAPTURE",
        "operation_type": "SKILL_EXECUTION",
        "classification": "INTERNAL_SUBOPERATION",
        "provenance_status": status,
    })
    assert findings == [f"SYNTHETIC_INTERNAL:INTERNAL_ENTRY_PROVENANCE_NOT_PROVEN:{status}"]

assert M.unrouted_operation_findings({
    "operation_code": "SYNTHETIC_INTERNAL",
    "status": "APROBADO_PRODUCCION_CONTROLADA",
    "operation_family": "CAPTURE",
    "operation_type": "SKILL_EXECUTION",
    "classification": "INTERNAL_SUBOPERATION",
    "provenance_status": "PROVEN",
}) == []

# Graph parser must understand both governed sequential aliases and known external
# repair/stop transitions without inventing missing-step findings.
clean_graph = {
    "operation_code": "SYNTHETIC_GRAPH",
    "active_steps": [
        {"step_id":"a","required":True,"step_order":1,"execution_order":10,"next_if_pass":"NEXT_LOWEST_STEP_ORDER","next_if_blocked":"RETURN_TO_WORKER_FOR_SELF_REPAIR_OR_BACKEND_CONFIG","step_contract_present":True},
        {"step_id":"b","required":True,"step_order":2,"execution_order":20,"next_if_pass":"NEXT_BY_EXECUTION_ORDER","next_if_blocked":"HITL_PAUSE","step_contract_present":True},
        {"step_id":"c","required":True,"step_order":3,"execution_order":30,"next_if_pass":None,"next_if_blocked":"STOP_AND_REGISTER_BLOCKED_OR_BATCH_PARTIAL","step_contract_present":True},
    ],
}
assert M.derive_step_graph_findings(clean_graph) == []

# A terminal before a required step must remain a hard reachability finding.
early_terminal = copy.deepcopy(clean_graph)
early_terminal["active_steps"][0]["next_if_pass"] = None
early_findings = M.derive_step_graph_findings(early_terminal)
assert "SYNTHETIC_GRAPH:REQUIRED_STEP_UNREACHABLE:b" in early_findings
assert "SYNTHETIC_GRAPH:REQUIRED_STEP_UNREACHABLE:c" in early_findings

# Missing internal targets, missing required step contracts and self-loops are distinct.
broken_graph = copy.deepcopy(clean_graph)
broken_graph["active_steps"][0]["next_if_blocked"] = "missing_internal_step"
broken_graph["active_steps"][1]["step_contract_present"] = False
broken_graph["active_steps"][2]["next_if_blocked"] = "c"
broken_findings = M.derive_step_graph_findings(broken_graph)
assert "SYNTHETIC_GRAPH:BLOCK_TARGET_MISSING:a->missing_internal_step" in broken_findings
assert "SYNTHETIC_GRAPH:REQUIRED_STEP_CONTRACT_MISSING:b" in broken_findings
assert "SYNTHETIC_GRAPH:UNJUSTIFIED_SELF_LOOP:c->c" in broken_findings

# A new registry operation appearing without a matrix row must make universe coverage fail.
expanded = copy.deepcopy(snapshot)
expanded["metadata"]["operation_count"] += 1
expanded_result = M.evaluate(expanded)
assert expanded_result["status"] == "BLOCK"
assert "MATRIX_OPERATION_UNIVERSE_INCOMPLETE" in expanded_result["findings"]

# An unexplained execution-like active route may not be silently treated as inspection.
bad_inspection = copy.deepcopy(snapshot)
bad_inspection["inspection_routes"][0]["action_code"] = "EXECUTE_UNKNOWN"
bad_inspection_result = M.evaluate(bad_inspection)
assert "ADAPTER:EXECUTE_UNKNOWN:UNPROVEN_NON_EXECUTION_ROUTE" in bad_inspection_result["findings"]

# Named distribution modes not explicitly proven fail-closed may never be silently accepted.
unknown_mode = copy.deepcopy(snapshot["direct_operations"][0])
unknown_mode["invalid_mode_verdict"] = "NOT_EXECUTED"
assert any("INVALID_DISTRIBUTION_MODE_NOT_PROVEN:NOT_EXECUTED" in x for x in M.direct_operation_findings(unknown_mode))

print("TRANSVERSAL_E2E_MATRIX_FAIL_CLOSED_V1_PASS")
