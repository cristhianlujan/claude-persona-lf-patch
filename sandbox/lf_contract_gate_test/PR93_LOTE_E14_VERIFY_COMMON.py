#!/usr/bin/env python3
"""Authoritative verifier for PR #93 LOTE-E.14 evidence bundles."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
import PR93_LOTE_E14_SEMANTICS as semantics

SCHEMA_VERSION = "PR93_E14_RECEIPT_V1"
HEAD_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
REQUIRED_EVIDENCE_FILES = (
    "PR93_E14_FULL_TRANSCRIPT.log",
    "PR93_E14_T1_TRANSCRIPT.log",
    "PR93_E14_T2_TRANSCRIPT.log",
    "PR93_E14_PRE_STATE.json",
    "PR93_E14_POST_STATE.json",
    "PR93_E14_PRE_STATE_COMMAND.log",
    "PR93_E14_POST_STATE_COMMAND.log",
)


RECEIPT_FILENAME = "PR93_E14_RECEIPT.json"
RECEIPT_SIDECAR_FILENAME = "PR93_E14_RECEIPT.sha256"
ALLOWED_BUNDLE_ENTRIES = REQUIRED_EVIDENCE_FILES + (
    RECEIPT_FILENAME,
    RECEIPT_SIDECAR_FILENAME,
)


def fail(message: str) -> None:
    raise ValueError(message)


def verify_bundle_inventory(bundle_argument: Path) -> Path:
    """CA-N128/N137: validate the unresolved root first, then canonicalise it.

    The argument is inspected with lstat() *before* any resolve(), so a symlink
    supplied as the bundle root is rejected instead of being silently followed.
    The comparison is made against the real directory listing, not against the
    receipt's declared evidence_files, so an extra regular file, an extra
    subdirectory, an extra symlink or an extra hidden entry is rejected. Each of
    the nine allowed entries must itself be a regular non-symlink file, and this
    is checked before any byte of the bundle is read.
    """
    absolute = bundle_argument.absolute()
    try:
        root_mode = absolute.lstat().st_mode
    except FileNotFoundError as exc:
        raise ValueError("bundle directory does not exist") from exc
    if stat.S_ISLNK(root_mode) or not stat.S_ISDIR(root_mode):
        fail("bundle directory must be a real directory, not a symlink")
    entries: dict[str, os.DirEntry[str]] = {}
    with os.scandir(absolute) as scan:
        for entry in scan:
            entries[entry.name] = entry
    allowed = set(ALLOWED_BUNDLE_ENTRIES)
    observed = set(entries)
    if observed != allowed:
        unexpected = sorted(observed - allowed)
        missing = sorted(allowed - observed)
        fail(
            "bundle inventory is not exact; "
            f"unexpected={unexpected}; missing={missing}"
        )
    for name in sorted(entries):
        entry = entries[name]
        if entry.is_symlink():
            fail(f"bundle entry must not be a symlink: {name}")
        if not entry.is_file(follow_symlinks=False):
            fail(f"bundle entry must be a regular file: {name}")
    return absolute.resolve(strict=True)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def exact_line_count(data: bytes) -> int:
    return len(data.splitlines())


def safe_child(root: Path, name: str) -> Path:
    if Path(name).name != name or name in {".", ".."}:
        fail(f"unsafe evidence filename: {name}")
    path = (root / name).resolve()
    if path.parent != root.resolve():
        fail(f"evidence path escapes bundle directory: {name}")
    return path


def exact_index(lines: list[str], marker: str) -> int:
    hits = [i for i, line in enumerate(lines) if line == marker]
    if len(hits) != 1:
        fail(f"marker {marker!r} must occur exactly once; observed {len(hits)}")
    return hits[0]


def prefix_index(lines: list[str], prefix: str) -> int:
    hits = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(hits) != 1:
        fail(f"prefix {prefix!r} must occur exactly once; observed {len(hits)}")
    return hits[0]


def parse_int_line(lines: list[str], prefix: str) -> int:
    value = lines[prefix_index(lines, prefix)][len(prefix):]
    try:
        return int(value)
    except ValueError as exc:
        raise ValueError(f"{prefix} must be an integer") from exc


def parse_bool_line(lines: list[str], prefix: str) -> bool:
    value = lines[prefix_index(lines, prefix)][len(prefix):]
    if value == "true":
        return True
    if value == "false":
        return False
    fail(f"{prefix} must be true or false")


def git_text(repo_root: Path, args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        fail(result.stderr.decode("utf-8", "replace").strip() or "git command failed")
    return result.stdout.decode("utf-8", "strict").strip()


def verify_sources(receipt: dict[str, Any], repo_root: Path) -> None:
    head_sha = receipt["head_sha"]
    if git_text(repo_root, ["rev-parse", "HEAD"]) != head_sha:
        fail("repository HEAD differs from receipt")
    if git_text(repo_root, ["status", "--porcelain=v1", "--untracked-files=all"]):
        fail("repository working tree is not clean")

    sources = receipt.get("source_artifacts")
    if not isinstance(sources, dict) or not sources:
        fail("source_artifacts must be a non-empty object")
    required_entrypoints = {
        "sandbox/lf_contract_gate_test/PR93_LOTE_E14_CAPTURE.py",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E14_VERIFY.py",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E14_NEGATIVE_TESTS.py",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E14_SEMANTICS.py",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E14_GUARDS.md",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E15_GUARDS.md",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E15_1_REGRESSION_TESTS.py",
        "sandbox/lf_contract_gate_test/.gitignore",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E13_STATE_READBACK.sql",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E13_T1.psql",
        "sandbox/lf_contract_gate_test/PR93_LOTE_E13_T2.psql",
    }
    if not required_entrypoints.issubset(sources):
        fail("receipt source inventory omits an authoritative E.14 artifact")

    for relative, expected in sources.items():
        if (
            not isinstance(relative, str)
            or relative.startswith("/")
            or ".." in Path(relative).parts
        ):
            fail(f"unsafe source path: {relative!r}")
        path = repo_root / relative
        if not path.is_file():
            fail(f"source artifact missing: {relative}")
        data = path.read_bytes()
        expected_sha = expected.get("sha256")
        expected_blob = expected.get("git_blob_sha1")
        if not isinstance(expected_sha, str) or SHA256_RE.fullmatch(expected_sha) is None:
            fail(f"invalid source SHA-256: {relative}")
        if not isinstance(expected_blob, str) or SHA1_RE.fullmatch(expected_blob) is None:
            fail(f"invalid source Git blob: {relative}")
        if sha256_bytes(data) != expected_sha:
            fail(f"source SHA-256 mismatch: {relative}")
        if git_text(repo_root, ["rev-parse", f"HEAD:{relative}"]) != expected_blob:
            fail(f"source Git blob mismatch: {relative}")
        if expected.get("size_bytes") != len(data):
            fail(f"source size mismatch: {relative}")


def verify_evidence(
    receipt: dict[str, Any], bundle_dir: Path
) -> dict[str, bytes]:
    evidence = receipt.get("evidence_files")
    if not isinstance(evidence, dict):
        fail("evidence_files must be an object")
    if set(evidence) != set(REQUIRED_EVIDENCE_FILES):
        fail("evidence file set is not exact")

    loaded: dict[str, bytes] = {}
    for name in REQUIRED_EVIDENCE_FILES:
        metadata = evidence.get(name)
        if not isinstance(metadata, dict):
            fail(f"missing evidence metadata: {name}")
        path = safe_child(bundle_dir, name)
        if not path.is_file():
            fail(f"missing evidence file: {name}")
        data = path.read_bytes()
        loaded[name] = data
        expected_sha = metadata.get("sha256")
        if not isinstance(expected_sha, str) or SHA256_RE.fullmatch(expected_sha) is None:
            fail(f"invalid evidence SHA-256: {name}")
        if sha256_bytes(data) != expected_sha:
            fail(f"evidence SHA-256 mismatch: {name}")
        if metadata.get("size_bytes") != len(data):
            fail(f"evidence size mismatch: {name}")
        if metadata.get("line_count") != exact_line_count(data):
            fail(f"evidence line-count mismatch: {name}")
    return loaded

