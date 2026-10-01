#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

HEX64 = re.compile(r"^[0-9a-f]{64}$")
CAPABILITY_CODE = "PLAN_AUTHORITY_DRIFT_GUARD"
CURRENTNESS_DECISIONS = {"CURRENT", "CURRENT_REBOUND"}
ENTRY_ACCEPTED = "ORCHESTRATOR_ENTRY_ACCEPTED"


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def sha256_text(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("CANONICAL_TEXT_REQUIRED")
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def component_hashes(live_snapshot: dict[str, Any]) -> dict[str, str]:
    required = {
        "workstream_sha256": "workstream_canonical_text",
        "work_items_sha256": "work_items_canonical_text",
        "dependencies_sha256": "dependencies_canonical_text",
    }
    out: dict[str, str] = {}
    for digest_name, text_name in required.items():
        text = live_snapshot.get(text_name)
        if not isinstance(text, str):
            raise ValueError(f"LIVE_SNAPSHOT_MISSING:{text_name}")
        out[digest_name] = sha256_text(text)
    return out


def delta_digest(delta: dict[str, Any]) -> str:
    material = {
        "schema_version": "LF_PLAN_AUTHORITY_DELTA_SHA256_V1",
        "delta_event_id": delta.get("delta_event_id"),
        "plan_id": delta.get("plan_id"),
        "previous_plan_digest": delta.get("previous_plan_digest"),
        "next_plan_digest": delta.get("next_plan_digest"),
        "workstream_sha256": delta.get("workstream_sha256"),
        "work_items_sha256": delta.get("work_items_sha256"),
        "dependencies_sha256": delta.get("dependencies_sha256"),
    }
    return canonical_sha256(material)


def _unregistered(reason: str, *, anchor: dict[str, Any] | None = None,
                  live_components: dict[str, str] | None = None,
                  request: dict[str, Any] | None = None,
                  currentness_receipt: dict[str, Any] | None = None) -> dict[str, Any]:
    out = {
        "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "decision": "UNREGISTERED_DRIFT",
        "ready": False,
        "reason": reason,
        "plan_id": (anchor or {}).get("plan_id"),
        "anchor_event_id": (anchor or {}).get("anchor_event_id"),
        "anchor_plan_digest": (anchor or {}).get("legacy_plan_digest"),
        "request_plan_digest": (request or {}).get("plan_digest"),
        "live_components": live_components or {},
        "currentness_receipt_sha256": (currentness_receipt or {}).get("receipt_sha256"),
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out


def _entry_is_valid(request: dict[str, Any]) -> tuple[bool, str]:
    if request.get("capability_code") != CAPABILITY_CODE:
        return False, "CAPABILITY_CODE_MISMATCH"
    entry = request.get("entry_guard_readback")
    if not isinstance(entry, dict) or entry.get("decision") != ENTRY_ACCEPTED:
        return False, "ORCHESTRATOR_ENTRY_REQUIRED"
    for field in (
        "orchestrator_execution_id",
        "consumer_execution_id",
        "plan_digest",
        "dispatch_receipt_id",
        "request_digest",
    ):
        if not isinstance(request.get(field), str) or not request.get(field):
            return False, f"REQUEST_FIELD_MISSING:{field}"
    return True, ""


def _currentness_is_valid(receipt: dict[str, Any]) -> tuple[bool, str]:
    if not isinstance(receipt, dict):
        return False, "CURRENTNESS_RECEIPT_REQUIRED"
    if receipt.get("schema_version") != "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1":
        return False, "CURRENTNESS_RECEIPT_SCHEMA_MISMATCH"
    if receipt.get("authority_layer") != "CURRENTNESS_AUTHORITY":
        return False, "CURRENTNESS_AUTHORITY_LAYER_MISMATCH"
    if receipt.get("ready") is not True or receipt.get("decision") not in CURRENTNESS_DECISIONS:
        return False, "CURRENTNESS_NOT_READY"
    digest = receipt.get("receipt_sha256")
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        return False, "CURRENTNESS_RECEIPT_DIGEST_INVALID"
    return True, ""


def evaluate_plan_authority(
    *,
    request: dict[str, Any],
    anchor: dict[str, Any],
    live_snapshot: dict[str, Any],
    currentness_receipt: dict[str, Any],
    authorized_deltas: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    entry_ok, entry_reason = _entry_is_valid(request)
    if not entry_ok:
        return _unregistered(entry_reason, anchor=anchor, request=request, currentness_receipt=currentness_receipt)

    curr_ok, curr_reason = _currentness_is_valid(currentness_receipt)
    if not curr_ok:
        return _unregistered(curr_reason, anchor=anchor, request=request, currentness_receipt=currentness_receipt)

    if anchor.get("anchor_event_id") != 19435:
        return _unregistered("ANCHOR_EVENT_MISMATCH", anchor=anchor, request=request, currentness_receipt=currentness_receipt)
    if anchor.get("plan_id") != "LF_SUPER_ADMIN_POST_PASE_ARCHITECTURE_V1":
        return _unregistered("ANCHOR_PLAN_ID_MISMATCH", anchor=anchor, request=request, currentness_receipt=currentness_receipt)
    if not HEX64.fullmatch(anchor.get("legacy_plan_digest") or ""):
        return _unregistered("ANCHOR_PLAN_DIGEST_INVALID", anchor=anchor, request=request, currentness_receipt=currentness_receipt)
    if live_snapshot.get("plan_id") != anchor.get("plan_id"):
        return _unregistered("LIVE_PLAN_ID_MISMATCH", anchor=anchor, request=request, currentness_receipt=currentness_receipt)

    try:
        live_components = component_hashes(live_snapshot)
    except ValueError as exc:
        return _unregistered(str(exc), anchor=anchor, request=request, currentness_receipt=currentness_receipt)

    anchor_components = {
        "workstream_sha256": anchor.get("workstream_sha256"),
        "work_items_sha256": anchor.get("work_items_sha256"),
        "dependencies_sha256": anchor.get("dependencies_sha256"),
    }
    if not all(isinstance(v, str) and HEX64.fullmatch(v) for v in anchor_components.values()):
        return _unregistered("ANCHOR_COMPONENT_HASH_INVALID", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)

    if live_components == anchor_components:
        if request.get("plan_digest") != anchor.get("legacy_plan_digest"):
            return _unregistered("REQUEST_PLAN_DIGEST_NOT_ANCHOR", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)
        out = {
            "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
            "capability_code": CAPABILITY_CODE,
            "decision": "MATCH",
            "ready": True,
            "reason": "LIVE_COMPONENTS_MATCH_IMMUTABLE_ANCHOR",
            "plan_id": anchor["plan_id"],
            "anchor_event_id": anchor["anchor_event_id"],
            "anchor_plan_digest": anchor["legacy_plan_digest"],
            "resolved_plan_digest": anchor["legacy_plan_digest"],
            "live_components": live_components,
            "authorized_delta_event_ids": [],
            "currentness_receipt_sha256": currentness_receipt["receipt_sha256"],
        }
        out["receipt_digest"] = canonical_sha256(out)
        return out

    deltas = authorized_deltas or []
    if not deltas:
        return _unregistered("LIVE_COMPONENT_DRIFT_WITHOUT_DELTA", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)

    expected_previous = anchor["legacy_plan_digest"]
    used_ids: list[int] = []
    final_components: dict[str, str] | None = None

    for delta in deltas:
        if delta.get("plan_id") != anchor["plan_id"]:
            return _unregistered("DELTA_PLAN_ID_MISMATCH", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)
        if delta.get("previous_plan_digest") != expected_previous:
            return _unregistered("DELTA_CHAIN_PREVIOUS_MISMATCH", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)
        if not isinstance(delta.get("delta_event_id"), int) or delta["delta_event_id"] <= anchor["anchor_event_id"]:
            return _unregistered("DELTA_EVENT_ID_INVALID", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)
        if not HEX64.fullmatch(delta.get("next_plan_digest") or ""):
            return _unregistered("DELTA_NEXT_DIGEST_INVALID", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)

        components = {
            "workstream_sha256": delta.get("workstream_sha256"),
            "work_items_sha256": delta.get("work_items_sha256"),
            "dependencies_sha256": delta.get("dependencies_sha256"),
        }
        if not all(isinstance(v, str) and HEX64.fullmatch(v) for v in components.values()):
            return _unregistered("DELTA_COMPONENT_HASH_INVALID", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)
        if delta.get("delta_digest") != delta_digest(delta):
            return _unregistered("DELTA_DIGEST_MISMATCH", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)

        expected_previous = delta["next_plan_digest"]
        final_components = components
        used_ids.append(delta["delta_event_id"])

    if final_components != live_components:
        return _unregistered("DELTA_FINAL_COMPONENTS_DO_NOT_MATCH_LIVE", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)
    if request.get("plan_digest") != expected_previous:
        return _unregistered("REQUEST_PLAN_DIGEST_NOT_DELTA_TIP", anchor=anchor, live_components=live_components, request=request, currentness_receipt=currentness_receipt)

    out = {
        "schema_version": "LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "decision": "AUTHORIZED_DELTA",
        "ready": True,
        "reason": "APPEND_ONLY_DELTA_CHAIN_PROVES_LIVE_PLAN",
        "plan_id": anchor["plan_id"],
        "anchor_event_id": anchor["anchor_event_id"],
        "anchor_plan_digest": anchor["legacy_plan_digest"],
        "resolved_plan_digest": expected_previous,
        "live_components": live_components,
        "authorized_delta_event_ids": used_ids,
        "currentness_receipt_sha256": currentness_receipt["receipt_sha256"],
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out
