#!/usr/bin/env python3
"""Fail-closed state machine for governed LF migration saga.

Authority stays with Router + ACTUALIZACION_DB_LF + DB_WRITE_TRANSPORT.
This helper performs no Git or database writes. It deterministically decides
whether the same governed migration identity may advance through:
write-ahead -> exact DB apply -> ledger readback -> parity verification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import asdict, dataclass
from pathlib import PurePosixPath
from typing import Any

SCHEMA_VERSION = "lf-migration-orchestrated-saga/v1"
OPERATION_CODE = "ACTUALIZACION_DB_LF"
PARITY_EVIDENCE_CONTRACT = "LF_GATE_ERROR_V1"
PARITY_EVIDENCE_PRODUCER = "LF_GATE_CHECK_OBSERVABILITY_V1"
PARITY_GATE_SUFFIX = "::MIGRATION_SOURCE_PARITY"
PARITY_STEP_ID = "migration_source_parity"
PARITY_SOURCE_PATH = "sandbox/lf_contract_gate_test/lf_migration_source_parity.py"
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
        raise ValueError("MIGRATION_SAGA_CANONICAL_PATH_REQUIRED")
    match = FILENAME_RE.fullmatch(normalized.rsplit("/", 1)[-1])
    if not match:
        raise ValueError("MIGRATION_SAGA_FILENAME_INVALID")
    return normalized, match.group("version"), match.group("name")


def _obj(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key)
    if not isinstance(value, dict):
        raise ValueError(f"MIGRATION_SAGA_{key.upper()}_OBJECT_REQUIRED")
    return value


def _canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def _evidence_digest(report: dict[str, Any]) -> str:
    payload = dict(report)
    payload.pop("manifest_sha256", None)
    return hashlib.sha256(_canonical_json(payload).encode("utf-8")).hexdigest()


def _validate_parity_evidence(parity: dict[str, Any], *, git_head: str) -> bool:
    evidence = parity.get("evidence")
    if not isinstance(evidence, dict):
        raise ValueError("MIGRATION_SAGA_PARITY_CANONICAL_EVIDENCE_REQUIRED")
    if evidence.get("contract") != PARITY_EVIDENCE_CONTRACT:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_CONTRACT_INVALID")
    if evidence.get("producer") != PARITY_EVIDENCE_PRODUCER:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_PRODUCER_INVALID")
    gate_id = str(evidence.get("gate_id") or "")
    if not gate_id.endswith(PARITY_GATE_SUFFIX):
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_GATE_INVALID")
    if evidence.get("step_id") != PARITY_STEP_ID:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_STEP_INVALID")
    if evidence.get("gate_result") != "PASS":
        return False
    if evidence.get("diagnostic_complete") is not True:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_INCOMPLETE")
    observed_digest = str(evidence.get("manifest_sha256") or "").lower()
    if SHA64_RE.fullmatch(observed_digest) is None or observed_digest != _evidence_digest(evidence):
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_DIGEST_MISMATCH")
    source_commit = str(evidence.get("source_commit") or "").lower()
    tested_commit = str(evidence.get("tested_commit") or "").lower()
    if source_commit != git_head or tested_commit != git_head:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_HEAD_MISMATCH")
    if evidence.get("source_path") != [PARITY_SOURCE_PATH]:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_SOURCE_INVALID")
    impacts = evidence.get("downstream_impact")
    if not isinstance(impacts, list) or "MIGRATION_SOURCE_PARITY" not in impacts:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_IMPACT_INVALID")
    if evidence.get("expected_check_count") != 1 or evidence.get("executed_check_count") != 1:
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_CHECK_COUNT_INVALID")
    if evidence.get("pass_count") != 1 or evidence.get("fail_count") != 0 or evidence.get("blocked_count") != 0:
        return False
    checks = evidence.get("checks")
    if not isinstance(checks, list) or len(checks) != 1 or not isinstance(checks[0], dict):
        raise ValueError("MIGRATION_SAGA_PARITY_EVIDENCE_CHECK_INVALID")
    check = checks[0]
    if check.get("check_status") != "PASS" or check.get("exit_code") != 0 or check.get("rc") != 0:
        return False
    if check.get("producer") != PARITY_EVIDENCE_PRODUCER:
        raise ValueError("MIGRATION_SAGA_PARITY_CHECK_PRODUCER_INVALID")
    if check.get("source_path") != PARITY_SOURCE_PATH:
        raise ValueError("MIGRATION_SAGA_PARITY_CHECK_SOURCE_INVALID")
    if str(check.get("source_commit") or "").lower() != git_head or str(check.get("tested_commit") or "").lower() != git_head:
        raise ValueError("MIGRATION_SAGA_PARITY_CHECK_HEAD_MISMATCH")
    return True


def evaluate(payload: dict[str, Any]) -> Verdict:
    if not isinstance(payload, dict):
        raise ValueError("MIGRATION_SAGA_PAYLOAD_OBJECT_REQUIRED")
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("MIGRATION_SAGA_SCHEMA_INVALID")
    if payload.get("operation_code") != OPERATION_CODE:
        raise ValueError("MIGRATION_SAGA_OPERATION_INVALID")

    execution_id = str(payload.get("execution_id") or "")
    if EXEC_RE.fullmatch(execution_id) is None:
        raise ValueError("MIGRATION_SAGA_EXECUTION_ID_INVALID")

    path, version, name = _identity(str(payload.get("target_path") or ""))
    if payload.get("migration_version") != version or payload.get("migration_name") != name:
        raise ValueError("MIGRATION_SAGA_TARGET_IDENTITY_MISMATCH")

    effect_scope = str(payload.get("effect_scope") or "")
    if effect_scope != f"MIGRATION:{version}":
        raise ValueError("MIGRATION_SAGA_EFFECT_SCOPE_MISMATCH")

    source_sha256 = str(payload.get("source_sha256") or "").lower()
    if SHA64_RE.fullmatch(source_sha256) is None:
        raise ValueError("MIGRATION_SAGA_SOURCE_SHA256_INVALID")

    git = _obj(payload, "git")
    if git.get("path") != path or git.get("source_sha256") != source_sha256:
        raise ValueError("MIGRATION_SAGA_GIT_IDENTITY_MISMATCH")
    git_head = str(git.get("head_sha") or "").lower()
    if SHA40_RE.fullmatch(git_head) is None:
        raise ValueError("MIGRATION_SAGA_GIT_HEAD_INVALID")
    if SHA40_RE.fullmatch(str(git.get("blob_sha1") or "").lower()) is None:
        raise ValueError("MIGRATION_SAGA_GIT_BLOB_INVALID")
    if git.get("persisted") is not True or git.get("readback") is not True:
        return Verdict(SCHEMA_VERSION, "BLOCKED", "BLOCK_WRITE_AHEAD_NOT_DURABLE",
                       execution_id, effect_scope, path, version, name, False, False)

    supabase = _obj(payload, "supabase")
    if supabase.get("applied") is not True:
        return Verdict(SCHEMA_VERSION, "READY_TO_APPLY", "WRITE_AHEAD_READY_FOR_EXACT_APPLY",
                       execution_id, effect_scope, path, version, name, True, False)

    if supabase.get("readback") is not True:
        return Verdict(SCHEMA_VERSION, "BLOCKED", "BLOCK_SUPABASE_READBACK_MISSING",
                       execution_id, effect_scope, path, version, name, False, False)
    if supabase.get("ledger_version") != version or supabase.get("ledger_name") != name:
        raise ValueError("MIGRATION_SAGA_LEDGER_IDENTITY_MISMATCH")

    parity = _obj(payload, "parity")
    if parity.get("source_path") != path:
        raise ValueError("MIGRATION_SAGA_PARITY_PATH_MISMATCH")
    if parity.get("migration_version") != version or parity.get("migration_name") != name:
        raise ValueError("MIGRATION_SAGA_PARITY_IDENTITY_MISMATCH")
    if parity.get("status") != "PASS":
        return Verdict(SCHEMA_VERSION, "BLOCKED", "BLOCK_DUAL_SURFACE_PARITY_NOT_PASS",
                       execution_id, effect_scope, path, version, name, False, False)
    if not _validate_parity_evidence(parity, git_head=git_head):
        return Verdict(SCHEMA_VERSION, "BLOCKED", "BLOCK_DUAL_SURFACE_PARITY_NOT_PASS",
                       execution_id, effect_scope, path, version, name, False, False)

    return Verdict(SCHEMA_VERSION, "CONSISTENT", "PASS_MIGRATION_SAGA_CONSISTENT",
                   execution_id, effect_scope, path, version, name, False, True)


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
