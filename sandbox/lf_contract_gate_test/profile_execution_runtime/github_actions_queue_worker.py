#!/usr/bin/env python3
"""Claim one private Supabase profile-runtime request, execute it, and persist the result."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import psycopg
from psycopg.types.json import Jsonb

TABLE = "private.lf_profile_runtime_queue_v1"
ADAPTER_BINDING_VIEW = "public.v_lf_router_adapter_bindings"


def _connect() -> psycopg.Connection:
    password = os.environ.get("LF_SUPABASE_DB_PASSWORD", "").strip()
    project = os.environ.get("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv").strip()
    host = os.environ.get("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com").strip()
    if not password:
        raise SystemExit("FAIL_PROFILE_RUNTIME_DB_PASSWORD_MISSING")
    return psycopg.connect(
        host=host, port=5432, user=f"postgres.{project}", password=password,
        dbname="postgres", sslmode="require", autocommit=False,
    )


def _claim(conn: psycopg.Connection, request_id: str, comment_id: int) -> dict:
    with conn.cursor() as cur:
        cur.execute(
            f"""
            update {TABLE}
               set status='RUNNING', started_at=now(), updated_at=now(),
                   github_comment_id=%s, github_run_id=%s, github_run_attempt=%s, github_sha=%s,
                   error_code=null, error_detail=null
             where request_id=%s::uuid and status='PENDING'
         returning request_id::text, operation_code, profile_code, profile_slug,
                   profile_source_paths, lf_adapter_resolution, input_literal, input_image_base64,
                   input_image_media_type, input_image_sha256
            """,
            (comment_id, int(os.environ["GITHUB_RUN_ID"]), int(os.environ.get("GITHUB_RUN_ATTEMPT", "1")),
             os.environ.get("GITHUB_SHA", ""), request_id),
        )
        row = cur.fetchone()
        if row is None:
            conn.rollback()
            raise SystemExit("BLOCK_PROFILE_RUNTIME_REQUEST_NOT_PENDING")
        cols = [d.name for d in cur.description]
        payload = dict(zip(cols, row))

        cur.execute(
            f"""
            select adapter_code, adapter_version, target_asset_code
              from {ADAPTER_BINDING_VIEW}
             where target_asset_code=%s and target_asset_type='PERFIL'
             order by adapter_code
            """,
            (payload["profile_code"],),
        )
        payload["governed_adapter_bindings"] = [
            {
                "adapter_asset_code": adapter_code,
                "adapter_version": adapter_version,
                "target_asset_code": target_asset_code,
            }
            for adapter_code, adapter_version, target_asset_code in cur.fetchall()
        ]
        conn.commit()
        return payload


def _persist(conn: psycopg.Connection, request_id: str, result: dict) -> None:
    status = result.get("status")
    if status not in {"SUCCEEDED", "BLOCKED", "FAILED"}:
        status = "FAILED"
        result = {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1", "status": status,
            "request_id": request_id, "error_code": "QUEUE_RESULT_STATUS_INVALID",
            "error_detail": str(result.get("status")),
        }
    receipt = result.get("receipt") if isinstance(result.get("receipt"), dict) else None
    attestation = receipt.get("runtime_attestation") if receipt else None
    raw_output = result.get("raw_output")
    with conn.cursor() as cur:
        cur.execute(
            f"""
            update {TABLE}
               set status=%s, completed_at=now(), updated_at=now(),
                   runtime_provider=%s, runtime_model_id=%s,
                   result_package=%s, raw_output=%s, receipt=%s, runtime_attestation=%s,
                   error_code=%s, error_detail=%s
             where request_id=%s::uuid and status='RUNNING'
            """,
            (
                status, result.get("runtime_provider"), result.get("runtime_model_id"),
                Jsonb(result), Jsonb(raw_output) if raw_output is not None else None,
                Jsonb(receipt) if receipt is not None else None,
                Jsonb(attestation) if attestation is not None else None,
                result.get("error_code"), result.get("error_detail"), request_id,
            ),
        )
        if cur.rowcount != 1:
            conn.rollback()
            raise SystemExit("FAIL_PROFILE_RUNTIME_RESULT_PERSIST_TARGET")
        conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request-id", required=True)
    parser.add_argument("--comment-id", required=True, type=int)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    args = parser.parse_args()

    conn = _connect()
    try:
        payload = _claim(conn, args.request_id, args.comment_id)
        with tempfile.TemporaryDirectory(prefix="lf-profile-queue-") as td:
            request_file = Path(td) / "request.json"
            result_file = Path(td) / "result.json"
            request_file.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
            completed = subprocess.run(
                [sys.executable,
                 str(args.repo_root / "sandbox/lf_contract_gate_test/profile_execution_runtime/run_zero_cost_profile_request.py"),
                 "--request", str(request_file), "--repo-root", str(args.repo_root), "--output", str(result_file)],
                cwd=args.repo_root, check=False,
            )
            if result_file.is_file():
                result = json.loads(result_file.read_text(encoding="utf-8"))
            else:
                result = {
                    "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1", "status": "FAILED",
                    "request_id": args.request_id, "error_code": "QUEUE_RESULT_FILE_MISSING",
                    "error_detail": f"executor_rc={completed.returncode}",
                }
            _persist(conn, args.request_id, result)
            print(f"LF_PROFILE_RUNTIME_REQUEST_ID={args.request_id}")
            print(f"LF_PROFILE_RUNTIME_FINAL_STATUS={result.get('status')}")
            if result.get("error_code"):
                print(f"LF_PROFILE_RUNTIME_ERROR_CODE={result['error_code']}")
            return 0 if result.get("status") == "SUCCEEDED" else 2
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
