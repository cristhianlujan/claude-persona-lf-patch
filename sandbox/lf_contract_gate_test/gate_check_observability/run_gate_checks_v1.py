#!/usr/bin/env python3
"""Produce durable check-level LF_GATE_ERROR_V1 diagnostics for CI gates.

Transversal deterministic producer used by LF CI gates. It does not mutate LF
operational state and does not replace the canonical Supabase recorder. Checks
may be discovered from Python file globs or declared as explicit argv arrays;
no shell interpretation is required for parameterized deterministic commands.
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


def failure_id(gate_id: str, source_path: str, rc: int, stdout_sha: str, stderr_sha: str) -> str:
    return sha256_text(
        canonical_json(
            {
                "gate_id": gate_id,
                "source_path": source_path,
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


def parse_command_spec(raw: str) -> dict:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid_json:{exc.msg}") from exc
    if not isinstance(value, dict):
        raise ValueError("command_spec_must_be_object")
    unknown = set(value) - {"argv", "source_path", "critical"}
    if unknown:
        raise ValueError(f"unknown_keys:{','.join(sorted(unknown))}")
    argv = value.get("argv")
    source_path = value.get("source_path")
    critical = value.get("critical", False)
    if not isinstance(argv, list) or len(argv) < 2 or any(not isinstance(item, str) or not item for item in argv):
        raise ValueError("argv_must_be_nonempty_string_array_min_2")
    if not isinstance(source_path, str) or not source_path.strip():
        raise ValueError("source_path_required")
    if not isinstance(critical, bool):
        raise ValueError("critical_must_be_boolean")
    return {"argv": argv, "source_path": source_path, "critical": critical}


def declared_checks(patterns: list[str], command_json: list[str]) -> list[dict]:
    checks = [
        {"argv": [sys.executable, path], "source_path": path, "critical": False}
        for path in normalize_paths(patterns)
    ]
    checks.extend(parse_command_spec(raw) for raw in command_json)
    return checks


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--gate-id", required=True)
    p.add_argument("--step-id", required=True)
    p.add_argument("--mode", choices=sorted(MODES), default="COLLECT_ALL")
    p.add_argument("--glob", action="append", dest="patterns", default=[])
    p.add_argument(
        "--command-json",
        action="append",
        default=[],
        help='JSON object: {"argv":["python3","script.py","--arg","value"],"source_path":"script.py","critical":false}',
    )
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


def blocked_report(
    *,
    args: argparse.Namespace,
    schema_ref: str,
    schema_sha256: str,
    source: str,
    tested: str,
    parent_trace_id: str,
    artifact_path: Path,
    error_class: str,
    reason: str,
    condition: str,
    expected: dict,
    actual: dict,
    source_paths: list[str],
) -> int:
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
        "error_id": stable_uuid("error", f"{args.run_id}:{args.gate_id}:{reason}"),
        "error_class": error_class,
        "condition": condition,
        "expected": expected,
        "actual": actual,
        "source_commit": source,
        "tested_commit": tested,
        "source_path": source_paths,
        "trace_id": f"LF-CI-{stable_uuid('trace', f'{args.run_id}:{args.gate_id}:{reason}')}",
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
    print(json.dumps({"gate_id": args.gate_id, "result": "BLOCKED", "reason": reason}, sort_keys=True))
    return 2


def main() -> int:
    args = parse_args()
    artifact_dir = Path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    tested = tested_commit()
    source = source_commit(args.source_commit, tested)
    schema_ref, schema_sha256 = schema_identity(Path(args.schema_ref))
    started_at = utc_now()
    parent_trace_id = f"LF-CI-GATE-{stable_uuid('parent-trace', f'{args.run_id}:{args.job_id}:{args.gate_id}')}"
    artifact_path = artifact_dir / args.artifact_name
    declared_source_paths = list(args.patterns)

    if schema_sha256 == "0" * 64:
        return blocked_report(
            args=args,
            schema_ref=schema_ref,
            schema_sha256=schema_sha256,
            source=source,
            tested=tested,
            parent_trace_id=parent_trace_id,
            artifact_path=artifact_path,
            error_class="GATE_DIAGNOSTIC_SCHEMA_MISSING",
            reason="SCHEMA_MISSING",
            condition="LF_GATE_ERROR_V1 schema exists",
            expected={"schema_exists": True},
            actual={"schema_exists": False},
            source_paths=declared_source_paths,
        )

    try:
        check_specs = declared_checks(args.patterns, args.command_json)
        declared_source_paths.extend(spec["source_path"] for spec in check_specs if spec["source_path"] not in declared_source_paths)
    except ValueError as exc:
        return blocked_report(
            args=args,
            schema_ref=schema_ref,
            schema_sha256=schema_sha256,
            source=source,
            tested=tested,
            parent_trace_id=parent_trace_id,
            artifact_path=artifact_path,
            error_class="GATE_COMMAND_SPEC_INVALID",
            reason="COMMAND_SPEC_INVALID",
            condition="all declared command specs are strict argv JSON objects",
            expected={"command_spec_valid": True},
            actual={"command_spec_valid": False, "detail": str(exc)},
            source_paths=declared_source_paths,
        )

    if not check_specs:
        return blocked_report(
            args=args,
            schema_ref=schema_ref,
            schema_sha256=schema_sha256,
            source=source,
            tested=tested,
            parent_trace_id=parent_trace_id,
            artifact_path=artifact_path,
            error_class="GATE_CHECK_SET_MISSING",
            reason="NO_CHECKS",
            condition="declared gate resolves at least one executable check",
            expected={"check_count_min": 1},
            actual={"check_count": 0},
            source_paths=declared_source_paths,
        )

    checks: list[dict] = []
    first_critical_failure: int | None = None
    for index, spec in enumerate(check_specs, start=1):
        check_id = f"{args.check_prefix}-{index:03d}"
        source_path = spec["source_path"]
        command = list(spec["argv"])
        critical = args.mode == "FAIL_FAST_CRITICAL" and (
            bool(spec.get("critical")) or is_critical(source_path, args.critical_pattern)
        )
        started = utc_now()
        try:
            proc = subprocess.run(command, capture_output=True, text=True)
            returncode = proc.returncode
            stdout = redact(proc.stdout or "")
            stderr = redact(proc.stderr or "")
        except OSError as exc:
            returncode = 127
            stdout = ""
            stderr = redact(f"{exc.__class__.__name__}: {exc}\n")

        log_base = artifact_dir / "checks" / check_id
        stdout_path = log_base.with_suffix(".stdout.log")
        stderr_path = log_base.with_suffix(".stderr.log")
        stdout_sha = write_text(stdout_path, stdout)
        stderr_sha = write_text(stderr_path, stderr)
        status = "PASS" if returncode == 0 else "FAIL"
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
            error_class, error_summary, assertion_text = classify_failure(stderr, stdout, returncode)
            trace_text, trace_present = traceback_text(stderr, stdout)
            if not trace_text:
                trace_text = f"PROCESS_EXIT_{returncode}\n"
            trace_path = log_base.with_suffix(".traceback.log")
            trace_sha = write_text(trace_path, trace_text)
            trace_ref = str(trace_path.as_posix())
            failure_digest = failure_id(args.gate_id, source_path, returncode, stdout_sha, stderr_sha)
            diagnostic_complete = bool(
                source_path and command and error_summary and stdout_sha and stderr_sha and trace_ref and trace_sha
            )

        safe_command = [redact(item) for item in command]
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
                "condition": "deterministic command exits with rc=0",
                "expected": {"rc": 0},
                "actual": {"rc": returncode},
                "command": safe_command,
                "exit_code": returncode,
                "input_ref": source_path,
                "evidence_ref": f"artifact://{args.artifact_name}#checks/{check_id}",
                "producer": source_path,
                "source_commit": source,
                "tested_commit": tested,
                "source_path": source_path,
                "trace_id": trace_id,
                "parent_trace_id": parent_trace_id,
                "rc": returncode,
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
        print(f"LF_GATE_CHECK check_id={check_id} status={status} rc={returncode} source={source_path}")
        if status != "PASS" and critical:
            first_critical_failure = index
            break

    expected_check_ids = [f"{args.check_prefix}-{i:03d}" for i in range(1, len(check_specs) + 1)]
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
        "source_path": declared_source_paths,
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
