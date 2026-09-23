#!/usr/bin/env python3
"""Execution-only facade for the Hetzner profile queue worker.

ACT-0001 routing is frozen upstream at queue ingress. This active worker verifies
that immutable envelope, materializes only the exact adapter capsule refs already
resolved by the Router, and owns its runtime control flow directly.

The historical worker is imported only as an allowlisted implementation library for
transport/model/evidence helpers. Its claim, Router resolution, adapter discovery,
profile discovery, run_once and main control flow are never called or monkeypatched.
"""
from __future__ import annotations

import argparse
import json
import re
import time
from pathlib import Path
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

import hetzner_queue_worker as legacy

try:
    from .runtime_envelope_materializer import materialize_router_advisory_envelope
except ImportError:  # direct script execution under systemd
    from runtime_envelope_materializer import materialize_router_advisory_envelope

TABLE = legacy.TABLE
PROVIDER = legacy.PROVIDER
REPO_ROOT = legacy.REPO_ROOT
MAX_RESOLVED_ADAPTERS = 4


def _verify_router_envelope(claimed: dict[str, Any]) -> dict[str, Any]:
    envelope = claimed.get("router_execution_envelope")
    expected_sha = claimed.get("router_execution_envelope_sha256")
    observed_sha = claimed.get("router_execution_envelope_observed_sha256")
    if not isinstance(envelope, dict):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_MISSING")
    if envelope.get("schema") != "LF_ROUTER_EXECUTION_ENVELOPE_V1":
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_SCHEMA_INVALID")
    if envelope.get("activation_source") != "ROUTER" or envelope.get("router") != "ACT-0001":
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_AUTHORITY_INVALID")
    if envelope.get("operation_code") != "EJECUCION_PERFIL_LF":
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_OPERATION_INVALID")
    if not isinstance(expected_sha, str) or re.fullmatch(r"sha256:[0-9a-f]{64}", expected_sha) is None:
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_DIGEST_INVALID")
    if observed_sha != expected_sha:
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_DIGEST_MISMATCH")

    target = envelope.get("target")
    if not isinstance(target, dict):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ENVELOPE_TARGET_INVALID")
    if target.get("profile_code") != claimed.get("profile_code"):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_PROFILE_CODE_MISMATCH")
    if target.get("profile_slug") != claimed.get("profile_slug"):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_PROFILE_SLUG_MISMATCH")
    if target.get("profile_source_paths") != claimed.get("profile_source_paths"):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_PROFILE_SOURCES_MISMATCH")

    route = envelope.get("route")
    if not isinstance(route, dict):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ROUTE_MISSING")
    if (
        route.get("status") != "READY_TO_EXECUTE"
        or route.get("router") != "ACT-0001"
        or route.get("operation_code") != "EJECUCION_PERFIL_LF"
        or route.get("downstream_execution_allowed") is not True
    ):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ROUTE_NOT_READY")
    asset = route.get("asset")
    if not isinstance(asset, dict) or asset.get("codigo_activo") != claimed.get("profile_code"):
        raise RuntimeError("HETZNER_ROUTER_EXECUTION_ASSET_MISMATCH")
    return envelope


def _materialize_resolved_adapter_sources(envelope: dict[str, Any]) -> list[dict[str, Any]]:
    bindings = envelope.get("resolved_runtime_adapters")
    if not isinstance(bindings, list):
        raise RuntimeError("HETZNER_RESOLVED_ADAPTER_BINDINGS_INVALID")
    if len(bindings) > MAX_RESOLVED_ADAPTERS:
        raise RuntimeError(f"HETZNER_RESOLVED_ADAPTER_BINDING_COUNT_EXCEEDED:{len(bindings)}")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in bindings:
        if not isinstance(item, dict):
            raise RuntimeError("HETZNER_RESOLVED_ADAPTER_BINDING_INVALID")
        required = (
            item.get("adapter_code"),
            item.get("adapter_version"),
            item.get("assurance_revision"),
            item.get("binding_ref"),
            item.get("target_ref"),
            item.get("ref"),
        )
        if not all(isinstance(v, str) and v.strip() for v in required):
            raise RuntimeError("HETZNER_RESOLVED_ADAPTER_BINDING_INCOMPLETE")
        if item.get("activation_source") != "ROUTER":
            raise RuntimeError("HETZNER_RESOLVED_ADAPTER_BINDING_AUTHORITY_INVALID")
        code = str(item["adapter_code"])
        if code in seen:
            raise RuntimeError(f"HETZNER_RESOLVED_ADAPTER_BINDING_DUPLICATE:{code}")
        seen.add(code)
        relative = Path(str(item["ref"]))
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError("HETZNER_RESOLVED_ADAPTER_CAPSULE_PATH_INVALID")
        path = (REPO_ROOT / relative).resolve()
        try:
            path.relative_to(REPO_ROOT.resolve())
        except ValueError as exc:
            raise RuntimeError("HETZNER_RESOLVED_ADAPTER_CAPSULE_PATH_ESCAPE") from exc
        if not path.is_file():
            raise RuntimeError(f"HETZNER_RESOLVED_ADAPTER_CAPSULE_MISSING:{item['ref']}")
        content = path.read_text(encoding="utf-8").strip()
        if not content or len(content) > 2000:
            raise RuntimeError(f"HETZNER_RESOLVED_ADAPTER_CAPSULE_BUDGET_INVALID:{len(content)}")
        result.append({**item, "content": content})
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
                   q.runtime_request_envelope,
                   q.router_execution_envelope,
                   q.router_execution_envelope_sha256,
                   'sha256:' || encode(
                     extensions.digest(
                       convert_to(q.router_execution_envelope::text,'UTF8'),
                       'sha256'
                     ),
                     'hex'
                   ) as router_execution_envelope_observed_sha256
            """,
            (PROVIDER,),
        )
        row = cur.fetchone()
        if row is None:
            conn.rollback()
            return None
        cols = [d.name for d in cur.description]
        claimed = dict(zip(cols, row))
        envelope = _verify_router_envelope(claimed)
        claimed["lf_adapter_sources"] = _materialize_resolved_adapter_sources(envelope)
        conn.commit()
        return claimed


def _begin_governed_pre_model(
    conn: psycopg.Connection,
    claimed: dict[str, Any],
) -> dict[str, Any]:
    router_envelope = _verify_router_envelope(claimed)
    request_id = str(claimed["request_id"])
    execution_id = legacy._governed_execution_id(request_id)
    source = legacy._profile_source_identity(claimed)
    input_sha = legacy._sha256_text(str(claimed["input_literal"]))
    input_digest = "sha256:" + input_sha
    request_sha = legacy._canonical_json_sha256(
        {
            "input_sha256": input_sha,
            "profile_code": claimed["profile_code"],
            "profile_slug": claimed["profile_slug"],
            "profile_source_digest": source["profile_source_digest"],
            "profile_source_revision": source["source_revision"],
            "profile_source_paths": claimed["profile_source_paths"],
            "router_execution_envelope_sha256": claimed["router_execution_envelope_sha256"],
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
        "router_execution_envelope": router_envelope,
        "router_execution_envelope_sha256": claimed["router_execution_envelope_sha256"],
        "read_only": True,
        "no_write": True,
        "no_promotion": True,
        "automatic_impact": False,
    }
    with conn.cursor() as cur:
        begun = legacy._fetch_json_scalar(
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
            raise RuntimeError(f"HETZNER_GOVERNED_BEGIN_FAILED:{begun.get('result')}")
        cur.execute(
            "select manifest from public.lf_operation_execution where execution_id=%s",
            (execution_id,),
        )
        row = cur.fetchone()
        execution_manifest = row[0] if row and isinstance(row[0], dict) else {}
        if execution_manifest.get("router_execution_envelope_sha256") != claimed["router_execution_envelope_sha256"]:
            raise RuntimeError("HETZNER_GOVERNED_ROUTER_ENVELOPE_MANIFEST_MISMATCH")

        legacy._record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="router",
            evidence_ref=f"router://ACT-0001/frozen/{request_id}",
            payload={
                "router_read": "READY_TO_EXECUTE",
                "action": "PROFILE_EXECUTION",
                "router_execution_envelope_sha256": claimed["router_execution_envelope_sha256"],
                "activation_source": "ROUTER",
            },
        )
        legacy._record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="profile_resolve",
            evidence_ref=f"router://ACT-0001/frozen/{request_id}#target",
            payload={
                "exact_profile_resolved": True,
                "codigo_activo": claimed["profile_code"],
                "profile_slug": claimed["profile_slug"],
                "router_execution_envelope_sha256": claimed["router_execution_envelope_sha256"],
            },
        )
        legacy._record_governed_step(
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
        legacy._record_governed_step(
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

        context = legacy._fetch_json_scalar(
            cur,
            "select public.lf_profile_execution_context_admission_v1(%s)",
            (execution_id,),
        )
        if context.get("status") != "READY" or context.get("server_validated") is not True:
            raise RuntimeError(
                f"HETZNER_GOVERNED_CONTEXT_NOT_READY:{context.get('blocking_code')}"
            )
        legacy._record_governed_step(
            cur,
            execution_id=execution_id,
            step_id="context_admission",
            evidence_ref=str(context["context_receipt_ref"]),
            payload=context,
        )

        existing_baseline = legacy._read_governed_step(
            cur,
            execution_id,
            "research_baseline_freeze",
        )
        if existing_baseline is not None and existing_baseline.get("status") == "STEP_PASS_WITH_EVIDENCE":
            baseline_first = {
                "outcome": "STEP_RECORDED",
                "replay": True,
                "status": existing_baseline["status"],
            }
        else:
            baseline_first = legacy._fetch_json_scalar(
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


def run_once() -> bool:
    conn = legacy._connect()
    request_id: str | None = None
    try:
        legacy._reconcile_governed_pending(conn)
        claimed = _claim(conn)
        if claimed is None:
            return False
        request_id = claimed["request_id"]
        governed = _begin_governed_pre_model(conn, claimed)
        baseline_first = governed.get("baseline_first") or {}
        if baseline_first.get("outcome") == "BASELINE_REQUIRED":
            baseline_accepted = legacy._api_json(
                "POST",
                "/v1/profile/research-baseline",
                legacy._baseline_api_payload(claimed, governed),
            )
            baseline_job_id = baseline_accepted.get("job_id")
            if not isinstance(baseline_job_id, str) or not baseline_job_id:
                raise RuntimeError("HETZNER_BASELINE_API_JOB_ID_MISSING")
            baseline_job = legacy._wait_job(baseline_job_id)
            baseline_envelope = legacy._baseline_envelope_from_job(baseline_job)
            legacy._persist_required_baseline(conn, governed, baseline_envelope)
        elif baseline_first.get("outcome") != "STEP_RECORDED":
            raise RuntimeError(
                "HETZNER_GOVERNED_BASELINE_HANDSHAKE_INVALID:"
                + str(baseline_first.get("outcome") or baseline_first.get("code") or "UNKNOWN")
            )

        model_governance = legacy._read_model_governance(conn, governed)
        envelope = claimed.get("runtime_request_envelope")
        if envelope is not None:
            envelope = materialize_router_advisory_envelope(
                request_id,
                envelope,
                live_adapter_sources=claimed.get("lf_adapter_sources") or [],
            )
            payload = legacy._validate_envelope(request_id, envelope)
            if "artifact_set" in payload:
                endpoint = "/v1/profile/artifact-set-execute"
                route = "GOVERNED_NONCANONICAL_ARTIFACT_SET"
            else:
                endpoint = "/v1/profile/execute"
                route = "GOVERNED_ENVELOPE"
        else:
            payload = legacy._queue_native_payload(claimed)
            endpoint = "/v1/profile/queue-execute"
            route = "QUEUE_NATIVE"
        payload = legacy._attach_governed_operation(payload, model_governance)
        accepted = legacy._api_json("POST", endpoint, payload)
        job_id = accepted.get("job_id")
        if not isinstance(job_id, str) or not job_id:
            raise RuntimeError("HETZNER_API_JOB_ID_MISSING")
        job = legacy._wait_job(job_id)
        legacy._persist_success(conn, request_id, job, claimed=claimed, governed=governed)
        print(f"HETZNER_QUEUE_REQUEST_ID={request_id}")
        print(f"HETZNER_QUEUE_ROUTE={route}")
        print(f"HETZNER_QUEUE_JOB_ID={job_id}")
        print(f"HETZNER_QUEUE_STATUS={job.get('status')}")
        return True
    except Exception as exc:
        if request_id is not None:
            try:
                legacy._persist_failure(conn, request_id, exc)
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
