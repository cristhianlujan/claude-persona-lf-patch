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

print("TRANSVERSAL_E2E_MATRIX_FAIL_CLOSED_V1_PASS")
