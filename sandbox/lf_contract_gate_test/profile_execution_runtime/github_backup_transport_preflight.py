#!/usr/bin/env python3
"""Read-only preflight for LF GitHub Actions profile-runtime backup workers.

Purpose: reject a request before any llama.cpp build/cache restore/model download
unless the durable queue row is PENDING, explicitly targets GITHUB_ACTIONS and
carries a non-empty runtime_backup_reason.

The validator is deterministic and dependency-free in --self-test / --fixture-json
mode. Live DB mode imports psycopg only after arguments and environment are valid.
It performs SELECT only and never claims or mutates the request.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.I,
)
MAX_BATCH = 3


class BackupPreflightBlocked(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(code if not detail else f"{code}:{detail}")
        self.code = code
        self.detail = detail


def normalize_request_ids(raw: str) -> list[str]:
    ids = [part.strip().lower() for part in raw.split(",") if part.strip()]
    if not 1 <= len(ids) <= MAX_BATCH:
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_BATCH_SIZE_INVALID", str(len(ids)))
    if len(set(ids)) != len(ids):
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_DUPLICATE_REQUEST_ID")
    bad = [value for value in ids if not UUID_RE.fullmatch(value)]
    if bad:
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_REQUEST_ID_INVALID", bad[0])
    return ids


def validate_rows(request_ids: list[str], rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_id = {str(row.get("request_id", "")).lower(): row for row in rows}
    if len(by_id) != len(rows):
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_DUPLICATE_DB_ROW")
    receipts: list[dict[str, Any]] = []
    for request_id in request_ids:
        row = by_id.get(request_id)
        if row is None:
            raise BackupPreflightBlocked("BACKUP_PREFLIGHT_REQUEST_NOT_FOUND", request_id)
        status = str(row.get("status") or "").strip().upper()
        target = str(row.get("runtime_target") or "").strip().upper()
        reason = str(row.get("runtime_backup_reason") or "").strip()
        if status != "PENDING":
            raise BackupPreflightBlocked("BACKUP_PREFLIGHT_REQUEST_NOT_PENDING", f"{request_id}:{status or 'NULL'}")
        if target != "GITHUB_ACTIONS":
            raise BackupPreflightBlocked("BACKUP_PREFLIGHT_TARGET_NOT_GITHUB_ACTIONS", f"{request_id}:{target or 'NULL'}")
        if not reason:
            raise BackupPreflightBlocked("BACKUP_PREFLIGHT_REASON_MISSING", request_id)
        receipts.append({
            "request_id": request_id,
            "status": status,
            "runtime_target": target,
            "runtime_backup_reason_present": True,
        })
    return {
        "schema": "LF_GITHUB_BACKUP_TRANSPORT_PREFLIGHT_V1",
        "read_only": True,
        "request_count": len(receipts),
        "requests": receipts,
        "heavy_provisioning_authorized": True,
    }


def _connect():
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com").strip()
    if not password:
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_DB_PASSWORD_MISSING")
    if not project or not host:
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_DB_CONFIG_MISSING")
    try:
        import psycopg
    except ImportError as exc:
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_PSYCOPG_MISSING") from exc
    return psycopg.connect(
        host=host,
        port=5432,
        user=f"postgres.{project}",
        password=password,
        dbname="postgres",
        sslmode="require",
        autocommit=True,
    )


def read_rows_live(request_ids: list[str]) -> list[dict[str, Any]]:
    conn = _connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                select request_id::text, status, runtime_target, runtime_backup_reason
                  from private.lf_profile_runtime_queue_v1
                 where request_id = any(%s::uuid[])
                 order by request_id
                """,
                (request_ids,),
            )
            columns = [item.name for item in cur.description]
            return [dict(zip(columns, row)) for row in cur.fetchall()]
    finally:
        conn.close()


def _fixture_rows(path: str) -> list[dict[str, Any]]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, list) or not all(isinstance(row, dict) for row in payload):
        raise BackupPreflightBlocked("BACKUP_PREFLIGHT_FIXTURE_INVALID")
    return payload


def self_test() -> None:
    a = "11111111-1111-4111-8111-111111111111"
    b = "22222222-2222-4222-8222-222222222222"
    base = {"status": "PENDING", "runtime_target": "GITHUB_ACTIONS", "runtime_backup_reason": "HETZNER_EXACT_CAPABILITY_UNAVAILABLE"}
    assert validate_rows([a], [{"request_id": a, **base}])["heavy_provisioning_authorized"] is True
    assert validate_rows([a, b], [{"request_id": a, **base}, {"request_id": b, **base}])["request_count"] == 2
    cases = [
        ([a], [{"request_id": a, **base, "runtime_target": "HETZNER"}], "BACKUP_PREFLIGHT_TARGET_NOT_GITHUB_ACTIONS"),
        ([a], [{"request_id": a, **base, "runtime_backup_reason": ""}], "BACKUP_PREFLIGHT_REASON_MISSING"),
        ([a], [{"request_id": a, **base, "status": "RUNNING"}], "BACKUP_PREFLIGHT_REQUEST_NOT_PENDING"),
    ]
    for ids, rows, expected in cases:
        try:
            validate_rows(ids, rows)
        except BackupPreflightBlocked as exc:
            assert exc.code == expected, (exc.code, expected)
        else:
            raise AssertionError(expected)
    print("GITHUB_BACKUP_TRANSPORT_PREFLIGHT_SELF_TEST_PASS 5/5")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request-ids", help="one UUID or comma-separated UUIDs, max 3")
    parser.add_argument("--fixture-json", help="read-only test fixture instead of DB")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        if not args.request_ids:
            return 0
    if not args.request_ids:
        parser.error("--request-ids is required unless --self-test is used alone")

    try:
        request_ids = normalize_request_ids(args.request_ids)
        rows = _fixture_rows(args.fixture_json) if args.fixture_json else read_rows_live(request_ids)
        receipt = validate_rows(request_ids, rows)
    except BackupPreflightBlocked as exc:
        payload = {"schema": "LF_GITHUB_BACKUP_TRANSPORT_PREFLIGHT_V1", "read_only": True, "heavy_provisioning_authorized": False, "blocker": exc.code, "detail": exc.detail}
        if args.json:
            print(json.dumps(payload, sort_keys=True))
        else:
            print("BLOCK_GITHUB_BACKUP_TRANSPORT_PREFLIGHT=" + json.dumps(payload, sort_keys=True), file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(receipt, sort_keys=True))
    else:
        print("PASS_GITHUB_BACKUP_TRANSPORT_PREFLIGHT=" + json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
