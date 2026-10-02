#!/usr/bin/env python3
"""Regression for fail-closed FULL_REGRESSION source-path classification."""
from __future__ import annotations

from lf_ci_lane_router import classify

EXACT_PATHS = (
    "sandbox/lf_contract_gate_test/transversal_assets/README.md",
    "sandbox/lf_contract_gate_test/transversal_assets/full_regression/README.md",
    "sandbox/lf_contract_gate_test/transversal_assets/full_regression/full_regression_v1.py",
    "sandbox/lf_contract_gate_test/transversal_assets/full_regression/judge_full_regression_semantics_v1.py",
)


def main() -> int:
    decision = classify(EXACT_PATHS)
    assert decision.mode == "CI_ROUTER_SELFTEST_ONLY", decision
    assert decision.required_controls == ("CI_ROUTER_SELFTEST",), decision
    assert decision.ci_router_selftest_required is True
    assert decision.migration_parity_required is False
    assert decision.input_governance_parity_required is False
    assert decision.p0_exact_head_external_required is False
    assert decision.deep_shared is False

    lookalike = classify((
        "sandbox/lf_contract_gate_test/transversal_assets/full_regression/unbound_sibling.py",
    ))
    assert lookalike.mode == "CLASSIFICATION_REQUIRED", lookalike
    assert lookalike.deep_shared is True
    assert lookalike.ci_router_selftest_required is False
    assert lookalike.migration_parity_required is False
    assert lookalike.input_governance_parity_required is False
    assert lookalike.p0_exact_head_external_required is False

    print("FULL_REGRESSION_SHARED_PATH_OWNERSHIP_V1=PASS exact=4 lookalike_fail_closed=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
