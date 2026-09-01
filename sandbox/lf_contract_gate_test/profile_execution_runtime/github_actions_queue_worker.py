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

HELPER_ROOT = Path(__file__).resolve().parents[1]
if str(HELPER_ROOT) not in sys.path:
    sys.path.insert(0, str(HELPER_ROOT))

from product_director_input_governance_binding_v1 import (  # noqa: E402
    GovernanceBindingError,
    build_bound_governance_receipt,
)

TABLE = "private.lf_profile_runtime_queue_v1"
MAX_LF_ADAPTERS = 4
INPUT_GOVERNANCE_CONSUMER = "CONTEXT_PACK"


def _assistant_completion(raw_output: object) -> str:
    if not isinstance(raw_output, str):
        return ""
    text = raw_output.strip()
    if not text:
        return ""
    if "Assistant:" in text:
        return text.rsplit("Assistant:", 1)[1].strip()
    return text


def _enforce_nonempty_completion(result: dict) -> dict:
    if result.get("status") != "SUCCEEDED":
        return result
    if _assistant_completion(result.get("raw_output")):
        return result
    result = dict(result)
    result["status"] = "BLOCKED"
    result["error_code"] = "LOCAL_RUNTIME_ASSISTANT_COMPLETION_EMPTY"
    result["error_detail"] = "llama.cpp returned success but no assistant completion after the rendered prompt"
    return result


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


def _resolve_enabled_adapter_bindings(cur: psycopg.Cursor, profile_code: str) -> list[dict]:
    cur.execute(
        """
        select adapter_code,
               adapter_metadata->>'canonical_adapter_id' as canonical_adapter_id,
               adapter_metadata->>'current_path' as current_path,
               adapter_version,
               relacion_tipo,
               adapter_metadata
          from public.v_lf_router_adapter_bindings
         where target_asset_code=%s
           and lower(coalesce(adapter_metadata->>'router_discoverable','false'))='true'
           and lower(coalesce(adapter_metadata->>'runtime_enabled','false'))='true'
         order by adapter_code
        """,
        (profile_code,),
    )
    rows = cur.fetchall()
    if len(rows) > MAX_LF_ADAPTERS:
        raise SystemExit(f"BLOCK_LF_ADAPTER_BINDING_COUNT_EXCEEDED:{len(rows)}")
    result: list[dict] = []
    seen: set[str] = set()
    for adapter_asset_code, canonical_adapter_id, current_path, adapter_version, relation_type, adapter_metadata in rows:
        if not all(isinstance(value, str) and value.strip() for value in (adapter_asset_code, canonical_adapter_id, current_path, relation_type)):
            raise SystemExit("BLOCK_LF_ADAPTER_BINDING_INCOMPLETE")
        if canonical_adapter_id in seen:
            raise SystemExit(f"BLOCK_DUPLICATE_ADAPTER_INVOCATION:{canonical_adapter_id}")
        if not isinstance(adapter_metadata, dict):
            raise SystemExit("BLOCK_LF_ADAPTER_METADATA_INVALID")
        seen.add(canonical_adapter_id)
        result.append({
            "adapter_asset_code": adapter_asset_code,
            "canonical_adapter_id": canonical_adapter_id,
            "current_path": current_path,
            "adapter_version": adapter_version,
            "relation_type": relation_type,
            "binding_ref": f"public.v_lf_router_adapter_bindings:{adapter_asset_code}:{profile_code}",
            "adapter_metadata": adapter_metadata,
        })
    return result


def _resolve_input_governance_binding(cur: psycopg.Cursor, payload: dict) -> dict | None:
    bindings = payload.get("lf_adapter_bindings", [])
    required = any(
        isinstance(item, dict)
        and isinstance(item.get("adapter_metadata"), dict)
        and item["adapter_metadata"].get("input_governance_receipt_required") is True
        for item in bindings
    )
    if not required:
        return None
    cur.execute(
        "select programacion.fn_lf_router_input_governance_resolve_v1(%s,%s,%s)",
        (payload["input_literal"], Jsonb(bindings), INPUT_GOVERNANCE_CONSUMER),
    )
    row = cur.fetchone()
    router_result = row[0] if row else None
    try:
        return build_bound_governance_receipt(
            router_result,
            request_id=str(payload["request_id"]),
            profile_code=payload["profile_code"],
            input_literal=payload["input_literal"],
            governance_consumer=INPUT_GOVERNANCE_CONSUMER,
        )
    except GovernanceBindingError as exc:
        blocking_code = router_result.get("blocking_code") if isinstance(router_result, dict) else None
        detail = blocking_code or str(exc)
        raise SystemExit(f"BLOCK_INPUT_GOVERNANCE_RECEIPT_REQUIRED:{detail}") from exc


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
                   profile_source_paths, input_literal, input_image_base64,
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
        payload["lf_adapter_bindings"] = _resolve_enabled_adapter_bindings(cur, payload["profile_code"])
        governance_binding = _resolve_input_governance_binding(cur, payload)
        if governance_binding is not None:
            payload["input_governance_binding"] = governance_binding
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
            result = _enforce_nonempty_completion(result)
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
