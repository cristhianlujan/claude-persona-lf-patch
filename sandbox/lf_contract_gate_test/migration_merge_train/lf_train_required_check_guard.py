#!/usr/bin/env python3
"""Fail-closed exact-head gate for the two mandatory PASE Train checks."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any

REQUIRED_CHECKS = (
    "lf-independent-change-admission",
    "ig-runtime-candidate-judge",
)
WAIT = 10
BLOCK = 2


def evaluate(payload: Any, expected_head: str, *, final: bool = False) -> tuple[int, str]:
    if not isinstance(payload, dict) or not isinstance(payload.get("check_runs"), list):
        return BLOCK, "FAIL_TRAIN_PASE_CHECKS_INVALID"

    runs = payload["check_runs"]
    for name in REQUIRED_CHECKS:
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
    parser.add_argument("--final", action="store_true")
    args = parser.parse_args()
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError):
        print("FAIL_TRAIN_PASE_CHECKS_INVALID")
        return BLOCK
    code, message = evaluate(payload, args.head_sha, final=args.final)
    print(message)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
