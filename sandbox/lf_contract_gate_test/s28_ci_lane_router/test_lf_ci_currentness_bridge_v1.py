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
        ".github/workflows/lf-db-regression.yml": "name: db-regression\n",
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


def test_main_advanced_after_pr_snapshot_rebinds_without_false_block() -> None:
    # Local-only race fixture: PR evidence is bound, then main advances on an
    # unrelated path before evaluation. Currentness must rebind to live main.
    repo, bound = setup_repo()
    (repo / "unrelated/readme.md").write_text("main advanced after PR snapshot\n", encoding="utf-8")
    live_main = commit_all(repo, "unrelated main advance after PR snapshot")
    r = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=live_main
    )
    assert r["decision"] == "CURRENT_REBOUND", r
    assert r["ready"] is True, r
    assert r["rebind_allowed"] is True, r
    assert r["resolved_revision"] == live_main


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


def pr_receipt(*, authority_change: bool, current_head: bool = False):
    repo, base = setup_repo()
    sh(repo, "checkout", "-b", "feature")
    (repo / "unrelated/readme.md").write_text("feature\n", encoding="utf-8")
    head = commit_all(repo, "feature")
    sh(repo, "checkout", "master")
    changed_path = "sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py"
    path = changed_path if authority_change else "unrelated/readme.md"
    (repo / path).write_text("main advance\n", encoding="utf-8")
    current = commit_all(repo, "main advance")
    if current_head:
        sh(repo, "checkout", "feature")
        sh(repo, "merge", "--no-edit", current)
        head = sh(repo, "rev-parse", "HEAD")
    bound = M.resolve_authority_evidence_revision(
        repo=repo, event_name="pull_request", ref_name="feature",
        diff_base_revision=base, candidate_head_revision=head,
        current_revision=current,
    )
    return M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=bound, current_revision=current,
        event_name="pull_request", candidate_head_revision=head,
    ), changed_path


def blocked_message(receipt):
    try:
        M.require_ready(receipt)
    except RuntimeError as exc:
        return str(exc)
    raise AssertionError("blocked receipt was accepted")


def test_stale_pr_preserves_reason_and_adds_selector_hint() -> None:
    receipt, path = pr_receipt(authority_change=True)
    assert receipt["stale_base"] is True
    assert receipt["reason"] == "COMPATIBILITY_ASSESSMENT_MISSING"
    assert receipt["changed_ci_authority_paths"] == [path]
    message = blocked_message(receipt)
    assert message.startswith(
        "BLOCK_CI_AUTHORITY_CURRENTNESS:UNKNOWN_FAIL_CLOSED:"
        "COMPATIBILITY_ASSESSMENT_MISSING:STALE_BASE\n"
    ), message
    assert f"La rama está atrás de main y main cambió reglas de CI: {path}." in message
    assert "Actualiza la rama con main (o etiqueta ready-to-merge: el Train sincroniza)." in message


def test_current_pr_has_no_stale_hint() -> None:
    receipt, _ = pr_receipt(authority_change=True, current_head=True)
    assert receipt["stale_base"] is False
    assert receipt["ready"] is True
    M.require_ready(receipt)
    # Even the same blocking reason must retain the original message when current.
    receipt.update(ready=False, decision="UNKNOWN_FAIL_CLOSED",
                   reason="COMPATIBILITY_ASSESSMENT_MISSING")
    assert blocked_message(receipt) == (
        "BLOCK_CI_AUTHORITY_CURRENTNESS:UNKNOWN_FAIL_CLOSED:"
        "COMPATIBILITY_ASSESSMENT_MISSING"
    )


def test_stale_pr_without_selector_changes_stays_ready() -> None:
    receipt, _ = pr_receipt(authority_change=False)
    assert receipt["stale_base"] is True
    assert receipt["changed_ci_authority_paths"] == []
    assert receipt["ready"] is True
    assert receipt["decision"] == "CURRENT_REBOUND"
    M.require_ready(receipt)


def test_stale_hint_does_not_relabel_other_block_reasons() -> None:
    receipt, _ = pr_receipt(authority_change=True)
    receipt["reason"] = "COMPATIBILITY_UNKNOWN"
    assert blocked_message(receipt) == (
        "BLOCK_CI_AUTHORITY_CURRENTNESS:UNKNOWN_FAIL_CLOSED:COMPATIBILITY_UNKNOWN"
    )


def test_stale_selector_paths_are_sorted_and_capped_at_ten() -> None:
    repo, base = setup_repo()
    for i in range(12):
        (repo / f"sandbox/lf_contract_gate_test/s28_ci_lane_router/probe_{i:02}.py").write_text(
            "# selector fixture\n", encoding="utf-8"
        )
    current = commit_all(repo, "twelve selector changes")
    receipt = M.evaluate_ci_authority_currentness(
        repo=repo, bound_revision=base, current_revision=current,
        event_name="pull_request", candidate_head_revision=base,
    )
    paths = receipt["changed_ci_authority_paths"]
    assert len(paths) == 10 and paths == sorted(paths)
    assert paths[-1].endswith("probe_09.py")


def main() -> None:
    tests = [
        test_unrelated_main_change_is_current_rebound,
        test_main_advanced_after_pr_snapshot_rebinds_without_false_block,
        test_ci_authority_change_blocks_without_compatibility_proof,
        test_same_revision_is_current,
        test_pr_that_contains_current_main_binds_current_authority,
        test_pr_that_does_not_contain_current_main_keeps_historical_evidence,
        test_pr_uses_live_merge_base_not_stale_event_base,
        test_push_to_main_binds_new_evidence_to_current_main,
        test_feature_push_uses_merge_base_not_diff_base_as_authority,
        test_stale_pr_preserves_reason_and_adds_selector_hint,
        test_current_pr_has_no_stale_hint,
        test_stale_pr_without_selector_changes_stays_ready,
        test_stale_hint_does_not_relabel_other_block_reasons,
        test_stale_selector_paths_are_sorted_and_capped_at_ten,
    ]
    for test in tests:
        test()
    print(f"LF_CI_CURRENTNESS_BRIDGE_V1_PASS={len(tests)}/{len(tests)}")


if __name__ == "__main__":
    main()
