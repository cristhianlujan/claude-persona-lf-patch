#!/usr/bin/env python3
"""Compatibility wrapper for PR93 runtime scope with an exact Customer Profile Creator lane.

The historical validator is preserved byte-for-byte in CORE_BASE_V1. This wrapper
adds only the exclusive Customer Profile Creator branch/path/blob tuple required
by PR #470, then delegates every other case to the preserved validator.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from collections.abc import Mapping, Sequence

import PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_BASE_V1 as _base
from PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_BASE_V1 import *  # noqa: F401,F403

CUSTOMER_PROFILE_CREATOR_BRANCH = "lf/profiles/profile-creator-customer-caller-20260902"
CUSTOMER_PROFILE_CREATOR_PR_NUMBER = 470
CUSTOMER_PROFILE_CREATOR_WORKFLOW = ".github/workflows/lf-customer-profile-creator-governance-caller.yml"
CUSTOMER_PROFILE_CREATOR_BLOBS = {
    CUSTOMER_PROFILE_CREATOR_WORKFLOW: "3a0842729dc695bb478f1a5989b3bfa4e660f123",
    "supabase/functions/lf-profile-creator-governance-caller-v1/index.ts": "d840f2964b886f9c1daa0e5ac2a344c3e3f2cd7b",
    "supabase/functions/run-creacion-perfil-lf/index.ts": "6902090913c7d393737d5dc83bbed919e11ddcbf",
}
CUSTOMER_PROFILE_CREATOR_PATHS = frozenset(CUSTOMER_PROFILE_CREATOR_BLOBS)

EXPECTED_RUNTIME_BLOBS = dict(_base.EXPECTED_RUNTIME_BLOBS)
EXPECTED_RUNTIME_BLOBS.update(CUSTOMER_PROFILE_CREATOR_BLOBS)
EXPECTED_EDGE_PATHS = frozenset(
    path for path in EXPECTED_RUNTIME_BLOBS if path.startswith("supabase/functions/")
)
CONTROLLED_RUNTIME_PATHS = frozenset(EXPECTED_RUNTIME_BLOBS)


def _verify_customer_main_merge_via_github() -> bool:
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
        f"https://api.github.com/repos/{TARGET_REPOSITORY}/pulls/{CUSTOMER_PROFILE_CREATOR_PR_NUMBER}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "profile-creator-customer-runtime-scope-v1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, UnicodeDecodeError, json.JSONDecodeError):
        return False
    return (
        isinstance(payload, dict)
        and payload.get("merged") is True
        and (payload.get("base") or {}).get("ref") == MAIN_BRANCH
        and (payload.get("head") or {}).get("ref") == CUSTOMER_PROFILE_CREATOR_BRANCH
        and payload.get("merge_commit_sha") == head_sha
    )


def _evaluate_customer_profile_creator_scope(
    changed_files: Sequence[str],
    *,
    branch: str,
    blob_by_path: Mapping[str, str],
    mode_by_path: Mapping[str, str] | None = None,
    main_merge_verified: bool = False,
) -> bool:
    changed = set(changed_files)
    controlled = {
        path
        for path in changed
        if path in CONTROLLED_RUNTIME_PATHS or path.startswith("supabase/functions/")
    }
    if controlled != set(CUSTOMER_PROFILE_CREATOR_PATHS):
        unexpected = sorted(controlled - set(CUSTOMER_PROFILE_CREATOR_PATHS))
        missing = sorted(set(CUSTOMER_PROFILE_CREATOR_PATHS) - controlled)
        raise RuntimeScopeError(
            "FAIL_RUNTIME_CUSTOMER_PROFILE_CREATOR_SCOPE",
            f"exclusive Customer Profile Creator runtime scope mismatch: unexpected={unexpected!r} missing={missing!r}",
        )
    if branch == MAIN_BRANCH:
        if not (main_merge_verified or _verify_customer_main_merge_via_github()):
            raise RuntimeScopeError(
                "FAIL_RUNTIME_MAIN_NOT_MERGED",
                "Customer Profile Creator main transition requires merged PR #470 at the exact workflow SHA",
            )
    elif branch != CUSTOMER_PROFILE_CREATOR_BRANCH:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_BRANCH_MISMATCH",
            f"Customer Profile Creator runtime requires {CUSTOMER_PROFILE_CREATOR_BRANCH!r} or verified main; got {branch!r}",
        )
    for path, expected_blob in CUSTOMER_PROFILE_CREATOR_BLOBS.items():
        observed = blob_by_path.get(path)
        if observed != expected_blob:
            raise RuntimeScopeError(
                "FAIL_RUNTIME_BLOB_MISMATCH",
                f"Customer Profile Creator blob mismatch for {path}: expected={expected_blob} observed={observed}",
            )
        if mode_by_path is not None and mode_by_path.get(path) != "100644":
            raise RuntimeScopeError(
                "FAIL_RUNTIME_MODE_MISMATCH",
                f"Customer Profile Creator path must be regular file 100644: {path}",
            )
    return True


def _sync_base_extensions() -> None:
    _base.EXPECTED_RUNTIME_BLOBS = EXPECTED_RUNTIME_BLOBS
    _base.EXPECTED_EDGE_PATHS = EXPECTED_EDGE_PATHS
    _base.CONTROLLED_RUNTIME_PATHS = CONTROLLED_RUNTIME_PATHS


def evaluate_controlled_runtime_scope(
    changed_files: Sequence[str],
    *,
    branch: str,
    blob_by_path: Mapping[str, str],
    mode_by_path: Mapping[str, str] | None = None,
    main_merge_verified: bool = False,
) -> bool:
    changed = set(changed_files)
    if changed & set(CUSTOMER_PROFILE_CREATOR_PATHS):
        return _evaluate_customer_profile_creator_scope(
            changed_files,
            branch=branch,
            blob_by_path=blob_by_path,
            mode_by_path=mode_by_path,
            main_merge_verified=main_merge_verified,
        )
    _sync_base_extensions()
    return _base.evaluate_controlled_runtime_scope(
        changed_files,
        branch=branch,
        blob_by_path=blob_by_path,
        mode_by_path=mode_by_path,
        main_merge_verified=main_merge_verified,
    )


def _customer_scope_self_test() -> None:
    exact = dict(CUSTOMER_PROFILE_CREATOR_BLOBS)
    modes = {path: "100644" for path in exact}
    paths = list(CUSTOMER_PROFILE_CREATOR_PATHS)
    if not _evaluate_customer_profile_creator_scope(
        paths,
        branch=CUSTOMER_PROFILE_CREATOR_BRANCH,
        blob_by_path=exact,
        mode_by_path=modes,
    ):
        raise SystemExit("FAIL_CUSTOMER_PROFILE_CREATOR_SCOPE_POSITIVE")
    workflow_lookalike = ".github/workflows/lf-customer-profile-creator-governance-caller-copy.yml"
    negative_cases = [
        ("branch", "feature/arbitrary", exact, paths),
        ("blob", CUSTOMER_PROFILE_CREATOR_BRANCH, {**exact, CUSTOMER_PROFILE_CREATOR_WORKFLOW: "0" * 40}, paths),
        ("edge_path", CUSTOMER_PROFILE_CREATOR_BRANCH, exact, [*paths, "supabase/functions/arbitrary/index.ts"]),
        (
            "workflow_path",
            CUSTOMER_PROFILE_CREATOR_BRANCH,
            {**{k: v for k, v in exact.items() if k != CUSTOMER_PROFILE_CREATOR_WORKFLOW}, workflow_lookalike: exact[CUSTOMER_PROFILE_CREATOR_WORKFLOW]},
            [workflow_lookalike, *[path for path in paths if path != CUSTOMER_PROFILE_CREATOR_WORKFLOW]],
        ),
    ]
    for label, test_branch, blobs, test_paths in negative_cases:
        try:
            _evaluate_customer_profile_creator_scope(
                test_paths,
                branch=test_branch,
                blob_by_path=blobs,
                mode_by_path={path: "100644" for path in test_paths},
            )
        except RuntimeScopeError:
            continue
        raise SystemExit(f"FAIL_CUSTOMER_PROFILE_CREATOR_SCOPE_NEGATIVE_{label.upper()}")
    print("PASS_CUSTOMER_PROFILE_CREATOR_EXACT_RUNTIME_SCOPE=5/5")


_original_base_get_changed_files = _base.get_changed_files


def _customer_get_changed_files() -> list[str]:
    """Admit the exact workflow to the historical .github scanner only after scope proof.

    The base validator keeps broad .github default-denied. The single exact workflow
    becomes visible to its historical ALLOWED_GITHUB_EXACT check only after the
    branch/path/blob/mode gate above has already passed for the changed-file set.
    """
    changed_files = _original_base_get_changed_files()
    changed = set(changed_files)
    if CUSTOMER_PROFILE_CREATOR_WORKFLOW in changed:
        branch = current_event_branch()
        if branch != CUSTOMER_PROFILE_CREATOR_BRANCH:
            raise RuntimeScopeError(
                "FAIL_RUNTIME_BRANCH_MISMATCH",
                f"Customer workflow admission requires {CUSTOMER_PROFILE_CREATOR_BRANCH!r}; got {branch!r}",
            )
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
