#!/usr/bin/env python3
"""M4.6 cross-family 10-case SQL harness; fail-closed and fully reversible.

Uses the existing exact SQL fixture, which owns BEGIN/ROLLBACK. No DB credentials
are stored in Git and no synthetic PASS is emitted. --inspect-only is NOT a test run.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = HERE / "m46_cross_family_detector_cases_v1.sql"
SCHEMA = "M46_CROSS_FAMILY_DETECTOR_TEST_RUN_V1"


def check_source() -> tuple[str, str]:
    source = SOURCE.read_text(encoding="utf-8")
    stripped = re.sub(r"(?m)^\s*--[^\n]*", "", source).strip().lower()
    if not stripped.startswith("begin;") or not stripped.endswith("rollback;"):
        raise ValueError("M46_SQL_MUST_BEGIN_AND_ROLLBACK")
    if source.count("M46_CROSS_FAMILY_DETECTOR_TEST_RUN_V1") != 1:
        raise ValueError("M46_SQL_SCHEMA_ID_MISMATCH")
    sha = subprocess.check_output(
        ["git", "-C", str(ROOT), "hash-object", str(SOURCE)], text=True
    ).strip()
    dirty = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--quiet", "HEAD", "--", str(SOURCE)],
        check=False,
    )
    if dirty.returncode:
        raise ValueError("M46_CANONICAL_SQL_DIRTY")
    return source, sha


def run_sql(source: str) -> dict:
    db_url = os.environ.get("IG_SANDBOX_DATABASE_URL")
    if not db_url:
        raise ValueError("M46_SANDBOX_DB_CREDENTIAL_MISSING")
    env = dict(os.environ)
    env["PGDATABASE"] = db_url
    env.pop("IG_SANDBOX_DATABASE_URL", None)
    result = subprocess.run(
        ["psql", "-X", "--no-password", "-v", "ON_ERROR_STOP=1", "-t", "-A"],
        input=source,
        text=True,
        capture_output=True,
        timeout=90,
        env=env,
        check=False,
    )
    if result.returncode:
        raise ValueError(f"M46_SQL_EXECUTION_FAILED:psql_exit={result.returncode}")
    runs = []
    for line in result.stdout.splitlines():
        try:
            row = json.loads(line.strip())
        except (ValueError, TypeError):
            continue
        if isinstance(row, dict) and row.get("schema_version") == SCHEMA:
            runs.append(row)
    if len(runs) != 1:
        raise ValueError(f"M46_RUN_REPORT_COUNT_INVALID:{len(runs)}")
    return runs[0]


def validate(report: dict) -> None:
    expected = {
        "schema_version": SCHEMA,
        "actual_execution": True,
        "synthetic_pass": False,
        "transaction_policy": "ROLLBACK_ALL_FIXTURES",
        "case_count": 10,
        "pass_count": 10,
        "failure_count": 0,
        "positive_passed": 5,
        "negative_detected": 5,
    }
    for key, value in expected.items():
        if report.get(key) != value:
            raise ValueError(f"M46_ASSERTION_FAILED:{key}:{report.get(key)}")
    rows = report.get("results")
    if not isinstance(rows, list) or len(rows) != 10:
        raise ValueError("M46_CASE_REPORT_COUNT_INVALID")
    codes = [r.get("test_code") for r in rows]
    if len(set(codes)) != 10 or any(r.get("status") != "PASS" for r in rows):
        raise ValueError("M46_PER_CASE_REPORT_FAILED")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inspect-only", action="store_true")
    parser.add_argument("--output", default="m46_qualification_report.json")
    args = parser.parse_args()
    try:
        source, source_sha = check_source()
        head = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip()
        if args.inspect_only:
            report = {
                "status": "SOURCE_VALIDATED_NOT_EXECUTED",
                "actual_execution": False,
                "source_git_blob_sha": source_sha,
                "source_commit_sha": head,
                "activation_authorized": False,
            }
        else:
            report = run_sql(source)
            validate(report)
            report["source_git_blob_sha"] = source_sha
            report["source_commit_sha"] = head
            report["activation_authorized"] = False
        Path(args.output).write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
        print(f"M46 {report.get('status', 'PASS_10_OF_10')} blob={source_sha}; activation=DISABLED")
        return 0
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"FAIL_CLOSED:{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
