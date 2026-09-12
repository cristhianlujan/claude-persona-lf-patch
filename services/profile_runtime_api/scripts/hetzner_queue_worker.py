#!/usr/bin/env python3
"""Consume HETZNER profile-runtime rows and relay them to the local persistent API.

Routing modes:
- governed screen requests: exact runtime_request_envelope -> /v1/profile/execute;
- normal text/profile queue requests: queue-native payload -> /v1/profile/queue-execute.

The worker never fabricates screen Input Governance, Card or image evidence. Image-bound work
without an explicit governed envelope remains ineligible for the queue-native route.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

TABLE = "private.lf_profile_runtime_queue_v1"
PROVIDER = "hetzner_profile_runtime_api"
MAX_LF_ADAPTERS = 4
REPO_ROOT = Path(__file__).resolve().parents[3]


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _connect() -> psycopg.Connection:
    password = _env("LF_SUPABASE_DB_PASSWORD")
    project = _env("SUPABASE_PROJECT_ID", "mhwmirqcgxxukpctffuv")
    host = _env("SUPABASE_POOLER_HOST", "aws-1-us-east-1.pooler.supabase.com")
    if not password:
        raise SystemExit("HETZNER_QUEUE_DB_PASSWORD_MISSING")
    return psycopg.connect(
        host=host,
        port=5432,
        user=f"postgres.{project}",
        password=password,
        dbname="postgres",
        sslmode="require",
        autocommit=False,
    )


def _adapter_sources(cur: psycopg.Cursor, profile_code: str) -> list[dict[str, Any]]:
    cur.execute(
        """
        select adapter_code,
               adapter_metadata->>'canonical_adapter_id' as canonical_adapter_id,
               adapter_metadata->>'runtime_capsule_path' as runtime_capsule_path,
               coalesce(adapter_metadata->>'assurance_revision', adapter_version) as assurance_revision,
               adapter_version
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
        raise RuntimeError(f"HETZNER_ADAPTER_BINDING_COUNT_EXCEEDED:{len(rows)}")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for asset_code, canonical_id, capsule_path, assurance_revision, adapter_version in rows:
        if not all(
            isinstance(v, str) and v.strip()
            for v in (asset_code, canonical_id, capsule_path, assurance_revision)
        ):
            raise RuntimeError("HETZNER_ADAPTER_BINDING_INCOMPLETE")
        if canonical_id in seen:
            raise RuntimeError(f"HETZNER_ADAPTER_BINDING_DUPLICATE:{canonical_id}")
        seen.add(canonical_id)
        relative = Path(capsule_path)
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError("HETZNER_ADAPTER_CAPSULE_PATH_INVALID")
        path = (REPO_ROOT / relative).resolve()
        try:
            path.relative_to(REPO_ROOT.resolve())
        except ValueError as exc:
            raise RuntimeError("HETZNER_ADAPTER_CAPSULE_PATH_ESCAPE") from exc
        if not path.is_file():
            raise RuntimeError(f"HETZNER_ADAPTER_CAPSULE_MISSING:{capsule_path}")
        content = path.read_text(encoding="utf-8").strip()
        if not content or len(content) > 2000:
            raise RuntimeError(f"HETZNER_ADAPTER_CAPSULE_BUDGET_INVALID:{len(content)}")
        result.append(
            {
                "adapter_code": canonical_id,
                "adapter_version": adapter_version,
                "assurance_revision": assurance_revision,
                "activation_source": "ROUTER",
                "binding_ref": f"public.v_lf_router_adapter_bindings:{asset_code}:{profile_code}",
                "target_ref": profile_code,
                "ref": capsule_path,
                "content": content,
            }
        )
    return result


def _claim(conn: psycopg.Connection) -> dict[str, Any] | None:
    with conn.cursor() as cur:
        cur.execute(
            f"""
            with candidate as (
              select request_id
                from {TABLE}
               where status='PENDING'
                 and runtime_target='HETZNER'
               order by created_at, request_id
               for update skip locked
               limit 1
            )
            update {TABLE} q
               set status='RUNNING',
                   started_at=now(),
                   updated_at=now(),
                   runtime_provider=%s,
                   github_comment_id=null,
                   github_run_id=null,
                   github_run_attempt=null,
                   github_sha=null,
                   error_code=null,
                   error_detail=null
              from candidate c
             where q.request_id=c.request_id
         returning q.request_id::text,
                   q.operation_code,
                   q.profile_code,
                   q.profile_slug,
                   q.profile_source_paths,
                   q.input_literal,
                   q.input_image_base64,
                   q.input_image_media_type,
                   q.input_image_sha256,
                   q.runtime_request_envelope
            """,
            (PROVIDER,),
        )
        row = cur.fetchone()
        if row is None:
            conn.rollback()
            return None
        cols = [d.name for d in cur.description]
        payload = dict(zip(cols, row))
        if payload["runtime_request_envelope"] is None:
            payload["lf_adapter_sources"] = _adapter_sources(cur, payload["profile_code"])
        conn.commit()
        return payload


def _api_json(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    base = _env("PROFILE_RUNTIME_WORKER_API_BASE", "http://127.0.0.1:8090").rstrip("/")
    token = _env("PROFILE_RUNTIME_API_TOKEN")
    if not token:
        raise RuntimeError("PROFILE_RUNTIME_API_TOKEN_MISSING")
    body = (
        None
        if payload is None
        else json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    )
    headers = {"Authorization": f"Bearer {token}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = str(len(body))
    request = urllib.request.Request(base + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(
            request, timeout=float(_env("PROFILE_RUNTIME_WORKER_HTTP_TIMEOUT", "30"))
        ) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        raise RuntimeError(f"PROFILE_RUNTIME_API_HTTP_{exc.code}:{detail}") from exc
    except OSError as exc:
        raise RuntimeError(f"PROFILE_RUNTIME_API_UNREACHABLE:{type(exc).__name__}") from exc
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise RuntimeError("PROFILE_RUNTIME_API_RESPONSE_NOT_OBJECT")
    return data


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _validate_envelope(request_id: str, envelope: Any) -> dict[str, Any]:
    if not isinstance(envelope, dict):
        raise RuntimeError("HETZNER_REQUEST_ENVELOPE_NOT_OBJECT")
    profile = envelope.get("profile")
    if not isinstance(profile, dict) or profile.get("request_id") != request_id:
        raise RuntimeError("HETZNER_REQUEST_ID_ENVELOPE_MISMATCH")
    profile_code = profile.get("profile_code")
    if not isinstance(profile_code, str) or not profile_code:
        raise RuntimeError("HETZNER_PROFILE_CODE_MISSING")

    governance = envelope.get("input_governance")
    if (
        not isinstance(governance, dict)
        or governance.get("current") is not True
        or governance.get("ready") is not True
    ):
        raise RuntimeError("HETZNER_INPUT_GOVERNANCE_NOT_READY")
    canonical = governance.get("canonical_receipt")
    if not isinstance(canonical, dict):
        raise RuntimeError("HETZNER_INPUT_GOVERNANCE_CANONICAL_RECEIPT_MISSING")
    required_governance = (
        "run_id",
        "governance_agent_used",
        "governance_version",
        "consumer",
        "sections_consumed",
        "source_refs",
        "source_snapshot_sha256",
        "contract_snapshot_sha256",
        "currentness",
        "decision",
    )
    for key in required_governance:
        if canonical.get(key) in (None, "", [], {}):
            raise RuntimeError(f"HETZNER_INPUT_GOVERNANCE_CANONICAL_FIELD_MISSING:{key}")
    if canonical.get("governance_agent_used") != "INPUT_GOVERNANCE_AGENT":
        raise RuntimeError("HETZNER_INPUT_GOVERNANCE_AGENT_MISMATCH")
    if canonical.get("consumer") != "CONTEXT_PACK":
        raise RuntimeError("HETZNER_INPUT_GOVERNANCE_CONSUMER_MISMATCH")
    if canonical.get("currentness") != "LIVE_CURRENT" or canonical.get("decision") != "PASS":
        raise RuntimeError("HETZNER_INPUT_GOVERNANCE_CANONICAL_NOT_CURRENT_PASS")

    artifact = envelope.get("artifact")
    if not isinstance(artifact, dict) or not artifact.get("image_sha256"):
        raise RuntimeError("HETZNER_ARTIFACT_BINDING_MISSING")

    adapter_sources = profile.get("lf_adapter_sources")
    if not isinstance(adapter_sources, list):
        raise RuntimeError("HETZNER_ADAPTER_SOURCES_NOT_ARRAY")
    adapter_by_code: dict[str, dict[str, Any]] = {}
    for item in adapter_sources:
        if not isinstance(item, dict):
            raise RuntimeError("HETZNER_ADAPTER_SOURCE_INVALID")
        code = item.get("adapter_code")
        if not isinstance(code, str) or not code:
            raise RuntimeError("HETZNER_ADAPTER_CODE_MISSING")
        if code in adapter_by_code:
            raise RuntimeError(f"HETZNER_ADAPTER_DUPLICATE:{code}")
        if item.get("target_ref") != profile_code:
            raise RuntimeError(f"HETZNER_ADAPTER_TARGET_MISMATCH:{code}")
        adapter_by_code[code] = item
    required_adapters = profile.get("required_adapter_codes") or []
    if not isinstance(required_adapters, list):
        raise RuntimeError("HETZNER_REQUIRED_ADAPTER_CODES_NOT_ARRAY")
    for code in required_adapters:
        source = adapter_by_code.get(code)
        if source is None:
            raise RuntimeError(f"HETZNER_REQUIRED_ADAPTER_MISSING:{code}")
        if not source.get("adapter_version") or not source.get("binding_ref"):
            raise RuntimeError(f"HETZNER_REQUIRED_ADAPTER_BINDING_INCOMPLETE:{code}")

    card_sources = profile.get("lf_card_sources")
    if not isinstance(card_sources, list):
        raise RuntimeError("HETZNER_CARD_SOURCES_NOT_ARRAY")
    card_by_ref: dict[str, dict[str, Any]] = {}
    for item in card_sources:
        if not isinstance(item, dict):
            raise RuntimeError("HETZNER_CARD_SOURCE_INVALID")
        card_ref = item.get("card_ref")
        if not isinstance(card_ref, str) or not card_ref:
            raise RuntimeError("HETZNER_CARD_REF_MISSING")
        if card_ref in card_by_ref:
            raise RuntimeError(f"HETZNER_CARD_DUPLICATE:{card_ref}")
        content = item.get("content")
        if not isinstance(content, str) or not content:
            raise RuntimeError(f"HETZNER_CARD_CONTENT_MISSING:{card_ref}")
        if _sha256_text(content) != item.get("content_sha256"):
            raise RuntimeError(f"HETZNER_CARD_CONTENT_SHA256_MISMATCH:{card_ref}")
        budget = item.get("budget_chars")
        if not isinstance(budget, int) or budget <= 0 or len(content) > budget:
            raise RuntimeError(f"HETZNER_CARD_CONTENT_BUDGET_INVALID:{card_ref}")
        if not item.get("selected_sections") or not item.get("card_version"):
            raise RuntimeError(f"HETZNER_CARD_BINDING_INCOMPLETE:{card_ref}")
        card_by_ref[card_ref] = item
    required_cards = profile.get("required_card_refs") or []
    if not isinstance(required_cards, list):
        raise RuntimeError("HETZNER_REQUIRED_CARD_REFS_NOT_ARRAY")
    for card_ref in required_cards:
        if card_ref not in card_by_ref:
            raise RuntimeError(f"HETZNER_REQUIRED_CARD_MISSING:{card_ref}")
    return envelope


def _queue_native_payload(claimed: dict[str, Any]) -> dict[str, Any]:
    if (
        claimed.get("input_image_base64")
        or claimed.get("input_image_sha256")
        or claimed.get("input_image_media_type")
    ):
        raise RuntimeError("HETZNER_QUEUE_NATIVE_IMAGE_REQUIRES_GOVERNED_ENVELOPE")
    return {
        "profile": {
            "request_id": claimed["request_id"],
            "operation_code": claimed["operation_code"],
            "profile_code": claimed["profile_code"],
            "profile_slug": claimed["profile_slug"],
            "profile_source_paths": claimed["profile_source_paths"],
            "input_literal": claimed["input_literal"],
            "lf_adapter_sources": claimed.get("lf_adapter_sources") or [],
            "send_image_to_model": False,
        }
    }


def _wait_job(job_id: str) -> dict[str, Any]:
    deadline = time.monotonic() + float(
        _env("PROFILE_RUNTIME_WORKER_JOB_TIMEOUT_SECONDS", "900")
    )
    poll = max(0.5, float(_env("PROFILE_RUNTIME_WORKER_POLL_SECONDS", "2")))
    while True:
        record = _api_json("GET", f"/v1/jobs/{job_id}")
        status = str(record.get("status", ""))
        if status in {"COMPLETED", "FAILED"}:
            return record
        if time.monotonic() >= deadline:
            raise RuntimeError("HETZNER_API_JOB_TIMEOUT")
        time.sleep(poll)


def _profile_result(job: dict[str, Any]) -> dict[str, Any] | None:
    result = job.get("result")
    if not isinstance(result, dict):
        return None
    inner = result.get("result")
    return inner if isinstance(inner, dict) else None


def _persist_success(conn: psycopg.Connection, request_id: str, job: dict[str, Any]) -> None:
    profile = _profile_result(job)
    if profile is None:
        raise RuntimeError("HETZNER_API_RESULT_MISSING")
    completion = profile.get("runtime_completion") or {}
    transport_pass = completion.get("status") == "PASS"
    status = "SUCCEEDED" if transport_pass else "BLOCKED"
    codes = completion.get("blocking_codes") or []
    error_code = (
        None
        if transport_pass
        else (str(codes[0]) if codes else "HETZNER_RUNTIME_COMPLETION_FAILED")
    )
    receipt = completion.get("receipt") if isinstance(completion.get("receipt"), dict) else None
    attestation = None
    if receipt and isinstance(receipt.get("runtime_attestation"), dict):
        attestation = receipt["runtime_attestation"]
    model_id = attestation.get("model_id") if attestation else None

    with conn.cursor() as cur:
        cur.execute(
            f"""
            update {TABLE}
               set status=%s,
                   completed_at=now(),
                   updated_at=now(),
                   runtime_provider=%s,
                   runtime_model_id=%s,
                   result_package=%s,
                   raw_output=%s,
                   receipt=%s,
                   runtime_attestation=%s,
                   error_code=%s,
                   error_detail=%s
             where request_id=%s::uuid
               and status='RUNNING'
               and runtime_target='HETZNER'
            """,
            (
                status,
                PROVIDER,
                model_id,
                Jsonb(job),
                Jsonb(profile.get("raw_output")) if profile.get("raw_output") is not None else None,
                Jsonb(receipt) if receipt is not None else None,
                Jsonb(attestation) if attestation is not None else None,
                error_code,
                None,
                request_id,
            ),
        )
        if cur.rowcount != 1:
            conn.rollback()
            raise RuntimeError("HETZNER_QUEUE_PERSIST_TARGET_MISMATCH")
        conn.commit()


def _persist_failure(conn: psycopg.Connection, request_id: str, exc: BaseException) -> None:
    detail = f"{type(exc).__name__}:{str(exc)}"[:1500]
    with conn.cursor() as cur:
        cur.execute(
            f"""
            update {TABLE}
               set status='FAILED',
                   completed_at=now(),
                   updated_at=now(),
                   runtime_provider=%s,
                   error_code='HETZNER_QUEUE_WORKER_FAILED',
                   error_detail=%s
             where request_id=%s::uuid
               and status='RUNNING'
               and runtime_target='HETZNER'
            """,
            (PROVIDER, detail, request_id),
        )
        conn.commit()


def run_once() -> bool:
    conn = _connect()
    request_id: str | None = None
    try:
        claimed = _claim(conn)
        if claimed is None:
            return False
        request_id = claimed["request_id"]
        envelope = claimed.get("runtime_request_envelope")
        if envelope is not None:
            payload = _validate_envelope(request_id, envelope)
            endpoint = "/v1/profile/execute"
            route = "GOVERNED_ENVELOPE"
        else:
            payload = _queue_native_payload(claimed)
            endpoint = "/v1/profile/queue-execute"
            route = "QUEUE_NATIVE"
        accepted = _api_json("POST", endpoint, payload)
        job_id = accepted.get("job_id")
        if not isinstance(job_id, str) or not job_id:
            raise RuntimeError("HETZNER_API_JOB_ID_MISSING")
        job = _wait_job(job_id)
        _persist_success(conn, request_id, job)
        print(f"HETZNER_QUEUE_REQUEST_ID={request_id}")
        print(f"HETZNER_QUEUE_ROUTE={route}")
        print(f"HETZNER_QUEUE_JOB_ID={job_id}")
        print(f"HETZNER_QUEUE_STATUS={job.get('status')}")
        return True
    except Exception as exc:
        if request_id is not None:
            try:
                _persist_failure(conn, request_id, exc)
            except Exception:
                conn.rollback()
        print(f"HETZNER_QUEUE_ERROR={type(exc).__name__}:{str(exc)[:500]}", flush=True)
        return True
    finally:
        conn.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--idle-seconds", type=float, default=3.0)
    args = parser.parse_args()
    if not args.daemon:
        return 0 if run_once() else 4
    while True:
        did_work = run_once()
        if not did_work:
            time.sleep(max(0.5, args.idle_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
