#!/usr/bin/env python3
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "transversal_e2e_matrix"
SPEC = importlib.util.spec_from_file_location("matrix_engine_v1", SHARED / "matrix_engine_v1.py")
M = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(M)

result = M.evaluate_file(SHARED / "live_snapshot_20260913_v1.json")
findings = set(result["findings"])

# S30 must consume the shared matrix and remain fail-closed until its strategy/control
# surfaces and transversal bypass findings are repaired/proven.
assert result["coverage"]["operations_accounted"] == 36
assert "CREACION_ESTRATEGIA_LF:ACTIVE_CONTRACT_MISSING" in findings
assert "CREACION_ESTRATEGIA_LF:REQUIRED_POLICY_RESOLUTION_MISMATCH:5!=4" in findings
assert "DIRECT_OPERATION_RESERVATION_ROUTER_PROVENANCE_NOT_REQUIRED" in findings
assert "ROUTER_TARGET_HINT_CAN_OVERRIDE_CANONICAL_TARGET" in findings

# This is a detector regression, not a waiver: a clean/freeze receipt must require
# result.status == PASS after the underlying findings are repaired.
assert result["status"] == "BLOCK"
print("S30_TRANSVERSAL_E2E_MATRIX_CONSUMER_V1_PASS expected_closure_state=BLOCK")
