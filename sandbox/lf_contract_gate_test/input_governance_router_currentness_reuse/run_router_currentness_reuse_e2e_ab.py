#!/usr/bin/env python3
"""Full-chain A/B canary for Router currentness reuse.

This is test-only. It does not alter live Router functions or contracts. It clones three
previously successful read-only profile requests, runs the current Router preflight (A)
and a shadow currentness-reuse preflight (B), then executes the exact same downstream
profile runtime, verifier, persistence and readback path.
"""
from __future__ import annotations

import json
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

from psycopg.types.json import Jsonb

from github_actions_queue_worker import (
    _claim,
    _connect,
    _enforce_nonempty_completion,
    _persist,
)
from github_actions_batch_queue_worker import (
    _router_adapter_payload,
    _run_one,
    _screen_identity,
)
from runtime_optimization_contract import (
    artifact_verification_decision,
    governance_receipt_reusable,
    image_binding_complete,
)

SOURCE_REQUESTS = (
    "d803f95d-5d3c-48f1-b5c4-4dee4497443f",  # UI Architect
    "7993e614-e49a-4f12-9004-d3c466605da6",  # Product Director
    "227a7409-0f76-4637-a8d1-40ed39e476d8",  # Quality Pack
)
EXPECTED_PROFILES = {
    "PERFIL-UI-ARCHITECT",
    "PERFIL-PRODUCT-DIRECTOR-LF",
    "PERFIL-QUALITY-PACK",
}


def _clone_requests(conn, mode: str) -> list[str]:
    run_id = os.environ.get("GITHUB_RUN_ID", "unknown")
    out: list[str] = []
    with conn.cursor() as cur:
        for source_id in SOURCE_REQUESTS:
            cur.execute(
                """
                insert into private.lf_profile_runtime_queue_v1(
                  operation_code,profile_code,profile_slug,profile_source_paths,input_literal,
                  input_image_base64,input_image_media_type,input_image_sha256,status,requested_by,
                  runtime_target,runtime_request_envelope
                )
                select operation_code,profile_code,profile_slug,profile_source_paths,input_literal,
                       input_image_base64,input_image_media_type,input_image_sha256,'PENDING',%s,
                       'GITHUB_ACTIONS',null
                  from private.lf_profile_runtime_queue_v1
                 where request_id=%s::uuid and status='SUCCEEDED'
                returning request_id::text,profile_code
                """,
                (f"ROUTER_CURRENTNESS_E2E_AB_{mode}_{run_id}", source_id),
            )
            row = cur.fetchone()
            if row is None:
                raise SystemExit(f"FAIL_E2E_SOURCE_REQUEST_NOT_CLONEABLE:{source_id}")
            request_id, profile_code = str(row[0]), str(row[1])
            if profile_code not in EXPECTED_PROFILES:
                raise SystemExit(f"FAIL_E2E_SOURCE_PROFILE_UNEXPECTED:{profile_code}")
            out.append(request_id)
    conn.commit()
    return out


def _required_governance_adapters(adapters: list[dict[str, Any]]) -> tuple[list[str], bool]:
    required: list[str] = []
    invalid = False
    for item in adapters:
        meta = item.get("adapter_metadata") or {}
        applies = (
            str(meta.get("router_discoverable", "false")).lower() == "true"
            and str(meta.get("runtime_enabled", "false")).lower() == "true"
            and str(meta.get("input_governance_receipt_required", "false")).lower() == "true"
        )
        if not applies:
            continue
        required.append(str(meta.get("canonical_adapter_id") or item.get("adapter_code") or ""))
        if (
            meta.get("input_governance_continuation_policy") != "PASS_ONLY"
            or meta.get("input_governance_contract_resolution") != "LIVE_CURRENT"
            or meta.get("input_governance_authority_contract") != "INPUT_READINESS_CONTRACT"
        ):
            invalid = True
    return sorted(required), invalid


def _governance_baseline(conn, payload: dict[str, Any]) -> tuple[dict[str, Any], str | None, int]:
    _, screen_code = _screen_identity(conn, payload["input_literal"])
    adapters = _router_adapter_payload(conn, payload["profile_code"])
    started = time.perf_counter()
    with conn.cursor() as cur:
        cur.execute(
            "select programacion.fn_lf_router_input_governance_resolve_v1(%s,%s,'STORY_CREATOR')",
            (payload["input_literal"], Jsonb(adapters)),
        )
        result = cur.fetchone()[0]
    return result, screen_code, int(round((time.perf_counter() - started) * 1000))


def _governance_candidate(conn, payload: dict[str, Any]) -> tuple[dict[str, Any], str | None, int]:
    pantalla_id, screen_code = _screen_identity(conn, payload["input_literal"])
    adapters = _router_adapter_payload(conn, payload["profile_code"])
    required, invalid = _required_governance_adapters(adapters)
    started = time.perf_counter()

    if not required:
        return {
            "applicable": False,
            "status": "NOT_REQUIRED",
            "blocking_code": None,
            "decision": "N/A",
            "continuation_allowed": True,
            "required_by_adapters": [],
        }, screen_code, int(round((time.perf_counter() - started) * 1000))

    if invalid:
        return {
            "applicable": True,
            "status": "BLOCKED",
            "blocking_code": "BLOCK_INPUT_GOVERNANCE_ADAPTER_CONTRACT_INVALID",
            "decision": "BLOCKED",
            "continuation_allowed": False,
            "required_by_adapters": required,
        }, screen_code, int(round((time.perf_counter() - started) * 1000))

    if pantalla_id is None or screen_code is None:
        # This shadow canary only advances canonical single-screen requests. The production
        # resolver retains the richer ambiguous/unresolved routing behavior until a later
        # dedicated negative lot proves those paths.
        return {
            "applicable": True,
            "status": "BLOCKED",
            "blocking_code": "BLOCK_SHADOW_SUBJECT_NOT_SINGLE_CANONICAL_SCREEN",
            "decision": "BLOCKED",
            "continuation_allowed": False,
            "required_by_adapters": required,
        }, screen_code, int(round((time.perf_counter() - started) * 1000))

    with conn.cursor() as cur:
        cur.execute(
            "select programacion.fn_input_governance_execute(%s,'STORY_CREATOR')",
            (pantalla_id,),
        )
        agent = cur.fetchone()[0]

    status = agent.get("status")
    if status == "READY":
        try:
            run_id = int(agent.get("run_id"))
        except (TypeError, ValueError):
            run_id = -1
        worker = agent.get("worker_spec") if isinstance(agent.get("worker_spec"), dict) else {}
        worker_run = worker.get("current_run_id")
        try:
            worker_run_id = int(worker_run)
        except (TypeError, ValueError):
            worker_run_id = -2
        with conn.cursor() as cur:
            cur.execute(
                """
                select source_snapshot_sha256,contract_revision,contract_snapshot_sha256,created_at
                  from programacion.input_readiness_runs
                 where id=%s and pantalla_id=%s and status='COMPLETED' and invalidated_at is null
                """,
                (run_id, pantalla_id),
            )
            row = cur.fetchone()
        durable_ok = bool(
            row
            and all(value is not None for value in row[:3])
            and agent.get("pantalla_id") == pantalla_id
            and agent.get("screen_code") == screen_code
            and worker_run_id == run_id
            and worker.get("required_role") == "NONE"
        )
        if not durable_ok:
            result = {
                "applicable": True,
                "status": "INPUT_GOVERNANCE_REQUIRED",
                "blocking_code": "BLOCK_INPUT_GOVERNANCE_RECEIPT_STALE",
                "decision": "PENDING",
                "continuation_allowed": False,
                "required_by_adapters": required,
                "pantalla_id": pantalla_id,
                "screen_code": screen_code,
                "worker_spec": worker,
            }
        else:
            source_sha, contract_revision, contract_sha, created_at = row
            result = {
                "applicable": True,
                "status": "READY",
                "blocking_code": None,
                "decision": "PASS",
                "continuation_allowed": True,
                "required_by_adapters": required,
                "pantalla_id": pantalla_id,
                "screen_code": screen_code,
                "worker_spec": worker,
                "governance_receipt": {
                    "governance_agent_used": True,
                    "governance_agent": "input-governance-agent-v1",
                    "governance_version": contract_revision,
                    "sections_consumed": [
                        "APPLICABILITY_READINESS",
                        "SOURCE_AUTHORITY_PROVENANCE",
                        "FRESHNESS_INVALIDATION",
                        "NEGATIVE_REQUIREMENTS",
                        "CONFLICT_PRECEDENCE",
                    ],
                    "source_refs": [
                        f"programacion.input_readiness_runs/{run_id}",
                        f"lf_ops.pantallas/{pantalla_id}",
                        f"programacion.contratos/INPUT_READINESS_CONTRACT@{contract_revision}",
                    ],
                    "snapshot_hash": source_sha,
                    "contract_snapshot_hash": contract_sha,
                    "decision": "PASS",
                    "gap_or_na": "NONE",
                    "timestamp": created_at.isoformat() if hasattr(created_at, "isoformat") else str(created_at),
                    "run_id": run_id,
                    "pantalla_id": pantalla_id,
                    "screen_code": screen_code,
                    "run_created_at": created_at.isoformat() if hasattr(created_at, "isoformat") else str(created_at),
                    "agent_output_sha256": agent.get("output_sha256"),
                    "currentness": "LIVE_CURRENT",
                },
            }
    elif status == "HUMAN_DECISION_REQUIRED":
        result = {
            "applicable": True,
            "status": "HUMAN_DECISION_REQUIRED",
            "blocking_code": "BLOCK_INPUT_GOVERNANCE_HUMAN_DECISION_REQUIRED",
            "decision": "PARTIAL",
            "continuation_allowed": False,
            "required_by_adapters": required,
            "pantalla_id": pantalla_id,
            "screen_code": screen_code,
            "run_id": agent.get("run_id"),
            "agent_output_sha256": agent.get("output_sha256"),
        }
    elif status == "BLOCKED":
        result = {
            "applicable": True,
            "status": "BLOCKED",
            "blocking_code": "BLOCK_INPUT_GOVERNANCE",
            "decision": "BLOCKED",
            "continuation_allowed": False,
            "required_by_adapters": required,
            "pantalla_id": pantalla_id,
            "screen_code": screen_code,
            "run_id": agent.get("run_id"),
            "agent_output_sha256": agent.get("output_sha256"),
        }
    else:
        result = {
            "applicable": True,
            "status": "INPUT_GOVERNANCE_REQUIRED",
            "blocking_code": "BLOCK_INPUT_GOVERNANCE_RUNTIME_REQUIRED",
            "decision": "PENDING",
            "continuation_allowed": False,
            "required_by_adapters": required,
            "pantalla_id": pantalla_id,
            "screen_code": screen_code,
            "worker_spec": agent.get("worker_spec"),
            "agent_status": status,
        }
    return result, screen_code, int(round((time.perf_counter() - started) * 1000))


def _stable_governance_projection(result: dict[str, Any]) -> dict[str, Any]:
    worker = result.get("worker_spec") if isinstance(result.get("worker_spec"), dict) else {}
    receipt = result.get("governance_receipt") if isinstance(result.get("governance_receipt"), dict) else {}
    return {
        "applicable": result.get("applicable"),
        "status": result.get("status"),
        "decision": result.get("decision"),
        "continuation_allowed": result.get("continuation_allowed"),
        "pantalla_id": result.get("pantalla_id"),
        "screen_code": result.get("screen_code"),
        "required_by_adapters": result.get("required_by_adapters"),
        "worker_current_run_id": worker.get("current_run_id"),
        "worker_required_role": worker.get("required_role"),
        "worker_runtime_action": worker.get("runtime_action"),
        "receipt_decision": receipt.get("decision"),
        "receipt_currentness": receipt.get("currentness"),
        "receipt_run_id": receipt.get("run_id"),
        "receipt_snapshot_hash": receipt.get("snapshot_hash"),
        "receipt_contract_snapshot_hash": receipt.get("contract_snapshot_hash"),
        "receipt_sections": receipt.get("sections_consumed"),
        "receipt_source_refs": receipt.get("source_refs"),
    }


def _preflight(conn, payload: dict[str, Any], mode: str) -> tuple[dict[str, Any] | None, int]:
    if mode == "A_BASELINE":
        governance, screen_code, governance_ms = _governance_baseline(conn, payload)
    elif mode == "B_CANDIDATE":
        governance, screen_code, governance_ms = _governance_candidate(conn, payload)
    else:
        raise SystemExit(f"FAIL_E2E_MODE:{mode}")
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
        }, governance_ms
    if governance.get("applicable") and not governance_receipt_reusable(governance, screen_code=screen_code):
        return {
            "schema": "LF_PROFILE_RUNTIME_QUEUE_RESULT_V1",
            "status": "BLOCKED",
            "request_id": payload["request_id"],
            "error_code": "BLOCK_INPUT_GOVERNANCE_RECEIPT_INVALID",
            "error_detail": "READY receipt was not reusable/current",
            "input_governance": governance,
        }, governance_ms
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
        }, governance_ms
    return None, governance_ms


def _run_phase(conn, request_ids: list[str], mode: str, repo_root: str) -> dict[str, dict[str, Any]]:
    payloads: list[dict[str, Any]] = []
    preblocked: dict[str, dict[str, Any]] = {}
    preflight_ms: dict[str, int] = {}
    phase_started = time.perf_counter()

    for request_id in request_ids:
        payload = _claim(conn, request_id, 0)
        blocked, ms = _preflight(conn, payload, mode)
        preflight_ms[request_id] = ms
        if blocked is not None:
            preblocked[request_id] = blocked
        payloads.append(payload)

    results: dict[str, tuple[dict[str, Any], str | None, int]] = {}
    runnable = [p for p in payloads if p["request_id"] not in preblocked]
    if runnable:
        from pathlib import Path
        with ThreadPoolExecutor(max_workers=2, thread_name_prefix=f"lf-{mode.lower()}") as pool:
            futures = {pool.submit(_run_one, p, Path(repo_root)): p["request_id"] for p in runnable}
            for future in as_completed(futures):
                results[futures[future]] = future.result()

    phase_ms = int(round((time.perf_counter() - phase_started) * 1000))
    by_profile: dict[str, dict[str, Any]] = {}
    for payload in payloads:
        request_id = payload["request_id"]
        if request_id in preblocked:
            result, inference_started_at, inference_ms = preblocked[request_id], None, 0
        else:
            result, inference_started_at, inference_ms = results[request_id]
        result = _enforce_nonempty_completion(result)
        result["input_governance"] = payload.get("input_governance_result")
        result["artifact_verified"] = payload.get("artifact_verified", result.get("artifact_verified"))
        result["router_currentness_e2e_ab"] = {
            "mode": mode,
            "governance_preflight_ms": preflight_ms[request_id],
            "profile_inference_ms": inference_ms,
            "phase_wall_ms": phase_ms,
            "source_branch": os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME"),
            "github_run_id": os.environ.get("GITHUB_RUN_ID"),
        }
        _persist(conn, request_id, result)
        by_profile[payload["profile_code"]] = {
            "request_id": request_id,
            "result": result,
            "governance_ms": preflight_ms[request_id],
            "inference_ms": inference_ms,
            "phase_ms": phase_ms,
        }
    return by_profile


def _attestation_projection(result: dict[str, Any]) -> dict[str, Any]:
    receipt = result.get("receipt") if isinstance(result.get("receipt"), dict) else {}
    att = receipt.get("runtime_attestation") if isinstance(receipt.get("runtime_attestation"), dict) else {}
    return {
        "status": result.get("status"),
        "error_code": result.get("error_code"),
        "runtime_provider": result.get("runtime_provider"),
        "runtime_model_id": result.get("runtime_model_id"),
        "request_sha256": att.get("request_sha256"),
        "profile_source_sha256": att.get("profile_source_sha256"),
        "input_sha256": att.get("input_sha256"),
        "system_prompt_sha256": att.get("system_prompt_sha256"),
        "input_image_sha256": att.get("input_image_sha256"),
        "lf_adapter_invocation_count": att.get("lf_adapter_invocation_count"),
        "context_tokens": att.get("context_tokens"),
        "max_output_tokens": att.get("max_output_tokens"),
    }


def _raw_output_sha(result: dict[str, Any]) -> str | None:
    receipt = result.get("receipt") if isinstance(result.get("receipt"), dict) else {}
    att = receipt.get("runtime_attestation") if isinstance(receipt.get("runtime_attestation"), dict) else {}
    value = att.get("raw_output_file_sha256")
    return value if isinstance(value, str) else None


def main() -> int:
    repo_root = os.getcwd()
    conn = _connect()
    try:
        baseline_ids = _clone_requests(conn, "A_BASELINE")
        candidate_ids = _clone_requests(conn, "B_CANDIDATE")
        baseline = _run_phase(conn, baseline_ids, "A_BASELINE", repo_root)
        candidate = _run_phase(conn, candidate_ids, "B_CANDIDATE", repo_root)

        failures: list[str] = []
        comparisons: dict[str, Any] = {}
        for profile in sorted(EXPECTED_PROFILES):
            a = baseline.get(profile)
            b = candidate.get(profile)
            if not a or not b:
                failures.append(f"MISSING_PROFILE_PAIR:{profile}")
                continue
            ag = _stable_governance_projection(a["result"].get("input_governance") or {})
            bg = _stable_governance_projection(b["result"].get("input_governance") or {})
            gov_equal = ag == bg
            att_a = _attestation_projection(a["result"])
            att_b = _attestation_projection(b["result"])
            att_equal = att_a == att_b
            status_equal = a["result"].get("status") == b["result"].get("status")
            raw_equal = _raw_output_sha(a["result"]) == _raw_output_sha(b["result"])
            comparisons[profile] = {
                "baseline_request_id": a["request_id"],
                "candidate_request_id": b["request_id"],
                "governance_projection_equal": gov_equal,
                "attestation_projection_equal": att_equal,
                "status_equal": status_equal,
                "raw_output_sha_equal": raw_equal,
                "baseline_governance_ms": a["governance_ms"],
                "candidate_governance_ms": b["governance_ms"],
                "baseline_inference_ms": a["inference_ms"],
                "candidate_inference_ms": b["inference_ms"],
                "baseline_phase_ms": a["phase_ms"],
                "candidate_phase_ms": b["phase_ms"],
                "baseline_status": a["result"].get("status"),
                "candidate_status": b["result"].get("status"),
            }
            if not gov_equal:
                failures.append(f"GOVERNANCE_PROJECTION_DRIFT:{profile}")
            if not status_equal:
                failures.append(f"STATUS_DRIFT:{profile}")
            if not att_equal:
                failures.append(f"ATTESTATION_PROJECTION_DRIFT:{profile}")
            if a["result"].get("status") != "SUCCEEDED" or b["result"].get("status") != "SUCCEEDED":
                failures.append(f"E2E_NOT_SUCCEEDED:{profile}")

        a_gov = sorted(v["governance_ms"] for v in baseline.values())
        b_gov = sorted(v["governance_ms"] for v in candidate.values())
        median_a = a_gov[len(a_gov)//2] if a_gov else 0
        median_b = b_gov[len(b_gov)//2] if b_gov else 0
        if median_b >= median_a:
            failures.append(f"GOVERNANCE_MEDIAN_NOT_IMPROVED:{median_a}->{median_b}")

        summary = {
            "schema": "LF_INPUT_GOVERNANCE_ROUTER_CURRENTNESS_E2E_AB_V1",
            "status": "PASS" if not failures else "FAIL",
            "branch": os.environ.get("GITHUB_HEAD_REF") or os.environ.get("GITHUB_REF_NAME"),
            "github_run_id": os.environ.get("GITHUB_RUN_ID"),
            "baseline_governance_ms": a_gov,
            "candidate_governance_ms": b_gov,
            "baseline_governance_median_ms": median_a,
            "candidate_governance_median_ms": median_b,
            "comparisons": comparisons,
            "failures": failures,
            "notes": [
                "A and B clone the same three previously successful read-only requests.",
                "Downstream profile runtime and verifier code are identical; only Router/Input Governance preflight differs.",
                "Raw-output SHA equality is reported but is not a hard gate; semantic/quality adjudication remains separate if model output differs despite fixed seed.",
            ],
        }
        print(json.dumps(summary, indent=2, sort_keys=True))
        return 0 if not failures else 2
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
