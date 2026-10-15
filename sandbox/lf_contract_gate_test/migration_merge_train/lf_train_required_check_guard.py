#!/usr/bin/env python3
"""Fail-closed exact-head gate for Train-required check runs.

The workflow invokes this script from its trusted checkout of current main, so
both this code and its versioned check list come from main, never the PR head.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

DEFAULT_CHECKS_FILE = Path(__file__).with_name("lf_train_required_pre_apply_checks_v1.json")
WAIT = 10
BLOCK = 2


def load_required_checks(path: Path = DEFAULT_CHECKS_FILE) -> tuple[str, ...]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"FAIL_TRAIN_REQUIRED_CHECKS_CONFIG_INVALID path={path}") from exc
    checks = document.get("required_checks") if isinstance(document, dict) else None
    if not isinstance(document, dict) or document.get("schema_version") != "lf-train-required-pre-apply-checks/v1":
        raise ValueError("FAIL_TRAIN_REQUIRED_CHECKS_CONFIG_SCHEMA")
    if (not isinstance(checks, list) or not checks
            or any(not isinstance(name, str) or not name.strip() for name in checks)
            or len(set(checks)) != len(checks)):
        raise ValueError("FAIL_TRAIN_REQUIRED_CHECKS_CONFIG_INVALID")
    return tuple(checks)


def evaluate(payload: Any, expected_head: str, required_checks: tuple[str, ...], *, final: bool = False) -> tuple[int, str]:
    pages = payload if isinstance(payload, list) else [payload]
    if not pages or any(not isinstance(page, dict) or not isinstance(page.get("check_runs"), list) for page in pages):
        return BLOCK, "FAIL_TRAIN_PASE_CHECKS_INVALID"

    runs = [row for page in pages for row in page["check_runs"]]
    for name in required_checks:
        matching = [row for row in runs if isinstance(row, dict) and row.get("name") == name]
        if not matching:
            code = "FAIL" if final else "WAIT"
            return (BLOCK if final else WAIT), f"{code}_TRAIN_REQUIRED_CHECK_MISSING check={name}"

        for row in matching:
            observed_head = row.get("head_sha")
            if observed_head != expected_head:
                return BLOCK, (
                    f"FAIL_TRAIN_REQUIRED_CHECK_HEAD_MISMATCH check={name} "
                    f"expected={expected_head} observed={observed_head or 'NOT_OBSERVED'}"
                )

        pending = [row for row in matching if row.get("status") != "completed"]
        if pending:
            if final:
                return BLOCK, (
                    f"FAIL_TRAIN_REQUIRED_CHECK_NOT_COMPLETED check={name} "
                    f"status={pending[0].get('status') or 'NOT_OBSERVED'}"
                )
            return WAIT, (
                f"WAIT_TRAIN_REQUIRED_CHECK_PENDING check={name} "
                f"status={pending[0].get('status') or 'NOT_OBSERVED'}"
            )

        for row in matching:
            conclusion = row.get("conclusion")
            if conclusion != "success":
                return BLOCK, (
                    f"FAIL_TRAIN_REQUIRED_CHECK_NOT_SUCCESS check={name} "
                    f"conclusion={conclusion or 'NOT_OBSERVED'}"
                )

    return 0, "PASS_TRAIN_REQUIRED_PASE_CHECKS"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--checks-file", type=Path, default=DEFAULT_CHECKS_FILE)
    parser.add_argument("--final", action="store_true")
    args = parser.parse_args()
    try:
        required_checks = load_required_checks(args.checks_file)
        payload = json.load(sys.stdin)
    except ValueError as exc:
        print(str(exc))
        return BLOCK
    except (json.JSONDecodeError, UnicodeDecodeError):
        print("FAIL_TRAIN_PASE_CHECKS_INVALID")
        return BLOCK
    code, message = evaluate(payload, args.head_sha, required_checks, final=args.final)
    print(message)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
