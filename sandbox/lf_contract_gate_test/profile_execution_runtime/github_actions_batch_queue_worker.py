#!/usr/bin/env python3
"""Execute 1-3 queued LF profile requests on one prepared zero-cost runtime."""
from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from psycopg.types.json import Jsonb

from github_actions_queue_worker import (
    _claim,
    _connect,
    _enforce_nonempty_completion,
    _enforce_profile_output_contract,
    _persist,
)
from profile_runtime_runner import RuntimeExecutionBlocked
from run_zero_cost_profile_request import execute_request
from runtime_optimization_contract import (
    artifact_verification_decision,
    build_metrics,
    effective_parallelism,
    governance_cache_key,
    governance_receipt_reusable,
    image_binding_complete,
    iso_now,
    validate_batch_request_ids,
)


def _screen_identity(conn, input_literal: str) -> tuple[int | None, str | None]:
    with conn.cursor() as cur:
        cur.execute(
            """
            with q as (
              select ' ' || btrim(regexp_replace(lower(coalesce(%s,'')), '[^a-z0-9_]+', ' ', 'g')) || ' ' as txt
            )
            select p.id, p.codigo
              from lf_ops.pantallas p, q
             where p.activa
               and strpos(q.txt, ' ' || btrim(regexp_replace(lower(p.codigo), '[^a-z0-9_]+', ' ', 'g')) || ' ') > 0
             order by p.id
            """,
            (input_literal,),
        )
        rows = cur.fetchall()
    if len(rows) != 1:
        return None, None
    return int(rows[0][0]), str(rows[0][1])


def _router_adapter_payload(conn, profile_code: str) -> list[dict[str, Any]]:
    with conn.cursor() as cur:
        cur.execute(
            """
            select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code), '[]'::jsonb)
              from public.v_lf_router_adapter_bindings x
             where x.target_asset_code=%s
               and lower(coalesce(x.adapter_metadata->>'router_discoverable','false'))='true'
               and lower(coalesce(x.adapter_metadata->>'runtime_enabled','false'))='true'
            """,
            (profile_code,),
        )
        return list(cur.fetchone()[0] or [])


def _governance_result(conn, payload: dict[str, Any], cache: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], str | None]:
    _, screen_code = _screen_identity(conn, payload["input_literal"])
    adapters = _router_adapter_payload(conn, payload["profile_code"])
    key = governance_cache_key(screen_code=screen_code, adapters=adapters, input_literal=payload["input_literal"])
    if key in cache:
        return cache[key], screen_code
    with conn.cursor() as cur:
        cur.execute(
            "select programacion.fn_lf_router_input_governance_resolve_v1(%s,%s,'STORY_CREATOR')",
            (payload["input_literal"], Jsonb(adapters)),
        )
        result = cur.fetchone()[0]
    cache[key] = result
    return result, screen_code


def _preflight(conn, payload: dict[str, Any], cache: dict[str, dict[str, Any]]) -> dict[str, Any] | None:
    governance, screen_code = _governance_result(conn, payload, cache)
    payload["screen_code"] = screen_code
    payload["input_governance_result"] = governance
    if governance.get("applicable") and not governance.get("continuation_allowed"):
        return {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "BLOCKED",
            "request_id": payload["request_id"],
            "error_code": governance.get("blocking_code") or "BLOCK_INPUT_GOVERNANCE",
            "error_detail": governance.get("status"),
            "input_governance": governance,
        }
    if governance.get("applicable") and not governance_receipt_reusable(governance, screen_code=screen_code):
        return {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "BLOCKED",
            "request_id": payload["request_id"],
            "error_code": "BLOCK_INPUT_GOVERNANCE_RECEIPT_INVALID",
            "error_detail": "READY receipt was not reusable/current",
            "input_governance": governance,
        }
    decision = artifact_verification_decision(
        profile_code=payload["profile_code"],
        screen_code=screen_code,
        image_sha256=payload.get("input_image_sha256") if image_binding_complete(payload) else None,
    )
    payload["artifact_verified"] = decision
    if decision == "FAIL":
        return {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "BLOCKED",
            "request_id": payload["request_id"],
            "error_code": "ARTIFACT_VERIFIED_VISUAL_BYTES_REQUIRED",
            "error_detail": f"profile={payload['profile_code']} screen={screen_code} has no verified raster bytes",
            "artifact_verified": "FAIL",
            "input_governance": governance,
        }
    return None


def _run_one(payload: dict[str, Any], repo_root: Path) -> tuple[dict[str, Any], str | None, int]:
    inference_started_at = iso_now()
    started = time.perf_counter()
    try:
        with tempfile.TemporaryDirectory(prefix="lf-profile-batch-") as td:
            result = execute_request(payload, repo_root=repo_root, work_dir=Path(td))
        result = _enforce_nonempty_completion(result)
        result = _enforce_profile_output_contract(result)
    except RuntimeExecutionBlocked as exc:
        result = {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "BLOCKED",
            "request_id": payload["request_id"],
            "error_code": exc.code,
            "error_detail": exc.detail,
        }
    except Exception as exc:
        result = {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "FAILED",
            "request_id": payload["request_id"],
            "error_code": "BATCH_RUNTIME_UNEXPECTED_EXCEPTION",
            "error_detail": type(exc).__name__,
        }
    return result, inference_started_at, int(round((time.perf_counter() - started) * 1000))


def _dt(value: Any) -> str:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    return str(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request-ids", required=True, help="comma-separated UUIDs, max 3")
    parser.add_argument("--comment-id", required=True, type=int)
    parser.add_argument("--parallelism", type=int, default=2)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    args = parser.parse_args()

    request_ids = validate_batch_request_ids([x.strip() for x in args.request_ids.split(",") if x.strip()])
    parallelism = effective_parallelism(len(request_ids), args.parallelism)
    repo_root = args.repo_root.resolve()
    runtime_ready_at = os.environ.get("LF_RUNTIME_READY_AT") or iso_now()
    runtime_prepare_ms = int(os.environ.get("LF_RUNTIME_PREPARE_MS", "0"))
    model_download_ms = int(os.environ.get("LF_MODEL_DOWNLOAD_MS", "0"))
    cache_hit_runtime = os.environ.get("LF_CACHE_HIT_RUNTIME", "false").lower() == "true"
    cache_hit_model = os.environ.get("LF_CACHE_HIT_MODEL", "false").lower() == "true"

    conn = _connect()
    governance_cache: dict[str, dict[str, Any]] = {}
    claimed: list[dict[str, Any]] = []
    preblocked: dict[str, dict[str, Any]] = {}
    try:
        for request_id in request_ids:
            payload = _claim(conn, request_id, args.comment_id)
            with conn.cursor() as cur:
                cur.execute(
                    "select created_at, started_at from private.lf_profile_runtime_queue_v1 where request_id=%s::uuid",
                    (request_id,),
                )
                created_at, started_at = cur.fetchone()
            payload["queued_at"] = _dt(created_at)
            payload["started_at"] = _dt(started_at)
            blocked = _preflight(conn, payload, governance_cache)
            if blocked is not None:
                preblocked[request_id] = blocked
            claimed.append(payload)

        batch_started = time.perf_counter()
        results: dict[str, tuple[dict[str, Any], str | None, int]] = {}
        runnable = [p for p in claimed if p["request_id"] not in preblocked]
        if runnable:
            with ThreadPoolExecutor(max_workers=parallelism, thread_name_prefix="lf-profile") as pool:
                futures = {pool.submit(_run_one, payload, repo_root): payload["request_id"] for payload in runnable}
                for future in as_completed(futures):
                    results[futures[future]] = future.result()
        batch_total_ms = int(round((time.perf_counter() - batch_started) * 1000))

        exit_code = 0
        for payload in claimed:
            request_id = payload["request_id"]
            if request_id in preblocked:
                result, inference_started_at, inference_ms = preblocked[request_id], None, 0
            else:
                result, inference_started_at, inference_ms = results[request_id]
            completed_at = iso_now()
            metrics = build_metrics(
                queued_at=payload["queued_at"], started_at=payload["started_at"], runtime_ready_at=runtime_ready_at,
                inference_started_at=inference_started_at, completed_at=completed_at,
                runtime_prepare_ms=runtime_prepare_ms, model_download_ms=model_download_ms,
                inference_ms=inference_ms, cache_hit_runtime=cache_hit_runtime, cache_hit_model=cache_hit_model,
                batch_size=len(claimed), parallelism=parallelism, batch_total_ms=batch_total_ms,
            )
            result["runtime_metrics"] = metrics
            result["batch_id"] = f"github-actions:{os.environ.get('GITHUB_RUN_ID','unknown')}:{os.environ.get('GITHUB_RUN_ATTEMPT','1')}"
            result["input_governance"] = payload.get("input_governance_result")
            result["artifact_verified"] = payload.get("artifact_verified", result.get("artifact_verified"))
            _persist(conn, request_id, result)
            print(json.dumps({"request_id": request_id, "status": result.get("status"), "runtime_metrics": metrics}, sort_keys=True))
            if result.get("status") != "SUCCEEDED":
                exit_code = 2
        print(f"LF_PROFILE_BATCH_SIZE={len(claimed)}")
        print(f"LF_PROFILE_BATCH_PARALLELISM={parallelism}")
        print(f"LF_PROFILE_BATCH_TOTAL_MS={batch_total_ms}")
        return exit_code
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
