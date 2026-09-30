#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("s36_wp06_ci_completeness_gate.py")
spec = importlib.util.spec_from_file_location("s36_wp06_ci_completeness_gate", MODULE_PATH)
if spec is None or spec.loader is None:
    raise SystemExit("TEST_COVERAGE_DEBT_GUARD_COMPAT_LOAD_FAILED")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert mod.CAPABILITY_CODE == "TEST_COVERAGE_DEBT_GUARD"
assert mod.SUCCESS_RESULT == "DEBT_STABLE"
assert mod.FAILURE_RESULT == "DEBT_GROWTH_BLOCKED"
assert mod.PROVIDER_BLOCK_STATE == "BLOCK"

# Compatibility surface preserves the exact debt query contract but delegates
# ownership to the canonical transversal runner.
assert "NEW_REQUIRED_OPERATION_DEBT" in mod.SQL
assert "LIVE_BLOCKED" in mod.SQL
assert "ACCEPTED_DEBT_STATE_CHANGED_WITHOUT_COVERAGE" in mod.SQL
assert "BINDING_ACTIVITY_WITHOUT_COVERAGE" in mod.SQL
assert "NEW_RUN_ACTIVITY_WITHOUT_COVERAGE" in mod.SQL
assert "lifecycle_state_code = 'OP_OPERATIONAL'" in mod.SQL
assert "assurance_obligation = 'REQUIRED'" in mod.SQL
assert "where id = 61" in mod.SQL
assert "coverage_state <> 'COVERED'" in mod.SQL
assert "l.coverage_state = 'BLOCK'" in mod.SQL
assert "l.coverage_state = 'BLOCKED'" not in mod.SQL
assert "x->>'accepted_state'" in mod.SQL
assert "x->>'baseline_required_binding_count'" in mod.SQL
assert "x->>'baseline_observed_run_count'" in mod.SQL
assert "jsonb_array_elements(coalesce(b,'[]'::jsonb))" in mod.SQL
assert "b->'rows'" not in mod.SQL

stable = mod.classify_debt_rows([])
assert stable["result"] == "DEBT_STABLE"
assert stable["material_assurance_pass"] is False
assert stable["material_test_pass"] is False
assert stable["material_qualification_pass"] is False

blocked = mod.classify_debt_rows([("OP-X", "BLOCK", "LIVE_BLOCKED")])
assert blocked["result"] == "DEBT_GROWTH_BLOCKED"
assert blocked["material_assurance_pass"] is False

source = MODULE_PATH.read_text(encoding="utf-8")
for foreign_token in (
    "lf_finalize_qualification_independent_review_v1",
    "lf_qualification_receipts",
    "update public.lf_test_runs",
    "update public.lf_test_suite_runs",
    "QUAL_REVIEW_MATERIALIZATION_COUNT_MISMATCH",
    "PASS_S36_ASSURANCE_COMPLETENESS",
    "FAIL_S36_ASSURANCE_COMPLETENESS",
):
    assert foreign_token not in source, f"FAIL_DEBT_GUARD_COMPAT_CONTAMINATION:{foreign_token}"

print("TEST_COVERAGE_DEBT_GUARD_COMPAT_SELFTEST=PASS block_enum=BLOCK")
