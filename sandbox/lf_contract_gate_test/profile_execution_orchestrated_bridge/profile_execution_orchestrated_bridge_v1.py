import copy
import hashlib
import json
import re
import uuid
from typing import Any, Dict


SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
PROFILE_SOURCE_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
CAPABILITY_CODE = "PROFILE_EXECUTION_RUNTIME"
DYNAMIC_BINDING_KEYS = {
    "orchestrator_execution_id",
    "dispatch_receipt_ref",
    "entry_guard_code",
    "entry_guard_decision",
}


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _digest(value: Any) -> str:
    return _sha256_text(_canonical_json(value))


def _block(decision: str, detail: Any = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_PLAN_V2",
        "status": "BLOCKED",
        "decision": decision,
    }
    if detail is not None:
        result["detail"] = detail
    result["result_digest"] = _digest(result)
    return result


def _validate_static_seed(
    *,
    orchestrator_execution_id: str,
    profile_code: str,
    task_packet_seed: Dict[str, Any],
) -> Dict[str, Any] | None:
    if not isinstance(task_packet_seed, dict):
        return _block("BLOCK_TASK_PACKET_SEED_INVALID")
    worker_binding = task_packet_seed.get("worker_binding")
    if not isinstance(worker_binding, dict):
        return _block("BLOCK_TASK_PACKET_WORKER_BINDING_SEED_MISSING")
    if worker_binding.get("resolution_mode") != "ORCHESTRATOR_RESOLVED":
        return _block("BLOCK_TASK_PACKET_WORKER_BINDING_MODE")
    if worker_binding.get("worker_kind") != "PROFILE":
        return _block("BLOCK_PROFILE_BRIDGE_WORKER_KIND_MISMATCH")
    if worker_binding.get("worker_ref") != profile_code:
        return _block("BLOCK_PROFILE_BRIDGE_WORKER_REF_MISMATCH")
    for key in ("binding_authority_ref", "binding_revision", "binding_digest"):
        if not isinstance(worker_binding.get(key), str) or not worker_binding[key].strip():
            return _block("BLOCK_STATIC_WORKER_BINDING_INCOMPLETE", key)
    if not SHA64_RE.fullmatch(worker_binding["binding_digest"]):
        return _block("BLOCK_STATIC_WORKER_BINDING_DIGEST_INVALID")
    forbidden = sorted(DYNAMIC_BINDING_KEYS.intersection(worker_binding))
    if forbidden:
        return _block(
            "BLOCK_PREMATURE_EXECUTION_AUTHORITY_IN_SEED",
            {"forbidden_keys": forbidden},
        )
    if "orchestrator_execution_id" in task_packet_seed:
        return _block("BLOCK_PREMATURE_EXECUTION_AUTHORITY_IN_SEED", {"forbidden_key": "orchestrator_execution_id"})
    if not orchestrator_execution_id.strip():
        return _block("BLOCK_ORCHESTRATOR_EXECUTION_ID_MISSING")
    return None


def build_pre_dispatch_plan(
    *,
    orchestrator_execution_id: str,
    request_id: str,
    profile_code: str,
    profile_slug: str,
    target_repo: str,
    profile_source_paths: list[str],
    profile_source_digest: str,
    source_revision: str,
    task_packet_seed: Dict[str, Any],
    parent_plan_digest: str,
    expected_capability_manifest_sha256: str,
) -> Dict[str, Any]:
    try:
        request_uuid = uuid.UUID(request_id)
    except (ValueError, TypeError, AttributeError):
        return _block("BLOCK_PROFILE_RUNTIME_REQUEST_ID_INVALID")
    request_id_norm = str(request_uuid)

    if not isinstance(orchestrator_execution_id, str) or not orchestrator_execution_id.strip():
        return _block("BLOCK_ORCHESTRATOR_EXECUTION_ID_MISSING")
    if not isinstance(profile_code, str) or not profile_code.strip():
        return _block("BLOCK_PROFILE_CODE_MISSING")
    if not isinstance(profile_slug, str) or not profile_slug.strip():
        return _block("BLOCK_PROFILE_SLUG_MISSING")
    if not isinstance(target_repo, str) or not target_repo.strip():
        return _block("BLOCK_PROFILE_TARGET_REPO_MISSING")
    if not isinstance(profile_source_paths, list) or not profile_source_paths:
        return _block("BLOCK_PROFILE_SOURCE_PATHS_MISSING")
    if any(not isinstance(path, str) or not path.strip() for path in profile_source_paths):
        return _block("BLOCK_PROFILE_SOURCE_PATH_INVALID")
    if len(set(profile_source_paths)) != len(profile_source_paths):
        return _block("BLOCK_PROFILE_SOURCE_PATH_DUPLICATE")
    if not PROFILE_SOURCE_DIGEST_RE.fullmatch(profile_source_digest or ""):
        return _block("BLOCK_PROFILE_SOURCE_DIGEST_INVALID")
    if not SHA40_RE.fullmatch(source_revision or ""):
        return _block("BLOCK_SOURCE_REVISION_INVALID")
    if not SHA64_RE.fullmatch(parent_plan_digest or ""):
        return _block("BLOCK_PARENT_PLAN_DIGEST_INVALID")
    if not SHA64_RE.fullmatch(expected_capability_manifest_sha256 or ""):
        return _block("BLOCK_CAPABILITY_MANIFEST_SHA_INVALID")

    seed_error = _validate_static_seed(
        orchestrator_execution_id=orchestrator_execution_id,
        profile_code=profile_code,
        task_packet_seed=task_packet_seed,
    )
    if seed_error:
        return seed_error

    task_packet_work_digest = _digest(task_packet_seed)
    child_request_material = {
        "schema_version": "LF_PROFILE_CHILD_RESERVATION_IDEMPOTENCY_V1",
        "task_packet_work_digest": task_packet_work_digest,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "profile_source_digest": profile_source_digest,
        "source_revision": source_revision,
        "profile_source_paths": profile_source_paths,
    }
    child_request_sha256 = _digest(child_request_material)
    consumer_execution_id = f"EXEC-PROFILE-RUNTIME-{request_id_norm}"
    idempotency_key = f"profile-runtime-orchestrated:{request_id_norm}"

    child_manifest = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_CHILD_V2",
        "orchestrator_execution_id": orchestrator_execution_id,
        "plan_digest": parent_plan_digest,
        "capability_code": CAPABILITY_CODE,
        "task_packet_work_digest": task_packet_work_digest,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "profile_source_digest": profile_source_digest,
        "profile_source_paths": profile_source_paths,
        "source_revision": source_revision,
        "request_id": request_id_norm,
        "read_only": True,
        "automatic_impact": False,
    }

    dispatch_scope = {
        "schema_version": "LF_PROFILE_EXECUTION_DISPATCH_SCOPE_V2",
        "request_id": request_id_norm,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "step_id": task_packet_seed.get("step_id"),
        "task_id": task_packet_seed.get("task_id"),
        "task_packet_work_digest": task_packet_work_digest,
        "profile_source_digest": profile_source_digest,
        "profile_source_paths": profile_source_paths,
        "source_revision": source_revision,
        "read_only": True,
    }

    ordered_actions = [
        {
            "action": "BEGIN_CHILD_EXECUTION",
            "rpc": "public.lf_profile_execution_begin_v1",
            "args": {
                "execution_id": consumer_execution_id,
                "idempotency_key": idempotency_key,
                "request_sha256": child_request_sha256,
                "actor_execution_id": orchestrator_execution_id,
                "profile_code": profile_code,
                "target_repo": target_repo,
                "target_path": profile_source_paths[0],
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
                "plan_digest": parent_plan_digest,
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
                "plan_digest": parent_plan_digest,
                "dispatch_receipt_id": "<FROM_ISSUE_DISPATCH_RECEIPT>",
                "actor_execution_id": orchestrator_execution_id,
            },
        },
    ]

    plan = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_PLAN_V2",
        "status": "PRE_DISPATCH_READY",
        "decision": "PROFILE_CHILD_RESERVATION_READY",
        "capability_code": CAPABILITY_CODE,
        "orchestrator_execution_id": orchestrator_execution_id,
        "consumer_execution_id": consumer_execution_id,
        "request_id": request_id_norm,
        "profile_code": profile_code,
        "profile_slug": profile_slug,
        "profile_source_digest": profile_source_digest,
        "profile_source_paths": profile_source_paths,
        "source_revision": source_revision,
        "parent_plan_digest": parent_plan_digest,
        "task_packet_seed": copy.deepcopy(task_packet_seed),
        "task_packet_work_digest": task_packet_work_digest,
        "child_request_sha256": child_request_sha256,
        "ordered_actions": ordered_actions,
    }
    plan["pre_dispatch_plan_digest"] = _digest(plan)
    return plan


def finalize_after_guard(
    pre_dispatch_plan: Dict[str, Any],
    *,
    dispatch_receipt_readback: Dict[str, Any],
    entry_guard_readback: Dict[str, Any],
) -> Dict[str, Any]:
    if not isinstance(pre_dispatch_plan, dict) or pre_dispatch_plan.get("decision") != "PROFILE_CHILD_RESERVATION_READY":
        return _block("BLOCK_PRE_DISPATCH_PLAN_INVALID")
    if not isinstance(dispatch_receipt_readback, dict) or dispatch_receipt_readback.get("ready") is not True:
        return _block("BLOCK_DISPATCH_RECEIPT_NOT_READY")
    receipt_id = dispatch_receipt_readback.get("receipt_id")
    receipt_sha256 = dispatch_receipt_readback.get("receipt_sha256")
    try:
        receipt_id_norm = str(uuid.UUID(str(receipt_id)))
    except (ValueError, TypeError, AttributeError):
        return _block("BLOCK_DISPATCH_RECEIPT_ID_INVALID")
    if not SHA64_RE.fullmatch(str(receipt_sha256 or "")):
        return _block("BLOCK_DISPATCH_RECEIPT_SHA_INVALID")

    if not isinstance(entry_guard_readback, dict) or entry_guard_readback.get("ready") is not True:
        return _block("BLOCK_ENTRY_GUARD_NOT_READY")
    if entry_guard_readback.get("decision") != "ORCHESTRATOR_ENTRY_ACCEPTED":
        return _block("BLOCK_ENTRY_GUARD_DECISION_INVALID")
    if entry_guard_readback.get("guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1":
        return _block("BLOCK_ENTRY_GUARD_CODE_INVALID")
    if str(entry_guard_readback.get("receipt_id")) != receipt_id_norm:
        return _block("BLOCK_ENTRY_GUARD_RECEIPT_MISMATCH")
    if entry_guard_readback.get("orchestrator_execution_id") != pre_dispatch_plan["orchestrator_execution_id"]:
        return _block("BLOCK_ENTRY_GUARD_ORCHESTRATOR_MISMATCH")
    if entry_guard_readback.get("consumer_execution_id") != pre_dispatch_plan["consumer_execution_id"]:
        return _block("BLOCK_ENTRY_GUARD_CONSUMER_MISMATCH")
    if entry_guard_readback.get("capability_code") != CAPABILITY_CODE:
        return _block("BLOCK_ENTRY_GUARD_CAPABILITY_MISMATCH")
    if entry_guard_readback.get("plan_digest") != pre_dispatch_plan["parent_plan_digest"]:
        return _block("BLOCK_ENTRY_GUARD_PLAN_MISMATCH")

    final_packet = copy.deepcopy(pre_dispatch_plan["task_packet_seed"])
    worker_binding = dict(final_packet["worker_binding"])
    worker_binding.update(
        {
            "orchestrator_execution_id": pre_dispatch_plan["orchestrator_execution_id"],
            "dispatch_receipt_ref": (
                f"supabase://private.lf_orchestrator_dispatch_receipts_v1/{receipt_id_norm}"
                f"@sha256:{receipt_sha256}"
            ),
            "entry_guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
            "entry_guard_decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
        }
    )
    final_packet["worker_binding"] = worker_binding

    static_projection = copy.deepcopy(final_packet)
    for key in DYNAMIC_BINDING_KEYS:
        static_projection["worker_binding"].pop(key, None)
    if _digest(static_projection) != pre_dispatch_plan["task_packet_work_digest"]:
        return _block("BLOCK_FINAL_TASK_PACKET_STATIC_PROJECTION_DRIFT")

    final_packet_digest = _digest(final_packet)
    runtime_request_envelope = {
        "schema_version": "LF_PROFILE_RUNTIME_ORCHESTRATED_REQUEST_V2",
        "orchestrator_execution_id": pre_dispatch_plan["orchestrator_execution_id"],
        "consumer_execution_id": pre_dispatch_plan["consumer_execution_id"],
        "capability_code": CAPABILITY_CODE,
        "plan_digest": pre_dispatch_plan["parent_plan_digest"],
        "task_packet_work_digest": pre_dispatch_plan["task_packet_work_digest"],
        "final_task_packet_digest": final_packet_digest,
        "dispatch_receipt_id": receipt_id_norm,
        "dispatch_receipt_sha256": receipt_sha256,
        "entry_guard": copy.deepcopy(entry_guard_readback),
        "profile_source_digest": pre_dispatch_plan["profile_source_digest"],
        "source_revision": pre_dispatch_plan["source_revision"],
        "attach_existing_child_execution": True,
    }

    enqueue = {
        "action": "ENQUEUE_EXISTING_PROFILE_RUNTIME",
        "target": "private.lf_profile_runtime_queue_v1",
        "request_id": pre_dispatch_plan["request_id"],
        "consumer_execution_id": pre_dispatch_plan["consumer_execution_id"],
        "profile_code": pre_dispatch_plan["profile_code"],
        "profile_slug": pre_dispatch_plan["profile_slug"],
        "profile_source_paths": pre_dispatch_plan["profile_source_paths"],
        "input_literal": _canonical_json(final_packet),
        "runtime_request_envelope": runtime_request_envelope,
    }

    result = {
        "schema_version": "LF_PROFILE_EXECUTION_ORCHESTRATED_PLAN_V2",
        "status": "READY_TO_ENQUEUE",
        "decision": "PROFILE_EXECUTION_AUTHORITY_FINALIZED",
        "task_packet_work_digest": pre_dispatch_plan["task_packet_work_digest"],
        "final_task_packet": final_packet,
        "final_task_packet_digest": final_packet_digest,
        "runtime_request_envelope": runtime_request_envelope,
        "enqueue_action": enqueue,
    }
    result["finalization_digest"] = _digest(result)
    return result
