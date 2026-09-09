#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

WORKFLOW = Path(".github/workflows/lf-contract-check.yml")
ROUTER = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
ROUTER_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py"
SELFTEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py"
P0_EXTERNAL_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_p0_external_applicability_entrypoint.py"
ENTRYPOINT = Path("sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT.py")


def require(text: str, token: str, code: str) -> None:
    if token not in text:
        raise SystemExit(f"{code}:{token}")


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    require(text, ROUTER, "FAIL_CI_LANE_ROUTER_NOT_WIRED")
    require(text, ROUTER_TEST, "FAIL_CI_LANE_ROUTER_TEST_NOT_WIRED")
    require(text, SELFTEST, "FAIL_CI_LANE_WORKFLOW_TEST_NOT_WIRED")
    require(text, "migration_parity_required", "FAIL_MIGRATION_APPLICABILITY_OUTPUT_MISSING")
    require(text, "input_governance_parity_required", "FAIL_INPUT_GOV_APPLICABILITY_OUTPUT_MISSING")
    require(text, "ci_router_selftest_required", "FAIL_CI_ROUTER_SELFTEST_OUTPUT_MISSING")
    require(
        text,
        "steps.feedback_tier.outputs.migration_parity_required == 'true'",
        "FAIL_LF_MIGRATION_STEP_NOT_PATH_SCOPED",
    )
    require(
        text,
        "steps.feedback_tier.outputs.input_governance_parity_required == 'true'",
        "FAIL_INPUT_GOV_STEP_NOT_PATH_SCOPED",
    )
    require(
        text,
        "steps.feedback_tier.outputs.ci_router_selftest_required == 'true'",
        "FAIL_SELFTEST_STEP_NOT_PATH_SCOPED",
    )
    # The same required job name must remain intact; the ruleset must not be bypassed.
    require(text, "name: lf-contract-check", "FAIL_REQUIRED_CHECK_CONTEXT_CHANGED")
    require(text, "if: needs.dedupe-router.outputs.run_deep == 'true'", "FAIL_DEEP_JOB_GUARD_CHANGED")

    entrypoint = ENTRYPOINT.read_text(encoding="utf-8")
    require(entrypoint, "p0_exact_head_external_required", "FAIL_P0_EXTERNAL_DECISION_NOT_WIRED")
    require(entrypoint, "P0_EXACT_HEAD_EXTERNAL_APPLICABILITY", "FAIL_P0_EXTERNAL_APPLICABILITY_READBACK_MISSING")

    completed = subprocess.run(
        [sys.executable, P0_EXTERNAL_TEST],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.stderr:
        print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")
    if completed.returncode != 0:
        raise SystemExit("FAIL_P0_EXTERNAL_APPLICABILITY_BEHAVIOR")

    print("PASS_CI_LANE_WORKFLOW_INTEGRATION=13/13")


if __name__ == "__main__":
    main()
