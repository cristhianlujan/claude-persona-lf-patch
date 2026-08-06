#!/usr/bin/env python3
"""Fail-closed PR93 runtime-scope adapter layered over the E.16 validator.

This adapter preserves the byte-identical E.16 base validator and grants one
narrow exception: the exact HMAC alert-sink source is accepted only when it is
paired with the exact reconciliation migration, on the PR93 branch, and both
files match their pinned Git blob identifiers.
"""
from __future__ import annotations

import os
import re
import sys
from collections.abc import Mapping, Sequence

import PR93_LOTE_E16_CONTRACT_CHECK_ENTRYPOINT as e16

sys.dont_write_bytecode = True

RUNTIME_BRANCH = "lf/architecture-v7-hardening"
RUNTIME_EDGE_PATH = "supabase/functions/lf-architecture-alert-sink-v4/index.ts"
RUNTIME_MIGRATION_PATH = (
    "supabase/migrations/"
    "20260806063000_pr93_p0_hmac_attempt_receipt_reconciliation_v5.sql"
)
EXPECTED_RUNTIME_BLOBS = {
    RUNTIME_EDGE_PATH: "f944dab3e8b9fa6cfb15fcfa3e355b64c057327a",
    RUNTIME_MIGRATION_PATH: "24d114782b870c76cd0fa9190241faa6921a48ab",
}
BLOB_RE = re.compile(r"^[0-9a-f]{40}$")


class RuntimeScopeError(ValueError):
    """Controlled runtime scope validation error."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def evaluate_controlled_runtime_scope(
    changed_files: Sequence[str],
    *,
    branch: str,
    blob_by_path: Mapping[str, str],
) -> bool:
    """Return True only for the pinned Edge+migration scope.

    A change set without any Edge Function is outside this special exception
    and returns False so the original E.16 rules remain authoritative.
    """

    changed = set(changed_files)
    edge_paths = sorted(
        path for path in changed if path.startswith("supabase/functions/")
    )
    if not edge_paths:
        return False

    if edge_paths != [RUNTIME_EDGE_PATH]:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_EDGE_SCOPE",
            f"Edge paths must be exactly {RUNTIME_EDGE_PATH!r}: {edge_paths!r}",
        )
    if RUNTIME_MIGRATION_PATH not in changed:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_MIGRATION_PAIR_MISSING",
            f"{RUNTIME_EDGE_PATH} requires {RUNTIME_MIGRATION_PATH}",
        )
    if branch != RUNTIME_BRANCH:
        raise RuntimeScopeError(
            "FAIL_RUNTIME_BRANCH_MISMATCH",
            f"runtime scope is restricted to {RUNTIME_BRANCH!r}, got {branch!r}",
        )

    for path, expected_blob in EXPECTED_RUNTIME_BLOBS.items():
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


_runtime_scope_enabled = False
_original_is_allowed_path = e16.base.is_allowed_path


def get_changed_files() -> list[str]:
    global _runtime_scope_enabled
    changed_files = e16.get_changed_files()
    edge_present = any(
        path.startswith("supabase/functions/") for path in changed_files
    )
    blobs: dict[str, str] = {}
    if edge_present:
        for path in EXPECTED_RUNTIME_BLOBS:
            try:
                blobs[path] = git_blob_for_path(path)
            except Exception as exc:
                e16.fail(
                    "FAIL_RUNTIME_BLOB_UNRESOLVED",
                    f"could not read Git blob for {path}: {exc}",
                )

    try:
        _runtime_scope_enabled = evaluate_controlled_runtime_scope(
            changed_files,
            branch=current_event_branch(),
            blob_by_path=blobs,
        )
    except RuntimeScopeError as exc:
        e16.fail(exc.code, exc.message)
    return changed_files


def is_allowed_path(path: str) -> bool:
    if path == RUNTIME_EDGE_PATH:
        return _runtime_scope_enabled
    return _original_is_allowed_path(path)


def main() -> None:
    e16.base.get_changed_files = get_changed_files
    e16.base.is_allowed_path = is_allowed_path
    e16.base.main()


if __name__ == "__main__":
    main()
