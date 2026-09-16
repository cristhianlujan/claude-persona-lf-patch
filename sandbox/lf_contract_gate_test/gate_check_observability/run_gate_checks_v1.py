#!/usr/bin/env python3
"""Produce durable check-level LF_GATE_ERROR_V1 diagnostics for CI gates.

This is a producer only. It does not mutate LF operational state and does not
replace the canonical Supabase recorder. A governed ingestion path may later
persist the same check facts with catalog error_id / occurrence_id references.
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Iterable

CONTRACT = "LF_GATE_ERROR_V1"
MODES = {"COLLECT_ALL", "FAIL_FAST_CRITICAL"}
_SECRET_PATTERNS = [
    re.compile(r"(?i)(authorization\s*:\s*bearer\s+)[^\s]+"),
    re.compile(r"(?i)((?:password|secret|token|api[_-]?key|service[_-]?role)\s*[=:]\s*)[^\s]+"),
]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()


def redact(value: str) -> str:
    out = value
    for pattern in _SECRET_PATTERNS:
        out = pattern.sub(r"\1[REDACTED]", out)
    return out


def stable_uuid(namespace: str, value: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"lf://{namespace}/{value}"))


def normalize_paths(patterns: Iterable[str]) -> list[str]:
    paths: set[str] = set()
    for pattern in patterns:
        paths.update(p for p in glob.glob(pattern, recursive=True) if Path(p).is_file())
    return sorted(paths)


def git_head() -> str:
    env_sha = (os.environ.get("GITHUB_SHA") or "").strip()
    if re.fullmatch(r"[0-9a-f]{40}", env_sha):
        return env_sha
    try:
        value = subprocess.run(
            ["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True
        ).stdout.strip()
        if re.fullmatch(r"[0-9a-f]{40}", value):
            return value
    except (OSError, subprocess.CalledProcessError):
        pass
    return "UNKNOWN_SOURCE_COMMIT"


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--gate-id", required=True)
    p.add_argument("--step-id", required=True)
    p.add_argument("--mode", choices=sorted(MODES), default="COLLECT_ALL")
    p.add_argument("--glob", action="append", dest="patterns", required=True)
    p.add_argument("--artifact-dir", required=True)
    p.add_argument("--artifact-name", default="lf_gate_error_v1.json")
    p.add_argument("--check-prefix", default="CHECK")
    p.add_argument("--owner", required=True)
    p.add_argument("--next-action", required=True)
    p.add_argument("--run-id", default=os.environ.get("GITHUB_RUN_ID") or "LOCAL")
    p.add_argument("--job-id", default=os.environ.get("GITHUB_JOB") or "LOCAL")
    p.add_argument("--source-commit", default=None)
    p.add_argument("--downstream-impact", action="append", default=[])
    p.add_argument(
        "--critical-pattern",
        action="append",
        default=[],
        help="fnmatch-like regex fragment; only used by FAIL_FAST_CRITICAL",
    )
    return p.parse_args()


def is_critical(path: str, patterns: list[str]) -> bool:
    return any(re.search(pattern, path) for pattern in patterns)


def main() -> int:
    args = parse_args()
    artifact_dir = Path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    source_commit = args.source_commit or git_head()
    test_paths = normalize_paths(args.patterns)
    started_at = utc_now()
    parent_trace_id = f"LF-CI-GATE-{stable_uuid('parent-trace', f'{args.run_id}:{args.job_id}:{args.gate_id}')}"

    if not test_paths:
        blocked = {
            "contract": CONTRACT,
            "run_id": str(args.run_id),
            "job_id": str(args.job_id),
            "step_id": args.step_id,
            "gate_id": args.gate_id,
            "gate_mode": args.mode,
            "gate_result": "BLOCKED",
            "error_id": stable_uuid("error", f"{args.run_id}:{args.gate_id}:NO_CHECKS"),
            "error_class": "GATE_CHECK_SET_MISSING",
            "condition": "declared gate resolves at least one executable check",
            "expected": {"check_count_min": 1},
            "actual": {"check_count": 0},
            "source_commit": source_commit,
            "source_path": args.patterns,
            "trace_id": f"LF-CI-{stable_uuid('trace', f'{args.run_id}:{args.gate_id}:NO_CHECKS')}",
            "parent_trace_id": parent_trace_id,
            "rc": 2,
            "timestamp": utc_now(),
            "downstream_impact": args.downstream_impact,
            "owner": args.owner,
            "next_action": args.next_action,
            "checks": [],
        }
        write_text(artifact_dir / args.artifact_name, json.dumps(blocked, indent=2, sort_keys=True) + "\n")
        print(json.dumps({"gate_id": args.gate_id, "result": "BLOCKED", "reason": "NO_CHECKS"}, sort_keys=True))
        return 2

    checks: list[dict] = []
    first_critical_failure: int | None = None
    for index, test_path in enumerate(test_paths, start=1):
        check_id = f"{args.check_prefix}-{index:03d}"
        critical = args.mode == "FAIL_FAST_CRITICAL" and is_critical(test_path, args.critical_pattern)
        started = utc_now()
        proc = subprocess.run([sys.executable, test_path], capture_output=True, text=True)
        stdout = redact(proc.stdout or "")
        stderr = redact(proc.stderr or "")
        log_base = artifact_dir / "checks" / check_id
        stdout_path = log_base.with_suffix(".stdout.log")
        stderr_path = log_base.with_suffix(".stderr.log")
        write_text(stdout_path, stdout)
        write_text(stderr_path, stderr)
        status = "PASS" if proc.returncode == 0 else "FAIL"
        error_id = None if status == "PASS" else stable_uuid("error", f"{args.run_id}:{args.job_id}:{args.gate_id}:{check_id}:{source_commit}")
        trace_id = f"LF-CI-{stable_uuid('trace', f'{args.run_id}:{args.job_id}:{args.gate_id}:{check_id}:{source_commit}')}"
        checks.append(
            {
                "check_id": check_id,
                "check_status": status,
                "critical": critical,
                "error_id": error_id,
                "error_class": None if status == "PASS" else "PROCESS_EXIT_NONZERO",
                "condition": "independent Python validation exits with rc=0",
                "expected": {"rc": 0},
                "actual": {"rc": proc.returncode},
                "input_ref": test_path,
                "evidence_ref": f"artifact://{args.artifact_name}#checks/{check_id}",
                "producer": test_path,
                "source_commit": source_commit,
                "source_path": test_path,
                "trace_id": trace_id,
                "parent_trace_id": parent_trace_id,
                "rc": proc.returncode,
                "timestamp": utc_now(),
                "started_at": started,
                "stdout_ref": str(stdout_path.as_posix()),
                "stderr_ref": str(stderr_path.as_posix()),
                "stdout_sha256": sha256_text(stdout),
                "stderr_sha256": sha256_text(stderr),
                "downstream_impact": args.downstream_impact if status != "PASS" else [],
                "owner": args.owner,
                "next_action": args.next_action if status != "PASS" else "NONE",
            }
        )
        print(f"LF_GATE_CHECK check_id={check_id} status={status} rc={proc.returncode} source={test_path}")
        if status != "PASS" and critical:
            first_critical_failure = index
            break

    expected_check_ids = [f"{args.check_prefix}-{i:03d}" for i in range(1, len(test_paths) + 1)]
    executed_ids = [c["check_id"] for c in checks]
    failures = [c for c in checks if c["check_status"] == "FAIL"]
    if args.mode == "COLLECT_ALL":
        gate_result = "FAIL" if failures else "PASS"
        completeness = executed_ids == expected_check_ids
        if not completeness:
            gate_result = "BLOCKED"
    else:
        gate_result = "FAIL" if failures else "PASS"
        completeness = first_critical_failure is not None or executed_ids == expected_check_ids
        if not completeness:
            gate_result = "BLOCKED"

    report = {
        "contract": CONTRACT,
        "run_id": str(args.run_id),
        "job_id": str(args.job_id),
        "step_id": args.step_id,
        "gate_id": args.gate_id,
        "gate_mode": args.mode,
        "gate_result": gate_result,
        "source_commit": source_commit,
        "source_path": args.patterns,
        "trace_id": parent_trace_id,
        "parent_trace_id": None,
        "timestamp": utc_now(),
        "started_at": started_at,
        "expected_check_ids": expected_check_ids,
        "executed_check_ids": executed_ids,
        "expected_check_count": len(expected_check_ids),
        "executed_check_count": len(executed_ids),
        "pass_count": sum(1 for c in checks if c["check_status"] == "PASS"),
        "fail_count": len(failures),
        "blocked_count": 1 if gate_result == "BLOCKED" else 0,
        "remaining_after_fail_fast": expected_check_ids[len(executed_ids):],
        "downstream_impact": args.downstream_impact if gate_result != "PASS" else [],
        "owner": args.owner,
        "next_action": args.next_action if gate_result != "PASS" else "NONE",
        "checks": checks,
    }
    artifact_path = artifact_dir / args.artifact_name
    write_text(artifact_path, json.dumps(report, indent=2, sort_keys=True) + "\n")
    write_text(
        artifact_dir / "checks.jsonl",
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in checks),
    )
    print(
        json.dumps(
            {
                "contract": CONTRACT,
                "gate_id": args.gate_id,
                "gate_result": gate_result,
                "expected": len(expected_check_ids),
                "executed": len(executed_ids),
                "failures": len(failures),
                "artifact": str(artifact_path),
            },
            sort_keys=True,
        )
    )
    if gate_result == "PASS":
        return 0
    if gate_result == "FAIL":
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
