#!/usr/bin/env python3
"""Fail-closed PR93 runtime-source adapter layered over the E.16 validator.

Only pinned governed Edge source sets, platform function configuration, and the
versioned Story Creator P0 sandbox candidate are admitted beyond the base LF
contract scope. The historical PR93 branch remains supported. Story Agent
verifier branches and the exact governed Profile Creator source-parity branch
are admitted only with exact pinned blobs. A push on main is accepted only when
GitHub proves the exact workflow SHA came from an allowed merged pull request.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from collections.abc import Mapping, Sequence
from pathlib import Path

import PR93_LOTE_E16_CONTRACT_CHECK_ENTRYPOINT as e16

sys.dont_write_bytecode = True

TARGET_REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
TARGET_PR_NUMBER = 93
PR_BRANCH = "lf/architecture-v7-hardening"
MAIN_BRANCH = "main"
STORY_AGENT_VERIFIER_BRANCH_PREFIX = "lf/story-agent-evidence-verifier-"
PROFILE_CREATOR_SOURCE_PARITY_BRANCH = "lf/profile-creator-runtime-source-parity-20260902"
RUNTIME_ALERT_PATH = "supabase/functions/lf-architecture-alert-sink-v4/index.ts"
RUNTIME_ALERT_CONFIG_PATH = "supabase/functions/lf-architecture-alert-sink-v4/deno.json"
RUNTIME_PLATFORM_CONFIG_PATH = "supabase/config.toml"
RUNTIME_RECONCILE_PATH = "supabase/functions/lf-github-reconcile-v3/index.ts"
RUNTIME_RECONCILE_CANONICAL_PATH = "supabase/functions/lf-github-reconcile-v3/canonical_payload_v7.ts"
RUNTIME_RECONCILE_CONFIG_PATH = "supabase/functions/lf-github-reconcile-v3/deno.json"
RUNTIME_MIGRATION_PATH = (
    "supabase/migrations/"
    "20260806194820_pr93_p0_hmac_attempt_receipt_v6_no_downgrade.sql"
)
EXPECTED_RUNTIME_BLOBS = {
    RUNTIME_ALERT_PATH: "74b0a2123ceb5a66008231599bf3a5fb0ec3d66b",
    RUNTIME_ALERT_CONFIG_PATH: "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    RUNTIME_PLATFORM_CONFIG_PATH: "71c6530d72f81f4e787dd1a261b9cb08c73f80fd",
    RUNTIME_RECONCILE_PATH: "b001a62a6d1ce8fb662a864eb5a29d3e2a996725",
    RUNTIME_RECONCILE_CANONICAL_PATH: "2eb32d646fae7d36a50b2bf0087924a8bc5ff9d4",
    RUNTIME_RECONCILE_CONFIG_PATH: "26f214064a9165492dfd8a2cf6dc143dd8b29c63",
    RUNTIME_MIGRATION_PATH: "93510429231fd95a1c5ef3b2400ee38fabba4258",
    "supabase/functions/run-github-write-perfil-lf/index.ts": "9c49218c718391a8829587960d7a7e4165bff383",
    "supabase/functions/run-github-write-perfil-lf/deno.json": "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    "supabase/functions/run-github-readback-perfil-lf/index.ts": "0f3de697b0806ea5cb775a40a4e0d1cc58ac3dc4",
    "supabase/functions/run-github-readback-perfil-lf/deno.json": "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    "supabase/functions/run-creacion-perfil-lf/index.ts": "6dd4c65f3315d5b6d8ffaaf54d2d733603c408e9",
    "supabase/functions/run-creacion-perfil-lf/deno.json": "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    "supabase/functions/lf-profiles-governance-caller-v1/index.ts": "76999acf9fe19d3f753e59361696bd6f4ccce1ee",
    "supabase/functions/run-formalizacion-perfil-lf/index.ts": "5fc0953c08307af25703c9e4be2339a0c3d66d4d",
    "supabase/functions/run-formalizacion-perfil-lf/deno.json": "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    "supabase/functions/get-perfil-lf-runtime-protocol/index.ts": "c87779d11f64f0284e7a69ef63b72e12210cbb30",
    "supabase/functions/get-perfil-lf-runtime-protocol/deno.json": "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    "supabase/functions/get-perfil-lf-runtime-protocol-public-test/index.ts": "9d5672ba788843330cc0c4785d8413eb12d2d11e",
    "supabase/functions/get-perfil-lf-runtime-protocol-public-test/deno.json": "762e9b22bb21b951e9ddc5a171fe1be106d7cc31",
    "supabase/functions/story-agent-evidence-verifier-v1/index.ts": "133db8727f48c90511e8e75480ae51efac479c69",
    "supabase/functions/story-agent-evidence-verifier-v1/deno.json": "26f214064a9165492dfd8a2cf6dc143dd8b29c63",
}
EXPECTED_EDGE_PATHS = frozenset(
    path for path in EXPECTED_RUNTIME_BLOBS if path.startswith("supabase/functions/")
)
CONTROLLED_RUNTIME_PATHS = frozenset(EXPECTED_RUNTIME_BLOBS)
BLOB_RE = re.compile(r"^[0-9a-f]{40}$")
P0_CANDIDATE_PREFIX = "sandbox/story_creator_p0_visual/v1.1/"


class RuntimeScopeError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def _validate_path(path: str) -> None:
    if (
        not isinstance(path, str)
        or not path
        or not path.isascii()
        or path.startswith("/")
        or "\\" in path
        or "//" in path
        or any(part in ("", ".", "..") for part in path.split("/"))
    ):
        raise RuntimeScopeError("FAIL_RUNTIME_PATH_INVALID", f"invalid controlled path: {path!r}")


def _allowed_runtime_branch(branch: str) -> bool:
    return (
        branch == PR_BRANCH
        or branch.startswith(STORY_AGENT_VERIFIER_BRANCH_PREFIX)
        or branch == PROFILE_CREATOR_SOURCE_PARITY_BRANCH
    )


def _allowed_merged_head_branch(branch: str) -> bool:
    return branch.startswith(STORY_AGENT_VERIFIER_BRANCH_PREFIX) or branch == PROFILE_CREATOR_SOURCE_PARITY_BRANCH


def evaluate_controlled_runtime_scope(
    changed_files: Sequence[str],
    *,
    branch: str,
    blob_by_path: Mapping[str, str],
    mode_by_path: Mapping[str, str] | None = None,
    main_merge_verified: bool = False,
) -> bool:
    changed = set(changed_files)
    edge_paths = sorted(path for path in changed if path.startswith("supabase/functions/"))
    controlled_paths = sorted(
        path
        for path in changed
        if path in CONTROLLED_RUNTIME_PATHS or path.startswith("supabase/functions/")
    )
    if not controlled_paths:
        return False

    for path in controlled_paths:
        _validate_path(path)
    unexpected = sorted(set(edge_paths) - EXPECTED_EDGE_PATHS)
    if unexpected:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_EDGE_SCOPE",
            f"unexpected Edge paths: {unexpected!r}",
        )
    if (
        RUNTIME_ALERT_PATH in changed or RUNTIME_ALERT_CONFIG_PATH in changed
    ) and RUNTIME_MIGRATION_PATH not in changed:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_MIGRATION_PAIR_MISSING",
            f"alert sink source/config requires {RUNTIME_MIGRATION_PATH}",
        )

    if _allowed_runtime_branch(branch):
        pass
    elif branch == MAIN_BRANCH:
        if not main_merge_verified:
            raise RuntimeScopeError(
                "FAIL_RUNTIME_MAIN_NOT_MERGED",
                "main is accepted only after GitHub confirms an allowed governed PR merged at this SHA",
            )
    else:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_BRANCH_MISMATCH",
            f"runtime scope is restricted to governed runtime branches or verified {MAIN_BRANCH!r}; got {branch!r}",
        )

    modes = mode_by_path or {}
    for path, expected_blob in EXPECTED_RUNTIME_BLOBS.items():
        _validate_path(path)
        observed_blob = blob_by_path.get(path)
        if not isinstance(observed_blob, str) or BLOB_RE.fullmatch(observed_blob) is None:
            raise RuntimeScopeError(
                "FAIL_RUNTIME_BLOB_UNRESOLVED",
                f"could not resolve a valid Git blob for {path}",
            )
        if observed_blob != expected_blob:
            raise RuntimeScopeError(
                "FAIL_RUNTIME_BLOB_MISMATCH",
                f"{path} blob {observed_blob} differs from pinned {expected_blob}",
            )
        observed_mode = modes.get(path, "100644")
        if observed_mode != "100644":
            raise RuntimeScopeError(
                "FAIL_RUNTIME_FILE_MODE",
                f"{path} mode {observed_mode!r} is not a regular non-executable blob",
            )
    return True


def current_event_branch() -> str:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    if event_name == "pull_request":
        return os.environ.get("GITHUB_HEAD_REF", "")
    if event_name == "push":
        return os.environ.get("GITHUB_REF_NAME", "")
    return ""


def git_blob_for_path(path: str) -> str:
    return e16.run_git(["rev-parse", f"HEAD:{path}"]).strip()


def git_mode_for_path(path: str) -> str:
    output = e16.run_git(["ls-tree", "HEAD", "--", path]).strip()
    if not output:
        raise RuntimeError(f"path missing from HEAD: {path}")
    return output.split(None, 1)[0]


def _github_json(url: str, token: str, user_agent: str):
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": user_agent,
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read().decode("utf-8"))


def verify_main_merge_via_github() -> bool:
    if current_event_branch() != MAIN_BRANCH:
        return False
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

    try:
        historical = _github_json(
            f"https://api.github.com/repos/{TARGET_REPOSITORY}/pulls/{TARGET_PR_NUMBER}",
            token,
            "pr93-runtime-gate",
        )
        if historical.get("merged") is True and historical.get("merge_commit_sha") == head_sha:
            return True
        payload = _github_json(
            f"https://api.github.com/repos/{TARGET_REPOSITORY}/commits/{head_sha}/pulls",
            token,
            "runtime-gate-v2",
        )
    except (urllib.error.URLError, TimeoutError, UnicodeDecodeError, json.JSONDecodeError):
        return False
    if not isinstance(payload, list):
        return False
    return any(
        isinstance(pr, dict)
        and pr.get("merged_at")
        and pr.get("merge_commit_sha") == head_sha
        and (pr.get("base") or {}).get("ref") == MAIN_BRANCH
        and _allowed_merged_head_branch(str((pr.get("head") or {}).get("ref", "")))
        for pr in payload
    )


def _profile_creator_continuation_source_self_test() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    sources = {
        "caller": (repo_root / "supabase/functions/lf-profiles-governance-caller-v1/index.ts").read_text(encoding="utf-8"),
        "runtime": (repo_root / "supabase/functions/run-creacion-perfil-lf/index.ts").read_text(encoding="utf-8"),
        "recorder": (repo_root / "supabase/migrations/20260902133319_profile_creator_step_recorder_v1.sql").read_text(encoding="utf-8"),
    }
    checks = (
        ("caller", 'body.action === "profile_creator_record_step_v1"', "POS_CALLER_ACTION"),
        ("caller", 'action: "record_profile_creation_step_v1"', "POS_DELEGATION"),
        ("caller", 'result.outcome === "STEP_RECORDED"', "POS_CALLER_RESULT"),
        ("runtime", 'body.action === "record_profile_creation_step_v1"', "POS_RUNTIME_ACTION"),
        ("runtime", 'rpc("lf_record_creacion_perfil_step_v1"', "POS_CANONICAL_RPC"),
        ("caller", "OIDC_TOKEN_INVALID", "NEG_OIDC_TOKEN"),
        ("caller", "OIDC_REPOSITORY_MISMATCH", "NEG_OIDC_REPOSITORY"),
        ("caller", "OIDC_WORKFLOW_MISMATCH", "NEG_OIDC_WORKFLOW"),
        ("caller", "PROFILE_CREATOR_STEP_INPUT_INVALID", "NEG_CALLER_INPUT"),
        ("runtime", "GOVERNED_CALLER_MISSING", "NEG_CALLER_MISSING"),
        ("runtime", "GOVERNED_CALLER_METHOD_INVALID", "NEG_CALLER_METHOD"),
        ("runtime", "GOVERNED_CALLER_REPOSITORY_INVALID", "NEG_CALLER_REPOSITORY"),
        ("runtime", "GOVERNED_CALLER_WORKFLOW_INVALID", "NEG_CALLER_WORKFLOW"),
        ("runtime", "EXECUTION_ID_INVALID", "NEG_EXECUTION_ID"),
        ("runtime", "STEP_EXECUTION_IDENTITY_MISMATCH", "NEG_EXECUTION_IDENTITY"),
        ("runtime", "STEP_EVIDENCE_INPUT_INVALID", "NEG_EVIDENCE_INPUT"),
        ("recorder", "INIT_STEP_IMMUTABLE", "NEG_INIT_IMMUTABLE"),
        ("recorder", "PRIOR_REQUIRED_STEP_NOT_CLEAN", "NEG_PRIOR_STEP"),
        ("recorder", "REQUIRED_EVIDENCE_MISSING", "NEG_REQUIRED_EVIDENCE"),
        ("recorder", "BLOCKING_CODES_INVALID", "NEG_BLOCKING_CODES"),
        ("recorder", "STEP_ALREADY_RECORDED_DIFFERENT_EVIDENCE", "NEG_REPLAY_MISMATCH"),
        ("recorder", "PROFILE_CLOSE_GATE_FAILED", "NEG_CLOSE_GATE"),
    )
    missing = [code for source, token, code in checks if token not in sources[source]]
    if missing:
        e16.fail(
            "FAIL_PROFILE_CREATOR_CONTINUATION_SOURCE_TEST",
            f"Profile Creator continuation source matrix failed: {missing!r}",
        )
    print(f"PASS_PROFILE_CREATOR_CONTINUATION_SOURCE_MATRIX:{len(checks)}/{len(checks)}")


_runtime_scope_enabled = False
_original_is_allowed_path = e16.base.is_allowed_path


def get_changed_files() -> list[str]:
    global _runtime_scope_enabled
    changed_files = e16.get_changed_files()
    runtime_present = any(
        path in CONTROLLED_RUNTIME_PATHS or path.startswith("supabase/functions/")
        for path in changed_files
    )
    blobs: dict[str, str] = {}
    modes: dict[str, str] = {}
    if runtime_present:
        for path in EXPECTED_RUNTIME_BLOBS:
            try:
                blobs[path] = git_blob_for_path(path)
                modes[path] = git_mode_for_path(path)
            except Exception as exc:
                e16.fail("FAIL_RUNTIME_BLOB_UNRESOLVED", f"could not read pinned path {path}: {exc}")

    branch = current_event_branch()
    try:
        _runtime_scope_enabled = evaluate_controlled_runtime_scope(
            changed_files,
            branch=branch,
            blob_by_path=blobs,
            mode_by_path=modes,
            main_merge_verified=verify_main_merge_via_github() if branch == MAIN_BRANCH else False,
        )
    except RuntimeScopeError as exc:
        e16.fail(exc.code, exc.message)
    return changed_files


def is_allowed_path(path: str) -> bool:
    if path in CONTROLLED_RUNTIME_PATHS:
        return _runtime_scope_enabled
    if path.startswith(P0_CANDIDATE_PREFIX):
        return True
    return _original_is_allowed_path(path)


def main() -> None:
    if current_event_branch() == PROFILE_CREATOR_SOURCE_PARITY_BRANCH:
        _profile_creator_continuation_source_self_test()
    e16.base.get_changed_files = get_changed_files
    e16.base.is_allowed_path = is_allowed_path
    e16.base.main()


if __name__ == "__main__":
    main()
