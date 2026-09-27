#!/usr/bin/env python3
"""Guard the E.16 -> VISUAL_EVIDENCE_GATE ownership separation."""
from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
INTEGRATION = REPO_ROOT / "sandbox/lf_contract_gate_test/PR93_LOTE_E16_INTEGRATION_TESTS.py"
RUNTIME_SCOPE = REPO_ROOT / "sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_SCOPE_TESTS.py"


def main() -> int:
    integration = INTEGRATION.read_text(encoding="utf-8")
    runtime_scope = RUNTIME_SCOPE.read_text(encoding="utf-8")

    forbidden_integration = (
        "P0_OCR_CAUSAL_REGRESSION_V1.py",
        "P0_TEXT_GROUP_FAMILY_GENERALIZATION_V1.py",
        "PASS_P0_OCR_CAUSAL_REGRESSION",
        "PASS_P0_TEXT_GROUP_FAMILY_GENERALIZATION",
    )
    leaked_integration = [term for term in forbidden_integration if term in integration]
    if leaked_integration:
        raise SystemExit("FAIL_E16_VISUAL_INTEGRATION_LEAK:" + ",".join(leaked_integration))

    forbidden_runtime_scope = (
        "attest_p0_visual_test_dependencies",
        "run_p0_quality_regressions",
        "P0_VISUAL_QUALITY_REGRESSION_FAILED",
        "p0_visual_quality_runtime_regression_suite.py",
        "p0_visual_fidelity_v3_suite.py",
        "p0_visual_discovery_v4_suite.py",
    )
    leaked_runtime = [term for term in forbidden_runtime_scope if term in runtime_scope]
    if leaked_runtime:
        raise SystemExit("FAIL_E16_VISUAL_RUNTIME_SCOPE_LEAK:" + ",".join(leaked_runtime))

    required_integration = (
        "PASS_STORY_CREATOR_ARCHITECTURE_HARDENING=1/1",
        "PASS_OPENAI_PROFILE_RUNTIME_PROVIDER=10/10",
        "PASS_EKB_EXECUTABLE_BINDING_GATE=3/3",
        "PASS_E16_WORKFLOW_BINDING=15/15",
        "PASS_E16_CONTRACT_CHECK_INTEGRATION=3/3",
    )
    missing_integration = [term for term in required_integration if term not in integration]
    if missing_integration:
        raise SystemExit("FAIL_E16_INTEGRATION_COVERAGE_REMOVED:" + ",".join(missing_integration))

    required_runtime_scope = (
        "PASS_PR93_P0_RUNTIME_SCOPE_MATRIX=20/20",
        "run_functional_red_team_regression(repo_root)",
        "PASS_FUNCTIONAL_RED_TEAM_V1_REGRESSION=30/30",
    )
    missing_runtime = [term for term in required_runtime_scope if term not in runtime_scope]
    if missing_runtime:
        raise SystemExit("FAIL_E16_RUNTIME_SCOPE_COVERAGE_REMOVED:" + ",".join(missing_runtime))

    print("PASS_E16_VISUAL_OWNERSHIP_CLEANUP=2/2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
