#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
CONTRACT = HERE / "test_coverage_debt_guard_contract_v1.json"
LEGACY = ROOT / "sandbox/lf_contract_gate_test/s36_wp06_ci_completeness_gate.py"


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    legacy = LEGACY.read_text(encoding="utf-8")

    assert contract["capability"] == "TEST_COVERAGE_DEBT_GUARD"
    assert contract["target_owner"] == "FULL_REGRESSION"
    assert contract["pass_semantics"] == "ACCEPTED_TEST_COVERAGE_DEBT_NOT_GROWING"
    assert contract["applicability"]["normal_pase"] is False
    assert contract["applicability"]["full_regression"] is True

    forbidden = set(contract["forbidden_claims"])
    assert "ASSURANCE_COMPLETENESS_PASS" in forbidden
    assert "QUALIFICATION_PASS" in forbidden
    assert "CHANGESET_SAFE" in forbidden

    for key, value in contract["reuse_only"].items():
        assert value is False, f"FAIL_DEBT_GUARD_PARALLEL_OWNER:{key}"

    # Existing implementation is debt monotonicity over the canonical coverage provider.
    assert "public.lf_s36_operation_assurance_coverage_v1()" in legacy
    assert "accepted_debt_baseline" in legacy
    assert "where id = 61" in legacy
    assert "accepted_debt_not_growing=true" in legacy
    for code in contract["issue_codes"]:
        assert code in legacy, f"FAIL_DEBT_GUARD_LEGACY_ISSUE_CODE_MISSING:{code}"

    # It must not be reinterpreted as review, qualification or test execution.
    lowered = legacy.lower()
    for token in (
        "lf_finalize_qualification_independent_review_v1",
        "lf_independent_strategy_review_begin_v1",
        "insert into public.lf_test_runs",
        "update public.lf_test_runs",
        "create table",
    ):
        assert token not in lowered, f"FAIL_DEBT_GUARD_FOREIGN_RESPONSIBILITY:{token}"

    print("TEST_COVERAGE_DEBT_GUARD_BOUNDARY=PASS")


if __name__ == "__main__":
    main()
