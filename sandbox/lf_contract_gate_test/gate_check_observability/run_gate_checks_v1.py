#!/usr/bin/env python3
"""Produce durable check-level LF_GATE_ERROR_V1 diagnostics for CI gates.

Transversal deterministic producer used by LF CI gates. It does not mutate LF
operational state and does not replace the canonical Supabase recorder. The
producer captures exact check identity, rc, error/assertion summary, stdout,
stderr, traceback/diagnostic artifact refs and hashes, plus source/tested SHA.
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
PRODUCER = "LF_GATE_CHECK_OBSERVABILITY_V1"
MODES = {"COLLECT_ALL", "FAIL_FAST_CRITICAL"}
DEFAULT_SCHEMA = Path(__file__).with_name("lf_gate_error_v1.schema.json")
_SECRET_PATTERNS = [
    re.compile(r"(?i)(authorization\s*:\s*bearer\s+)[^\s]+"),
    re.compile(r"(?i)((?:password|secret|token|api[_-]?key|service[_-]?role)\s*[=:]\s*)[^\s]+"),
]
_ERROR_LINE = re.compile(
    r"^(?P<class>[A-Za-z_][A-Za-z0-9_.]*(?:Error|Exception)|AssertionError|SystemExit)(?::\s*(?P<detail>.*))?$"
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def manifest_digest(report: dict) -> str:
    payload = dict(report)
    payload.pop("manifest_sha256", None)
    return sha256_text(canonical_json(payload))


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


def _valid_sha(value: str) -> bool:
    return re.fullmatch(r"[0-9a-f]{40}", value) is not None


def event_pull_request_head_sha() -> str:
    event_path = (os.environ.get("GITHUB_EVENT_PATH") or "").strip()
    if not event_path:
        return ""
    try:
        payload = json.loads(Path(event_path).read_text(encoding="utf-8"))
        candidate = (((payload.get("pull_request") or {}).get("head") or {}).get("sha") or "").strip().lower()
    except Exception:
        return ""
    return candidate if _valid_sha(candidate) else ""


def tested_commit() -> str:
    try:
        value = subprocess.run(
            ["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True
        ).stdout.strip().lower()
    except (OSError, subprocess.CalledProcessError):
        value = ""
    return value if _valid_sha(value) else "UNKNOWN_TESTED_COMMIT"


def source_commit(explicit: str | None, tested: str) -> str:
    explicit_value = (explicit or "").strip().lower()
    if explicit_value:
        return explicit_value if _valid_sha(explicit_value) else "UNKNOWN_SOURCE_COMMIT"
    pr_head = event_pull_request_head_sha()
    if pr_head:
        return pr_head
    for key in ("GITHUB_HEAD_SHA", "GITHUB_SHA"):
        value = (os.environ.get(key) or "").strip().lower()
        if _valid_sha(value):
            return value
    return tested if _valid_sha(tested) else "UNKNOWN_SOURCE_COMMIT"


def write_text(path: Path, value: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")
    return sha256_text(value)


def traceback_text(stderr: str, stdout: str) -> tuple[str, bool]:
    for text in (stderr, stdout):
        marker = "Traceback (most recent call last):"
        index = text.find(marker)
        if index >= 0:
            return text[index:].strip() + "\n", True
    fallback = stderr.strip() or stdout.strip()
    return ((fallback + "\n") if fallback else ""), False


def classify_failure(stderr: str, stdout: str, returncode: int) -> tuple[str, str, str | None]:
    combined = stderr if stderr.strip() else stdout
    lines = [line.strip() for line in combined.splitlines() if line.strip()]
    for line in reversed(lines):
        match = _ERROR_LINE.match(line)
        if match:
            error_class = match.group("class")
            summary = line
            assertion = line if error_class == "AssertionError" else None
            return error_class, summary, assertion
    if lines:
        return "PROCESS_EXIT_NONZERO", lines[-1], None
    return "PROCESS_EXIT_NONZERO", f"PROCESS_EXIT_{returncode}", None


def failure_id(gate_id: str, test_path: str, rc: int, stdout_sha: str, stderr_sha: str) -> str:
    return sha256_text(
        canonical_json(
            {
                "gate_id": gate_id,
                "test_path": test_path,
                "rc": rc,
                "stdout_sha256": stdout_sha,
                "stderr_sha256": stderr_sha,
            }
        )
    )


def schema_identity(schema_path: Path) -> tuple[str, str]:
    if not schema_path.is_file():
        return str(schema_path.as_posix()), "0" * 64
    return str(schema_path.as_posix()), sha256_bytes(schema_path.read_bytes())


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--gate-id", required=True)
    p.add_argument("--step-id", required=True)
    p.add_argument("--mode", choices=sorted(MODES), default="COLLECT_ALL")
    p.add_argument("--glob", action="append", dest="patterns", required=True)
    p.add_argument("--artifact-dir", required=True)
    p.add_argument("--artifact-name", default="lf_gate_error_v1.json")
    p.add_argument("--schema-ref", default=str(DEFAULT_SCHEMA.as_posix()))
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
        help="regex fragment; only used by FAIL_FAST_CRITICAL",
    )
    return p.parse_args()


def is_critical(path: str, patterns: list[str]) -> bool:
    return any(re.search(pattern, path) for pattern in patterns)


def _finalize_report(report: dict, artifact_path: Path) -> None:
    report["manifest_sha256"] = manifest_digest(report)
    write_text(artifact_path, json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def main() -> int:
    args = parse_args()
    artifact_dir = Path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    tested = tested_commit()
    source = source_commit(args.source_commit, tested)
    schema_ref, schema_sha256 = schema_identity(Path(args.schema_ref))
    test_paths = normalize_paths(args.patterns)
    started_at = utc_now()
    parent_trace_id = f"LF-CI-GATE-{stable_uuid('parent-trace', f'{args.run_id}:{args.job_id}:{args.gate_id}')}"
    artifact_path = artifact_dir / args.artifact_name

    if schema_sha256 == "0" * 64:
        blocked = {
            "contract": CONTRACT,
            "producer": PRODUCER,
            "schema_ref": schema_ref,
            "schema_sha256": schema_sha256,
            "run_id": str(args.run_id),
            "job_id": str(args.job_id),
            "step_id": args.step_id,
            "gate_id": args.gate_id,
            "gate_mode": args.mode,
            "gate_result": "BLOCKED",
            "diagnostic_complete": False,
            "error_id": stable_uuid("error", f"{args.run_id}:{args.gate_id}:SCHEMA_MISSING"),
            "error_class": "GATE_DIAGNOSTIC_SCHEMA_MISSING",
            "condition": "LF_GATE_ERROR_V1 schema exists",
            "expected": {"schema_exists": True},
            "actual": {"schema_exists": False},
            "source_commit": source,
            "tested_commit": tested,
            "source_path": args.patterns,
            "trace_id": f"LF-CI-{stable_uuid('trace', f'{args.run_id}:{args.gate_id}:SCHEMA_MISSING')}",
            "parent_trace_id": parent_trace_id,
            "rc": 2,
            "timestamp": utc_now(),
            "downstream_impact": args.downstream_impact,
            "owner": args.owner,
            "next_action": args.next_action,
            "checks": [],
            "manifest_sha256": "",
        }
        _finalize_report(blocked, artifact_path)
        print(json.dumps({"gate_id": args.gate_id, "result": "BLOCKED", "reason": "SCHEMA_MISSING"}, sort_keys=True))
        return 2

    if not test_paths:
        blocked = {
            "contract": CONTRACT,
            "producer": PRODUCER,
            "schema_ref": schema_ref,
            "schema_sha256": schema_sha256,
            "run_id": str(args.run_id),
            "job_id": str(args.job_id),
            "step_id": args.step_id,
            "gate_id": args.gate_id,
            "gate_mode": args.mode,
            "gate_result": "BLOCKED",
            "diagnostic_complete": False,
            "error_id": stable_uuid("error", f"{args.run_id}:{args.gate_id}:NO_CHECKS"),
            "error_class": "GATE_CHECK_SET_MISSING",
            "condition": "declared gate resolves at least one executable check",
            "expected": {"check_count_min": 1},
            "actual": {"check_count": 0},
            "source_commit": source,
            "tested_commit": tested,
            "source_path": args.patterns,
            "trace_id": f"LF-CI-{stable_uuid('trace', f'{args.run_id}:{args.gate_id}:NO_CHECKS')}",
            "parent_trace_id": parent_trace_id,
            "rc": 2,
            "timestamp": utc_now(),
            "downstream_impact": args.downstream_impact,
            "owner": args.owner,
            "next_action": args.next_action,
            "checks": [],
            "manifest_sha256": "",
        }
        _finalize_report(blocked, artifact_path)
        print(json.dumps({"gate_id": args.gate_id, "result": "BLOCKED", "reason": "NO_CHECKS"}, sort_keys=True))
        return 2

    checks: list[dict] = []
    first_critical_failure: int | None = None
    for index, test_path in enumerate(test_paths, start=1):
        check_id = f"{args.check_prefix}-{index:03d}"
        critical = args.mode == "FAIL_FAST_CRITICAL" and is_critical(test_path, args.critical_pattern)
        started = utc_now()
        command = [sys.executable, test_path]
        proc = subprocess.run(command, capture_output=True, text=True)
        stdout = redact(proc.stdout or "")
        stderr = redact(proc.stderr or "")
        log_base = artifact_dir / "checks" / check_id
        stdout_path = log_base.with_suffix(".stdout.log")
        stderr_path = log_base.with_suffix(".stderr.log")
        stdout_sha = write_text(stdout_path, stdout)
        stderr_sha = write_text(stderr_path, stderr)
        status = "PASS" if proc.returncode == 0 else "FAIL"
        error_id = None
        failure_digest = None
        error_class = None
        error_summary = None
        assertion_text = None
        trace_ref = None
        trace_sha = None
        trace_present = False
        diagnostic_complete = True

        if status == "FAIL":
            error_id = stable_uuid("error", f"{args.run_id}:{args.job_id}:{args.gate_id}:{check_id}:{source}")
            error_class, error_summary, assertion_text = classify_failure(stderr, stdout, proc.returncode)
            trace_text, trace_present = traceback_text(stderr, stdout)
            if not trace_text:
                trace_text = f"PROCESS_EXIT_{proc.returncode}\n"
            trace_path = log_base.with_suffix(".traceback.log")
            trace_sha = write_text(trace_path, trace_text)
            trace_ref = str(trace_path.as_posix())
            failure_digest = failure_id(args.gate_id, test_path, proc.returncode, stdout_sha, stderr_sha)
            diagnostic_complete = bool(
                test_path
                and command
                and error_summary
                and stdout_sha
                and stderr_sha
                and trace_ref
                and trace_sha
            )

        trace_id = f"LF-CI-{stable_uuid('trace', f'{args.run_id}:{args.job_id}:{args.gate_id}:{check_id}:{source}')}"
        checks.append(
            {
                "check_id": check_id,
                "check_status": status,
                "critical": critical,
                "failure_id": failure_digest,
                "error_id": error_id,
                "error_class": error_class,
                "error_summary": error_summary,
                "assertion_text": assertion_text,
                "condition": "independent Python validation exits with rc=0",
                "expected": {"rc": 0},
                "actual": {"rc": proc.returncode},
                "command": command,
                "exit_code": proc.returncode,
                "input_ref": test_path,
                "evidence_ref": f"artifact://{args.artifact_name}#checks/{check_id}",
                "producer": test_path,
                "source_commit": source,
                "tested_commit": tested,
                "source_path": test_path,
                "trace_id": trace_id,
                "parent_trace_id": parent_trace_id,
                "rc": proc.returncode,
                "timestamp": utc_now(),
                "started_at": started,
                "stdout_ref": str(stdout_path.as_posix()),
                "stderr_ref": str(stderr_path.as_posix()),
                "stdout_sha256": stdout_sha,
                "stderr_sha256": stderr_sha,
                "traceback_ref": trace_ref,
                "traceback_sha256": trace_sha,
                "traceback_present": trace_present,
                "diagnostic_complete": diagnostic_complete,
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

    diagnostic_complete = bool(
        completeness
        and all(c.get("diagnostic_complete") is True for c in checks if c["check_status"] == "FAIL")
    )
    report = {
        "contract": CONTRACT,
        "producer": PRODUCER,
        "schema_ref": schema_ref,
        "schema_sha256": schema_sha256,
        "run_id": str(args.run_id),
        "job_id": str(args.job_id),
        "step_id": args.step_id,
        "gate_id": args.gate_id,
        "gate_mode": args.mode,
        "gate_result": gate_result,
        "diagnostic_complete": diagnostic_complete,
        "source_commit": source,
        "tested_commit": tested,
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
        "manifest_sha256": "",
    }
    _finalize_report(report, artifact_path)
    write_text(
        artifact_dir / "checks.jsonl",
        "".join(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n" for row in checks),
    )
    print(
        json.dumps(
            {
                "contract": CONTRACT,
                "gate_id": args.gate_id,
                "gate_result": gate_result,
                "diagnostic_complete": diagnostic_complete,
                "expected": len(expected_check_ids),
                "executed": len(executed_ids),
                "failures": len(failures),
                "artifact": str(artifact_path),
                "manifest_sha256": report["manifest_sha256"],
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
