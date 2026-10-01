#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

CAPABILITY_CODE = "WAIVER_AUTHORITY"
ENTRY_ACCEPTED = "ORCHESTRATOR_ENTRY_ACCEPTED"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
CURRENTNESS_DECISIONS = {"CURRENT", "CURRENT_REBOUND"}
PLAN_DECISIONS = {"MATCH", "AUTHORIZED_DELTA"}


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _without_digest(value: dict[str, Any], field: str) -> dict[str, Any]:
    out = dict(value)
    out.pop(field, None)
    return out


def receipt_digest(value: dict[str, Any], field: str) -> str:
    return canonical_sha256(_without_digest(value, field))


def _blocked(reason: str, request: dict[str, Any] | None = None, waiver_id: Any = None) -> dict[str, Any]:
    out = {
        "schema_version": "LF_WAIVER_AUTHORITY_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "decision": "WAIVER_BLOCKED",
        "ready": False,
        "reason": reason,
        "post_pase_execution_id": (request or {}).get("post_pase_execution_id"),
        "control_id": (request or {}).get("control_id"),
        "plan_digest": (request or {}).get("plan_digest"),
        "merge_sha": (request or {}).get("merge_sha"),
        "source_revision": (request or {}).get("source_revision"),
        "subject_ref": (request or {}).get("subject_ref"),
        "request_digest": (request or {}).get("request_digest"),
        "waiver_id": waiver_id,
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out


def _validate_request(request: dict[str, Any]) -> str | None:
    if request.get("schema_version") != "LF_WAIVER_AUTHORITY_REQUEST_V1":
        return "REQUEST_SCHEMA_MISMATCH"
    if request.get("capability_code") != CAPABILITY_CODE:
        return "CAPABILITY_CODE_MISMATCH"
    entry = request.get("entry_guard_readback")
    if not isinstance(entry, dict) or entry.get("decision") != ENTRY_ACCEPTED:
        return "ORCHESTRATOR_ENTRY_REQUIRED"
    for field in (
        "orchestrator_execution_id",
        "consumer_execution_id",
        "dispatch_receipt_id",
        "post_pase_execution_id",
        "control_id",
        "subject_ref",
        "plan_digest",
        "merge_sha",
        "source_revision",
        "request_digest",
    ):
        if not isinstance(request.get(field), str) or not request.get(field):
            return f"REQUEST_FIELD_MISSING:{field}"
    if not HEX64.fullmatch(request["plan_digest"]) or not HEX64.fullmatch(request["request_digest"]):
        return "REQUEST_DIGEST_INVALID"
    if not HEX40.fullmatch(request["merge_sha"]) or not HEX40.fullmatch(request["source_revision"]):
        return "REQUEST_REVISION_INVALID"
    refs = request.get("authority_refs")
    if not isinstance(refs, dict):
        return "AUTHORITY_REFS_REQUIRED"
    for field in ("plan_authority_receipt_digest", "currentness_receipt_sha256", "grant_readback_digest", "consumption_readback_digest"):
        if not HEX64.fullmatch(refs.get(field) or ""):
            return f"AUTHORITY_REF_INVALID:{field}"
    return None


def _validate_plan(request: dict[str, Any], receipt: dict[str, Any]) -> str | None:
    if not isinstance(receipt, dict) or receipt.get("schema_version") != "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1":
        return "PLAN_AUTHORITY_RECEIPT_REQUIRED"
    if receipt.get("decision") not in PLAN_DECISIONS or receipt.get("ready") is not True:
        return "PLAN_AUTHORITY_NOT_READY"
    if receipt.get("resolved_plan_digest") != request["plan_digest"]:
        return "PLAN_AUTHORITY_DIGEST_MISMATCH"
    if receipt.get("receipt_digest") != receipt_digest(receipt, "receipt_digest"):
        return "PLAN_AUTHORITY_RECEIPT_DIGEST_MISMATCH"
    if request["authority_refs"]["plan_authority_receipt_digest"] != receipt["receipt_digest"]:
        return "PLAN_AUTHORITY_REQUEST_CROSSBIND_MISMATCH"
    return None


def _validate_currentness(request: dict[str, Any], receipt: dict[str, Any]) -> str | None:
    if not isinstance(receipt, dict) or receipt.get("schema_version") != "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1":
        return "CURRENTNESS_RECEIPT_REQUIRED"
    if receipt.get("authority_layer") != "CURRENTNESS_AUTHORITY":
        return "CURRENTNESS_AUTHORITY_LAYER_MISMATCH"
    if receipt.get("decision") not in CURRENTNESS_DECISIONS or receipt.get("ready") is not True:
        return "CURRENTNESS_NOT_READY"
    if receipt.get("current_revision") != request["source_revision"]:
        return "CURRENTNESS_SOURCE_REVISION_MISMATCH"
    if receipt.get("receipt_sha256") != receipt_digest(receipt, "receipt_sha256"):
        return "CURRENTNESS_RECEIPT_DIGEST_MISMATCH"
    if request["authority_refs"]["currentness_receipt_sha256"] != receipt["receipt_sha256"]:
        return "CURRENTNESS_REQUEST_CROSSBIND_MISMATCH"
    return None


def _identity(request: dict[str, Any]) -> dict[str, Any]:
    return {
        "post_pase_execution_id": request["post_pase_execution_id"],
        "control_id": request["control_id"],
        "plan_digest": request["plan_digest"],
        "merge_sha": request["merge_sha"],
        "source_revision": request["source_revision"],
        "subject_ref": request["subject_ref"],
    }


def _validate_grant(request: dict[str, Any], grant: dict[str, Any]) -> str | None:
    if not isinstance(grant, dict) or grant.get("schema_version") != "LF_POST_PASE_WAIVER_GRANT_READBACK_V1":
        return "WAIVER_GRANT_READBACK_REQUIRED"
    if grant.get("authority_layer") != "WAIVER_AUTHORITY_STORE":
        return "WAIVER_GRANT_AUTHORITY_LAYER_MISMATCH"
    if grant.get("decision") != "WAIVER_GRANT_CURRENT" or grant.get("ready") is not True:
        return "WAIVER_GRANT_NOT_CURRENT"
    if grant.get("scope") != _identity(request):
        return "WAIVER_GRANT_SCOPE_MISMATCH"
    if grant.get("approval_authority") != "LF_GOVERNANCE" or grant.get("approval_decision") != "APPROVED":
        return "WAIVER_APPROVAL_AUTHORITY_INVALID"
    if not isinstance(grant.get("approval_event_id"), int) or grant["approval_event_id"] <= 0:
        return "WAIVER_APPROVAL_EVENT_INVALID"
    if grant.get("max_uses") != 1 or grant.get("uses_count") != 0 or grant.get("active") is not True:
        return "WAIVER_GRANT_ONE_USE_STATE_INVALID"
    if grant.get("consumed_at") is not None:
        return "WAIVER_GRANT_ALREADY_CONSUMED"
    if not isinstance(grant.get("rationale"), str) or len(grant["rationale"].strip()) < 20:
        return "WAIVER_RATIONALE_INVALID"
    if not HEX64.fullmatch(grant.get("grant_sha256") or ""):
        return "WAIVER_GRANT_DIGEST_INVALID"
    if grant.get("readback_digest") != receipt_digest(grant, "readback_digest"):
        return "WAIVER_GRANT_READBACK_DIGEST_MISMATCH"
    if request["authority_refs"]["grant_readback_digest"] != grant["readback_digest"]:
        return "WAIVER_GRANT_REQUEST_CROSSBIND_MISMATCH"
    return None


def _validate_consumption(request: dict[str, Any], grant: dict[str, Any], consumption: dict[str, Any]) -> str | None:
    if not isinstance(consumption, dict) or consumption.get("schema_version") != "LF_POST_PASE_WAIVER_CONSUMPTION_READBACK_V1":
        return "WAIVER_CONSUMPTION_READBACK_REQUIRED"
    if consumption.get("authority_layer") != "WAIVER_AUTHORITY_STORE":
        return "WAIVER_CONSUMPTION_AUTHORITY_LAYER_MISMATCH"
    if consumption.get("decision") != "WAIVER_CONSUMED" or consumption.get("ready") is not True:
        return "WAIVER_NOT_CONSUMED"
    if consumption.get("waiver_id") != grant.get("waiver_id"):
        return "WAIVER_CONSUMPTION_ID_MISMATCH"
    if consumption.get("scope") != _identity(request):
        return "WAIVER_CONSUMPTION_SCOPE_MISMATCH"
    if consumption.get("max_uses") != 1 or consumption.get("uses_count") != 1 or consumption.get("active") is not False:
        return "WAIVER_CONSUMPTION_ONE_USE_STATE_INVALID"
    if not consumption.get("consumed_at"):
        return "WAIVER_CONSUMPTION_TIMESTAMP_MISSING"
    if consumption.get("consumed_by_execution_id") != request["consumer_execution_id"]:
        return "WAIVER_CONSUMPTION_EXECUTION_MISMATCH"
    if consumption.get("consumed_by_request_digest") != request["request_digest"]:
        return "WAIVER_CONSUMPTION_REQUEST_MISMATCH"
    if consumption.get("grant_sha256") != grant.get("grant_sha256"):
        return "WAIVER_CONSUMPTION_GRANT_DIGEST_MISMATCH"
    if consumption.get("readback_digest") != receipt_digest(consumption, "readback_digest"):
        return "WAIVER_CONSUMPTION_READBACK_DIGEST_MISMATCH"
    if request["authority_refs"]["consumption_readback_digest"] != consumption["readback_digest"]:
        return "WAIVER_CONSUMPTION_REQUEST_CROSSBIND_MISMATCH"
    return None


def evaluate_waiver_authority(
    *,
    request: dict[str, Any],
    plan_authority_receipt: dict[str, Any],
    currentness_receipt: dict[str, Any],
    grant_readback: dict[str, Any],
    consumption_readback: dict[str, Any],
) -> dict[str, Any]:
    reason = _validate_request(request)
    if reason:
        return _blocked(reason, request)
    reason = _validate_plan(request, plan_authority_receipt)
    if reason:
        return _blocked(reason, request)
    reason = _validate_currentness(request, currentness_receipt)
    if reason:
        return _blocked(reason, request)
    reason = _validate_grant(request, grant_readback)
    if reason:
        return _blocked(reason, request, grant_readback.get("waiver_id") if isinstance(grant_readback, dict) else None)
    reason = _validate_consumption(request, grant_readback, consumption_readback)
    if reason:
        return _blocked(reason, request, grant_readback.get("waiver_id"))

    out = {
        "schema_version": "LF_WAIVER_AUTHORITY_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "decision": "WAIVER_AUTHORIZED",
        "ready": True,
        "reason": "EXACT_APPROVED_CURRENT_ONE_USE_WAIVER_CONSUMED",
        **_identity(request),
        "request_digest": request["request_digest"],
        "waiver_id": grant_readback["waiver_id"],
        "grant_sha256": grant_readback["grant_sha256"],
        "approval_event_id": grant_readback["approval_event_id"],
        "approval_authority": "LF_GOVERNANCE",
        "plan_authority_receipt_digest": plan_authority_receipt["receipt_digest"],
        "currentness_receipt_sha256": currentness_receipt["receipt_sha256"],
        "grant_readback_digest": grant_readback["readback_digest"],
        "consumption_readback_digest": consumption_readback["readback_digest"],
        "consumed_at": consumption_readback["consumed_at"],
        "consumed_by_execution_id": consumption_readback["consumed_by_execution_id"],
        "closure_status": None,
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out
