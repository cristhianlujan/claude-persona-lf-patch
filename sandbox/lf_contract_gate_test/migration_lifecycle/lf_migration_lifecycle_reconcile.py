#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

FILENAME_RE = re.compile(r"^(20\d{12})_([a-z0-9][a-z0-9_]*)\.sql$")
VERSION_RE = re.compile(r"^20\d{12}$")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_]*$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class ReconcileError(RuntimeError):
    pass


@dataclass(frozen=True)
class LedgerEntry:
    version: str
    name: str
    statement_count: int
    source_base64: str | None
    source_git_blob_sha1: str | None
    source_sha256: str | None

    @property
    def filename(self) -> str:
        return f"{self.version}_{self.name}.sql"


@dataclass(frozen=True)
class LocalEntry:
    version: str
    name: str
    path: Path
    raw: bytes
    git_blob_sha1: str
    sha256: str


def git_blob_sha1(raw: bytes) -> str:
    header = f"blob {len(raw)}\0".encode("ascii")
    return hashlib.sha1(header + raw).hexdigest()


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def fail(code: str, detail: str = "") -> None:
    raise ReconcileError(f"{code}{':' + detail if detail else ''}")


def _load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail("LEDGER_JSON_INVALID", type(exc).__name__)


def load_ledger(path: Path) -> dict[str, LedgerEntry]:
    payload = _load_json(path)
    if not isinstance(payload, list):
        fail("LEDGER_JSON_NOT_ARRAY")
    out: dict[str, LedgerEntry] = {}
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            fail("LEDGER_ENTRY_NOT_OBJECT", str(index))
        version = item.get("version")
        name = item.get("name")
        count = item.get("statement_count")
        source_b64 = item.get("source_base64")
        source_git_sha = item.get("source_git_blob_sha1")
        source_sha = item.get("source_sha256")
        if not isinstance(version, str) or not VERSION_RE.fullmatch(version):
            fail("LEDGER_VERSION_INVALID", str(version))
        if not isinstance(name, str) or not NAME_RE.fullmatch(name):
            fail("LEDGER_NAME_INVALID", str(name))
        if not isinstance(count, int) or count < 1:
            fail("LEDGER_STATEMENT_COUNT_INVALID", version)
        if source_b64 is not None and not isinstance(source_b64, str):
            fail("LEDGER_SOURCE_BASE64_INVALID", version)
        if source_git_sha is not None and (
            not isinstance(source_git_sha, str) or not SHA1_RE.fullmatch(source_git_sha)
        ):
            fail("LEDGER_SOURCE_GIT_SHA1_INVALID", version)
        if source_sha is not None and (
            not isinstance(source_sha, str) or not SHA256_RE.fullmatch(source_sha)
        ):
            fail("LEDGER_SOURCE_SHA256_INVALID", version)
        if version in out:
            fail("LEDGER_VERSION_DUPLICATE", version)
        out[version] = LedgerEntry(
            version=version,
            name=name,
            statement_count=count,
            source_base64=source_b64,
            source_git_blob_sha1=source_git_sha,
            source_sha256=source_sha,
        )
    return out


def load_local(migrations_dir: Path) -> dict[str, LocalEntry]:
    if not migrations_dir.is_dir():
        fail("MIGRATIONS_DIR_MISSING", str(migrations_dir))
    out: dict[str, LocalEntry] = {}
    for path in sorted(migrations_dir.glob("*.sql")):
        match = FILENAME_RE.fullmatch(path.name)
        if not match:
            continue
        version, name = match.groups()
        raw = path.read_bytes()
        if version in out:
            fail("LOCAL_VERSION_DUPLICATE", version)
        out[version] = LocalEntry(
            version=version,
            name=name,
            path=path,
            raw=raw,
            git_blob_sha1=git_blob_sha1(raw),
            sha256=sha256(raw),
        )
    return out


def decode_ledger_source(entry: LedgerEntry) -> bytes:
    if entry.source_base64 is None:
        fail("LEDGER_SOURCE_NOT_HYDRATED", entry.version)
    try:
        raw = base64.b64decode(entry.source_base64, validate=True)
    except Exception as exc:  # binascii.Error derives ValueError in some runtimes
        fail("LEDGER_SOURCE_BASE64_DECODE_FAILED", f"{entry.version}:{type(exc).__name__}")
    actual_git = git_blob_sha1(raw)
    actual_sha = sha256(raw)
    if entry.source_git_blob_sha1 is None or actual_git != entry.source_git_blob_sha1:
        fail("LEDGER_SOURCE_GIT_SHA1_MISMATCH", entry.version)
    if entry.source_sha256 is not None and actual_sha != entry.source_sha256:
        fail("LEDGER_SOURCE_SHA256_MISMATCH", entry.version)
    return raw


def reconcile(
    *,
    ledger: dict[str, LedgerEntry],
    local: dict[str, LocalEntry],
    migrations_dir: Path,
    owner_prefix: str,
    min_version: str | None,
    max_version: str | None,
    materialize_remote_only: bool,
) -> dict[str, object]:
    if not NAME_RE.fullmatch(owner_prefix.rstrip("_")):
        fail("OWNER_PREFIX_INVALID", owner_prefix)

    def in_window(version: str) -> bool:
        return (min_version is None or version >= min_version) and (
            max_version is None or version <= max_version
        )

    scoped_ledger = {
        v: e
        for v, e in ledger.items()
        if in_window(v) and e.name.startswith(owner_prefix)
    }
    scoped_local = {
        v: e
        for v, e in local.items()
        if in_window(v) and e.name.startswith(owner_prefix)
    }

    remote_only = sorted(set(scoped_ledger) - set(scoped_local))
    local_only = sorted(set(scoped_local) - set(scoped_ledger))
    common = sorted(set(scoped_ledger) & set(scoped_local))
    name_mismatch: list[str] = []
    content_mismatch: list[str] = []
    exact: list[str] = []

    for version in common:
        remote = scoped_ledger[version]
        current = scoped_local[version]
        if remote.name != current.name:
            name_mismatch.append(version)
            continue
        if remote.source_git_blob_sha1 is not None:
            if current.git_blob_sha1 == remote.source_git_blob_sha1:
                exact.append(version)
            else:
                content_mismatch.append(version)
        elif remote.source_sha256 is not None:
            if current.sha256 == remote.source_sha256:
                exact.append(version)
            else:
                content_mismatch.append(version)
        else:
            fail("LEDGER_PROOF_MISSING", version)

    materialized: list[dict[str, str]] = []
    blocked_recovery: list[dict[str, object]] = []
    if materialize_remote_only:
        for version in remote_only:
            entry = scoped_ledger[version]
            # Recovery from ledger is exceptional. It is only safe when the ledger
            # preserved one source payload and carries an exact git-blob proof.
            if entry.statement_count != 1:
                blocked_recovery.append(
                    {"version": version, "reason": "STATEMENT_COUNT_NOT_ONE"}
                )
                continue
            if entry.source_git_blob_sha1 is None:
                blocked_recovery.append(
                    {"version": version, "reason": "GIT_BLOB_PROOF_MISSING"}
                )
                continue
            raw = decode_ledger_source(entry)
            target = migrations_dir / entry.filename
            if target.exists():
                fail("RECOVERY_TARGET_ALREADY_EXISTS", str(target))
            target.write_bytes(raw)
            readback = target.read_bytes()
            if readback != raw or git_blob_sha1(readback) != entry.source_git_blob_sha1:
                fail("RECOVERY_READBACK_MISMATCH", version)
            materialized.append(
                {
                    "version": version,
                    "path": target.as_posix(),
                    "git_blob_sha1": entry.source_git_blob_sha1,
                    "sha256": sha256(readback),
                }
            )

    state = "PASS"
    if local_only or name_mismatch or content_mismatch or blocked_recovery:
        state = "BLOCKED"
    elif remote_only and not materialize_remote_only:
        state = "DRIFT_DETECTED"
    elif remote_only and materialize_remote_only and len(materialized) != len(remote_only):
        state = "BLOCKED"
    elif remote_only and materialize_remote_only:
        state = "RECOVERED_TO_WORKTREE"

    return {
        "schema_version": "lf-migration-lifecycle-reconcile/v1",
        "state": state,
        "owner_prefix": owner_prefix,
        "window": {"min_version": min_version, "max_version": max_version},
        "counts": {
            "ledger": len(scoped_ledger),
            "local": len(scoped_local),
            "exact": len(exact),
            "remote_only": len(remote_only),
            "local_only": len(local_only),
            "name_mismatch": len(name_mismatch),
            "content_mismatch": len(content_mismatch),
            "materialized": len(materialized),
            "blocked_recovery": len(blocked_recovery),
        },
        "exact": exact,
        "remote_only": remote_only,
        "local_only": local_only,
        "name_mismatch": name_mismatch,
        "content_mismatch": content_mismatch,
        "materialized": materialized,
        "blocked_recovery": blocked_recovery,
        "invariants": {
            "ddl_replay": False,
            "main_write": False,
            "auto_merge": False,
            "unknown_transport": "BLOCK",
            "ledger_recovery": "EXCEPTION_ONLY_SINGLE_SOURCE_PAYLOAD_WITH_GIT_BLOB_PROOF",
        },
    }


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ledger-json", required=True, type=Path)
    parser.add_argument("--migrations-dir", required=True, type=Path)
    parser.add_argument("--owner-prefix", required=True)
    parser.add_argument("--min-version")
    parser.add_argument("--max-version")
    parser.add_argument("--materialize-remote-only", action="store_true")
    parser.add_argument("--receipt", type=Path)
    return parser.parse_args(list(argv))


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        ledger = load_ledger(args.ledger_json)
        local = load_local(args.migrations_dir)
        receipt = reconcile(
            ledger=ledger,
            local=local,
            migrations_dir=args.migrations_dir,
            owner_prefix=args.owner_prefix,
            min_version=args.min_version,
            max_version=args.max_version,
            materialize_remote_only=args.materialize_remote_only,
        )
    except ReconcileError as exc:
        print(json.dumps({"state": "ERROR", "error": str(exc)}, sort_keys=True))
        return 2

    rendered = json.dumps(receipt, sort_keys=True, indent=2)
    print(rendered)
    if args.receipt is not None:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(rendered + "\n", encoding="utf-8")
    return 0 if receipt["state"] in {"PASS", "DRIFT_DETECTED", "RECOVERED_TO_WORKTREE"} else 3


if __name__ == "__main__":
    raise SystemExit(main())
