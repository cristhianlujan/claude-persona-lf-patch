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
MAX_LF_ADAPTERS = 4
QUALITY_PACK_PROFILE_CODE = "PERFIL-QUALITY-PACK"
QUALITY_PACK_VERDICTS = {
    "PASS_TO_COMPOSER",
    "PASS_WITH_RESTRICTIONS",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "RETURN_TO_ORCHESTRATOR",
    "BLOCK_PIPELINE",
}
QUALITY_PACK_PASS_VERDICTS = {"PASS_TO_COMPOSER", "PASS_WITH_RESTRICTIONS"}
QUALITY_PACK_REQUIRED_KEYS = {
    "review_id",
    "reviewed_artifact",
    "verdict",
    "score_breakdown",
    "evidence_map",
    "blocking_codes",
    "repair_actions",
    "remaining_risks",
    "next_gate",
    "routing",
}
QUALITY_PACK_SCORE_KEYS = {
    "contract_schema_compliance",
    "evidence_integrity",
    "lf_safety_governance",
    "handoff_readiness",
    "leakage_scope_control",
    "total",
}
QUALITY_PACK_ROUTE_BY_VERDICT = {
    "PASS_TO_COMPOSER": ("CONTINUE", "COMPOSER"),
    "PASS_WITH_RESTRICTIONS": ("CONTINUE_WITH_RESTRICTIONS", "COMPOSER"),
    "RETURN_TO_WORKER_FOR_SELF_REPAIR": ("RETURN_TO_ORCHESTRATOR", "PRODUCER_REPAIR"),
    "RETURN_TO_ORCHESTRATOR": ("RETURN_TO_ORCHESTRATOR", "AUTHORITY_OR_CONTEXT_RESOLUTION"),
    "BLOCK_PIPELINE": ("BLOCK_PIPELINE", "NONE"),
}


def _assistant_completion(raw_output: object) -> str:
    if not isinstance(raw_output, str):
        return ""
    text = raw_output.strip()
    if not text:
        return ""
    if "Assistant:" in text:
        return text.rsplit("Assistant:", 1)[1].strip()
    return text


def _blocked_result(result: dict, code: str, detail: str) -> dict:
    blocked = dict(result)
    blocked["status"] = "BLOCKED"
    blocked["error_code"] = code
    blocked["error_detail"] = detail
    return blocked


def _enforce_nonempty_completion(result: dict) -> dict:
    if result.get("status") != "SUCCEEDED":
        return result
    if _assistant_completion(result.get("raw_output")):
        return result
    return _blocked_result(
        result,
        "LOCAL_RUNTIME_ASSISTANT_COMPLETION_EMPTY",
        "llama.cpp returned success but no assistant completion after the rendered prompt",
    )


def _quality_pack_profile_code(result: dict) -> str | None:
    package = result.get("package")
    if not isinstance(package, dict):
        return None
    request = package.get("request")
    if not isinstance(request, dict):
        return None
    profile_code = request.get("profile_code")
    return profile_code if isinstance(profile_code, str) else None


def _validate_quality_pack_completion(payload: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(payload, dict):
        return ["OUTPUT_NOT_OBJECT"]
    missing = sorted(QUALITY_PACK_REQUIRED_KEYS - set(payload))
    if missing:
        errors.append("MISSING_KEYS=" + ",".join(missing))
    verdict = payload.get("verdict")
    if verdict not in QUALITY_PACK_VERDICTS:
        errors.append("VERDICT_INVALID")

    score = payload.get("score_breakdown")
    if not isinstance(score, dict):
        errors.append("SCORE_BREAKDOWN_INVALID")
    else:
        score_missing = sorted(QUALITY_PACK_SCORE_KEYS - set(score))
        if score_missing:
            errors.append("SCORE_KEYS_MISSING=" + ",".join(score_missing))
        component_keys = sorted(QUALITY_PACK_SCORE_KEYS - {"total"})
        values: list[int] = []
        for key in component_keys:
            value = score.get(key)
            if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 5:
                errors.append(f"SCORE_{key.upper()}_INVALID")
            else:
                values.append(value)
        total = score.get("total")
        if not isinstance(total, int) or isinstance(total, bool) or not 0 <= total <= 25:
            errors.append("SCORE_TOTAL_INVALID")
        elif len(values) == len(component_keys) and total != sum(values):
            errors.append("SCORE_TOTAL_MISMATCH")

    for key in ("evidence_map", "blocking_codes", "repair_actions", "remaining_risks"):
        if not isinstance(payload.get(key), list):
            errors.append(f"{key.upper()}_NOT_ARRAY")

    if verdict in QUALITY_PACK_PASS_VERDICTS and isinstance(payload.get("evidence_map"), list) and not payload["evidence_map"]:
        errors.append("PASS_EVIDENCE_MAP_EMPTY")

    routing = payload.get("routing")
    if not isinstance(routing, dict):
        errors.append("ROUTING_INVALID")
    else:
        if routing.get("via") != "ORCHESTRATOR":
            errors.append("ROUTING_VIA_INVALID")
        if routing.get("activation_path") not in {"DIRECT", "ROUTER"}:
            errors.append("ROUTING_ACTIVATION_PATH_INVALID")
        expected = QUALITY_PACK_ROUTE_BY_VERDICT.get(verdict)
        if expected is not None:
            if routing.get("pipeline_action") != expected[0]:
                errors.append("ROUTING_PIPELINE_ACTION_MISMATCH")
            if routing.get("resolution_target") != expected[1]:
                errors.append("ROUTING_RESOLUTION_TARGET_MISMATCH")
    return sorted(set(errors))


def _enforce_profile_output_contract(result: dict) -> dict:
    if result.get("status") != "SUCCEEDED":
        return result
    if _quality_pack_profile_code(result) != QUALITY_PACK_PROFILE_CODE:
        return result
    completion = _assistant_completion(result.get("raw_output"))
    try:
        payload = json.loads(completion)
    except (TypeError, ValueError, json.JSONDecodeError):
        return _blocked_result(
            result,
            "QUALITY_PACK_OUTPUT_NOT_JSON",
            "Quality Pack runtime output must be one JSON object matching the governed quality review contract",
        )
    errors = _validate_quality_pack_completion(payload)
    if errors:
        return _blocked_result(
            result,
            "QUALITY_PACK_OUTPUT_CONTRACT_INVALID",
            ";".join(errors),
        )
    normalized = dict(result)
    normalized["normalized_profile_output"] = payload
    return normalized


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
               relacion_tipo
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
    for adapter_asset_code, canonical_adapter_id, current_path, adapter_version, relation_type in rows:
        if not all(isinstance(value, str) and value.strip() for value in (adapter_asset_code, canonical_adapter_id, current_path, relation_type)):
            raise SystemExit("BLOCK_LF_ADAPTER_BINDING_INCOMPLETE")
        if canonical_adapter_id in seen:
            raise SystemExit(f"BLOCK_DUPLICATE_ADAPTER_INVOCATION:{canonical_adapter_id}")
        seen.add(canonical_adapter_id)
        result.append({
            "adapter_asset_code": adapter_asset_code,
            "canonical_adapter_id": canonical_adapter_id,
            "current_path": current_path,
            "adapter_version": adapter_version,
            "relation_type": relation_type,
            "binding_ref": f"public.v_lf_router_adapter_bindings:{adapter_asset_code}:{profile_code}",
        })
    return result


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
            result = _enforce_profile_output_contract(result)
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
