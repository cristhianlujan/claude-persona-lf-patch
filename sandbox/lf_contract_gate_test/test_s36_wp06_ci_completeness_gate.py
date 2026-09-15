#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("s36_wp06_ci_completeness_gate.py")
spec = importlib.util.spec_from_file_location("s36_wp06_ci_completeness_gate", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("FAIL_S36_COMPLETENESS_GATE_LOAD")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert "NEW_REQUIRED_OPERATION_DEBT" in mod.SQL
assert "LIVE_BLOCKED" in mod.SQL
assert "ACCEPTED_DEBT_STATE_CHANGED_WITHOUT_COVERAGE" in mod.SQL
assert "BINDING_ACTIVITY_WITHOUT_COVERAGE" in mod.SQL
assert "NEW_RUN_ACTIVITY_WITHOUT_COVERAGE" in mod.SQL
assert "lifecycle_state_code = 'OP_OPERATIONAL'" in mod.SQL
assert "assurance_obligation = 'REQUIRED'" in mod.SQL
assert "where id = 61" in mod.SQL
assert "coverage_state <> 'COVERED'" in mod.SQL
print("S36_WP06_COMPLETENESS_GATE_SELFTEST=PASS")
