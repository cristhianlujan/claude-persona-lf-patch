#!/usr/bin/env python3
"""Fail-closed dual-surface state gate for governed LF migrations.

Authority stays with ACTUALIZACION_DB_LF + DB_WRITE_TRANSPORT. This helper
never performs Git or database writes. It verifies that one governed execution
may advance from durable Git source -> exact Supabase apply -> dual readback.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass
from pathlib import PurePosixPath
from typing import Any

SCHEMA_VERSION = "lf-migration-persist-verify/v1"
OPERATION_CODE = "ACTUALIZACION_DB_LF"
FILENAME_RE = re.compile(r"^(?P<version>\d{14})_(?P<name>[A-Za-z0-9][A-Za-z0-9_]*)\.sql$")
SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
EXEC_RE = re.compile(r"^EXEC-[A-Z0-9_-]+$")


@dataclass(frozen=True)
class Verdict:
    schema_version: str
    status: str
    code: str
    execution_id: str
    effect_scope: str
    target_path: str
    migration_version: str
    migration_name: str
    ready_to_apply: bool
    consistent: bool


def _identity(path: str) -> tuple[str, str, str]:
    normalized = (path or "").replace("\\", "/").strip("/")
    parts = PurePosixPath(normalized).parts
    if not normalized.startswith("supabase/migrations/") or ".." in parts:
        raise ValueError("MIGRATION_SYNC_CANONICAL_PATH_REQUIRED")
    match = FILENAME_RE.fullmatch(normalized.rsplit("/", 1)[-1])
    if not match:
        raise ValueError("MIGRATION_SYNC_FILENAME_INVALID")
    return normalized, match.group("version"), match.group("name")


def _obj(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    if not isinstance(value, dict):
        raise ValueError(f"MIGRATION_SYNC_{key.upper()}_OBJECT_REQUIRED")
    return value


def evaluate(payload: dict[str, Any]) -> Verdict:
    if not isinstance(payload, dict):
        raise ValueError("MIGRATION_SYNC_PAYLOAD_OBJECT_REQUIRED")
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("MIGRATION_SYNC_SCHEMA_INVALID")
    if payload.get("operation_code") != OPERATION_CODE:
        raise ValueError("MIGRATION_SYNC_OPERATION_INVALID")

    execution_id = str(payload.get("execution_id") or "")
    if EXEC_RE.fullmatch(execution_id) is None:
        raise ValueError("MIGRATION_SYNC_EXECUTION_ID_INVALID")

    path, version, name = _identity(str(payload.get("target_path") or ""))
    if payload.get("migration_version") != version or payload.get("migration_name") != name:
        raise ValueError("MIGRATION_SYNC_TARGET_IDENTITY_MISMATCH")

    effect_scope = str(payload.get("effect_scope") or "")
    if effect_scope != f"MIGRATION:{version}":
        raise ValueError("MIGRATION_SYNC_EFFECT_SCOPE_MISMATCH")

    source_sha256 = str(payload.get("source_sha256") or "").lower()
    if SHA64_RE.fullmatch(source_sha256) is None:
        raise ValueError("MIGRATION_SYNC_SOURCE_SHA256_INVALID")

    git = _obj(payload, "git")
    if git.get("path") != path or git.get("source_sha256") != source_sha256:
        raise ValueError("MIGRATION_SYNC_GIT_IDENTITY_MISMATCH")
    if SHA40_RE.fullmatch(str(git.get("head_sha") or "").lower()) is None:
        raise ValueError("MIGRATION_SYNC_GIT_HEAD_INVALID")
    if SHA40_RE.fullmatch(str(git.get("blob_sha1") or "").lower()) is None:
        raise ValueError("MIGRATION_SYNC_GIT_BLOB_INVALID")
    if git.get("persisted") is not True or git.get("readback") is not True:
        return Verdict(
            SCHEMA_VERSION, "BLOCKED", "BLOCK_GIT_SOURCE_NOT_DURABLE",
            execution_id, effect_scope, path, version, name, False, False,
        )

    supabase = _obj(payload, "supabase")
    if supabase.get("applied") is not True:
        return Verdict(
            SCHEMA_VERSION, "READY_TO_APPLY", "GIT_SOURCE_DURABLE_READY_FOR_EXACT_APPLY",
            execution_id, effect_scope, path, version, name, True, False,
        )

    if supabase.get("readback") is not True:
        return Verdict(
            SCHEMA_VERSION, "BLOCKED", "BLOCK_SUPABASE_READBACK_MISSING",
            execution_id, effect_scope, path, version, name, False, False,
        )
    if supabase.get("ledger_version") != version or supabase.get("ledger_name") != name:
        raise ValueError("MIGRATION_SYNC_LEDGER_IDENTITY_MISMATCH")

    parity = _obj(payload, "parity")
    if parity.get("source_path") != path:
        raise ValueError("MIGRATION_SYNC_PARITY_PATH_MISMATCH")
    if parity.get("migration_version") != version or parity.get("migration_name") != name:
        raise ValueError("MIGRATION_SYNC_PARITY_IDENTITY_MISMATCH")
    if parity.get("status") != "PASS":
        return Verdict(
            SCHEMA_VERSION, "BLOCKED", "BLOCK_DUAL_SURFACE_PARITY_NOT_PASS",
            execution_id, effect_scope, path, version, name, False, False,
        )

    return Verdict(
        SCHEMA_VERSION, "CONSISTENT", "PASS_GIT_SUPABASE_DUAL_READBACK",
        execution_id, effect_scope, path, version, name, False, True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json")
    parser.add_argument("--file")
    args = parser.parse_args()
    if bool(args.json) == bool(args.file):
        parser.error("provide exactly one of --json or --file")
    payload = json.loads(args.json) if args.json else json.loads(open(args.file, encoding="utf-8").read())
    print(json.dumps(asdict(evaluate(payload)), sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
