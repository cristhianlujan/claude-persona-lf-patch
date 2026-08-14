#!/usr/bin/env python3
"""Fail-closed PR93 contract wrapper with exact-head P0 real-source evidence.

The wrapper must remain a substitutable adapter for the historical PR93 runtime
entrypoint. Public runtime-scope symbols are re-exported from the versioned core
so existing regression consumers exercise the same contract while this wrapper
adds only the exact-head real-source hook.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_V1 as core
from p0_exact_head_real_source_ci_v2 import governed_ref

sys.dont_write_bytecode = True

# Preserve the public surface of the previous entrypoint. This is explicit
# instead of ``from ... import *`` so an accidental core interface change is
# reviewable and fails consumers deterministically.
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
EXPECTED_RUNTIME_BLOBS = core.EXPECTED_RUNTIME_BLOBS
EXPECTED_EDGE_PATHS = core.EXPECTED_EDGE_PATHS
CONTROLLED_RUNTIME_PATHS = core.CONTROLLED_RUNTIME_PATHS
BLOB_RE = core.BLOB_RE
P0_CANDIDATE_PREFIX = core.P0_CANDIDATE_PREFIX
RuntimeScopeError = core.RuntimeScopeError
evaluate_controlled_runtime_scope = core.evaluate_controlled_runtime_scope
current_event_branch = core.current_event_branch
git_blob_for_path = core.git_blob_for_path
git_mode_for_path = core.git_mode_for_path
verify_main_merge_via_github = core.verify_main_merge_via_github
get_changed_files = core.get_changed_files
is_allowed_path = core.is_allowed_path

HELPER = Path(__file__).with_name("p0_exact_head_real_source_ci_v2.py")


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
    original_pass_check = core.e16.base.pass_check

    def pass_check_with_real_source(message: str) -> None:
        _run_exact_head_real_source_if_required()
        original_pass_check(message)

    core.e16.base.pass_check = pass_check_with_real_source
    core.main()


if __name__ == "__main__":
    main()
