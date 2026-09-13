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

# S26 consumes the same matrix, adding its profile/runtime authority expectations.
# Current snapshot intentionally proves that invalid distribution mode can reduce
# policy consumption and that the runtime-update route lacks an executable step path.
assert result["coverage"]["operations_accounted"] == 36
assert "EJECUCION_PERFIL_LF:INVALID_DISTRIBUTION_MODE_POLICY_BYPASS:BYPASS_AND_READY" in findings
assert "ACTUALIZACION_PERFIL_LF:INVALID_DISTRIBUTION_MODE_POLICY_BYPASS:POLICY_FILTER_BYPASS_BUT_OTHER_GATE_BLOCKS" in findings
assert "ACTUALIZACION_RUNTIME_EJECUCION_PERFIL_LF:ACTIVE_STEPS_MISSING" in findings
assert "ROUTER_TARGET_HINT_CAN_OVERRIDE_CANONICAL_TARGET" in findings

# Detector regression only. S26 cannot use this as a clean assurance receipt while
# the shared matrix is BLOCK.
assert result["status"] == "BLOCK"
print("S26_TRANSVERSAL_E2E_MATRIX_CONSUMER_V1_PASS expected_closure_state=BLOCK")
