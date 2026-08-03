#!/usr/bin/env python3
"""Capture PR #93 E.13 evidence with deterministic receipts and rollback attestation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "PR93_E13_RECEIPT_V1"
REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
HEAD_RE = re.compile(r"^[0-9a-f]{40}$")

SOURCE_PATHS = (
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E10_RUNBOOK.psql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_T1.psql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_T2.psql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_STATE_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E10_CORRELATION_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E11_SYSTEM_IDENTIFIER_PROBE.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E8_EXECUTION_CONTEXT_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E6_DEPENDENCY_PREFLIGHT.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_C_EVIDENCE_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E5_FINAL_INTEGRITY_READBACK.sql",
    "sandbox/lf_contract_gate_test/PR93_WRITER_V7_ADVERSARIAL_TESTS.sql",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_GUARDS.md",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def run_checked(
    cmd: list[str], cwd: Path, timeout: int, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False, timeout=timeout, env=env
    )


def git_text(repo_root: Path, args: list[str], timeout: int) -> str:
    result = run_checked(["git", *args], repo_root, timeout)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode("utf-8", "replace").strip() or "git command failed")
    return result.stdout.decode("utf-8", "strict").strip()


def assert_repository(repo_root: Path, head_sha: str, timeout: int) -> None:
    if not HEAD_RE.fullmatch(head_sha):
        raise ValueError("head SHA must be exactly 40 lowercase hexadecimal characters")
    actual_head = git_text(repo_root, ["rev-parse", "HEAD"], timeout)
    if actual_head != head_sha:
        raise RuntimeError(f"HEAD mismatch: expected {head_sha}, observed {actual_head}")
    status = git_text(repo_root, ["status", "--porcelain=v1", "--untracked-files=all"], timeout)
    if status:
        raise RuntimeError("working tree must be clean before evidence capture")


def source_inventory(repo_root: Path, timeout: int) -> dict[str, dict[str, str | int]]:
    inventory: dict[str, dict[str, str | int]] = {}
    for relative in SOURCE_PATHS:
        path = repo_root / relative
        if not path.is_file():
            raise RuntimeError(f"required source artifact is missing: {relative}")
        data = path.read_bytes()
        blob = git_text(repo_root, ["rev-parse", f"HEAD:{relative}"], timeout)
        inventory[relative] = {
            "git_blob_sha1": blob,
            "sha256": sha256_bytes(data),
            "size_bytes": len(data),
        }
    return inventory


def psql_command(psql_bin: str, script: Path, head_sha: str | None = None) -> list[str]:
    command = [
        psql_bin,
        "-X",
        "--no-psqlrc",
        "--set=ON_ERROR_STOP=1",
        "--set=VERBOSITY=terse",
    ]
    if head_sha is not None:
        command.append(f"--set=E13_HEAD_SHA={head_sha}")
    command.extend(["--file", str(script)])
    return command


def run_psql(psql_bin: str, database_url: str, script: Path, cwd: Path, timeout: int, head_sha: str | None = None) -> tuple[int, bytes]:
    child_env = os.environ.copy()
    child_env.pop("DATABASE_URL", None)
    child_env["PGDATABASE"] = database_url
    child_env["PGAPPNAME"] = "pr93-e13-evidence"
    result = subprocess.run(
        psql_command(psql_bin, script, head_sha), cwd=cwd, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False, timeout=timeout, env=child_env
    )
    return result.returncode, result.stdout


def run_state_readback(psql_bin: str, database_url: str, script: Path, cwd: Path, timeout: int) -> tuple[int, bytes, Any | None]:
    command = [
        psql_bin,
        "-X",
        "--no-psqlrc",
        "--tuples-only",
        "--no-align",
        "--set=ON_ERROR_STOP=1",
        "--set=VERBOSITY=terse",
        "--file",
        str(script),
    ]
    child_env = os.environ.copy()
    child_env.pop("DATABASE_URL", None)
    child_env["PGDATABASE"] = database_url
    child_env["PGAPPNAME"] = "pr93-e13-state-readback"
    result = subprocess.run(
        command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        check=False, timeout=timeout, env=child_env
    )
    output = result.stdout
    if result.returncode != 0:
        return result.returncode, output, None
    text = output.decode("utf-8", "strict").strip()
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return 90, output + b"\nE13_STATE_JSON_INVALID\n", None
    return 0, output, value


def exact_line_count(data: bytes) -> int:
    return len(data.splitlines())


def count_exact_line(data: bytes, marker: str) -> int:
    return sum(1 for line in data.decode("utf-8", "replace").splitlines() if line == marker)


def write_exclusive(path: Path, data: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--psql-bin", default="psql")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    args = parser.parse_args()

    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        parser.error("DATABASE_URL environment variable is required")
    if args.timeout_seconds < 1:
        parser.error("--timeout-seconds must be positive")

    repo_root = args.repo_root.resolve()
    output_dir = args.output_dir.resolve()
    started_at = utc_now()
    assert_repository(repo_root, args.head_sha, args.timeout_seconds)
    if output_dir == repo_root or repo_root in output_dir.parents:
        raise RuntimeError("output directory must be outside the audited repository")
    if output_dir.exists():
        raise RuntimeError("output directory already exists; evidence capture refuses overwrite")
    output_dir.mkdir(parents=True, exist_ok=False)
    sources = source_inventory(repo_root, args.timeout_seconds)

    sandbox = repo_root / "sandbox/lf_contract_gate_test"
    t1_script = sandbox / "PR93_LOTE_E13_T1.psql"
    t2_script = sandbox / "PR93_LOTE_E13_T2.psql"
    state_script = sandbox / "PR93_LOTE_E13_STATE_READBACK.sql"

    t1_exit, t1_output = run_psql(
        args.psql_bin, database_url, t1_script, sandbox, args.timeout_seconds, args.head_sha
    )

    pre_exit = post_exit = 99
    pre_output = post_output = b""
    pre_state = post_state = None
    t2_exit = 99
    t2_output = b"E13_T2_NOT_EXECUTED\n"

    if t1_exit == 0:
        pre_exit, pre_output, pre_state = run_state_readback(
            args.psql_bin, database_url, state_script, sandbox, args.timeout_seconds
        )
        if pre_exit == 0:
            t2_exit, t2_output = run_psql(
                args.psql_bin, database_url, t2_script, sandbox, args.timeout_seconds, args.head_sha
            )
            post_exit, post_output, post_state = run_state_readback(
                args.psql_bin, database_url, state_script, sandbox, args.timeout_seconds
            )

    state_match = pre_state is not None and post_state is not None and pre_state == post_state
    explicit_rollback_count = count_exact_line(t2_output, "ROLLBACK")
    if t2_exit == 0 and explicit_rollback_count == 1 and state_match:
        rollback_status = "EXPLICIT"
    elif t2_exit != 0 and state_match:
        rollback_status = "IMPLICIT_ON_DISCONNECT"
    else:
        rollback_status = "NOT_VERIFIED"

    t1_ok = (
        t1_exit == 0
        and count_exact_line(t1_output, "E13_T1_BEGIN") == 1
        and count_exact_line(t1_output, "E13_T1_ROLLBACK_COMPLETE") == 1
    )
    t2_ok = (
        t2_exit == 0
        and count_exact_line(t2_output, "E13_T2_BEGIN") == 1
        and count_exact_line(t2_output, "E13_T2_CONTEXT_GUARD_PASS") == 1
        and count_exact_line(t2_output, "E13_T2_COMPLETE") == 1
        and rollback_status == "EXPLICIT"
    )
    overall_status = "PASS" if t1_ok and t2_ok else "FAIL"

    pre_state_bytes = canonical_json_bytes(pre_state) if pre_state is not None else b"null\n"
    post_state_bytes = canonical_json_bytes(post_state) if post_state is not None else b"null\n"

    finished_at = utc_now()
    marker_lines = [
        b"E13_CAPTURE_BEGIN\n",
        f"E13_HEAD_SHA={args.head_sha}\n".encode(),
        f"E13_STARTED_AT={started_at}\n".encode(),
        b"E13_T1_PROCESS_BEGIN\n",
        t1_output,
        f"E13_T1_PROCESS_EXIT={t1_exit}\n".encode(),
        b"E13_T2_PRE_STATE_BEGIN\n",
        pre_state_bytes,
        f"E13_T2_PRE_STATE_EXIT={pre_exit}\n".encode(),
        b"E13_T2_PROCESS_BEGIN\n",
        t2_output,
        f"E13_T2_PROCESS_EXIT={t2_exit}\n".encode(),
        b"E13_T2_POST_STATE_BEGIN\n",
        post_state_bytes,
        f"E13_T2_POST_STATE_EXIT={post_exit}\n".encode(),
        f"E13_T2_STATE_MATCH={str(state_match).lower()}\n".encode(),
        f"E13_T2_ROLLBACK_STATUS={rollback_status}\n".encode(),
        f"E13_OVERALL_STATUS={overall_status}\n".encode(),
        f"E13_FINISHED_AT={finished_at}\n".encode(),
        b"E13_CAPTURE_END\n",
    ]
    full_output = b"".join(marker_lines)

    files: dict[str, bytes] = {
        "PR93_E13_FULL_TRANSCRIPT.log": full_output,
        "PR93_E13_T1_TRANSCRIPT.log": t1_output,
        "PR93_E13_T2_TRANSCRIPT.log": t2_output,
        "PR93_E13_PRE_STATE.json": pre_state_bytes,
        "PR93_E13_POST_STATE.json": post_state_bytes,
        "PR93_E13_PRE_STATE_COMMAND.log": pre_output,
        "PR93_E13_POST_STATE_COMMAND.log": post_output,
    }
    for name, data in files.items():
        write_exclusive(output_dir / name, data)

    evidence_files = {
        name: {
            "sha256": sha256_bytes(data),
            "size_bytes": len(data),
            "line_count": exact_line_count(data),
        }
        for name, data in files.items()
    }

    receipt = {
        "schema_version": SCHEMA_VERSION,
        "repository": REPOSITORY,
        "head_sha": args.head_sha,
        "started_at_utc": started_at,
        "finished_at_utc": finished_at,
        "source_artifacts": sources,
        "evidence_files": evidence_files,
        "t1": {
            "exit_code": t1_exit,
            "rollback_complete_marker_count": count_exact_line(t1_output, "E13_T1_ROLLBACK_COMPLETE"),
            "status": "PASS" if t1_ok else "FAIL",
        },
        "t2": {
            "exit_code": t2_exit,
            "context_guard_pass_marker_count": count_exact_line(t2_output, "E13_T2_CONTEXT_GUARD_PASS"),
            "complete_marker_count": count_exact_line(t2_output, "E13_T2_COMPLETE"),
            "explicit_rollback_marker_count": explicit_rollback_count,
            "pre_state_exit_code": pre_exit,
            "post_state_exit_code": post_exit,
            "state_match": state_match,
            "rollback_status": rollback_status,
            "status": "PASS" if t2_ok else "FAIL",
        },
        "overall_status": overall_status,
        "capture_invariants": {
            "full_transcript_first_line": "E13_CAPTURE_BEGIN",
            "full_transcript_last_line": "E13_CAPTURE_END",
            "receipt_requires_external_trust_anchor": True,
            "output_directory_created_exclusively": True,
        },
    }
    receipt_bytes = canonical_json_bytes(receipt)
    receipt_path = output_dir / "PR93_E13_RECEIPT.json"
    write_exclusive(receipt_path, receipt_bytes)
    receipt_sha = sha256_bytes(receipt_bytes)
    write_exclusive(
        output_dir / "PR93_E13_RECEIPT.sha256",
        f"{receipt_sha}  PR93_E13_RECEIPT.json\n".encode(),
    )

    print(f"E13_RECEIPT_SHA256={receipt_sha}")
    print(f"E13_OVERALL_STATUS={overall_status}")
    print(f"E13_T2_ROLLBACK_STATUS={rollback_status}")

    if overall_status == "PASS":
        return 0
    if not t1_ok:
        return 10
    if rollback_status == "NOT_VERIFIED":
        return 12
    return 11


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"E13_CAPTURE_FATAL={exc}", file=sys.stderr)
        raise SystemExit(20)
