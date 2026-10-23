import copy
import hashlib
import json
import re
import uuid
from typing import Any, Dict


SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
SHA64_RE = re.compile(r"^[0-9a-f]{64}$")
CAPABILITY_CODE = "PROFILE_EXECUTION_RUNTIME"
DYNAMIC_KEYS = {
    "orchestrator_execution_id",
    "dispatch_receipt_ref",
    "entry_guard_code",
    "entry_guard_decision",
}


def _canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical(value).encode("utf-8")).hexdigest()


def _block(decision: str, details: Dict[str, Any] | None = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "schema_version": "LF_PROFILE_RUNTIME_ORCHESTRATED_ATTACH_RESULT_V1",
        "status": "BLOCKED",
        "decision": decision,
    }
    if details:
        result["details"] = details
    result["result_digest"] = _digest(result)
    return result


def validate_attach(
    *,
    queue_row: Dict[str, Any],
    child_execution: Dict[str, Any],
    receipt_readback: Dict[str, Any],
    task_runtime_binding_resolution: Dict[str, Any] | None,
    runtime_source_revision: str,
) -> Dict[str, Any]:
    if not isinstance(queue_row, dict):
        return _block("BLOCK_QUEUE_ROW_INVALID")
    envelope = queue_row.get("runtime_request_envelope")
    if not isinstance(envelope, dict):
        return _block("BLOCK_ORCHESTRATED_ENVELOPE_MISSING")
    if envelope.get("schema_version") != "LF_PROFILE_RUNTIME_ORCHESTRATED_REQUEST_V2":
        return _block("BLOCK_ORCHESTRATED_ENVELOPE_SCHEMA")
    if envelope.get("attach_existing_child_execution") is not True:
        return _block("BLOCK_EXISTING_CHILD_ATTACH_NOT_REQUESTED")
    if envelope.get("capability_code") != CAPABILITY_CODE:
        return _block("BLOCK_CAPABILITY_MISMATCH")

    request_id = str(queue_row.get("request_id") or "")
    try:
        request_id = str(uuid.UUID(request_id))
    except (ValueError, TypeError, AttributeError):
        return _block("BLOCK_QUEUE_REQUEST_ID_INVALID")
    expected_child_id = f"EXEC-PROFILE-RUNTIME-{request_id}"
    consumer_execution_id = envelope.get("consumer_execution_id")
    if consumer_execution_id != expected_child_id:
        return _block("BLOCK_CONSUMER_EXECUTION_ID_MISMATCH")

    required_text = (
        "orchestrator_execution_id",
        "consumer_execution_id",
        "plan_digest",
        "task_packet_work_digest",
        "final_task_packet_digest",
        "dispatch_receipt_id",
        "dispatch_receipt_sha256",
        "profile_source_digest",
        "source_revision",
    )
    missing = [key for key in required_text if not isinstance(envelope.get(key), str) or not envelope[key].strip()]
    if missing:
        return _block("BLOCK_ORCHESTRATED_ENVELOPE_INCOMPLETE", {"missing": missing})
    if any(not SHA64_RE.fullmatch(envelope[key]) for key in ("plan_digest", "task_packet_work_digest", "final_task_packet_digest", "dispatch_receipt_sha256")):
        return _block("BLOCK_ORCHESTRATED_ENVELOPE_DIGEST_INVALID")
    if not SHA40_RE.fullmatch(envelope["source_revision"]):
        return _block("BLOCK_SOURCE_REVISION_INVALID")
    try:
        receipt_id = str(uuid.UUID(envelope["dispatch_receipt_id"]))
    except (ValueError, TypeError, AttributeError):
        return _block("BLOCK_DISPATCH_RECEIPT_ID_INVALID")

    input_literal = queue_row.get("input_literal")
    if not isinstance(input_literal, str) or not input_literal:
        return _block("BLOCK_FINAL_TASK_PACKET_MISSING")
    try:
        final_packet = json.loads(input_literal)
    except json.JSONDecodeError:
        return _block("BLOCK_FINAL_TASK_PACKET_JSON_INVALID")
    if not isinstance(final_packet, dict):
        return _block("BLOCK_FINAL_TASK_PACKET_ROOT_INVALID")
    if _digest(final_packet) != envelope["final_task_packet_digest"]:
        return _block("BLOCK_FINAL_TASK_PACKET_DIGEST_MISMATCH")
    worker_binding = final_packet.get("worker_binding")
    if not isinstance(worker_binding, dict):
        return _block("BLOCK_FINAL_WORKER_BINDING_MISSING")
    if worker_binding.get("orchestrator_execution_id") != envelope["orchestrator_execution_id"]:
        return _block("BLOCK_FINAL_WORKER_ORCHESTRATOR_MISMATCH")
    if worker_binding.get("entry_guard_code") != "ORCHESTRATOR_EXECUTION_GUARD_V1" or worker_binding.get("entry_guard_decision") != "ORCHESTRATOR_ENTRY_ACCEPTED":
        return _block("BLOCK_FINAL_WORKER_GUARD_INVALID")
    receipt_ref = worker_binding.get("dispatch_receipt_ref")
    expected_suffix = f"/{receipt_id}@sha256:{envelope['dispatch_receipt_sha256']}"
    if not isinstance(receipt_ref, str) or not receipt_ref.endswith(expected_suffix):
        return _block("BLOCK_FINAL_WORKER_RECEIPT_REF_MISMATCH")

    static_packet = copy.deepcopy(final_packet)
    for key in DYNAMIC_KEYS:
        static_packet["worker_binding"].pop(key, None)
    if _digest(static_packet) != envelope["task_packet_work_digest"]:
        return _block("BLOCK_FINAL_TASK_PACKET_STATIC_PROJECTION_DRIFT")

    if not isinstance(child_execution, dict):
        return _block("BLOCK_EXISTING_CHILD_MISSING")
    if child_execution.get("execution_id") != consumer_execution_id:
        return _block("BLOCK_EXISTING_CHILD_ID_MISMATCH")
    if child_execution.get("operation_code") != "EJECUCION_PERFIL_LF":
        return _block("BLOCK_EXISTING_CHILD_OPERATION_MISMATCH")
    if child_execution.get("status") != "IN_PROGRESS":
        return _block("BLOCK_EXISTING_CHILD_NOT_IN_PROGRESS")
    manifest = child_execution.get("manifest")
    if not isinstance(manifest, dict):
        return _block("BLOCK_EXISTING_CHILD_MANIFEST_MISSING")
    expected_manifest = {
        "orchestrator_execution_id": envelope["orchestrator_execution_id"],
        "plan_digest": envelope["plan_digest"],
        "capability_code": CAPABILITY_CODE,
        "task_packet_work_digest": envelope["task_packet_work_digest"],
        "profile_source_digest": envelope["profile_source_digest"],
        "source_revision": envelope["source_revision"],
    }
    mismatches = [key for key, value in expected_manifest.items() if manifest.get(key) != value]
    if mismatches:
        return _block("BLOCK_EXISTING_CHILD_MANIFEST_CROSSBIND_MISMATCH", {"fields": mismatches})

    if not isinstance(receipt_readback, dict):
        return _block("BLOCK_DISPATCH_RECEIPT_READBACK_MISSING")
    expected_receipt = {
        "receipt_id": receipt_id,
        "receipt_sha256": envelope["dispatch_receipt_sha256"],
        "consumer_execution_id": consumer_execution_id,
        "orchestrator_execution_id": envelope["orchestrator_execution_id"],
        "capability_code": CAPABILITY_CODE,
        "plan_digest": envelope["plan_digest"],
    }
    receipt_mismatch = [key for key, value in expected_receipt.items() if str(receipt_readback.get(key)) != str(value)]
    if receipt_mismatch:
        return _block("BLOCK_DISPATCH_RECEIPT_CROSSBIND_MISMATCH", {"fields": receipt_mismatch})

    guard = envelope.get("entry_guard")
    if not isinstance(guard, dict) or guard.get("ready") is not True:
        return _block("BLOCK_ENTRY_GUARD_READBACK_MISSING")
    guard_expected = {
        "decision": "ORCHESTRATOR_ENTRY_ACCEPTED",
        "guard_code": "ORCHESTRATOR_EXECUTION_GUARD_V1",
        "receipt_id": receipt_id,
        "orchestrator_execution_id": envelope["orchestrator_execution_id"],
        "consumer_execution_id": consumer_execution_id,
        "capability_code": CAPABILITY_CODE,
        "plan_digest": envelope["plan_digest"],
    }
    guard_mismatch = [key for key, value in guard_expected.items() if str(guard.get(key)) != str(value)]
    if guard_mismatch:
        return _block("BLOCK_ENTRY_GUARD_CROSSBIND_MISMATCH", {"fields": guard_mismatch})

    if envelope["source_revision"] != runtime_source_revision:
        return _block("BLOCK_RUNTIME_SOURCE_REVISION_MISMATCH")

    profile_source_paths = queue_row.get("profile_source_paths")
    embedded = isinstance(profile_source_paths, list) and any(
        isinstance(path, str) and path.startswith("skills/") for path in profile_source_paths
    )
    if embedded:
        if not isinstance(task_runtime_binding_resolution, dict):
            return _block("BLOCK_EMBEDDED_PROFILE_TASK_BINDING_MISSING")
        if task_runtime_binding_resolution.get("schema_version") != "LF_PROFILE_TASK_RUNTIME_BINDING_V1" or task_runtime_binding_resolution.get("status") != "RESOLVED":
            return _block("BLOCK_EMBEDDED_PROFILE_TASK_BINDING_INVALID")
        binding = task_runtime_binding_resolution.get("binding")
        binding_digest = task_runtime_binding_resolution.get("binding_digest")
        if not isinstance(binding, dict) or not isinstance(binding_digest, str) or _digest(binding) != binding_digest:
            return _block("BLOCK_EMBEDDED_PROFILE_TASK_BINDING_DIGEST_MISMATCH")
        if binding.get("source_mode") != "EMBEDDED_SKILL_PROFILE":
            return _block("BLOCK_EMBEDDED_PROFILE_SOURCE_MODE_MISMATCH")
        if binding.get("profile_code") != queue_row.get("profile_code") or binding.get("profile_slug") != queue_row.get("profile_slug"):
            return _block("BLOCK_EMBEDDED_PROFILE_IDENTITY_MISMATCH")
        if binding.get("source_revision") != runtime_source_revision:
            return _block("BLOCK_EMBEDDED_PROFILE_REVISION_MISMATCH")

    result = {
        "schema_version": "LF_PROFILE_RUNTIME_ORCHESTRATED_ATTACH_RESULT_V1",
        "status": "READY",
        "decision": "ATTACH_EXISTING_CHILD_ACCEPTED",
        "consumer_execution_id": consumer_execution_id,
        "orchestrator_execution_id": envelope["orchestrator_execution_id"],
        "task_packet_work_digest": envelope["task_packet_work_digest"],
        "final_task_packet_digest": envelope["final_task_packet_digest"],
        "dispatch_receipt_id": receipt_id,
        "profile_source_mode": "EMBEDDED_SKILL_PROFILE" if embedded else "STANDALONE_PROFILE",
        "second_begin_allowed": False,
    }
    result["result_digest"] = _digest(result)
    return result
