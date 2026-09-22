#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "lf_ci_currentness_bridge_v1.py"


def load():
    spec = importlib.util.spec_from_file_location("lf_ci_currentness_bridge_v1_tested", TARGET)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


M = load()


def sh(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()


def setup_repo() -> tuple[Path, str]:
    repo = Path(tempfile.mkdtemp(prefix="lf-ci-currentness-"))
    sh(repo, "init")
    sh(repo, "config", "user.email", "ci@example.invalid")
    sh(repo, "config", "user.name", "CI")
    paths = {
        ".github/workflows/lf-contract-check.yml": "name: contract\n",
        ".github/workflows/validate-lf-packs.yml": "name: packs\n",
        ".github/workflows/lf-bootstrap-reproducibility.yml": "name: bootstrap\n",
        "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py": "print('router')\n",
        "sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py": "print('gates')\n",
        "sandbox/lf_contract_gate_test/transversal_assets/ci_fast_deep_lane_router/README.md": "# CI\n",
        "unrelated/readme.md": "v1\n",
    }
    for rel, text in paths.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", "base")
    return repo, sh(repo, "rev-parse", "HEAD")


def commit_all(repo: Path, message: str) -> str:
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", message)
    return sh(repo, "rev-parse", "HEAD")


def test_unrelated_main_change_is_current_rebound() -> None:
    repo, base = setup_repo()
    (repo / "unrelated/readme.md").write_text("v2\n", encoding="utf-8")
    current = commit_all(repo, "unrelated")
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=base, current_revision=current
    )
    assert r["decision"] == "CURRENT_REBOUND", r
    assert r["ready"] is True, r
    assert r["rebind_allowed"] is True, r
    assert r["evidence_revision"] == base
    assert r["resolved_revision"] == current
    assert r["evidence_semantics"] == "HISTORICAL_IMMUTABLE_REFERENCE_NOT_MOVING_AUTHORITY"


def test_ci_authority_change_blocks_without_compatibility_proof() -> None:
    repo, base = setup_repo()
    p = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    p.write_text("print('router v2')\n", encoding="utf-8")
    current = commit_all(repo, "authority change")
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=base, current_revision=current
    )
    assert r["ready"] is False, r
    assert r["decision"] == "UNKNOWN_FAIL_CLOSED", r
    assert r["reason"] == "COMPATIBILITY_ASSESSMENT_MISSING", r


def test_same_revision_is_current() -> None:
    repo, base = setup_repo()
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=base, current_revision=base
    )
    assert r["decision"] == "CURRENT", r
    assert r["ready"] is True, r
    assert r["rebind_allowed"] is False, r



def test_pr_that_contains_current_main_binds_current_authority() -> None:
    repo, base = setup_repo()
    p = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    p.write_text("print('router v2')\n", encoding="utf-8")
    current = commit_all(repo, "main authority update")
    sh(repo, "checkout", "-b", "feature")
    (repo / "unrelated/readme.md").write_text("feature after current main\n", encoding="utf-8")
    feature = commit_all(repo, "feature after current main")
    bound = M.resolve_authority_evidence_revision(
        repo=repo,
        event_name="pull_request",
        ref_name="feature",
        diff_base_revision=base,
        candidate_head_revision=feature,
        current_revision=current,
    )
    assert bound == current
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=current
    )
    assert r["decision"] == "CURRENT", r
    assert r["ready"] is True, r


def test_pr_that_does_not_contain_current_main_keeps_historical_evidence() -> None:
    repo, base = setup_repo()
    sh(repo, "checkout", "-b", "feature")
    (repo / "unrelated/readme.md").write_text("feature\n", encoding="utf-8")
    feature = commit_all(repo, "feature")
    sh(repo, "checkout", "master")
    p = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    p.write_text("print('router v2')\n", encoding="utf-8")
    current = commit_all(repo, "main authority update")
    bound = M.resolve_authority_evidence_revision(
        repo=repo,
        event_name="pull_request",
        ref_name="feature",
        diff_base_revision=base,
        candidate_head_revision=feature,
        current_revision=current,
    )
    assert bound == base
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=current
    )
    assert r["decision"] == "UNKNOWN_FAIL_CLOSED", r
    assert r["reason"] == "COMPATIBILITY_ASSESSMENT_MISSING", r


def test_pr_uses_live_merge_base_not_stale_event_base() -> None:
    repo, event_base = setup_repo()
    p = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    p.write_text("print('router v2')\n", encoding="utf-8")
    main_at_branch = commit_all(repo, "authority update before branch")
    sh(repo, "checkout", "-b", "feature")
    (repo / "unrelated/readme.md").write_text("feature\n", encoding="utf-8")
    feature = commit_all(repo, "feature")
    sh(repo, "checkout", "master")
    (repo / "unrelated/readme.md").write_text("main unrelated after branch\n", encoding="utf-8")
    current = commit_all(repo, "unrelated main advance")
    bound = M.resolve_authority_evidence_revision(
        repo=repo,
        event_name="pull_request",
        ref_name="feature",
        diff_base_revision=event_base,
        candidate_head_revision=feature,
        current_revision=current,
    )
    assert bound == main_at_branch, (bound, main_at_branch)
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=current
    )
    assert r["decision"] == "CURRENT_REBOUND", r
    assert r["ready"] is True, r
    assert r["rebind_allowed"] is True, r


def test_push_to_main_binds_new_evidence_to_current_main() -> None:
    repo, base = setup_repo()
    p = repo / "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    p.write_text("print('router v2')\n", encoding="utf-8")
    current = commit_all(repo, "main update")
    bound = M.resolve_authority_evidence_revision(
        repo=repo,
        event_name="push",
        ref_name="main",
        diff_base_revision=base,
        candidate_head_revision=current,
        current_revision=current,
    )
    assert bound == current
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=current
    )
    assert r["decision"] == "CURRENT", r
    assert r["ready"] is True, r


def test_feature_push_uses_merge_base_not_diff_base_as_authority() -> None:
    repo, base = setup_repo()
    sh(repo, "checkout", "-b", "feature")
    (repo / "unrelated/readme.md").write_text("feature\n", encoding="utf-8")
    feature = commit_all(repo, "feature")
    sh(repo, "checkout", "master")
    (repo / "unrelated/readme.md").write_text("main-v2\n", encoding="utf-8")
    current = commit_all(repo, "main advance")
    bound = M.resolve_authority_evidence_revision(
        repo=repo,
        event_name="push",
        ref_name="feature",
        diff_base_revision=base,
        candidate_head_revision=feature,
        current_revision=current,
    )
    assert bound == base
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=current
    )
    assert r["decision"] == "CURRENT_REBOUND", r
    assert r["ready"] is True, r


def main() -> None:
    tests = [
        test_unrelated_main_change_is_current_rebound,
        test_ci_authority_change_blocks_without_compatibility_proof,
        test_same_revision_is_current,
        test_pr_that_contains_current_main_binds_current_authority,
        test_pr_that_does_not_contain_current_main_keeps_historical_evidence,
        test_pr_uses_live_merge_base_not_stale_event_base,
        test_push_to_main_binds_new_evidence_to_current_main,
        test_feature_push_uses_merge_base_not_diff_base_as_authority,
    ]
    for test in tests:
        test()
    print(f"LF_CI_CURRENTNESS_BRIDGE_V1_PASS={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
