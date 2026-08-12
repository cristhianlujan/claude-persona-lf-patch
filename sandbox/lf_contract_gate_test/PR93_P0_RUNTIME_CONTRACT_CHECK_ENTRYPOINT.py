#!/usr/bin/env python3
"""Fail-closed PR93 contract wrapper with exact-head P0 real-source evidence."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import PR93_P0_RUNTIME_CONTRACT_CHECK_CORE_V1 as core

sys.dont_write_bytecode = True

EXACT_HEAD_REF = "refs/heads/lf/p0-persistence-ocr-completion-20260812"
HELPER = Path(__file__).with_name("p0_exact_head_real_source_ci_v1.py")


def _run_exact_head_real_source_if_required() -> None:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    github_ref = os.environ.get("GITHUB_REF", "")
    if event_name not in {"push", "workflow_dispatch"} or github_ref != EXACT_HEAD_REF:
        return
    completed = subprocess.run(
        [sys.executable, str(HELPER)],
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
