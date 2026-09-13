from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

from .settings import Settings

PENDING_CLASSIFICATION = "INSTALLED_NOT_INTEGRATED_PENDING_LIVE_REVERIFY"
VERIFIED_CLASSIFICATION = "INTEGRATED_LIVE_REVERIFIED_READ_ONLY"
MARKER_SCHEMA = "lf-profile-runtime-live-reverify/v1"
_SHA40 = re.compile(r"^[0-9a-f]{40}$")


def marker_path(settings: Settings) -> Path:
    return settings.state_dir / "live_reverify.json"


def marker_digest(payload: dict[str, Any]) -> str:
    body = {key: value for key, value in payload.items() if key != "evidence_sha256"}
    raw = json.dumps(body, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _valid_marker(payload: Any, source_sha: str) -> bool:
    if not isinstance(payload, dict) or not _SHA40.fullmatch(source_sha):
        return False
    digest = payload.get("evidence_sha256")
    if not isinstance(digest, str) or digest != marker_digest(payload):
        return False
    if payload.get("schema") != MARKER_SCHEMA or payload.get("source_sha") != source_sha:
        return False
    if not isinstance(payload.get("request_id"), str) or not payload["request_id"].strip():
        return False
    if payload.get("queue_status") != "SUCCEEDED":
        return False
    if payload.get("runtime_completion") != "PASS":
        return False
    if payload.get("profile_contract_valid") != "PASS":
        return False
    if payload.get("semantic_utility") != "PASS":
        return False
    if payload.get("downstream_authorized") is not False:
        return False
    if payload.get("canonical_registration_required") is not False:
        return False
    if payload.get("read_only") is not True or payload.get("no_write") is not True or payload.get("no_promotion") is not True:
        return False
    return True


def deployment_state(settings: Settings) -> dict[str, Any]:
    pending = {
        "deployment_classification": PENDING_CLASSIFICATION,
        "operational_ready": False,
        "live_reverify_request_id": None,
        "live_reverify_verified_at": None,
        "downstream_authorized": False,
    }
    path = marker_path(settings)
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return pending
    if not _valid_marker(payload, settings.source_sha):
        return pending
    return {
        "deployment_classification": VERIFIED_CLASSIFICATION,
        "operational_ready": True,
        "live_reverify_request_id": payload["request_id"],
        "live_reverify_verified_at": payload.get("verified_at"),
        "downstream_authorized": False,
    }
