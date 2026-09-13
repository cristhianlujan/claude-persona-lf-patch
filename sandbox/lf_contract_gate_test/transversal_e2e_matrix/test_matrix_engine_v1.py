#!/usr/bin/env python3
from pathlib import Path
import importlib.util

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("matrix_engine_v1", HERE / "matrix_engine_v1.py")
M = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(M)

result = M.evaluate_file(HERE / "live_snapshot_20260913_v1.json")
assert result["status"] == "BLOCK", result
assert result["coverage"] == {
    "operations_expected": 36,
    "operations_accounted": 36,
    "routed_operations_expected": 14,
    "routed_operations_accounted": 14,
    "unrouted_operations_expected": 22,
    "unrouted_operations_accounted": 22,
    "active_route_rows_expected": 22,
    "active_route_rows_accounted": 22,
}, result

required_findings = {
    "CREACION_CARD_LF:REQUIRED_STEP_UNREACHABLE:contract_judge",
    "CREACION_CARD_LF:REQUIRED_STEP_UNREACHABLE:close",
    "CREACION_SKILL_LF:REQUIRED_STEP_UNREACHABLE:pre_write_execution_binding_gate",
    "ACTUALIZACION_DB_LF:BLOCK_TARGET_MISSING:preflight->close",
    "ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF:ACTIVE_STEPS_MISSING",
    "CREACION_ESTRATEGIA_LF:ACTIVE_CONTRACT_MISSING",
    "CREACION_ESTRATEGIA_LF:REQUIRED_POLICY_RESOLUTION_MISMATCH:5!=4",
    "ROUTER_TARGET_HINT_CAN_OVERRIDE_CANONICAL_TARGET",
    "DIRECT_OPERATION_RESERVATION_ROUTER_PROVENANCE_NOT_REQUIRED",
    "EJECUCION_SKILL_LF:INVALID_DISTRIBUTION_MODE_POLICY_BYPASS:BYPASS_AND_READY",
    "ACTUALIZACION_PERFIL_LF:INVALID_DISTRIBUTION_MODE_POLICY_BYPASS:POLICY_FILTER_BYPASS_BUT_OTHER_GATE_BLOCKS",
    "ORQUESTACION_PIPELINE_LF:INTERNAL_ENTRY_PROVENANCE_NOT_PROVEN:PENDING",
}
missing = required_findings.difference(result["findings"])
assert not missing, f"missing expected matrix findings: {sorted(missing)}"

assert M.classify_unrouted({
    "status": "APROBADO_PRODUCCION_CONTROLADA",
    "operation_family": "CAPTURE",
    "operation_type": "SKILL_EXECUTION",
}) == "INTERNAL_SUBOPERATION"
assert M.classify_unrouted({
    "status": "CANDIDATO_READ_ONLY",
    "operation_family": "ANY",
    "operation_type": "UPDATE_PROTOCOL",
}) == "CANDIDATE_INACTIVE"
assert M.classify_unrouted({
    "status": "APROBADO_PRODUCCION_CONTROLADA",
    "operation_family": "ORCHESTRATION",
    "operation_type": "SCHEDULER_DRIVEN",
}) == "SCHEDULER"

print(f"TRANSVERSAL_E2E_MATRIX_ENGINE_V1_PASS findings={result['finding_count']} coverage=36/36")
