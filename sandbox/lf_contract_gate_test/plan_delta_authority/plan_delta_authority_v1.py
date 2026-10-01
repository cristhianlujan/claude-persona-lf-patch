#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

SCHEMA_VERSION = "LF_PLAN_DELTA_AUTHORITY_READBACK_V1"
AUTHORITY = "PLAN_AUTHORITY"
GOVERNANCE_AUTHORITY = "LF_GOVERNANCE"
AUTHORIZATION_TOKEN = "PLAN_DELTA_AUTHORITY"
AUTHORIZED = "AUTHORIZED_PLAN_DELTA"
BLOCKED = "PLAN_DELTA_NOT_AUTHORIZED"
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _blocked(reason: str, event_id: Any = None) -> dict[str, Any]:
    out = {
        "schema_version": SCHEMA_VERSION,
        "authority": AUTHORITY,
        "decision": BLOCKED,
        "ready": False,
        "reason": reason,
        "event_id": event_id if isinstance(event_id, int) else None,
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out


def produce_plan_delta_authority(
    *,
    event: dict[str, Any],
    plan_id: str,
    previous_plan_digest: str,
    next_plan_digest: str,
) -> dict[str, Any]:
    if not isinstance(event, dict):
        return _blocked("AUTHORIZATION_EVENT_REQUIRED")
    event_id = event.get("id")
    if not isinstance(event_id, int) or event_id <= 0:
        return _blocked("AUTHORIZATION_EVENT_ID_INVALID", event_id)
    if event.get("evento_tipo") != "DECISION_ESTRATEGICA":
        return _blocked("AUTHORIZATION_EVENT_TYPE_MISMATCH", event_id)
    if event.get("entidad_tipo") != "PROGRAM_PLAN":
        return _blocked("AUTHORIZATION_ENTITY_TYPE_MISMATCH", event_id)
    if event.get("entidad_codigo") != plan_id:
        return _blocked("AUTHORIZATION_PLAN_ENTITY_MISMATCH", event_id)
    if not isinstance(plan_id, str) or not plan_id:
        return _blocked("PLAN_ID_REQUIRED", event_id)
    if not HEX64.fullmatch(previous_plan_digest or ""):
        return _blocked("PREVIOUS_PLAN_DIGEST_INVALID", event_id)
    if not HEX64.fullmatch(next_plan_digest or ""):
        return _blocked("NEXT_PLAN_DIGEST_INVALID", event_id)

    payload = event.get("payload")
    if not isinstance(payload, dict):
        return _blocked("AUTHORIZATION_PAYLOAD_REQUIRED", event_id)
    if payload.get("authority") != GOVERNANCE_AUTHORITY:
        return _blocked("AUTHORIZATION_AUTHORITY_MISMATCH", event_id)
    authorizes = payload.get("authorizes")
    if not isinstance(authorizes, list) or AUTHORIZATION_TOKEN not in authorizes:
        return _blocked("AUTHORIZATION_TOKEN_MISSING", event_id)
    if payload.get("authorization_scope") != AUTHORIZATION_TOKEN:
        return _blocked("AUTHORIZATION_SCOPE_MISMATCH", event_id)
    if payload.get("plan_id") != plan_id:
        return _blocked("AUTHORIZATION_PLAN_ID_MISMATCH", event_id)
    if payload.get("previous_plan_digest") != previous_plan_digest:
        return _blocked("AUTHORIZATION_PREVIOUS_DIGEST_MISMATCH", event_id)
    if payload.get("next_plan_digest") != next_plan_digest:
        return _blocked("AUTHORIZATION_NEXT_DIGEST_MISMATCH", event_id)
    if payload.get("self_authorization") is not False:
        return _blocked("SELF_AUTHORIZATION_NOT_EXPLICITLY_FORBIDDEN", event_id)

    proof = {
        "schema_version": SCHEMA_VERSION,
        "authority": AUTHORITY,
        "decision": AUTHORIZED,
        "event_id": event_id,
        "plan_id": plan_id,
        "previous_plan_digest": previous_plan_digest,
        "next_plan_digest": next_plan_digest,
    }
    proof["receipt_digest"] = canonical_sha256(proof)
    return proof
