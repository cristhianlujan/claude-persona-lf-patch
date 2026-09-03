#!/usr/bin/env python3
"""Exact governed runtime scope extension for the Customer Profile Creator lane."""
from __future__ import annotations

import json
import os
import subprocess
import urllib.error
import urllib.request
from collections.abc import Mapping, Sequence

import PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_BASE_V1 as _base
from PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_BASE_V1 import *  # noqa: F401,F403

CUSTOMER_PROFILE_CREATOR_BRANCH = "lf/profiles/profile-creator-customer-caller-20260902"
CUSTOMER_PROFILE_CREATOR_PR_NUMBER = 470  # historical merged admission; update only at a later authorized merge gate
CUSTOMER_PROFILE_CREATOR_WORKFLOW = ".github/workflows/lf-customer-profile-creator-governance-caller.yml"
CUSTOMER_PROFILE_CREATOR_BLOBS = {
    CUSTOMER_PROFILE_CREATOR_WORKFLOW: "b4a2b342a58bd26f63c88a18a11ed8ca28354be8",
    "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts": "d8ddbaf384913117ccf2bbf015548054f44f4083",
    "supabase/functions/lf-profile-creator-governance-caller-v1/batch.ts": "604b2934cf12dbd4d9ddc40453d77816c6a17ade",
    "supabase/functions/lf-profile-creator-governance-caller-v1/.trigger-customer-identity-privacy-20260902": "a07d7887f09b4d1a1cc267c74efc79a3e0383c09",
    "supabase/functions/lf-profile-creator-governance-caller-v1/.trigger-customer-payments-recovery-20260902": "a07d7887f09b4d1a1cc267c74efc79a3e0383c09",
    "supabase/functions/run-creacion-perfil-lf/index.ts": "a95a95f79d13a9f9360d5433b418c3f0a4b86354",
}
CUSTOMER_PROFILE_CREATOR_PATHS = frozenset(CUSTOMER_PROFILE_CREATOR_BLOBS)
EXPECTED_RUNTIME_BLOBS = dict(_base.EXPECTED_RUNTIME_BLOBS)
EXPECTED_RUNTIME_BLOBS.update(CUSTOMER_PROFILE_CREATOR_BLOBS)
EXPECTED_EDGE_PATHS = frozenset(path for path in EXPECTED_RUNTIME_BLOBS if path.startswith("supabase/functions/"))
CONTROLLED_RUNTIME_PATHS = frozenset(EXPECTED_RUNTIME_BLOBS)


def _sync_base_extensions() -> None:
    _base.EXPECTED_RUNTIME_BLOBS = EXPECTED_RUNTIME_BLOBS
    _base.EXPECTED_EDGE_PATHS = EXPECTED_EDGE_PATHS
    _base.CONTROLLED_RUNTIME_PATHS = CONTROLLED_RUNTIME_PATHS


def _verify_customer_main_merge_via_github() -> bool:
    if os.environ.get("GITHUB_EVENT_NAME") != "push" or os.environ.get("GITHUB_REPOSITORY") != TARGET_REPOSITORY or os.environ.get("GITHUB_REF") != "refs/heads/main":
        return False
    head_sha = os.environ.get("GITHUB_SHA", "")
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if BLOB_RE.fullmatch(head_sha) is None or not token:
        return False
    request = urllib.request.Request(
        f"https://api.github.com/repos/{TARGET_REPOSITORY}/pulls/{CUSTOMER_PROFILE_CREATOR_PR_NUMBER}",
        headers={"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "profile-creator-customer-runtime-scope-v1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, UnicodeDecodeError, json.JSONDecodeError):
        return False
    return isinstance(payload, dict) and payload.get("merged") is True and (payload.get("base") or {}).get("ref") == MAIN_BRANCH and (payload.get("head") or {}).get("ref") == CUSTOMER_PROFILE_CREATOR_BRANCH and payload.get("merge_commit_sha") == head_sha


def _evaluate_customer_profile_creator_scope(changed_files: Sequence[str], *, branch: str, blob_by_path: Mapping[str, str], mode_by_path: Mapping[str, str] | None = None, main_merge_verified: bool = False) -> bool:
    changed = set(changed_files)
    controlled = {path for path in changed if path in CONTROLLED_RUNTIME_PATHS or path.startswith("supabase/functions/")}
    if controlled != set(CUSTOMER_PROFILE_CREATOR_PATHS):
        raise RuntimeScopeError("FAIL_RUNTIME_CUSTOMER_PROFILE_CREATOR_SCOPE", f"exclusive Customer Profile Creator runtime scope mismatch: unexpected={sorted(controlled-set(CUSTOMER_PROFILE_CREATOR_PATHS))!r} missing={sorted(set(CUSTOMER_PROFILE_CREATOR_PATHS)-controlled)!r}")
    if branch == MAIN_BRANCH:
        if not (main_merge_verified or _verify_customer_main_merge_via_github()):
            raise RuntimeScopeError("FAIL_RUNTIME_MAIN_NOT_MERGED", "Customer Profile Creator main transition requires an exact merged governed PR")
    elif branch != CUSTOMER_PROFILE_CREATOR_BRANCH:
        raise RuntimeScopeError("FAIL_RUNTIME_BRANCH_MISMATCH", f"Customer Profile Creator runtime requires {CUSTOMER_PROFILE_CREATOR_BRANCH!r} or verified main; got {branch!r}")
    for path, expected_blob in CUSTOMER_PROFILE_CREATOR_BLOBS.items():
        observed = blob_by_path.get(path)
        if observed != expected_blob:
            raise RuntimeScopeError("FAIL_RUNTIME_BLOB_MISMATCH", f"Customer Profile Creator blob mismatch for {path}: expected={expected_blob} observed={observed}")
        if mode_by_path is not None and mode_by_path.get(path) != "100644":
            raise RuntimeScopeError("FAIL_RUNTIME_MODE_MISMATCH", f"Customer Profile Creator path must be regular file 100644: {path}")
    return True


def evaluate_controlled_runtime_scope(changed_files: Sequence[str], *, branch: str, blob_by_path: Mapping[str, str], mode_by_path: Mapping[str, str] | None = None, main_merge_verified: bool = False) -> bool:
    if set(changed_files) & set(CUSTOMER_PROFILE_CREATOR_PATHS):
        return _evaluate_customer_profile_creator_scope(changed_files, branch=branch, blob_by_path=blob_by_path, mode_by_path=mode_by_path, main_merge_verified=main_merge_verified)
    _sync_base_extensions()
    return _base.evaluate_controlled_runtime_scope(changed_files, branch=branch, blob_by_path=blob_by_path, mode_by_path=mode_by_path, main_merge_verified=main_merge_verified)


def _customer_scope_self_test() -> None:
    exact = dict(CUSTOMER_PROFILE_CREATOR_BLOBS)
    modes = {path: "100644" for path in exact}
    paths = list(CUSTOMER_PROFILE_CREATOR_PATHS)
    assert _evaluate_customer_profile_creator_scope(paths, branch=CUSTOMER_PROFILE_CREATOR_BRANCH, blob_by_path=exact, mode_by_path=modes)
    negatives = [
        ("branch", "feature/arbitrary", exact, paths),
        ("blob", CUSTOMER_PROFILE_CREATOR_BRANCH, {**exact, CUSTOMER_PROFILE_CREATOR_WORKFLOW: "0"*40}, paths),
        ("edge", CUSTOMER_PROFILE_CREATOR_BRANCH, exact, [*paths, "supabase/functions/arbitrary/index.ts"]),
    ]
    for label, branch, blobs, changed in negatives:
        try:
            _evaluate_customer_profile_creator_scope(changed, branch=branch, blob_by_path=blobs, mode_by_path={path: "100644" for path in changed})
        except RuntimeScopeError:
            continue
        raise SystemExit(f"FAIL_CUSTOMER_PROFILE_CREATOR_SCOPE_NEGATIVE_{label.upper()}")
    print("PASS_CUSTOMER_PROFILE_CREATOR_EXACT_RUNTIME_SCOPE=4/4")


_original_get_changed_files = _base.get_changed_files


def _customer_branch_scope_for_push() -> list[str]:
    subprocess.run(["git", "fetch", "--no-tags", "origin", MAIN_BRANCH], check=True, stdout=subprocess.DEVNULL)
    merge_base = _base.e16.run_git(["merge-base", f"origin/{MAIN_BRANCH}", "HEAD"]).strip()
    if BLOB_RE.fullmatch(merge_base) is None:
        raise RuntimeScopeError("FAIL_RUNTIME_CUSTOMER_PUSH_BASE_UNRESOLVED", "Customer Profile Creator push could not resolve merge-base with main")
    changed_files = _base.e16.git_changed_files(merge_base, "HEAD")
    blobs, modes = {}, {}
    for path in CUSTOMER_PROFILE_CREATOR_BLOBS:
        blobs[path] = git_blob_for_path(path)
        modes[path] = git_mode_for_path(path)
    _base._runtime_scope_enabled = _evaluate_customer_profile_creator_scope(changed_files, branch=CUSTOMER_PROFILE_CREATOR_BRANCH, blob_by_path=blobs, mode_by_path=modes)
    print(f"PASS_CUSTOMER_PROFILE_CREATOR_PUSH_PR_SCOPE_PARITY={len(changed_files)}")
    return changed_files


def _customer_get_changed_files() -> list[str]:
    if os.environ.get("GITHUB_EVENT_NAME") == "push" and current_event_branch() == CUSTOMER_PROFILE_CREATOR_BRANCH:
        changed_files = _customer_branch_scope_for_push()
    else:
        changed_files = _original_get_changed_files()
    if CUSTOMER_PROFILE_CREATOR_WORKFLOW in set(changed_files):
        if current_event_branch() != CUSTOMER_PROFILE_CREATOR_BRANCH:
            raise RuntimeScopeError("FAIL_RUNTIME_BRANCH_MISMATCH", "Customer workflow admission requires exact governed branch")
        _base.e16.base.ALLOWED_GITHUB_EXACT.add(CUSTOMER_PROFILE_CREATOR_WORKFLOW)
    return changed_files


def main() -> int:
    _sync_base_extensions()
    _base.evaluate_controlled_runtime_scope = evaluate_controlled_runtime_scope
    _base.get_changed_files = _customer_get_changed_files
    return _base.main()


_customer_scope_self_test()

if __name__ == "__main__":
    raise SystemExit(main())
