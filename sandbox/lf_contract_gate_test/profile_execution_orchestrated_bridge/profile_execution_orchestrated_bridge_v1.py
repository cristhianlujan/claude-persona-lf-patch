import hashlib
import json
import re
import uuid
from typing import Any, Dict


SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
CAPABILITY_CODE = "PROFILE_EXECUTION_RUNTIME"


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _block(decision: str, detail: str | None = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_PLAN_V1",
        "status": "BLOCKED",
        "decision": decision,
    }
    if detail:
        result["detail"] = detail
    result["plan_digest"] = _sha256_text(_canonical_json(result))
    return result


def build_plan(
    *,
    orchestrator_execution_id: str,
    request_id: str,
    profile_code: str,
    target_repo: str,
    target_path: str,
    source_revision: str,
    task_packet: Dict[str, Any],
    plan_digest: str,
    expected_capability_manifest_sha256: str,
) -> Dict[str, Any]:
    if not orchestrator_execution_id or not orchestrator_execution_id.strip():
        return _block("BLOCK_ORCHESTRATOR_EXECUTION_ID_MISSING")
    try:
        request_uuid = uuid.UUID(request_id)
    except (ValueError, TypeError, AttributeError):
        return _block("BLOCK_PROFILE_RUNTIME_REQUEST_ID_INVALID")
    request_id_norm = str(request_uuid)

    if not profile_code or not profile_code.strip():
        return _block("BLOCK_PROFILE_CODE_MISSING")
    if not target_repo or not target_repo.strip() or not target_path or not target_path.strip():
        return _block("BLOCK_PROFILE_TARGET_MISSING")
    if not SHA40_RE.fullmatch(source_revision or ""):
        return _block("BLOCK_SOURCE_REVISION_INVALID")
    if not SHA64_RE.fullmatch(plan_digest or ""):
        return _block("BLOCK_PARENT_PLAN_DIGEST_INVALID")
    if not SHA64_RE.fullmatch(expected_capability_manifest_sha256 or ""):
        return _block("BLOCK_CAPABILITY_MANIFEST_SHA_INVALID")
    if not isinstance(task_packet, dict):
        return _block("BLOCK_TASK_PACKET_INVALID")

    worker_binding = task_packet.get("worker_binding")
    if not isinstance(worker_binding, dict):
        return _block("BLOCK_TASK_PACKET_WORKER_BINDING_MISSING")
    if worker_binding.get("resolution_mode") != "ORCHESTRATOR_RESOLVED":
        return _block("BLOCK_TASK_PACKET_WORKER_BINDING_MODE")
    if worker_binding.get("worker_kind") != "PROFILE":
        return _block("BLOCK_PROFILE_BRIDGE_WORKER_KIND_MISMATCH")
    if worker_binding.get("worker_ref") != profile_code:
        return _block("BLOCK_PROFILE_BRIDGE_WORKER_REF_MISMATCH")
    if worker_binding.get("orchestrator_execution_id") != orchestrator_execution_id:
        return _block("BLOCK_PROFILE_BRIDGE_ORCHESTRATOR_MISMATCH")
    if worker_binding.get("entry_guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        return _block("BLOCK_PROFILE_BRIDGE_ENTRY_GUARD_CODE")
    if worker_binding.get("entry_guard_decision") != "ORCHESTRATOR_ENTRY_ACCEPTED":
        return _block("BLOCK_PROFILE_BRIDGE_ENTRY_GUARD_DECISION")

    task_packet_json = _canonical_json(task_packet)
    task_packet_digest = _sha256_text(task_packet_json)
    request_sha256 = _sha256_text(task_packet_json)
    consumer_execution_id = f"EXEC-PROFILE-RUNTIME-{request_id_norm}"
    idempotency_key = f"profile-runtime-queue:{request_id_norm}"

    child_manifest = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_CHILD_V1",
        "orchestrator_execution_id": orchestrator_execution_id,
        "plan_digest": plan_digest,
        "capability_code": CAPABILITY_CODE,
        "source_revision": source_revision,
        "task_packet_digest": task_packet_digest,
        "request_id": request_id_norm,
        "read_only": True,
        "automatic_impact": False,
    }

    dispatch_scope = {
        "schema_version": "LF_PROFILE_EXECUTION_DISPATCH_SCOPE_V1",
        "request_id": request_id_norm,
        "profile_code": profile_code,
        "step_id": task_packet.get("step_id"),
        "task_id": task_packet.get("task_id"),
        "task_packet_digest": task_packet_digest,
        "source_revision": source_revision,
        "read_only": True,
    }

    runtime_request_envelope = {
        "schema_version": "LF_PROFILE_RUNTIME_ORCHESTRATED_REQUEST_V1",
        "orchestrator_execution_id": orchestrator_execution_id,
        "consumer_execution_id": consumer_execution_id,
        "capability_code": CAPABILITY_CODE,
        "plan_digest": plan_digest,
        "dispatch_scope_digest": _sha256_text(_canonical_json(dispatch_scope)),
        "task_packet_digest": task_packet_digest,
        "source_revision": source_revision,
        "entry_guard_required": True,
    }

    ordered_actions = [
        {
            "action": "BEGIN_CHILD_EXECUTION",
            "rpc": "public.lf_profile_execution_begin_v1",
            "args": {
                "execution_id": consumer_execution_id,
                "idempotency_key": idempotency_key,
                "request_sha256": request_sha256,
                "actor_execution_id": orchestrator_execution_id,
                "profile_code": profile_code,
                "target_repo": target_repo,
                "target_path": target_path,
                "manifest": child_manifest,
            },
        },
        {
            "action": "ISSUE_DISPATCH_RECEIPT",
            "rpc": "public.fn_lf_orchestrator_dispatch_receipt_v1",
            "args": {
                "orchestrator_execution_id": orchestrator_execution_id,
                "consumer_execution_id": consumer_execution_id,
                "capability_code": CAPABILITY_CODE,
                "plan_digest": plan_digest,
                "dispatch_scope": dispatch_scope,
                "actor_execution_id": orchestrator_execution_id,
            },
        },
        {
            "action": "BIND_CAPABILITY_ENTRY_GUARD",
            "rpc": "public.fn_lf_capability_bind_from_orchestrator_v1",
            "args": {
                "execution_id": consumer_execution_id,
                "capability_code": CAPABILITY_CODE,
                "expected_manifest_sha256": expected_capability_manifest_sha256,
                "plan_digest": plan_digest,
                "dispatch_receipt_id": "<FROM_PREVIOUS_ACTION>",
                "actor_execution_id": orchestrator_execution_id,
            },
        },
        {
            "action": "ENQUEUE_EXISTING_PROFILE_RUNTIME",
            "target": "private.lf_profile_runtime_queue_v1",
            "request_id": request_id_norm,
            "consumer_execution_id": consumer_execution_id,
            "profile_code": profile_code,
            "input_literal": task_packet_json,
            "runtime_request_envelope": runtime_request_envelope,
        },
    ]

    plan = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_PLAN_V1",
        "status": "PLANNED",
        "decision": "PROFILE_EXECUTION_ORCHESTRATED_PLAN_READY",
        "capability_code": CAPABILITY_CODE,
        "orchestrator_execution_id": orchestrator_execution_id,
        "consumer_execution_id": consumer_execution_id,
        "request_id": request_id_norm,
        "profile_code": profile_code,
        "task_packet_digest": task_packet_digest,
        "source_revision": source_revision,
        "ordered_actions": ordered_actions,
    }
    plan["plan_digest"] = _sha256_text(_canonical_json(plan))
    return plan
