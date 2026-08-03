#!/usr/bin/env python3
"""Authoritative PR #93 LOTE-E.14 evidence capture."""
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

sys.dont_write_bytecode = True
import PR93_LOTE_E14_SEMANTICS as semantics

SCHEMA_VERSION = "PR93_E14_RECEIPT_V1"
REPOSITORY = "cristhianlujan/claude-persona-lf-patch"
HEAD_RE = re.compile(r"^[0-9a-f]{40}$")

SOURCE_PATHS = (
    "sandbox/lf_contract_gate_test/PR93_LOTE_E10_RUNBOOK.psql",
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
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_CAPTURE_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_VERIFY_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E13_NEGATIVE_TESTS_V2.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_CAPTURE.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_COMMON.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY_COMMON.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY_TRANSCRIPT.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_NEGATIVE_TESTS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_SEMANTICS.py",
    "sandbox/lf_contract_gate_test/PR93_LOTE_E14_GUARDS.md",
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def run_process(
    command: list[str],
    cwd: Path,
    timeout: int,
    env: dict[str, str],
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
        timeout=timeout,
        env=env,
    )


def git_text(repo_root: Path, args: list[str], timeout: int) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.decode("utf-8", "replace").strip() or "git command failed"
        )
    return result.stdout.decode("utf-8", "strict").strip()


def assert_repository(repo_root: Path, head_sha: str, timeout: int) -> None:
    if HEAD_RE.fullmatch(head_sha) is None:
        raise ValueError("head SHA must be exactly 40 lowercase hexadecimal characters")
    actual_head = git_text(repo_root, ["rev-parse", "HEAD"], timeout)
    if actual_head != head_sha:
        raise RuntimeError(f"HEAD mismatch: expected {head_sha}, observed {actual_head}")
    status = git_text(
        repo_root,
        ["status", "--porcelain=v1", "--untracked-files=all"],
        timeout,
    )
    if status:
        raise RuntimeError("working tree must be clean before evidence capture")


def source_inventory(
    repo_root: Path, timeout: int
) -> dict[str, dict[str, str | int]]:
    inventory: dict[str, dict[str, str | int]] = {}
    for relative in SOURCE_PATHS:
        path = repo_root / relative
        if not path.is_file():
            raise RuntimeError(f"required source artifact is missing: {relative}")
        data = path.read_bytes()
        inventory[relative] = {
            "git_blob_sha1": git_text(
                repo_root, ["rev-parse", f"HEAD:{relative}"], timeout
            ),
            "sha256": sha256_bytes(data),
            "size_bytes": len(data),
        }
    return inventory


def clean_child_env(app_name: str) -> dict[str, str]:
    env = os.environ.copy()
    env.pop("DATABASE_URL", None)
    env.pop("PGDATABASE", None)
    env["PGAPPNAME"] = app_name
    return env


def psql_base(psql_bin: str, database_url: str) -> list[str]:
    return [
        psql_bin,
        "--dbname",
        database_url,
        "-X",
        "--no-psqlrc",
        "--set=ON_ERROR_STOP=1",
        "--set=VERBOSITY=terse",
    ]


def connectivity_preflight(
    psql_bin: str,
    database_url: str,
    cwd: Path,
    timeout: int,
) -> tuple[int, bytes]:
    command = [
        *psql_base(psql_bin, database_url),
        "--tuples-only",
        "--no-align",
        "--command",
        "select 1",
    ]
    result = run_process(
        command,
        cwd,
        timeout,
        clean_child_env("pr93-e14-connectivity-preflight"),
    )
    output = result.stdout
    if result.returncode != 0:
        return result.returncode, output
    if output.decode("utf-8", "strict").strip() != "1":
        return 91, output + b"\nE14_CONNECTIVITY_PREFLIGHT_UNEXPECTED_OUTPUT\n"
    return 0, output


def run_psql(
    psql_bin: str,
    database_url: str,
    script: Path,
    cwd: Path,
    timeout: int,
    head_sha: str,
) -> tuple[int, bytes]:
    command = [
        *psql_base(psql_bin, database_url),
        f"--set=E13_HEAD_SHA={head_sha}",
        "--file",
        str(script),
    ]
    result = run_process(
        command,
        cwd,
        timeout,
        clean_child_env("pr93-e14-evidence"),
    )
    return result.returncode, result.stdout


def run_state_readback(
    psql_bin: str,
    database_url: str,
    script: Path,
    cwd: Path,
    timeout: int,
) -> tuple[int, bytes, Any | None]:
    command = [
        *psql_base(psql_bin, database_url),
        "--tuples-only",
        "--no-align",
        "--file",
        str(script),
    ]
    result = run_process(
        command,
        cwd,
        timeout,
        clean_child_env("pr93-e14-state-readback"),
    )
    output = result.stdout
    if result.returncode != 0:
        return result.returncode, output, None
    try:
        value = json.loads(output.decode("utf-8", "strict").strip())
    except json.JSONDecodeError:
        return 90, output + b"\nE14_STATE_JSON_INVALID\n", None
    if not isinstance(value, dict):
        return 92, output + b"\nE14_STATE_JSON_NOT_OBJECT\n", None
    return 0, output, value



def json_output_matches(output: bytes, state: Any | None) -> bool:
    if state is None:
        return False
    try:
        parsed = json.loads(output.decode("utf-8", "strict").strip())
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False
    return parsed == state

def exact_line_count(data: bytes) -> int:
    return len(data.splitlines())


def count_exact_line(data: bytes, marker: str) -> int:
    return sum(
        line == marker
        for line in data.decode("utf-8", "replace").splitlines()
    )


def count_prefixed_line(data: bytes, prefix: str) -> int:
    return sum(
        line.startswith(prefix)
        for line in data.decode("utf-8", "replace").splitlines()
    )


def write_exclusive(path: Path, data: bytes) -> None:
    with path.open("xb") as handle:
        handle.write(data)


