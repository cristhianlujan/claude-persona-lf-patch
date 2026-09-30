#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CONTRACT = HERE / "test_coverage_debt_guard_contract_v1.json"
RUNNER = HERE / "test_coverage_debt_guard_v1.py"
COMPAT = ROOT / "sandbox/lf_contract_gate_test/s36_wp06_ci_completeness_gate.py"
PROVIDER_SOURCE = ROOT / "supabase/migrations/20260914205435_s36_assurance_completeness_engine_v1.sql"

spec = importlib.util.spec_from_file_location("test_coverage_debt_guard_v1", RUNNER)
assert spec is not None and spec.loader is not None
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    runner = RUNNER.read_text(encoding="utf-8")
    compat = COMPAT.read_text(encoding="utf-8")
    provider_source = PROVIDER_SOURCE.read_text(encoding="utf-8")

    assert contract["capability"] == "TEST_COVERAGE_DEBT_GUARD"
    assert contract["status"] == "CANDIDATE_EXECUTABLE_DEBT_SEMANTICS"
    assert contract["target_owner"] == "FULL_REGRESSION"
    assert contract["success_result"] == "DEBT_STABLE"
    assert contract["failure_result"] == "DEBT_GROWTH_BLOCKED"
    assert contract["success_semantics"] == "ACCEPTED_TEST_COVERAGE_DEBT_NOT_GROWING"
    assert contract["material_pass_claimed"] is False
    assert contract["applicability"]["normal_pase"] is False
    assert contract["applicability"]["full_regression"] is True

    forbidden = set(contract["forbidden_claims"])
    for claim in (
        "ASSURANCE_PASS",
        "ASSURANCE_COMPLETENESS_PASS",
        "ALL_OPERATIONS_COVERED",
        "TESTS_PASSED",
        "QUALIFICATION_PASS",
        "CHANGESET_SAFE",
    ):
        assert claim in forbidden

    for key, value in contract["reuse_only"].items():
        assert value is False, f"FAIL_DEBT_GUARD_PARALLEL_OWNER:{key}"

    assert contract["legacy"]["historical_sql_aggregate_is_canonical"] is False
    assert contract["legacy"]["historical_sql_aggregate_allowed_as_new_consumer"] is False
    assert contract["legacy"]["compatibility_carrier_may_emit_assurance_pass"] is False

    # Canonical executable preserves the useful debt query and reuses the structural provider.
    assert "public.lf_s36_operation_assurance_coverage_v1()" in mod.SQL
    assert "accepted_debt_baseline" in mod.SQL
    assert "where id = 61" in mod.SQL
    assert "lifecycle_state_code = 'OP_OPERATIONAL'" in mod.SQL
    assert "assurance_obligation = 'REQUIRED'" in mod.SQL
    for code in contract["issue_codes"]:
        assert code in mod.SQL, f"FAIL_DEBT_GUARD_ISSUE_CODE_MISSING:{code}"

    # Provider/consumer enum must be exact. Provider emits BLOCK, never BLOCKED.
    assert "else 'COVERED'" in provider_source
    assert "then 'BLOCK'" in provider_source
    assert mod.PROVIDER_BLOCK_STATE == "BLOCK"
    assert "l.coverage_state = 'BLOCK'" in mod.SQL
    assert "l.coverage_state = 'BLOCKED'" not in mod.SQL

    stable = mod.classify_debt_rows([])
    assert stable["capability"] == "TEST_COVERAGE_DEBT_GUARD"
    assert stable["result"] == "DEBT_STABLE"
    assert stable["reason_code"] == "ACCEPTED_TEST_COVERAGE_DEBT_NOT_GROWING"
    assert stable["issue_count"] == 0
    assert stable["material_assurance_pass"] is False
    assert stable["material_test_pass"] is False
    assert stable["material_qualification_pass"] is False

    blocked = mod.classify_debt_rows([
        ("OP-X", "BLOCK", "LIVE_BLOCKED")
    ])
    assert blocked["result"] == "DEBT_GROWTH_BLOCKED"
    assert blocked["reason_code"] == "ACCEPTED_TEST_COVERAGE_DEBT_GREW"
    assert blocked["issue_count"] == 1
    assert blocked["material_assurance_pass"] is False

    malformed = mod.classify_debt_rows([("OP-X", "NOT_COVERED", "UNKNOWN")])
    assert malformed["result"] == "DEBT_GROWTH_BLOCKED"
    assert malformed["reason_code"] == "INVALID_DEBT_ISSUE_ROW"

    # Historical path is now only a delegating compatibility carrier.
    assert "transversal_assets" in compat
    assert "test_coverage_debt_guard_v1.py" in compat
    for token in (
        "accepted_debt_baseline",
        "public.lf_s36_operation_assurance_coverage_v1()",
        "PASS_S36_ASSURANCE_COMPLETENESS",
        "FAIL_S36_ASSURANCE_COMPLETENESS",
    ):
        assert token not in compat, f"LEGACY_CARRIER_STILL_OWNS_SEMANTICS:{token}"

    lowered = runner.lower()
    for token in (
        "lf_finalize_qualification_independent_review_v1",
        "lf_independent_strategy_review_begin_v1",
        "insert into public.lf_test_runs",
        "update public.lf_test_runs",
        "create table",
    ):
        assert token not in lowered, f"FAIL_DEBT_GUARD_FOREIGN_RESPONSIBILITY:{token}"

    assert "PASS_S36_ASSURANCE_COMPLETENESS" not in runner
    assert "ASSURANCE_COMPLETENESS_PASS" not in runner

    print("TEST_COVERAGE_DEBT_GUARD_BOUNDARY=PASS debt_semantics=true normal_pase=false block_enum=BLOCK")


if __name__ == "__main__":
    main()
