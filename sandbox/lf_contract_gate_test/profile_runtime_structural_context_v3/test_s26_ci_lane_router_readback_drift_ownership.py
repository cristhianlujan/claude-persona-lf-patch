#!/usr/bin/env python3
"""Regression for S26 commit-readback CI ownership classification.

The S26 merge-base-drift regression is a known CI self-test control. It must not
require the external P0 exact-head broker. Lookalike siblings remain fail-closed.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

LF_CONTRACT_GATE_ROOT = Path(__file__).resolve().parents[1]
ROUTER_PATH = LF_CONTRACT_GATE_ROOT / "s28_ci_lane_router" / "lf_ci_lane_router.py"
SPEC = importlib.util.spec_from_file_location("lf_ci_lane_router_s26_ownership_regression", ROUTER_PATH)
if SPEC is None or SPEC.loader is None:
    raise ImportError(f"cannot load CI lane router: {ROUTER_PATH}")
ROUTER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ROUTER
SPEC.loader.exec_module(ROUTER)

CONTROL = "sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/test_s26_commit_readback_pr_merge_base_drift.py"
LOOKALIKE = CONTROL + ".bak"


def require(condition: bool, code: str, detail: object) -> None:
    if not condition:
        raise AssertionError(f"{code}: {detail}")


def main() -> None:
    exact = ROUTER.classify([CONTROL])
    require(exact.mode == "CI_ROUTER_SELFTEST_ONLY", "S26_CI_OWNERSHIP_EXACT_MODE", exact)
    require(exact.ci_router_selftest_required is True, "S26_CI_OWNERSHIP_EXACT_SELFTEST", exact)
    require(exact.migration_parity_required is False, "S26_CI_OWNERSHIP_EXACT_MIGRATION", exact)
    require(exact.input_governance_parity_required is False, "S26_CI_OWNERSHIP_EXACT_INPUT_GOV", exact)
    require(exact.p0_exact_head_external_required is False, "S26_CI_OWNERSHIP_EXACT_P0_EXTERNAL", exact)
    require(exact.deep_shared is False, "S26_CI_OWNERSHIP_EXACT_DEEP_SHARED", exact)

    lookalike = ROUTER.classify([LOOKALIKE])
    require(lookalike.mode == "DEEP_SHARED_UNKNOWN", "S26_CI_OWNERSHIP_LOOKALIKE_MODE", lookalike)
    require(lookalike.migration_parity_required is True, "S26_CI_OWNERSHIP_LOOKALIKE_MIGRATION", lookalike)
    require(lookalike.input_governance_parity_required is True, "S26_CI_OWNERSHIP_LOOKALIKE_INPUT_GOV", lookalike)
    require(lookalike.p0_exact_head_external_required is True, "S26_CI_OWNERSHIP_LOOKALIKE_P0_EXTERNAL", lookalike)
    require(lookalike.deep_shared is True, "S26_CI_OWNERSHIP_LOOKALIKE_DEEP_SHARED", lookalike)

    combined = ROUTER.classify([ROUTER.S26_COMMIT_READBACK_CONTROL, CONTROL])
    require(combined.mode == "CI_ROUTER_SELFTEST_ONLY", "S26_CI_OWNERSHIP_COMBINED_MODE", combined)
    require(combined.p0_exact_head_external_required is False, "S26_CI_OWNERSHIP_COMBINED_P0_EXTERNAL", combined)

    print("S26_CI_LANE_ROUTER_READBACK_DRIFT_OWNERSHIP_PASS")


if __name__ == "__main__":
    main()
