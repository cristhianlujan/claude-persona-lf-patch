#!/usr/bin/env python3
"""Consume HETZNER profile-runtime rows and relay them to the local persistent API.

Routing modes:
- governed canonical screen requests: exact runtime_request_envelope -> /v1/profile/execute;
- governed non-canonical artifact sets: advisory read-only envelope -> /v1/profile/artifact-set-execute;
- normal text/profile queue requests: queue-native payload -> /v1/profile/queue-execute.

The worker never fabricates screen Input Governance, Card or image evidence. Image-bound work
without an explicit governed envelope remains ineligible for the queue-native route.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

try:
    from .runtime_envelope_materializer import materialize_router_advisory_envelope
except ImportError:  # direct script execution under systemd
    from runtime_envelope_materializer import materialize_router_advisory_envelope

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


def _reconcile_governed_pending(conn: psycopg.Connection) -> int:
    """Promote queue rows only after canonical governed execution closure proves PASS."""
    with conn.cursor() as cur:
        cur.execute(
            f"""
            select q.request_id::text,
                   e.execution_id,
                   e.status,
                   j.required_steps,
                   j.required_steps_pass,
                   j.fail_count,
                   j.blocked_count,
                   j.judge_result
              from {TABLE} q
              join public.lf_operation_execution e
                on e.execution_id='EXEC-PROFILE-RUNTIME-'||q.request_id::text
               and e.operation_code='EJECUCION_PERFIL_LF'
              left join public.v_lf_operation_execution_judge j
                on j.execution_id=e.execution_id
             where q.runtime_target='HETZNER'
               and q.status='BLOCKED'
               and q.error_code='HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING'
             order by q.updated_at, q.request_id
             limit 100
            """
        )
        rows = cur.fetchall()
        reconciled = 0
        for (
            request_id,
            execution_id,
            execution_status,
            required_steps,
            required_steps_pass,
            fail_count,
            blocked_count,
            judge_result,
        ) in rows:
            clean = (
                execution_status == "COMPLETED"
                and judge_result == "PASS"
                and isinstance(required_steps, int)
                and required_steps > 0
                and required_steps_pass == required_steps
                and fail_count == 0
                and blocked_count == 0
            )
            if clean:
                cur.execute(
                    f"""
                    update {TABLE}
                       set status='SUCCEEDED',
                           updated_at=now(),
                           error_code=null,
                           error_detail=null
                     where request_id=%s::uuid
                       and status='BLOCKED'
                       and error_code='HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING'
                    """,
                    (request_id,),
                )
                reconciled += cur.rowcount
            elif execution_status == "COMPLETED":
                cur.execute(
                    f"""
                    update {TABLE}
                       set updated_at=now(),
                           error_code='HETZNER_GOVERNED_TERMINAL_JUDGE_FAILED',
                           error_detail=%s
                     where request_id=%s::uuid
                       and status='BLOCKED'
                    """,
                    (
                        (
                            f"governed_execution={execution_id};"
                            f"judge_result={judge_result};required_steps={required_steps};"
                            f"required_steps_pass={required_steps_pass};fail_count={fail_count};"
                            f"blocked_count={blocked_count}"
                        )[:1500],
                        request_id,
                    ),
                )
        conn.commit()
        return reconciled


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
        envelope = payload["runtime_request_envelope"]
        if envelope is None:
            payload["lf_adapter_sources"] = _adapter_sources(cur, payload["profile_code"])
        elif isinstance(envelope, dict):
            if envelope.get("route_kind") == "QUEUE_NATIVE_RESEARCH":
                payload["lf_adapter_sources"] = _adapter_sources(cur, payload["profile_code"])
            else:
                governance = envelope.get("input_governance")
                if (
                    isinstance(governance, dict)
                    and governance.get("subject_mode") == "NON_CANONICAL_ARTIFACT"
                    and (governance.get("current") is not True or governance.get("ready") is not True)
                ):
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


def _canonical_json_sha256(value: Any) -> str:
    raw = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _governed_execution_id(request_id: str) -> str:
    if re.fullmatch(r"[0-9a-fA-F-]{36}", request_id or "") is None:
        raise RuntimeError("HETZNER_GOVERNED_REQUEST_ID_INVALID")
    return f"EXEC-PROFILE-RUNTIME-{request_id.lower()}"


def _profile_source_identity(claimed: dict[str, Any]) -> dict[str, Any]:
    profile_slug = str(claimed.get("profile_slug") or "")
    raw_paths = claimed.get("profile_source_paths")
    if not isinstance(raw_paths, list) or not raw_paths:
        raise RuntimeError("HETZNER_GOVERNED_PROFILE_SOURCE_PATHS_INVALID")
    manifest: list[dict[str, str]] = []
    for raw in raw_paths:
        if not isinstance(raw, str) or not raw:
            raise RuntimeError("HETZNER_GOVERNED_PROFILE_SOURCE_PATH_INVALID")
        rel = Path(raw)
        if rel.is_absolute() or ".." in rel.parts or not raw.startswith(f"profiles/{profile_slug}/"):
            raise RuntimeError(f"HETZNER_GOVERNED_PROFILE_SOURCE_PATH_ESCAPE:{raw}")
        path = (REPO_ROOT / rel).resolve()
        try:
            path.relative_to(REPO_ROOT.resolve())
        except ValueError as exc:
            raise RuntimeError("HETZNER_GOVERNED_PROFILE_SOURCE_PATH_ESCAPE") from exc
        if not path.is_file():
            raise RuntimeError(f"HETZNER_GOVERNED_PROFILE_SOURCE_MISSING:{raw}")
        content = path.read_text(encoding="utf-8")
        manifest.append({"ref": raw, "content_sha256": _sha256_text(content)})
    manifest.sort(key=lambda item: item["ref"])
    source_sha = _env("PROFILE_RUNTIME_SOURCE_SHA")
    if re.fullmatch(r"[0-9a-f]{40}", source_sha or "") is None:
        raise RuntimeError("HETZNER_GOVERNED_RUNTIME_SOURCE_SHA_INVALID")
    return {
        "source_revision": source_sha,
        "source_manifest": manifest,
        "profile_source_digest": "sha256:" + _canonical_json_sha256(manifest),
        "profile_source_ref": (
            f"github://cristhianlujan/claude-persona-lf-patch@{source_sha}/"
            f"profiles/{profile_slug}"
        ),
    }


def _fetch_json_scalar(cur: psycopg.Cursor, query: str, params: tuple[Any, ...]) -> dict[str, Any]:
    cur.execute(query, params)
    row = cur.fetchone()
    if row is None or not isinstance(row[0], dict):
        raise RuntimeError("HETZNER_GOVERNED_RPC_RESULT_INVALID")
    return dict(row[0])


def _record_governed_step(
    cur: psycopg.Cursor,
    *,
    execution_id: str,
    step_id: str,
    evidence_ref: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    existing = _read_governed_step(cur, execution_id, step_id)
    if existing is not None and existing.get("status") == "STEP_PASS_WITH_EVIDENCE":
        return {
            "outcome": "STEP_RECORDED",
            "replay": True,
            "step_id": step_id,
            "status": existing["status"],
        }
    result = _fetch_json_scalar(
        cur,
        "select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",
        (execution_id, step_id, evidence_ref, Jsonb(payload), execution_id),
    )
    if result.get("outcome") != "STEP_RECORDED":
        raise RuntimeError(
            f"HETZNER_GOVERNED_STEP_NOT_CLEAN:{step_id}:{result.get('code') or result.get('outcome')}"
        )
    return result


def _read_governed_step(
    cur: psycopg.Cursor, execution_id: str, step_id: str
) -> dict[str, Any] | None:
    cur.execute(
        """
        select status,evidence_ref,evidence_payload
          from public.lf_operation_execution_steps
         where execution_id=%s and step_id=%s
        """,
        (execution_id, step_id),
    )
    row = cur.fetchone()
    if row is None:
        return None
    return {
        "status": row[0],
        "evidence_ref": row[1],
        "evidence_payload": row[2] if isinstance(row[2], dict) else {},
    }


def _begin_governed_pre_model(
    conn: psycopg.Connection, claimed: dict[str, Any]
) -> dict[str, Any]:
    request_id = str(claimed["request_id"])
    execution_id = _governed_execution_id(request_id)
    source = _profile_source_identity(claimed)
    input_sha = _sha256_text(str(claimed["input_literal"]))
    input_digest = "sha256:" + input_sha
    request_sha = _canonical_json_sha256(
        {
            "input_sha256": input_sha,
            "profile_code": claimed["profile_code"],
            "profile_slug": claimed["profile_slug"],
            "profile_source_digest": source["profile_source_digest"],
            "profile_source_revision": source["source_revision"],
            "profile_source_paths": claimed["profile_source_paths"],
        }
    )
    target_path = str(claimed["profile_source_paths"][0])
    manifest = {
        "queue_request_id": request_id,
        "runtime_target": "HETZNER",
        "runtime_provider": PROVIDER,
        "runtime_source_revision": source["source_revision"],
        "input_sha256": input_digest,
        "profile_source_digest": source["profile_source_digest"],
        "read_only": True,
        "no_write": True,
        "no_promotion": True,
        "automatic_impact": False,
    }
    with conn.cursor() as cur:
        begun = _fetch_json_scalar(
            cur,
            "select public.lf_profile_execution_begin_v1(%s,%s,%s,%s,%s,%s,%s,%s)",
            (
                execution_id,
                f"profile-runtime-queue:{request_id}",
                request_sha,
                execution_id,
                claimed["profile_code"],
                "cristhianlujan/claude-persona-lf-patch",
                target_path,
                Jsonb(manifest),
            ),
        )
        if begun.get("result") not in {"RESERVED_NEW_EXECUTION", "REPLAY_EXISTING_EXECUTION"}:
            raise RuntimeError(
                f"HETZNER_GOVERNED_BEGIN_FAILED:{begun.get('result')}"
            )
        cur.execute(
            "select manifest from public.lf_operation_execution where execution_id=%s",
            (execution_id,),
        )
        execution_row = cur.fetchone()
        execution_manifest = (
            execution_row[0] if execution_row and isinstance(execution_row[0], dict) else {}
        )
        if not execution_manifest:
            raise RuntimeError("HETZNER_GOVERNED_EXECUTION_MANIFEST_MISSING")

        cur.execute(
            "select public.lf_router_resolve_v1(%s,%s,%s,%s,%s)",
            (
                claimed["input_literal"],
                claimed["profile_code"],
                "PROFILE_EXECUTION",
                "PERFIL",
                "ROUTER",
            ),
        )
        row = cur.fetchone()
        route = row[0] if row and isinstance(row[0], dict) else {}
        if (
            route.get("status") != "READY_TO_EXECUTE"
            or route.get("operation_code") != "EJECUCION_PERFIL_LF"
        ):
            raise RuntimeError("HETZNER_GOVERNED_ROUTER_NOT_READY")
        _record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="router",
            evidence_ref=f"supabase://public.lf_router_resolve_v1/{claimed['profile_code']}/PROFILE_EXECUTION",
            payload={"router_read": "READY_TO_EXECUTE", "action": "PROFILE_EXECUTION"},
        )

        cur.execute(
            """
            select codigo_activo,metadata->>'profile_slug',ruta_esperada
              from public.lf_activos
             where codigo_activo=%s and tipo_activo='PERFIL' and archived_at is null
             limit 1
            """,
            (claimed["profile_code"],),
        )
        asset = cur.fetchone()
        if asset is None or asset[1] != claimed["profile_slug"]:
            raise RuntimeError("HETZNER_GOVERNED_PROFILE_RESOLUTION_MISMATCH")
        _record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="profile_resolve",
            evidence_ref=f"supabase://public/lf_activos/{claimed['profile_code']}",
            payload={
                "exact_profile_resolved": True,
                "codigo_activo": claimed["profile_code"],
                "profile_slug": claimed["profile_slug"],
            },
        )
        _record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="profile_source_read",
            evidence_ref=source["profile_source_ref"],
            payload={
                "profile_source_ref": source["profile_source_ref"],
                "source_revision": source["source_revision"],
                "profile_source_digest": source["profile_source_digest"],
                "runtime_source_mode": "EXACT_DEPLOYED_GIT_REVISION",
            },
        )
        _record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="input_validate",
            evidence_ref=f"queue://private.lf_profile_runtime_queue_v1/{request_id}@{input_digest}",
            payload={
                "input_scope": f"QUEUE_REQUEST:{request_id}",
                "activation_trigger_match": True,
                "input_digest": input_digest,
                "read_only": True,
            },
        )

        context = _fetch_json_scalar(
            cur,
            "select public.lf_profile_execution_context_admission_v1(%s)",
            (execution_id,),
        )
        if context.get("status") != "READY" or context.get("server_validated") is not True:
            raise RuntimeError(
                f"HETZNER_GOVERNED_CONTEXT_NOT_READY:{context.get('blocking_code')}"
            )
        _record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="context_admission",
            evidence_ref=str(context["context_receipt_ref"]),
            payload=context,
        )

        existing_baseline = _read_governed_step(
            cur, execution_id, "research_baseline_freeze"
        )
        if (
            existing_baseline is not None
            and existing_baseline.get("status") == "STEP_PASS_WITH_EVIDENCE"
        ):
            baseline_first = {
                "outcome": "STEP_RECORDED",
                "replay": True,
                "status": existing_baseline["status"],
            }
        else:
            baseline_first = _fetch_json_scalar(
                cur,
                "select public.lf_profile_execution_research_baseline_v1(%s,%s,%s)",
                (execution_id, None, execution_id),
            )
    conn.commit()
    return {
        "execution_id": execution_id,
        "source": source,
        "input_digest": input_digest,
        "context": context,
        "baseline_first": baseline_first,
        "research_baseline_mode": execution_manifest.get("research_baseline_mode"),
        "research_baseline_contract": execution_manifest.get("research_baseline_contract"),
    }


def _persist_required_baseline(
    conn: psycopg.Connection,
    governed: dict[str, Any],
    baseline_envelope: dict[str, Any],
) -> dict[str, Any]:
    execution_id = governed["execution_id"]
    with conn.cursor() as cur:
        result = _fetch_json_scalar(
            cur,
            "select public.lf_profile_execution_research_baseline_v1(%s,%s,%s)",
            (execution_id, Jsonb(baseline_envelope), execution_id),
        )
        if result.get("outcome") != "STEP_RECORDED":
            raise RuntimeError(
                f"HETZNER_GOVERNED_BASELINE_PERSIST_FAILED:{result.get('code') or result.get('outcome')}"
            )
    conn.commit()
    return result


def _read_model_governance(
    conn: psycopg.Connection, governed: dict[str, Any]
) -> dict[str, Any]:
    execution_id = governed["execution_id"]
    with conn.cursor() as cur:
        context_step = _read_governed_step(cur, execution_id, "context_admission")
        baseline_step = _read_governed_step(cur, execution_id, "research_baseline_freeze")
    if context_step is None or baseline_step is None:
        raise RuntimeError("HETZNER_GOVERNED_PRE_MODEL_STEP_MISSING")
    context_payload = context_step["evidence_payload"]
    baseline_payload = baseline_step["evidence_payload"]
    binding = baseline_payload.get("research_baseline_binding")
    if not isinstance(binding, dict):
        raise RuntimeError("HETZNER_GOVERNED_BASELINE_BINDING_MISSING")
    applicability = binding.get("applicability")
    if applicability not in {"NOT_APPLICABLE", "REQUIRED"}:
        raise RuntimeError("HETZNER_GOVERNED_BASELINE_APPLICABILITY_INVALID")
    return {
        "execution_id": execution_id,
        "context_receipt_ref": context_payload.get("context_receipt_ref"),
        "context_receipt_digest": context_payload.get("context_receipt_digest"),
        "context_capsule": context_payload.get("context_capsule") or {},
        "research_baseline": {
            "applicability": applicability,
            "baseline_receipt_ref": baseline_payload.get("baseline_receipt_ref"),
            "baseline_digest": binding.get("baseline_digest"),
            "baseline_snapshot": binding.get("baseline_snapshot") or {},
            "research_baseline_contract": (
                governed.get("research_baseline_contract")
                if applicability == "REQUIRED"
                else None
            ),
        },
    }


def _baseline_api_payload(
    claimed: dict[str, Any], governed: dict[str, Any]
) -> dict[str, Any]:
    contract = governed.get("research_baseline_contract")
    if not isinstance(contract, dict):
        raise RuntimeError("HETZNER_GOVERNED_BASELINE_CONTRACT_MISSING")
    return {
        "request_id": str(claimed["request_id"]),
        "operation_code": "EJECUCION_PERFIL_LF",
        "profile_code": claimed["profile_code"],
        "profile_slug": claimed["profile_slug"],
        "profile_source_paths": claimed["profile_source_paths"],
        "input_literal": claimed["input_literal"],
        "input_digest": governed["input_digest"],
        "profile_source_digest": governed["source"]["profile_source_digest"],
        "research_baseline_contract": contract,
    }


def _baseline_envelope_from_job(job: dict[str, Any]) -> dict[str, Any]:
    result = _profile_result(job)
    if not isinstance(result, dict):
        raise RuntimeError("HETZNER_BASELINE_API_RESULT_MISSING")
    if result.get("status") != "PASS" or result.get("baseline_model_call_count") != 1:
        codes = _gate_blocking_codes(result)
        raise RuntimeError(
            "HETZNER_BASELINE_API_FAILED:"
            + (codes[0] if codes else str(result.get("status") or "UNKNOWN"))
        )
    envelope = result.get("baseline_envelope")
    if not isinstance(envelope, dict):
        raise RuntimeError("HETZNER_BASELINE_API_ENVELOPE_MISSING")
    return envelope



def _bind_external_authority_resolution(
    payload: dict[str, Any],
    model_governance: dict[str, Any],
    external_resolution: dict[str, Any] | None = None,
) -> dict[str, Any]:
    profile = payload.get("profile")
    if not isinstance(profile, dict):
        raise RuntimeError("HETZNER_GOVERNED_PROFILE_PAYLOAD_MISSING")
    if profile.get("profile_code") != "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF":
        return model_governance

    manifest = profile.get("evidence_manifest")
    if not isinstance(manifest, dict) or not manifest:
        raise RuntimeError("SRCR_EVIDENCE_MANIFEST_REQUIRED_BEFORE_MODEL")
    evidence = manifest.get("evidence")
    query_trace = manifest.get("query_trace")
    if not isinstance(evidence, list) or not evidence:
        raise RuntimeError("SRCR_EVIDENCE_MANIFEST_EMPTY_BEFORE_MODEL")
    if not isinstance(query_trace, list) or not query_trace:
        raise RuntimeError("SRCR_QUERY_TRACE_REQUIRED_BEFORE_MODEL")
    if (
        not isinstance(external_resolution, dict)
        or external_resolution.get("mode") != "EXTERNAL_AUTHORITY_RESOLVER"
    ):
        raise RuntimeError("SRCR_LIVE_RESEARCH_EXECUTION_PATH_MISSING")
    resolved = external_resolution.get("resolved_authority_context")
    if not isinstance(resolved, dict) or not resolved:
        raise RuntimeError("SRCR_RESOLVED_AUTHORITY_CONTEXT_REQUIRED")

    evidence_by_id: dict[str, dict[str, Any]] = {}
    for row in evidence:
        if not isinstance(row, dict):
            raise RuntimeError("SRCR_EVIDENCE_MANIFEST_ROW_INVALID")
        evidence_id = row.get("evidence_id")
        if not isinstance(evidence_id, str) or not evidence_id:
            raise RuntimeError("SRCR_EVIDENCE_MANIFEST_ID_INVALID")
        if evidence_id in evidence_by_id:
            raise RuntimeError("SRCR_EVIDENCE_MANIFEST_ID_DUPLICATE")
        evidence_by_id[evidence_id] = row
    if set(resolved) != set(evidence_by_id):
        raise RuntimeError("SRCR_RESOLVED_AUTHORITY_EVIDENCE_SET_MISMATCH")
    for evidence_id, evidence_row in evidence_by_id.items():
        resolved_row = resolved.get(evidence_id)
        if not isinstance(resolved_row, dict):
            raise RuntimeError(f"SRCR_RESOLVED_AUTHORITY_ROW_INVALID:{evidence_id}")
        if resolved_row.get("source_locator") != evidence_row.get("source_locator"):
            raise RuntimeError(f"SRCR_RESOLVED_AUTHORITY_LOCATOR_MISMATCH:{evidence_id}")
        if resolved_row.get("digest") != evidence_row.get("digest"):
            raise RuntimeError(f"SRCR_RESOLVED_AUTHORITY_DIGEST_MISMATCH:{evidence_id}")
        if "resolved_value" not in resolved_row:
            raise RuntimeError(f"SRCR_RESOLVED_AUTHORITY_VALUE_MISSING:{evidence_id}")

    bound = dict(model_governance)
    capsule = dict(bound.get("context_capsule") or {})
    capsule["research_execution_mode"] = "EXTERNAL_AUTHORITY_RESOLVER"
    capsule["resolved_authority_context"] = resolved
    capsule["evidence_manifest_sha256"] = "sha256:" + _canonical_json_sha256(manifest)
    capsule["query_trace_count"] = len(query_trace)
    capsule["evidence_count"] = len(evidence)
    capsule["resolved_authority_count"] = len(resolved)
    bound["context_capsule"] = capsule
    return bound


def _attach_governed_operation(
    payload: dict[str, Any], model_governance: dict[str, Any]
) -> dict[str, Any]:
    profile = payload.get("profile")
    if not isinstance(profile, dict):
        raise RuntimeError("HETZNER_GOVERNED_PROFILE_PAYLOAD_MISSING")
    external_resolution = payload.pop("_external_authority_resolution", None)
    profile["governed_operation"] = _bind_external_authority_resolution(
        payload, model_governance, external_resolution=external_resolution
    )
    return payload


def _record_post_model_governance(
    conn: psycopg.Connection,
    *,
    claimed: dict[str, Any],
    governed: dict[str, Any],
    job: dict[str, Any],
) -> dict[str, Any]:
    execution_id = governed["execution_id"]
    profile = _profile_result(job)
    if profile is None:
        return {"status": "BLOCKED", "error_code": "HETZNER_API_RESULT_MISSING"}
    completion = profile.get("runtime_completion")
    raw_output = profile.get("raw_output")
    if not isinstance(completion, dict) or completion.get("status") != "PASS":
        return {
            "status": "BLOCKED",
            "error_code": (_gate_blocking_codes(completion or {}) or ["HETZNER_RUNTIME_COMPLETION_FAILED"])[0],
        }
    if not isinstance(raw_output, str):
        return {"status": "BLOCKED", "error_code": "HETZNER_GOVERNED_RAW_OUTPUT_MISSING"}
    try:
        profile_output = json.loads(raw_output)
    except json.JSONDecodeError:
        return {"status": "BLOCKED", "error_code": "HETZNER_GOVERNED_RAW_OUTPUT_JSON_INVALID"}
    if not isinstance(profile_output, dict):
        return {"status": "BLOCKED", "error_code": "HETZNER_GOVERNED_RAW_OUTPUT_NOT_OBJECT"}

    model_governance = _read_model_governance(conn, governed)
    baseline = model_governance["research_baseline"]
    context_transport = {
        "profile_source_mode": "JIT_BY_REF",
        "jit_resolver_ref": "supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY",
        "jit_only": True,
        "policy_payloads": False,
        "full_ekb_entries": False,
        "full_readmes": False,
        "full_prefetch_count": 0,
        "hydrated_refs": [],
    }
    execute_payload = {
        "profile_output": profile_output,
        "source_refs": list(claimed["profile_source_paths"]),
        "context_receipt_ref": model_governance["context_receipt_ref"],
        "context_receipt_digest": model_governance["context_receipt_digest"],
        "context_transport": context_transport,
        "research_baseline_ref": baseline["baseline_receipt_ref"],
        "research_baseline_digest": baseline["baseline_digest"],
        "profile_source_digest": governed["source"]["profile_source_digest"],
        "profile_source_revision": governed["source"]["source_revision"],
        "producer_runtime": PROVIDER,
        "queue_request_id": str(claimed["request_id"]),
    }
    with conn.cursor() as cur:
        execute_result = _fetch_json_scalar(
            cur,
            "select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",
            (
                execution_id,
                "execute_profile",
                f"hetzner://profile-runtime/{claimed['request_id']}/execute",
                Jsonb(execute_payload),
                execution_id,
            ),
        )
        if execute_result.get("outcome") != "STEP_RECORDED":
            conn.commit()
            return {
                "status": "BLOCKED",
                "error_code": execute_result.get("code") or "HETZNER_GOVERNED_EXECUTE_STEP_NOT_CLEAN",
            }

        contract_gate = profile.get("profile_contract_valid")
        semantic_gate = profile.get("semantic_utility")
        canonical_quality = profile.get("canonical_quality")
        if isinstance(canonical_quality, dict) and canonical_quality.get("applicability") == "REQUIRED":
            if (
                canonical_quality.get("status") != "PENDING_INDEPENDENT_SEMANTIC_REVIEW"
                or canonical_quality.get("deterministic_floors_can_accept_quality") is not False
                or canonical_quality.get("receipt_required_for_pass_to_quality_pack") is not True
            ):
                conn.commit()
                return {
                    "status": "BLOCKED",
                    "error_code": "HETZNER_CANONICAL_QUALITY_BOUNDARY_INVALID",
                }
        contract_codes = _gate_blocking_codes(contract_gate if isinstance(contract_gate, dict) else {})
        output_payload = {
            "output_contract_result": (
                contract_gate.get("status") if isinstance(contract_gate, dict) else "MISSING"
            ),
            "deterministic_validation": {
                "profile_contract_valid": contract_gate,
                "runtime_semantic_utility": semantic_gate,
            },
            "canonical_quality": canonical_quality,
            "blocking_codes": contract_codes,
        }
        output_result = _fetch_json_scalar(
            cur,
            "select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",
            (
                execution_id,
                "output_validate",
                f"hetzner://profile-runtime/{claimed['request_id']}/output-validation",
                Jsonb(output_payload),
                execution_id,
            ),
        )
    conn.commit()
    if output_result.get("outcome") != "STEP_RECORDED":
        return {
            "status": "BLOCKED",
            "error_code": output_result.get("code") or "HETZNER_GOVERNED_OUTPUT_STEP_NOT_CLEAN",
        }
    return {
        "status": "READY_FOR_SEMANTIC_JUDGE",
        "error_code": None,
        "execution_id": execution_id,
        "next_gate": "semantic_judge",
        "semantic_judge_auto_recorded": False,
        "baseline_applicability": baseline["applicability"],
        "canonical_quality": canonical_quality,
    }


def _record_semantic_quality_result(
    conn: psycopg.Connection,
    *,
    execution_id: str,
    profile_code: str,
    semantic_execution_receipt_ref: str,
    semantic_result: dict[str, Any],
    finalize_result: dict[str, Any],
) -> dict[str, Any]:
    """Persist only a fully validated independent semantic PASS and canonical receipt.

    The independent semantic reviewer remains external to this worker. This function
    is the deterministic consumer after the review has been validated and the
    canonical quality receipt has been materialized.
    """
    if finalize_result.get("status") != "PASS":
        return {
            "status": "BLOCKED",
            "error_code": "CANONICAL_QUALITY_FINALIZE_NOT_PASS",
        }
    if _gate_blocking_codes(finalize_result):
        return {"status": "BLOCKED", "error_code": "CANONICAL_QUALITY_FINALIZE_HAS_BLOCKERS"}
    if finalize_result.get("canonical_quality_accepted") is not True:
        return {
            "status": "BLOCKED",
            "error_code": "CANONICAL_QUALITY_NOT_ACCEPTED",
        }
    receipt = finalize_result.get("quality_receipt")
    if not isinstance(receipt, dict):
        return {
            "status": "BLOCKED",
            "error_code": "CANONICAL_QUALITY_RECEIPT_MISSING",
        }
    if receipt.get("decision") != "PASS_TO_QUALITY_PACK":
        return {"status": "BLOCKED", "error_code": "CANONICAL_QUALITY_RECEIPT_NOT_PASS"}
    if _gate_blocking_codes(semantic_result):
        return {"status": "BLOCKED", "error_code": "SEMANTIC_REVIEW_HAS_BLOCKERS"}
    unsupported_claims = semantic_result.get("unsupported_claims")
    if unsupported_claims is None:
        unsupported_claims = []
    if not isinstance(unsupported_claims, list) or unsupported_claims:
        return {
            "status": "BLOCKED",
            "error_code": "SEMANTIC_REVIEW_UNSUPPORTED_CLAIMS_PRESENT",
        }
    if semantic_result.get("verdict") != "PASS_INDEPENDENT_SEMANTIC":
        return {
            "status": "BLOCKED",
            "error_code": "SEMANTIC_REVIEW_VERDICT_NOT_PASS",
        }

    semantic_payload = {
        "semantic_judge_result": {
            "status": "PASS",
            "verdict": semantic_result.get("verdict"),
            "candidate_sha256": semantic_result.get("candidate_sha256"),
            "scope_packet_sha256": semantic_result.get("scope_packet_sha256"),
            "canonical_quality_accepted": True,
            "quality_receipt": receipt,
        },
        "unsupported_claims": [],
    }
    with conn.cursor() as cur:
        semantic_step = _fetch_json_scalar(
            cur,
            "select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",
            (
                execution_id,
                "semantic_judge",
                semantic_execution_receipt_ref,
                Jsonb(semantic_payload),
                execution_id,
            ),
        )
        if semantic_step.get("outcome") != "STEP_RECORDED":
            conn.commit()
            return {
                "status": "BLOCKED",
                "error_code": semantic_step.get("code")
                or "SEMANTIC_JUDGE_STEP_NOT_CLEAN",
            }

        report_payload = {
            "result": "PASS_TO_QUALITY_PACK",
            "profile_code": profile_code,
            "execution_id": execution_id,
            "no_write_performed": True,
            "canonical_quality_accepted": True,
            "quality_receipt": receipt,
        }
        report_step = _fetch_json_scalar(
            cur,
            "select public.lf_record_profile_execution_step_v1(%s,%s,%s,%s,%s)",
            (
                execution_id,
                "report_output",
                f"{semantic_execution_receipt_ref}#quality-report",
                Jsonb(report_payload),
                execution_id,
            ),
        )
    conn.commit()
    if report_step.get("outcome") != "STEP_RECORDED":
        return {
            "status": "BLOCKED",
            "error_code": report_step.get("code") or "REPORT_OUTPUT_STEP_NOT_CLEAN",
        }
    return {
        "status": "COMPLETED",
        "error_code": None,
        "execution_id": execution_id,
        "canonical_quality_accepted": True,
        "quality_receipt": receipt,
    }


def finalize_semantic_quality_review(
    conn: psycopg.Connection, review_request: dict[str, Any]
) -> dict[str, Any]:
    """Consume an external review through the pure API and the existing recorder.

    No model is called here. The producer candidate must already be persisted by
    EJECUCION_PERFIL_LF; an arbitrary candidate cannot finalize another execution.
    """
    execution_id = review_request.get("producer_execution_id")
    if not isinstance(execution_id, str) or not execution_id:
        return {"status": "BLOCKED", "error_code": "SEMANTIC_REVIEW_PRODUCER_REQUIRED"}
    with conn.cursor() as cur:
        producer = _read_governed_step(cur, execution_id, "execute_profile")
        output = _read_governed_step(cur, execution_id, "output_validate")
    if (
        not isinstance(producer, dict)
        or not isinstance(output, dict)
        or producer.get("status") != "STEP_PASS_WITH_EVIDENCE"
        or output.get("status") != "STEP_PASS_WITH_EVIDENCE"
    ):
        return {"status": "BLOCKED", "error_code": "SEMANTIC_REVIEW_PREDECESSORS_NOT_CLEAN"}
    if (
        producer.get("evidence_ref") != review_request.get("producer_execution_receipt_ref")
        or producer.get("evidence_payload", {}).get("profile_output") != review_request.get("candidate")
    ):
        return {"status": "BLOCKED", "error_code": "SEMANTIC_REVIEW_PRODUCER_READBACK_MISMATCH"}

    response = _api_json("POST", "/v1/profile/semantic-quality-finalize", review_request)
    if (
        response.get("kind") != "semantic_quality_finalize"
        or any(response.get(key) != review_request.get(key) for key in ("request_id", "profile_code", "profile_slug"))
        or not isinstance(response.get("result"), dict)
    ):
        return {"status": "BLOCKED", "error_code": "SEMANTIC_QUALITY_API_RESPONSE_MISMATCH"}
    result = response["result"]
    if result.get("status") != "PASS" or result.get("canonical_quality_accepted") is not True:
        return {
            "status": "BLOCKED",
            "error_code": "CANONICAL_QUALITY_NOT_ACCEPTED",
            "finalization": result,
        }
    # Reuse the same recorder path; no direct step-state writes or second judge.
    recorded = _record_semantic_quality_result(
        conn,
        execution_id=execution_id,
        profile_code=review_request["profile_code"],
        semantic_execution_receipt_ref=review_request["semantic_execution_receipt_ref"],
        semantic_result=review_request["semantic_result"],
        finalize_result=result,
    )
    if recorded.get("status") != "COMPLETED":
        return recorded
    with conn.cursor() as cur:
        semantic = _read_governed_step(cur, execution_id, "semantic_judge")
        report = _read_governed_step(cur, execution_id, "report_output")
    expected_receipt = result["quality_receipt"]
    if (
        not isinstance(semantic, dict)
        or not isinstance(report, dict)
        or semantic.get("status") != "STEP_PASS_WITH_EVIDENCE"
        or report.get("status") != "STEP_PASS_WITH_EVIDENCE"
        or semantic.get("evidence_ref") != review_request["semantic_execution_receipt_ref"]
        or semantic.get("evidence_payload", {}).get("semantic_judge_result", {}).get("quality_receipt") != expected_receipt
        or report.get("evidence_payload", {}).get("quality_receipt") != expected_receipt
    ):
        return {"status": "BLOCKED", "error_code": "SEMANTIC_QUALITY_PERSISTENCE_READBACK_MISMATCH"}
    return {**recorded, "persistence_readback": "PASS", "downstream_authorized": False}


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

    has_artifact = "artifact" in envelope
    has_artifact_set = "artifact_set" in envelope
    if has_artifact == has_artifact_set:
        raise RuntimeError("HETZNER_ARTIFACT_ENVELOPE_MODE_AMBIGUOUS")

    if has_artifact_set:
        if governance.get("subject_mode") != "NON_CANONICAL_ARTIFACT":
            raise RuntimeError("HETZNER_NONCANONICAL_SUBJECT_MODE_MISMATCH")
        if governance.get("status") != "ADVISORY_READ_ONLY" or governance.get("decision") != "ADVISORY":
            raise RuntimeError("HETZNER_NONCANONICAL_GOVERNANCE_NOT_ADVISORY")
        if governance.get("canonical_receipt") is not None:
            raise RuntimeError("HETZNER_NONCANONICAL_CANONICAL_RECEIPT_FORBIDDEN")
        required_artifact_binding = governance.get("required_artifact_binding") or []
        if (
            not isinstance(required_artifact_binding, list)
            or len(required_artifact_binding) != 3
            or set(required_artifact_binding)
            != {"artifact_ref", "artifact_sha256", "dimensions"}
        ):
            raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_BINDING_INCOMPLETE")
        constraints = governance.get("constraints")
        if not isinstance(constraints, dict):
            raise RuntimeError("HETZNER_NONCANONICAL_CONSTRAINTS_MISSING")
        required_constraints = {
            "operation_must_equal": "EJECUCION_PERFIL_LF",
            "read_only": True,
            "no_write": True,
            "no_promotion": True,
            "canonical_registration_required": False,
            "artifact_binding_required_before_profile_execution": True,
        }
        if any(constraints.get(key) != value for key, value in required_constraints.items()):
            raise RuntimeError("HETZNER_NONCANONICAL_CONSTRAINTS_INVALID")

        artifact_set = envelope["artifact_set"]
        if not isinstance(artifact_set, dict):
            raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_SET_INVALID")
        if (
            artifact_set.get("schema") != "NON_CANONICAL_ARTIFACT_SET_V1"
            or artifact_set.get("subject_mode") != "NON_CANONICAL_ARTIFACT"
        ):
            raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_SET_CONTRACT_INVALID")
        items = artifact_set.get("artifacts")
        if not isinstance(items, list) or not 1 <= len(items) <= 8:
            raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_SET_SIZE_INVALID")
        refs: set[str] = set()
        shas: set[str] = set()
        for item in items:
            if not isinstance(item, dict):
                raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_ITEM_INVALID")
            ref = item.get("artifact_ref")
            artifact = item.get("artifact")
            if not isinstance(ref, str) or not ref or not isinstance(artifact, dict):
                raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_BINDING_MISSING")
            sha = artifact.get("image_sha256")
            width = artifact.get("width_px")
            height = artifact.get("height_px")
            if not isinstance(sha, str) or re.fullmatch(r"[0-9a-f]{64}", sha) is None:
                raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_SHA256_MISSING")
            if not isinstance(width, int) or width <= 0 or not isinstance(height, int) or height <= 0:
                raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_DIMENSIONS_INVALID")
            if ref in refs:
                raise RuntimeError(f"HETZNER_NONCANONICAL_ARTIFACT_REF_DUPLICATE:{ref}")
            if sha in shas:
                raise RuntimeError(f"HETZNER_NONCANONICAL_ARTIFACT_SHA256_DUPLICATE:{sha}")
            refs.add(ref)
            shas.add(sha)
        if profile.get("send_image_to_model") is True:
            raise RuntimeError("HETZNER_NONCANONICAL_ARTIFACT_SET_FULL_IMAGE_MODEL_UNSUPPORTED")
    else:
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
        artifact = envelope["artifact"]
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
    profile = {
        "request_id": claimed["request_id"],
        "operation_code": claimed["operation_code"],
        "profile_code": claimed["profile_code"],
        "profile_slug": claimed["profile_slug"],
        "profile_source_paths": claimed["profile_source_paths"],
        "input_literal": claimed["input_literal"],
        "lf_adapter_sources": claimed.get("lf_adapter_sources") or [],
        "send_image_to_model": False,
    }
    payload: dict[str, Any] = {"profile": profile}
    envelope = claimed.get("runtime_request_envelope")
    if isinstance(envelope, dict) and envelope.get("route_kind") == "QUEUE_NATIVE_RESEARCH":
        if envelope.get("schema") != "LF_PROFILE_RUNTIME_QUEUE_RESEARCH_V1":
            raise RuntimeError("SRCR_RESEARCH_QUEUE_ENVELOPE_SCHEMA_INVALID")
        if envelope.get("research_execution_mode") != "EXTERNAL_AUTHORITY_RESOLVER":
            raise RuntimeError("SRCR_LIVE_RESEARCH_EXECUTION_PATH_MISSING")
        manifest = envelope.get("evidence_manifest")
        resolved = envelope.get("resolved_authority_context")
        if not isinstance(manifest, dict) or not manifest:
            raise RuntimeError("SRCR_EVIDENCE_MANIFEST_REQUIRED_BEFORE_MODEL")
        if not isinstance(resolved, dict) or not resolved:
            raise RuntimeError("SRCR_RESOLVED_AUTHORITY_CONTEXT_REQUIRED")
        if len(json.dumps(resolved, ensure_ascii=False)) > 120_000:
            raise RuntimeError("SRCR_RESOLVED_AUTHORITY_CONTEXT_BUDGET_EXCEEDED")
        profile["evidence_manifest"] = manifest
        payload["_external_authority_resolution"] = {
            "mode": "EXTERNAL_AUTHORITY_RESOLVER",
            "resolved_authority_context": resolved,
        }
    return payload


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


def _gate_blocking_codes(gate: dict[str, Any]) -> list[str]:
    raw = gate.get("blocking_codes")
    if raw is None:
        return []
    if not isinstance(raw, list):
        return ["HETZNER_GATE_BLOCKING_CODES_INVALID"]
    return sorted({str(code) for code in raw if str(code).strip()})


def _execution_queue_outcome(profile: dict[str, Any]) -> dict[str, str | None]:
    """Project runtime + contract + deterministic utility into the queue terminal state.

    `runtime_completion=PASS` proves transport/model/attestation only. A queue row may be
    `SUCCEEDED` only when the canonical contract is also clean and any bound deterministic
    semantic utility floor is clean. Profiles without a bound utility policy remain compatible
    only through the explicit `NO_PROFILE_UTILITY_POLICY` sentinel.
    """
    gate_specs = (
        ("runtime_completion", "HETZNER_RUNTIME_COMPLETION_FAILED"),
        ("profile_contract_valid", "HETZNER_PROFILE_CONTRACT_FAILED"),
    )
    for gate_name, fallback_code in gate_specs:
        gate = profile.get(gate_name)
        if not isinstance(gate, dict):
            return {
                "status": "BLOCKED",
                "error_code": f"{fallback_code}_MISSING",
                "error_detail": f"gate={gate_name};gate_status=MISSING",
            }
        codes = _gate_blocking_codes(gate)
        if gate.get("status") != "PASS" or codes:
            return {
                "status": "BLOCKED",
                "error_code": codes[0] if codes else fallback_code,
                "error_detail": (
                    f"gate={gate_name};gate_status={gate.get('status')};"
                    f"blocking_codes={','.join(codes[:8])}"
                ),
            }

    semantic = profile.get("semantic_utility")
    if not isinstance(semantic, dict):
        return {
            "status": "BLOCKED",
            "error_code": "HETZNER_SEMANTIC_UTILITY_MISSING",
            "error_detail": "gate=semantic_utility;gate_status=MISSING",
        }
    semantic_codes = _gate_blocking_codes(semantic)
    semantic_status = semantic.get("status")
    explicit_unbound = (
        semantic_status == "NOT_EVALUATED"
        and semantic.get("evaluation_scope") == "NO_PROFILE_UTILITY_POLICY"
        and semantic_codes == ["SEMANTIC_UTILITY_POLICY_NOT_BOUND"]
    )
    if not (semantic_status == "PASS" and not semantic_codes) and not explicit_unbound:
        return {
            "status": "BLOCKED",
            "error_code": (
                semantic_codes[0] if semantic_codes else "HETZNER_SEMANTIC_UTILITY_FAILED"
            ),
            "error_detail": (
                f"gate=semantic_utility;gate_status={semantic_status};"
                f"blocking_codes={','.join(semantic_codes[:8])}"
            ),
        }
    return {"status": "SUCCEEDED", "error_code": None, "error_detail": None}


def _persist_success(
    conn: psycopg.Connection,
    request_id: str,
    job: dict[str, Any],
    *,
    claimed: dict[str, Any],
    governed: dict[str, Any],
) -> None:
    profile = _profile_result(job)
    if profile is None:
        raise RuntimeError("HETZNER_API_RESULT_MISSING")
    completion = profile.get("runtime_completion") or {}
    runtime_outcome = _execution_queue_outcome(profile)
    governed_outcome = _record_post_model_governance(
        conn, claimed=claimed, governed=governed, job=job
    )
    profile["governed_operation"] = governed_outcome
    governed_status = governed_outcome.get("status")
    if governed_status == "BLOCKED":
        status = "BLOCKED"
        error_code = governed_outcome.get("error_code") or "HETZNER_GOVERNED_OPERATION_BLOCKED"
        error_detail = (
            f"governed_execution={governed.get('execution_id')};"
            f"next_gate={governed_outcome.get('next_gate')};"
            f"runtime_status={runtime_outcome.get('status')}"
        )
    elif governed_status == "READY_FOR_SEMANTIC_JUDGE":
        status = "BLOCKED"
        if runtime_outcome.get("status") == "SUCCEEDED":
            error_code = "HETZNER_GOVERNED_SEMANTIC_JUDGE_PENDING"
            error_detail = (
                f"governed_execution={governed.get('execution_id')};"
                "next_gate=semantic_judge;"
                "runtime_status=SUCCEEDED"
            )
        else:
            error_code = runtime_outcome.get("error_code") or "HETZNER_RUNTIME_GATES_NOT_CLEAN"
            error_detail = runtime_outcome.get("error_detail") or (
                f"governed_execution={governed.get('execution_id')};"
                f"runtime_status={runtime_outcome.get('status')}"
            )
    elif governed_status == "COMPLETED":
        status = str(runtime_outcome["status"])
        error_code = runtime_outcome["error_code"]
        error_detail = runtime_outcome["error_detail"]
    else:
        status = "BLOCKED"
        error_code = "HETZNER_GOVERNED_OPERATION_STATE_INVALID"
        error_detail = (
            f"governed_execution={governed.get('execution_id')};"
            f"governed_status={governed_status};"
            f"runtime_status={runtime_outcome.get('status')}"
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
                error_detail,
                request_id,
            ),
        )
        if cur.rowcount != 1:
            conn.rollback()
            raise RuntimeError("HETZNER_QUEUE_PERSIST_TARGET_MISMATCH")
        conn.commit()


def _reconcile_queue_terminal(
    cur: psycopg.Cursor, request_id: str
) -> dict[str, Any]:
    """Reconcile an auxiliary queue terminal state to the exact canonical execution."""
    return _fetch_json_scalar(
        cur,
        "select public.lf_profile_execution_reconcile_queue_terminal_v1(%s::uuid,%s)",
        (request_id, _governed_execution_id(request_id)),
    )


def _persist_failure(
    conn: psycopg.Connection, request_id: str, exc: BaseException
) -> dict[str, Any]:
    raw = str(exc)
    candidate = raw.split(":", 1)[0]
    error_code = (
        candidate
        if re.fullmatch(r"[A-Z0-9][A-Z0-9_-]{2,119}", candidate or "")
        else "HETZNER_QUEUE_WORKER_FAILED"
    )
    detail = f"{type(exc).__name__}:{raw}"[:1500]
    with conn.cursor() as cur:
        cur.execute(
            f"""
            update {TABLE}
               set status='FAILED',
                   completed_at=now(),
                   updated_at=now(),
                   runtime_provider=%s,
                   error_code=%s,
                   error_detail=%s
             where request_id=%s::uuid
               and status='RUNNING'
               and runtime_target='HETZNER'
            """,
            (PROVIDER, error_code, detail, request_id),
        )
        if cur.rowcount != 1:
            conn.commit()
            return {
                "result": "QUEUE_FAILURE_NOT_PERSISTED",
                "blocking_code": "PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED",
            }

        terminal = _reconcile_queue_terminal(cur, request_id)
        terminal_result = terminal.get("result")
        accepted = {
            "CANONICAL_TERMINAL_RECONCILED",
            "TERMINAL_PAIR_ALREADY_RECONCILED",
            "NO_CANONICAL_EXECUTION",
        }
        if terminal_result not in accepted:
            detail_with_terminal = (
                f"{detail};terminal_reconciliation={terminal_result or 'UNKNOWN'};"
                f"terminal_blocking_code={terminal.get('blocking_code') or 'PROFILE_EXECUTION_TERMINALITY_RECONCILIATION_FAILED'}"
            )[:1500]
            cur.execute(
                f"""
                update {TABLE}
                   set error_detail=%s,
                       updated_at=now()
                 where request_id=%s::uuid
                   and status='FAILED'
                   and runtime_target='HETZNER'
                """,
                (detail_with_terminal, request_id),
            )
        conn.commit()
        return terminal


def run_once() -> bool:
    conn = _connect()
    request_id: str | None = None
    try:
        _reconcile_governed_pending(conn)
        claimed = _claim(conn)
        if claimed is None:
            return False
        request_id = claimed["request_id"]
        governed = _begin_governed_pre_model(conn, claimed)
        baseline_first = governed.get("baseline_first") or {}
        if baseline_first.get("outcome") == "BASELINE_REQUIRED":
            baseline_accepted = _api_json(
                "POST", "/v1/profile/research-baseline", _baseline_api_payload(claimed, governed)
            )
            baseline_job_id = baseline_accepted.get("job_id")
            if not isinstance(baseline_job_id, str) or not baseline_job_id:
                raise RuntimeError("HETZNER_BASELINE_API_JOB_ID_MISSING")
            baseline_job = _wait_job(baseline_job_id)
            baseline_envelope = _baseline_envelope_from_job(baseline_job)
            _persist_required_baseline(conn, governed, baseline_envelope)
        elif baseline_first.get("outcome") != "STEP_RECORDED":
            raise RuntimeError(
                "HETZNER_GOVERNED_BASELINE_HANDSHAKE_INVALID:"
                + str(baseline_first.get("outcome") or baseline_first.get("code") or "UNKNOWN")
            )

        model_governance = _read_model_governance(conn, governed)
        envelope = claimed.get("runtime_request_envelope")
        if isinstance(envelope, dict) and envelope.get("route_kind") == "QUEUE_NATIVE_RESEARCH":
            payload = _queue_native_payload(claimed)
            endpoint = "/v1/profile/queue-execute"
            route = "QUEUE_NATIVE_RESEARCH"
        elif envelope is not None:
            envelope = materialize_router_advisory_envelope(
                request_id,
                envelope,
                live_adapter_sources=claimed.get("lf_adapter_sources") or [],
            )
            payload = _validate_envelope(request_id, envelope)
            if "artifact_set" in payload:
                endpoint = "/v1/profile/artifact-set-execute"
                route = "GOVERNED_NONCANONICAL_ARTIFACT_SET"
            else:
                endpoint = "/v1/profile/execute"
                route = "GOVERNED_ENVELOPE"
        else:
            payload = _queue_native_payload(claimed)
            endpoint = "/v1/profile/queue-execute"
            route = "QUEUE_NATIVE"
        payload = _attach_governed_operation(payload, model_governance)
        accepted = _api_json("POST", endpoint, payload)
        job_id = accepted.get("job_id")
        if not isinstance(job_id, str) or not job_id:
            raise RuntimeError("HETZNER_API_JOB_ID_MISSING")
        job = _wait_job(job_id)
        _persist_success(conn, request_id, job, claimed=claimed, governed=governed)
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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--daemon", action="store_true")
    mode.add_argument("--semantic-review", type=Path, help="Consume an independently produced SemanticQualityFinalizeRequest JSON")
    parser.add_argument("--idle-seconds", type=float, default=3.0)
    args = parser.parse_args()
    if args.semantic_review is not None:
        request = json.loads(args.semantic_review.read_text(encoding="utf-8"))
        if not isinstance(request, dict):
            raise SystemExit("SEMANTIC_REVIEW_REQUEST_NOT_OBJECT")
        conn = _connect()
        try:
            result = finalize_semantic_quality_review(conn, request)
            print(json.dumps(result, ensure_ascii=False))
            return 0 if result.get("status") == "COMPLETED" else 1
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()
    if not args.daemon:
        return 0 if run_once() else 4
    while True:
        did_work = run_once()
        if not did_work:
            time.sleep(max(0.5, args.idle_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
