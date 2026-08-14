#!/usr/bin/env python3
"""Fail-closed PR93 contract wrapper with exact-head P0 real-source evidence.

The wrapper remains substitutable for the historical PR93 runtime entrypoint.
It preserves the original runtime scope while admitting one separately pinned
P0 exact-head broker extension on governed refs.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_V1 as core
from p0_exact_head_real_source_ci_v2 import governed_ref

sys.dont_writebytecode = True
sys.dont_write_bytecode = True

TARGET_REPOSITORY = core.TARGET_REPOSITORY
TARGET_PR_NUMBER = core.TARGET_PR_NUMBER
PR_BRANCH = core.PR_BRANCH
MAIN_BRANCH = core.MAIN_BRANCH
RUNTIME_ALERT_PATH = core.RUNTIME_ALERT_PATH
RUNTIME_ALERT_CONFIG_PATH = core.RUNTIME_ALERT_CONFIG_PATH
RUNTIME_PLATFORM_CONFIG_PATH = core.RUNTIME_PLATFORM_CONFIG_PATH
RUNTIME_RECONCILE_PATH = core.RUNTIME_RECONCILE_PATH
RUNTIME_RECONCILE_CANONICAL_PATH = core.RUNTIME_RECONCILE_CANONICAL_PATH
RUNTIME_RECONCILE_CONFIG_PATH = core.RUNTIME_RECONCILE_CONFIG_PATH
RUNTIME_MIGRATION_PATH = core.RUNTIME_MIGRATION_PATH
BLOB_RE = core.BLOB_RE
P0_CANDIDATE_PREFIX = core.P0_CANDIDATE_PREFIX
RuntimeScopeError = core.RuntimeScopeError
current_event_branch = core.current_event_branch
git_blob_for_path = core.git_blob_for_path
git_mode_for_path = core.git_mode_for_path
verify_main_merge_via_github = core.verify_main_merge_via_github

P0_EXACT_HEAD_BROKER_BLOBS = {
    "supabase/functions/lf-p0-exact-head-evidence-broker-v2/index.ts": "3654d0b9a174c86f547b07a81840a4cdd724f315",
    "supabase/functions/lf-p0-exact-head-evidence-broker-v2/policy.mjs": "c8fb441ceb9046b8f280a5b3f7f45e5e248eb848",
    "supabase/functions/lf-p0-exact-head-evidence-broker-v2/policy_test.mjs": "b7960666a34f536d642640c28c31c721dfee61f0",
}
P0_EXACT_HEAD_EXTENSION_PATHS = frozenset({RUNTIME_PLATFORM_CONFIG_PATH, *P0_EXACT_HEAD_BROKER_BLOBS})

_pinned = dict(core.EXPECTED_RUNTIME_BLOBS)
_pinned[RUNTIME_PLATFORM_CONFIG_PATH] = "e7f46a6874d254dcb474871f988d687678e218a0"
_pinned.update(P0_EXACT_HEAD_BROKER_BLOBS)
core.EXPECTED_RUNTIME_BLOBS = _pinned
core.EXPECTED_EDGE_PATHS = frozenset(path for path in _pinned if path.startswith("supabase/functions/"))
core.CONTROLLED_RUNTIME_PATHS = frozenset(_pinned)
EXPECTED_RUNTIME_BLOBS = core.EXPECTED_RUNTIME_BLOBS
EXPECTED_EDGE_PATHS = core.EXPECTED_EDGE_PATHS
CONTROLLED_RUNTIME_PATHS = core.CONTROLLED_RUNTIME_PATHS

_original_evaluate_controlled_runtime_scope = core.evaluate_controlled_runtime_scope


def _governed_p0_branch_name(branch: str) -> bool:
    return branch != MAIN_BRANCH and governed_ref(f"refs/heads/{branch}")


def _verify_p0_main_merge_via_github() -> bool:
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        return False
    if os.environ.get("GITHUB_REPOSITORY") != TARGET_REPOSITORY:
        return False
    if os.environ.get("GITHUB_REF") != "refs/heads/main":
        return False
    head_sha = os.environ.get("GITHUB_SHA", "")
    if BLOB_RE.fullmatch(head_sha) is None:
        return False
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        return False
    request = urllib.request.Request(
        f"https://api.github.com/repos/{TARGET_REPOSITORY}/commits/{head_sha}/pulls",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "p0-exact-head-runtime-extension-v2",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, UnicodeDecodeError, json.JSONDecodeError):
        return False
    if not isinstance(payload, list):
        return False
    return any(
        isinstance(pr, dict)
        and pr.get("merged_at")
        and (pr.get("base") or {}).get("ref") == MAIN_BRANCH
        and _governed_p0_branch_name((pr.get("head") or {}).get("ref", ""))
        and pr.get("merge_commit_sha") == head_sha
        for pr in payload
    )


def evaluate_controlled_runtime_scope(
    changed_files,
    *,
    branch: str,
    blob_by_path,
    mode_by_path=None,
    main_merge_verified: bool = False,
):
    changed = set(changed_files)
    controlled = {
        path for path in changed
        if path in CONTROLLED_RUNTIME_PATHS or path.startswith("supabase/functions/")
    }
    broker_specific = set(P0_EXACT_HEAD_BROKER_BLOBS)
    extension_only = bool(controlled & broker_specific) and controlled.issubset(P0_EXACT_HEAD_EXTENSION_PATHS)
    if not extension_only:
        return _original_evaluate_controlled_runtime_scope(
            changed_files,
            branch=branch,
            blob_by_path=blob_by_path,
            mode_by_path=mode_by_path,
            main_merge_verified=main_merge_verified,
        )
    if branch == MAIN_BRANCH:
        verified = main_merge_verified or _verify_p0_main_merge_via_github()
        if not verified:
            raise RuntimeScopeError(
                "FAIL_RUNTIME_MAIN_NOT_MERGED",
                "P0 exact-head broker main transition requires a merged governed P0 pull request at the exact workflow SHA",
            )
    elif not _governed_p0_branch_name(branch):
        raise RuntimeScopeError(
            "FAIL_RUNTIME_BRANCH_MISMATCH",
            f"P0 exact-head broker extension requires main or lf/p0-*; got {branch!r}",
        )
    return _original_evaluate_controlled_runtime_scope(
        changed_files,
        branch=PR_BRANCH,
        blob_by_path=blob_by_path,
        mode_by_path=mode_by_path,
        main_merge_verified=False,
    )


core.evaluate_controlled_runtime_scope = evaluate_controlled_runtime_scope
get_changed_files = core.get_changed_files
is_allowed_path = core.is_allowed_path

HELPER = Path(__file__).with_name("p0_exact_head_real_source_ci_v2.py")
HUMAN_REVIEW_CONVERGENCE_HELPER = Path(__file__).with_name("P0_HUMAN_REVIEW_CONVERGENCE_V1.py")


def _runtime_extension_self_test() -> None:
    exact = dict(EXPECTED_RUNTIME_BLOBS)
    modes = {path: "100644" for path in exact}
    broker = next(iter(P0_EXACT_HEAD_BROKER_BLOBS))
    if evaluate_controlled_runtime_scope(
        [broker, RUNTIME_PLATFORM_CONFIG_PATH],
        branch="lf/p0-exact-head-self-test",
        blob_by_path=exact,
        mode_by_path=modes,
    ) is not True:
        raise SystemExit("FAIL_P0_EXACT_HEAD_EXTENSION_POSITIVE")
    if evaluate_controlled_runtime_scope(
        [broker, RUNTIME_PLATFORM_CONFIG_PATH],
        branch=MAIN_BRANCH,
        blob_by_path=exact,
        mode_by_path=modes,
        main_merge_verified=True,
    ) is not True:
        raise SystemExit("FAIL_P0_EXACT_HEAD_EXTENSION_MAIN_POSITIVE")
    try:
        evaluate_controlled_runtime_scope(
            [broker],
            branch="feature/arbitrary",
            blob_by_path=exact,
            mode_by_path=modes,
        )
    except RuntimeScopeError as exc:
        if exc.code != "FAIL_RUNTIME_BRANCH_MISMATCH":
            raise
    else:
        raise SystemExit("FAIL_P0_EXACT_HEAD_EXTENSION_ARBITRARY_BRANCH_ALLOWED")
    try:
        evaluate_controlled_runtime_scope(
            [broker, "supabase/functions/arbitrary/index.ts"],
            branch="lf/p0-exact-head-self-test",
            blob_by_path=exact,
            mode_by_path=modes,
        )
    except RuntimeScopeError as exc:
        if exc.code not in {"FAIL_RUNTIME_EDGE_SCOPE", "FAIL_RUNTIME_BRANCH_MISMATCH"}:
            raise
    else:
        raise SystemExit("FAIL_P0_EXACT_HEAD_EXTENSION_ARBITRARY_EDGE_ALLOWED")
    print("PASS_P0_EXACT_HEAD_RUNTIME_EXTENSION_V2=4/4")


def _run_human_review_convergence_contract() -> None:
    completed = subprocess.run(
        [sys.executable, str(HUMAN_REVIEW_CONVERGENCE_HELPER)],
        cwd=Path(__file__).resolve().parents[2],
        env=os.environ.copy(),
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)
    print("PASS_P0_HUMAN_REVIEW_CONVERGENCE_GATE=1/1")


def _run_exact_head_real_source_if_required() -> None:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    github_ref = os.environ.get("GITHUB_REF", "")
    if event_name not in {"push", "workflow_dispatch"} or not governed_ref(github_ref):
        return
    completed = subprocess.run(
        [sys.executable, str(HELPER), "--evidence-capture"],
        cwd=Path(__file__).resolve().parents[2],
        env=os.environ.copy(),
        check=False,
    )
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


def main() -> None:
    _runtime_extension_self_test()
    _run_human_review_convergence_contract()
    original_pass_check = core.e16.base.pass_check

    def pass_check_with_real_source(message: str) -> None:
        _run_exact_head_real_source_if_required()
        original_pass_check(message)

    core.e16.base.pass_check = pass_check_with_real_source
    core.main()


if __name__ == "__main__":
    main()
