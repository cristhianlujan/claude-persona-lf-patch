#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

WORKFLOW = Path(".github/workflows/lf-contract-check.yml")
RECONCILE_WORKFLOW = Path(".github/workflows/lf-github-reconcile-v3.yml")
ROUTER = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
ROUTER_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_router.py"
SELFTEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_lane_workflow_integration.py"
P0_EXTERNAL_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_p0_external_applicability_entrypoint.py"
RECONCILE_OWNERSHIP_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_s26_reconcile_workflow_ownership.py"
RECONCILE_APPLICABILITY = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_applicability.py")
RECONCILE_POOLER_FALLBACK = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_github_reconcile_pooler_fallback.py")
PRODUCT_OWNERSHIP = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_product_lane_ownership.py")
PRODUCT_REGISTRY = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_product_lane_ownership_registry_v1.json")
ENTRYPOINT = Path("sandbox/lf_contract_gate_test/PR93_P0_RUNTIME_CONTRACT_CHECK_ENTRYPOINT.py")
CONTROL_MANIFEST = Path("sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_contract_check_control_manifest_v1.json")
GROUP_ORCHESTRATOR = "sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py"
PARITY_EQUIVALENCE = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_contract_check_parity_equivalence_v1.py"
PARITY_EQUIVALENCE_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_contract_check_parity_equivalence_v1.py"
EXECUTION_PLAN = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_execution_plan_v2.py"
IMPACT_REGISTRY = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json"
EXECUTION_PLAN_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_lf_ci_execution_plan_v2.py"
ROLLBACK_PROBE_TEST = "sandbox/lf_contract_gate_test/s28_ci_lane_router/test_run_changed_migrations_rollback_v1.py"


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


def future_registry(*, allowed_root: str = "sandbox/future_product/") -> dict:
    return {
        "registry_version": "LF_PRODUCT_CI_LANE_OWNERSHIP_V1",
        "namespaces": [
            {
                "namespace": "S42",
                "allowed_roots": [allowed_root],
            }
        ],
        "lanes": [
            {
                "lane_id": "S42-PRODUCT",
                "namespace": "S42",
                "ownership_class": "S42_PRODUCT",
                "mode": "S42_PRODUCT_ISOLATED",
                "matchers": [
                    {"kind": "prefix", "value": allowed_root}
                ],
                "migration_parity_required": False,
                "input_governance_parity_required": False,
                "p0_exact_head_external_required": False,
                "ci_router_selftest_required": False,
                "deep_shared": False,
                "known": True,
            }
        ],
    }


def assert_reconciliation_behavior(helper) -> None:
    s30_policy = "sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml"
    s30_c = "sandbox/lf_contract_gate_test/s30_c_reliability_harness/freeze_contract.json"
    s30_d = "sandbox/lf_contract_gate_test/s30_d_final_r09/r09_manifest_v1.json"
    skill = "skills/creating-integral-user-stories/SKILL.md"
    workflow = ".github/workflows/lf-github-reconcile-v3.yml"
    unknown = "sandbox/lf_contract_gate_test/unbound_future_validator.py"

    cases = [
        ("s30_only", [s30_policy], False, "S30_KNOWN_ISOLATED_ONLY"),
        ("s30_multi_lane", [s30_c, s30_d], False, "S30_KNOWN_ISOLATED_ONLY"),
        ("skill_requires_external", [skill], True, "UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION"),
        ("workflow_requires_external", [workflow], True, "UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION"),
        ("mixed_s30_skill_requires_external", [s30_d, skill], True, "UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION"),
        ("unknown_requires_external", [unknown], True, "UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION"),
        ("empty_fail_closed", [], True, "NO_CHANGED_PATHS_FAIL_CLOSED"),
    ]
    for name, paths, required, reason in cases:
        got = helper.classify_reconciliation_applicability(paths)
        assert got.required is required, (name, got)
        assert got.reason == reason, (name, got.reason, reason)

    bad_registry = {"registry_version": "BROKEN", "namespace": "S30", "lanes": []}
    got = helper.classify_reconciliation_applicability([s30_d], registry_data=bad_registry)
    assert got.required is True, got
    assert got.reason == "UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION", got
    assert got.router_mode == "DEEP_SHARED_REGISTRY_INVALID", got

    future_path = "sandbox/future_product/run.json"
    got = helper.classify_reconciliation_applicability(
        [future_path],
        registry_data=future_registry(),
    )
    assert got.required is False, got
    assert got.reason == "KNOWN_ISOLATED_OWNER_ONLY", got
    assert got.lane_ids == ("S42-PRODUCT",), got
    assert got.router_mode == "S42_PRODUCT_ISOLATED", got

    got = helper.classify_reconciliation_applicability(
        ["skills/shared.md"],
        registry_data=future_registry(allowed_root="skills/"),
    )
    assert got.required is True, got
    assert got.router_mode == "DEEP_SHARED_REGISTRY_INVALID", got

    future_shared_path = "sandbox/future_product/shared/run.json"
    future_shared = helper.LaneDecision(
        mode="S42_PRODUCT_SHARED",
        migration_parity_required=False,
        input_governance_parity_required=False,
        ci_router_selftest_required=False,
        p0_exact_head_external_required=False,
        deep_shared=True,
        reasons=(f"PRODUCT_LANE:S42-PRODUCT:{future_shared_path}",),
    )
    got = helper.classify_router_decision([future_shared_path], future_shared)
    assert got.required is True, got
    assert got.reason == "SHARED_OR_SPECIALIZED_GATE_REQUIRES_RECONCILIATION", got

    future_isolated = helper.LaneDecision(
        mode="S42_PRODUCT_ISOLATED",
        migration_parity_required=False,
        input_governance_parity_required=False,
        ci_router_selftest_required=False,
        p0_exact_head_external_required=False,
        deep_shared=False,
        reasons=(f"PRODUCT_LANE:S42-PRODUCT:{future_path}",),
    )
    got = helper.classify_router_decision([future_path, "skills/shared.md"], future_isolated)
    assert got.required is True, got
    assert got.reason == "UNBOUND_OR_SHARED_PATH_REQUIRES_RECONCILIATION", got

    print("PASS_GITHUB_RECONCILIATION_APPLICABILITY_BEHAVIOR=12/12")


def _git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        capture_output=True,
        check=True,
    )
    return completed.stdout.strip()


def assert_merge_path_recovery(helper) -> None:
    with tempfile.TemporaryDirectory(prefix="lf-reconcile-merge-") as td:
        repo = Path(td)
        _git(repo, "init", "-b", "main")
        _git(repo, "config", "user.name", "LF CI Test")
        _git(repo, "config", "user.email", "lf-ci@example.invalid")

        (repo / "base.txt").write_text("base\n", encoding="utf-8")
        _git(repo, "add", "base.txt")
        _git(repo, "commit", "-m", "base")

        _git(repo, "checkout", "-b", "feature")
        (repo / "product.txt").write_text("product\n", encoding="utf-8")
        _git(repo, "add", "product.txt")
        _git(repo, "commit", "-m", "product")

        _git(repo, "checkout", "main")
        (repo / "main.txt").write_text("main\n", encoding="utf-8")
        _git(repo, "add", "main.txt")
        _git(repo, "commit", "-m", "main diverges")
        _git(repo, "merge", "--no-ff", "feature", "-m", "merge feature")
        merge_sha = _git(repo, "rev-parse", "HEAD")

        recovered = helper.recover_changed_paths_from_exact_head(merge_sha, repo_root=repo)
        assert recovered == ["product.txt"], recovered

        empty = repo / "changed.txt"
        empty.write_text("", encoding="utf-8")
        resolved = helper.resolve_changed_paths(empty, source_head_sha=merge_sha, repo_root=repo)
        assert resolved == ["product.txt"], resolved

        supplied = repo / "supplied.txt"
        supplied.write_text("explicit.txt\n", encoding="utf-8")
        resolved = helper.resolve_changed_paths(supplied, source_head_sha=merge_sha, repo_root=repo)
        assert resolved == ["explicit.txt"], resolved

        assert helper.recover_changed_paths_from_exact_head("0" * 40, repo_root=repo) == []

    print("PASS_GITHUB_RECONCILIATION_MERGE_PATH_RECOVERY=4/4")


def run_child(path: str, failure_code: str) -> None:
    completed = subprocess.run(
        [sys.executable, path],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.stderr:
        print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")
    if completed.returncode != 0:
        raise SystemExit(failure_code)


def main() -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    require(text, ROUTER, "FAIL_CI_LANE_ROUTER_NOT_WIRED")
    require(text, ROUTER_TEST, "FAIL_CI_LANE_ROUTER_TEST_NOT_WIRED")
    require(text, SELFTEST, "FAIL_CI_LANE_WORKFLOW_TEST_NOT_WIRED")
    require(text, "migration_parity_required", "FAIL_MIGRATION_APPLICABILITY_OUTPUT_MISSING")
    require(text, "input_governance_parity_required", "FAIL_INPUT_GOV_APPLICABILITY_OUTPUT_MISSING")
    require(text, "ci_router_selftest_required", "FAIL_CI_ROUTER_SELFTEST_OUTPUT_MISSING")
    require(text, "required_controls_json", "FAIL_REQUIRED_CONTROLS_OUTPUT_MISSING")
    require(text, "execution authority: CI_FAST_DEEP_LANE_ROUTER plan -> carrier controls", "FAIL_UNIFIED_CI_PLAN_AUTHORITY_MARKER_MISSING")
    require(text, EXECUTION_PLAN, "FAIL_UNIFIED_CI_EXECUTION_PLAN_NOT_WIRED")
    require(text, "lf_contract_controls_json", "FAIL_CARRIER_CONTROL_OUTPUT_MISSING")
    require(text, EXECUTION_PLAN_TEST, "FAIL_CI_EXECUTION_PLAN_TEST_NOT_WIRED")
    require(text, ROLLBACK_PROBE_TEST, "FAIL_CANDIDATE_ROLLBACK_PROBE_TEST_NOT_WIRED")
    require(text, "Enforce lf-contract-check transversal closure prerequisites", "FAIL_TRANSVERSAL_CLOSURE_GUARD_STEP_MISSING")
    require(text, "transversal_asset_readme/validate_active_shared_readmes_v1.py", "FAIL_TRANSVERSAL_CLOSURE_VALIDATOR_NOT_WIRED")
    require(text, "--require-code GITHUB_CONTRACT_GATE_LF", "FAIL_TRANSVERSAL_CLOSURE_REQUIRED_OPERATION_MISSING")
    require(text, str(CONTROL_MANIFEST), "FAIL_DECLARATIVE_CONTROL_MANIFEST_NOT_WIRED")
    require(text, GROUP_ORCHESTRATOR, "FAIL_GATE_GROUP_ORCHESTRATOR_NOT_WIRED")
    require(text, "Prepare LF migration source parity frozen inputs", "FAIL_DECLARATIVE_PARITY_INPUT_PREP_MISSING")
    require(text, "Enforce required_controls through existing gate orchestrator", "FAIL_DECLARATIVE_PARITY_AUTHORITY_STEP_MISSING")
    require(text, "--group MIGRATION_SOURCE_PARITY", "FAIL_DECLARATIVE_PARITY_GROUP_NOT_SELECTED")
    require(text, PARITY_EQUIVALENCE_TEST, "FAIL_PARITY_EQUIVALENCE_TEST_NOT_WIRED")
    if "Verify legacy and declarative migration parity equivalence" in text:
        raise SystemExit("FAIL_RUNTIME_PARITY_EQUIVALENCE_STILL_ACTIVE_AFTER_PROMOTION")
    require(text, "lf-migration-statement-counts.csv", "FAIL_PARITY_EQUIVALENCE_FROZEN_COUNTS_MISSING")
    require(
        text,
        "contains(fromJSON(steps.feedback_tier.outputs.lf_contract_controls_json), 'MIGRATION_SOURCE_PARITY')",
        "FAIL_LF_MIGRATION_UNIFIED_PLAN_GUARD_MISSING",
    )
    if "if: steps.feedback_tier.outputs.migration_parity_required == 'true'" in text:
        raise SystemExit("FAIL_LEGACY_MIGRATION_BOOLEAN_STILL_EXECUTION_AUTHORITY")
    if "if: steps.feedback_tier.outputs.input_governance_parity_required == 'true'" in text:
        raise SystemExit("FAIL_LEGACY_INPUT_GOV_BOOLEAN_STILL_EXECUTION_AUTHORITY")
    if "if: steps.feedback_tier.outputs.ci_router_selftest_required == 'true'" in text:
        raise SystemExit("FAIL_LEGACY_SELFTEST_BOOLEAN_STILL_EXECUTION_AUTHORITY")
    require(
        text,
        "contains(fromJSON(steps.feedback_tier.outputs.lf_contract_controls_json), 'INPUT_GOVERNANCE_MIGRATION_PARITY')",
        "FAIL_INPUT_GOV_UNIFIED_PLAN_GUARD_MISSING",
    )
    require(
        text,
        "contains(fromJSON(steps.feedback_tier.outputs.lf_contract_controls_json), 'CI_ROUTER_SELFTEST')",
        "FAIL_SELFTEST_UNIFIED_PLAN_GUARD_MISSING",
    )
    require(text, "name: lf-contract-check", "FAIL_REQUIRED_CHECK_CONTEXT_CHANGED")
    require(text, "github.event.pull_request.head.sha", "FAIL_EXACT_PR_HEAD_CHECKOUT_MISSING")
    require(text, "if: needs.dedupe-router.outputs.run_deep == 'true'", "FAIL_DEEP_JOB_GUARD_CHANGED")

    control_manifest = json.loads(CONTROL_MANIFEST.read_text(encoding="utf-8"))
    assert control_manifest["consumer_code"] == "LF_CONTRACT_CHECK", control_manifest
    assert control_manifest["gate_id"] == "LF_CONTRACT_CHECK_DECLARATIVE_CONTROLS", control_manifest
    assert control_manifest["expected_total_checks"] == 1, control_manifest
    assert [g["group_id"] for g in control_manifest["groups"]] == ["MIGRATION_SOURCE_PARITY"], control_manifest
    parity_group = control_manifest["groups"][0]
    assert parity_group["execution_class"] == "DETERMINISTIC", parity_group
    assert parity_group["commands"][0]["source_path"] == "sandbox/lf_contract_gate_test/lf_migration_source_parity.py", parity_group

    router_text = Path(ROUTER).read_text(encoding="utf-8")
    require(router_text, PRODUCT_OWNERSHIP.name, "FAIL_GENERIC_PRODUCT_OWNERSHIP_NOT_WIRED")
    ownership_text = PRODUCT_OWNERSHIP.read_text(encoding="utf-8")
    require(ownership_text, PRODUCT_REGISTRY.name, "FAIL_GENERIC_PRODUCT_REGISTRY_NOT_AUTHORITY")

    entrypoint = ENTRYPOINT.read_text(encoding="utf-8")
    require(entrypoint, "p0_exact_head_external_required", "FAIL_P0_EXTERNAL_DECISION_NOT_WIRED")
    require(entrypoint, "P0_EXACT_HEAD_EXTERNAL_APPLICABILITY", "FAIL_P0_EXTERNAL_APPLICABILITY_READBACK_MISSING")

    reconcile = RECONCILE_WORKFLOW.read_text(encoding="utf-8")
    require(reconcile, str(RECONCILE_APPLICABILITY), "FAIL_RECONCILIATION_APPLICABILITY_NOT_WIRED")
    require(reconcile, str(RECONCILE_POOLER_FALLBACK), "FAIL_RECONCILIATION_POOLER_FALLBACK_NOT_WIRED")
    require(reconcile, "id: applicability", "FAIL_RECONCILIATION_APPLICABILITY_OUTPUT_MISSING")
    require(reconcile, "steps.applicability.outputs.required == 'true'", "FAIL_RECONCILIATION_EXTERNAL_STEPS_NOT_GUARDED")
    require(reconcile, "steps.applicability.outputs.required == 'false'", "FAIL_RECONCILIATION_NOT_APPLICABLE_RECEIPT_MISSING")
    require(reconcile, "S30_KNOWN_ISOLATED_ONLY", "FAIL_RECONCILIATION_BACKCOMPAT_REASON_NOT_EXPOSED")
    require(reconcile, "EDGE_402_POOLER_FALLBACK", "FAIL_RECONCILIATION_POOLER_FALLBACK_MARKER_MISSING")
    require(reconcile, "exceed_egress_quota", "FAIL_RECONCILIATION_POOLER_FALLBACK_QUOTA_CODE_MISSING")
    require(reconcile, "LF_SUPABASE_DB_PASSWORD", "FAIL_RECONCILIATION_POOLER_FALLBACK_DB_SECRET_NOT_WIRED")
    if "--retry-all-errors" in reconcile:
        raise SystemExit("FAIL_RECONCILIATION_402_BLIND_RETRY_PRESENT")

    run_child(P0_EXTERNAL_TEST, "FAIL_P0_EXTERNAL_APPLICABILITY_BEHAVIOR")
    run_child(RECONCILE_OWNERSHIP_TEST, "FAIL_S26_RECONCILE_WORKFLOW_OWNERSHIP")

    fallback = subprocess.run(
        [sys.executable, str(RECONCILE_POOLER_FALLBACK), "self-test"],
        text=True,
        capture_output=True,
        check=False,
    )
    if fallback.stdout:
        print(fallback.stdout, end="" if fallback.stdout.endswith("\n") else "\n")
    if fallback.stderr:
        print(fallback.stderr, file=sys.stderr, end="" if fallback.stderr.endswith("\n") else "\n")
    if fallback.returncode != 0:
        raise SystemExit("FAIL_RECONCILIATION_POOLER_FALLBACK_SELFTEST")

    helper = load_reconciliation_helper()
    assert_reconciliation_behavior(helper)
    assert_merge_path_recovery(helper)
    print("PASS_CI_LANE_WORKFLOW_INTEGRATION=44/44")


if __name__ == "__main__":
    main()
