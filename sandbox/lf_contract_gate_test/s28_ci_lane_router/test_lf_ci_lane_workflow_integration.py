#!/usr/bin/env python3
import importlib.util
import subprocess
import sys
from pathlib import Path

WORKFLOW = Path(".github/workflows/lf-contract-check.yml")
RECONCILE_WORKFLOW = Path(".github/workflows/lf-github-reconcile-v3.yml")
ROUTER = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
ROUTER_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py"
SELFTEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py"
P0_EXTERNAL_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_p0_external_applicability_entrypoint.py"
RECONCILE_APPLICABILITY = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_applicability.py")
ENTRYPOINT = Path("sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT.py")


def require(text: str, token: str, code: str) -> None:
    if token not in text:
        raise SystemExit(f"{code}:{token}")


def load_reconciliation_helper():
    spec = importlib.util.spec_from_file_location("lf_github_reconcile_applicability_test", RECONCILE_APPLICABILITY)
    if spec is None or spec.loader is None:
        raise SystemExit("FAIL_RECONCILIATION_APPLICABILITY_HELPER_LOAD")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def assert_reconciliation_behavior() -> None:
    helper = load_reconciliation_helper()
    s30_policy = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"
    s30_c = "sandbox/lf_contract_gate_test/s30_c_reliability_harness/freeze_contract.json"
    s30_d = "sandbox/lf_contract_gate_test/s30_d_final_r09/r09_manifest_v1.json"
    skill = "skills/creating-integral-user-stories/SKILL.md"
    workflow = ".github/workflows/lf-github-reconcile-v3.yml"
    unknown = "sandbox/lf_contract_gate_test/unbound_future_validator.py"

    cases = [
        ("s30_only", [s30_policy], False, "S30_KNOWN_ISOLATED_ONLY"),
        ("s30_multi_lane", [s30_c, s30_d], False, "S30_KNOWN_ISOLATED_ONLY"),
        ("skill_requires_external", [skill], True, "DEEP_SHARED_REQUIRES_RECONCILIATION"),
        ("workflow_requires_external", [workflow], True, "DEEP_SHARED_REQUIRES_RECONCILIATION"),
        ("mixed_s30_skill_requires_external", [s30_d, skill], True, "DEEP_SHARED_REQUIRES_RECONCILIATION"),
        ("unknown_requires_external", [unknown], True, "DEEP_SHARED_REQUIRES_RECONCILIATION"),
        ("empty_fail_closed", [], True, "NO_CHANGED_PATHS_FAIL_CLOSED"),
    ]
    for name, paths, required, reason in cases:
        got = helper.classify_reconciliation_applicability(paths)
        assert got.required is required, (name, got)
        assert got.reason == reason, (name, got.reason, reason)

    bad_registry = {"registry_version": "BROKEN", "namespace": "S30", "lanes": []}
    got = helper.classify_reconciliation_applicability([s30_d], registry_data=bad_registry)
    assert got.required is True, got
    assert got.reason == "DEEP_SHARED_REQUIRES_RECONCILIATION", got
    assert got.router_mode == "DEEP_SHARED_REGISTRY_INVALID", got

    # Future products inherit the quota-safe exit automatically from the
    # canonical router contract; this helper must not need product-specific code.
    future_isolated = helper.LaneDecision(
        mode="S42_PRODUCT_ISOLATED",
        migration_parity_required=False,
        input_governance_parity_required=False,
        ci_router_selftest_required=False,
        p0_exact_head_external_required=False,
        deep_shared=False,
        reasons=("S42_LANE:S42-PRODUCT:sandbox/future_product/",),
    )
    got = helper.classify_router_decision(1, future_isolated)
    assert got.required is False, got
    assert got.reason == "KNOWN_ISOLATED_OWNER_ONLY", got
    assert got.lane_ids == ("S42-PRODUCT",), got

    future_shared = helper.LaneDecision(
        mode="S42_PRODUCT_SHARED",
        migration_parity_required=False,
        input_governance_parity_required=False,
        ci_router_selftest_required=False,
        p0_exact_head_external_required=False,
        deep_shared=True,
        reasons=("S42_LANE:S42-PRODUCT:sandbox/future_product/shared/",),
    )
    got = helper.classify_router_decision(1, future_shared)
    assert got.required is True, got
    assert got.reason == "SHARED_OR_SPECIALIZED_GATE_REQUIRES_RECONCILIATION", got

    print("PASS_GITHUB_RECONCILIATION_APPLICABILITY_BEHAVIOR=10/10")


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

    reconcile = RECONCILE_WORKFLOW.read_text(encoding="utf-8")
    require(reconcile, str(RECONCILE_APPLICABILITY), "FAIL_RECONCILIATION_APPLICABILITY_NOT_WIRED")
    require(reconcile, "id: applicability", "FAIL_RECONCILIATION_APPLICABILITY_OUTPUT_MISSING")
    require(reconcile, "steps.applicability.outputs.required == 'true'", "FAIL_RECONCILIATION_EXTERNAL_STEPS_NOT_GUARDED")
    require(reconcile, "steps.applicability.outputs.required == 'false'", "FAIL_RECONCILIATION_NOT_APPLICABLE_RECEIPT_MISSING")
    require(reconcile, "S30_KNOWN_ISOLATED_ONLY", "FAIL_RECONCILIATION_BACKCOMPAT_REASON_NOT_EXPOSED")

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

    assert_reconciliation_behavior()
    print("PASS_CI_LANE_WORKFLOW_INTEGRATION=20/20")


if __name__ == "__main__":
    main()
