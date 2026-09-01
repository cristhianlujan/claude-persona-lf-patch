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
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import psycopg
from psycopg.types.json import Jsonb

from profile_runtime_runner import RuntimeExecutionBlocked

TABLE = "private.lf_profile_runtime_queue_v1"
MAX_LF_ADAPTERS = 4


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
        conn.commit()
        return payload


def _router_resolve(conn: psycopg.Connection, payload: dict[str, Any]) -> dict[str, Any]:
    with conn.cursor() as cur:
        cur.execute(
            "select public.lf_router_resolve_v1(%s,%s,%s,%s,%s)",
            (payload["input_literal"], payload["profile_code"], "PROFILE_EXECUTION", "PERFIL", "ROUTER"),
        )
        row = cur.fetchone()
    if row is None or not isinstance(row[0], dict):
        raise RuntimeExecutionBlocked("ROUTER_RESULT_INVALID")
    return row[0]


def _dispatch_input_governance(input_governance: dict[str, Any]) -> dict[str, Any]:
    project = os.environ.get("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv").strip()
    expected_url = f"https://{project}.supabase.co"
    configured_url = os.environ.get("SUPABASE_URL", expected_url).strip().rstrip("/")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if configured_url != expected_url:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_SUPABASE_URL_MISMATCH")
    if not service_key:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_SERVICE_ROLE_KEY_MISSING")

    pantalla_id = input_governance.get("pantalla_id")
    dispatch = input_governance.get("dispatch")
    if not isinstance(pantalla_id, int) or isinstance(pantalla_id, bool) or pantalla_id < 1:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_PANTALLA_ID_INVALID")
    if not isinstance(dispatch, dict):
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_DISPATCH_INVALID")
    if dispatch.get("runtime_orchestrator") != "SUPABASE_EDGE_FUNCTION:input-governance-agent-v1":
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_RUNTIME_ORCHESTRATOR_INVALID")
    consumer = dispatch.get("consumer")
    if not isinstance(consumer, str) or not consumer.strip():
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_CONSUMER_INVALID")

    body = json.dumps({"pantalla_id": pantalla_id, "consumer": consumer}).encode("utf-8")
    request = Request(
        f"{expected_url}/functions/v1/input-governance-agent-v1",
        data=body,
        method="POST",
        headers={
            "authorization": f"Bearer {service_key}",
            "content-type": "application/json",
        },
    )
    status = 0
    raw = b""
    try:
        with urlopen(request, timeout=900) as response:
            status = response.status
            raw = response.read(2_000_001)
    except HTTPError as exc:
        status = exc.code
        raw = exc.read(2_000_001)
        if status != 409:
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_EDGE_HTTP_FAILED", str(status)) from exc
    except (URLError, TimeoutError, OSError) as exc:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_EDGE_UNREACHABLE", type(exc).__name__) from exc
    if len(raw) > 2_000_000:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_EDGE_RESPONSE_TOO_LARGE")
    try:
        result = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_EDGE_RESPONSE_INVALID") from exc
    if not isinstance(result, dict):
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_EDGE_RESPONSE_INVALID")
    if result.get("runtime") not in {None, "input-governance-agent-v1"}:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_EDGE_RUNTIME_MISMATCH")
    return {"http_status": status, **result}


def _router_receipt(result: dict[str, Any]) -> dict[str, Any]:
    adapters: list[dict[str, Any]] = []
    for item in (result.get("adapters", []) if isinstance(result.get("adapters"), list) else []):
        if not isinstance(item, dict):
            continue
        metadata = item.get("adapter_metadata") if isinstance(item.get("adapter_metadata"), dict) else {}
        adapters.append({
            "adapter_code": item.get("adapter_code"),
            "canonical_adapter_id": metadata.get("canonical_adapter_id"),
            "runtime_enabled": metadata.get("runtime_enabled"),
            "router_discoverable": metadata.get("router_discoverable"),
            "input_governance_receipt_required": metadata.get("input_governance_receipt_required"),
        })
    return {
        "router": result.get("router"),
        "status": result.get("status"),
        "blocking_code": result.get("blocking_code"),
        "operation_code": result.get("operation_code"),
        "asset": result.get("asset"),
        "adapters": adapters,
        "input_governance": result.get("input_governance"),
        "downstream_execution_allowed": result.get("downstream_execution_allowed"),
    }


def _normalize_router_bindings(result: dict[str, Any], profile_code: str) -> list[dict[str, Any]]:
    raw_adapters = result.get("adapters")
    if not isinstance(raw_adapters, list):
        raise RuntimeExecutionBlocked("ROUTER_ADAPTERS_INVALID")
    bindings: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw_adapters:
        if not isinstance(item, dict):
            raise RuntimeExecutionBlocked("ROUTER_ADAPTER_BINDING_INVALID")
        metadata = item.get("adapter_metadata")
        if not isinstance(metadata, dict):
            raise RuntimeExecutionBlocked("ROUTER_ADAPTER_METADATA_INVALID")
        if metadata.get("runtime_enabled") is not True or metadata.get("router_discoverable") is not True:
            continue
        adapter_asset_code = item.get("adapter_code")
        canonical_adapter_id = metadata.get("canonical_adapter_id")
        current_path = metadata.get("current_path")
        relation_type = item.get("relacion_tipo")
        governance_required = metadata.get("input_governance_receipt_required")
        if not all(isinstance(value, str) and value.strip() for value in (adapter_asset_code, canonical_adapter_id, current_path, relation_type)):
            raise RuntimeExecutionBlocked("ROUTER_ADAPTER_BINDING_INCOMPLETE")
        if not isinstance(governance_required, bool):
            raise RuntimeExecutionBlocked("ROUTER_ADAPTER_GOVERNANCE_FLAG_INVALID", canonical_adapter_id)
        if governance_required:
            expected_contract = {
                "input_governance_continuation_policy": "PASS_ONLY",
                "input_governance_contract_resolution": "LIVE_CURRENT",
                "input_governance_authority_contract": "INPUT_READINESS_CONTRACT",
            }
            for key, expected in expected_contract.items():
                if metadata.get(key) != expected:
                    raise RuntimeExecutionBlocked("ROUTER_ADAPTER_GOVERNANCE_CONTRACT_INVALID", f"{canonical_adapter_id}:{key}")
        if canonical_adapter_id in seen:
            raise RuntimeExecutionBlocked("BLOCK_DUPLICATE_ADAPTER_INVOCATION", canonical_adapter_id)
        seen.add(canonical_adapter_id)
        bindings.append({
            "adapter_asset_code": adapter_asset_code,
            "canonical_adapter_id": canonical_adapter_id,
            "current_path": current_path,
            "adapter_version": item.get("adapter_version"),
            "relation_type": relation_type,
            "binding_ref": f"public.v_lf_router_adapter_bindings:{adapter_asset_code}:{profile_code}",
            "input_governance_receipt_required": governance_required,
            "input_governance_continuation_policy": metadata.get("input_governance_continuation_policy"),
            "input_governance_contract_resolution": metadata.get("input_governance_contract_resolution"),
            "input_governance_authority_contract": metadata.get("input_governance_authority_contract"),
        })
    if len(bindings) > MAX_LF_ADAPTERS:
        raise RuntimeExecutionBlocked("BLOCK_LF_ADAPTER_BINDING_COUNT_EXCEEDED", str(len(bindings)))
    return sorted(bindings, key=lambda item: item["canonical_adapter_id"])


def _prepare_governed_payload(
    payload: dict[str, Any],
    *,
    router_resolver: Callable[[dict[str, Any]], dict[str, Any]],
    governance_dispatcher: Callable[[dict[str, Any]], dict[str, Any]],
) -> dict[str, Any]:
    result = router_resolver(payload)
    payload["router_trace"] = [_router_receipt(result)]
    payload["router_receipt"] = payload["router_trace"][-1]

    if result.get("status") == "INPUT_GOVERNANCE_REQUIRED":
        governance = result.get("input_governance")
        if not isinstance(governance, dict):
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_DISPATCH_INVALID")
        payload["input_governance_execution"] = governance_dispatcher(governance)
        result = router_resolver(payload)
        payload["router_trace"].append(_router_receipt(result))
        payload["router_receipt"] = payload["router_trace"][-1]

    if result.get("status") != "READY_TO_EXECUTE":
        code = result.get("blocking_code") or f"ROUTER_STATUS_{result.get('status', 'INVALID')}"
        raise RuntimeExecutionBlocked(str(code))
    if result.get("router") != "ACT-0001":
        raise RuntimeExecutionBlocked("ROUTER_AUTHORITY_INVALID")
    if result.get("operation_code") != payload.get("operation_code"):
        raise RuntimeExecutionBlocked("ROUTER_OPERATION_MISMATCH")
    asset = result.get("asset")
    if not isinstance(asset, dict) or asset.get("codigo_activo") != payload.get("profile_code"):
        raise RuntimeExecutionBlocked("ROUTER_PROFILE_MISMATCH")

    bindings = _normalize_router_bindings(result, payload["profile_code"])
    required_adapters = sorted(
        item["canonical_adapter_id"]
        for item in bindings
        if item["input_governance_receipt_required"]
    )
    input_governance = result.get("input_governance")
    if required_adapters:
        if not isinstance(input_governance, dict):
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_RECEIPT_MISSING")
        if input_governance.get("status") != "READY" or input_governance.get("decision") != "PASS":
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_DECISION_NOT_PASS")
        if input_governance.get("continuation_allowed") is not True:
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_CONTINUATION_NOT_ALLOWED")
        if result.get("downstream_execution_allowed") is not True:
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_DOWNSTREAM_NOT_ALLOWED")
        claimed_adapters = input_governance.get("required_by_adapters")
        if not isinstance(claimed_adapters, list) or not all(isinstance(code, str) for code in claimed_adapters):
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_REQUIRED_ADAPTERS_INVALID")
        if sorted(claimed_adapters) != required_adapters:
            raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_REQUIRED_ADAPTERS_MISMATCH")
        payload["input_governance"] = input_governance
    elif input_governance is not None:
        raise RuntimeExecutionBlocked("INPUT_GOVERNANCE_UNEXPECTED")

    payload["lf_adapter_bindings"] = bindings
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
    payload: dict[str, Any] | None = None
    try:
        payload = _claim(conn, args.request_id, args.comment_id)
        try:
            payload = _prepare_governed_payload(
                payload,
                router_resolver=lambda request: _router_resolve(conn, request),
                governance_dispatcher=_dispatch_input_governance,
            )
        except RuntimeExecutionBlocked as exc:
            result = {
                "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
                "status": "BLOCKED",
                "request_id": args.request_id,
                "error_code": exc.code,
                "error_detail": exc.detail,
                "router_receipt": payload.get("router_receipt"),
                "router_trace": payload.get("router_trace"),
                "input_governance_execution": payload.get("input_governance_execution"),
            }
            _persist(conn, args.request_id, result)
            print(f"LF_PROFILE_RUNTIME_REQUEST_ID={args.request_id}")
            print("LF_PROFILE_RUNTIME_FINAL_STATUS=BLOCKED")
            print(f"LF_PROFILE_RUNTIME_ERROR_CODE={exc.code}")
            return 2
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
