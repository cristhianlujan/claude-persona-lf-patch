#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
from typing import Any

SCHEMA = "LF_INPUT_GOVERNANCE_RUNTIME_BINDING_V1"
ALLOWED_GOVERNANCE_CONSUMERS = {"STORY_CREATOR", "CONTEXT_PACK", "MANUAL"}


class GovernanceBindingError(ValueError):
    pass


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _canonical_sha256(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return _sha256_text(raw)


def _is_sha256(value: Any) -> bool:
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def build_bound_governance_receipt(
    router_result: dict[str, Any], *, request_id: str, profile_code: str, input_literal: str,
    governance_consumer: str = "CONTEXT_PACK",
) -> dict[str, Any]:
    if governance_consumer not in ALLOWED_GOVERNANCE_CONSUMERS:
        raise GovernanceBindingError("INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED")
    if not isinstance(router_result, dict):
        raise GovernanceBindingError("ROUTER_RESULT_NOT_OBJECT")
    if router_result.get("status") != "READY" or router_result.get("continuation_allowed") is not True:
        raise GovernanceBindingError("INPUT_GOVERNANCE_NOT_READY")
    receipt = router_result.get("governance_receipt")
    if not isinstance(receipt, dict):
        raise GovernanceBindingError("INPUT_GOVERNANCE_RECEIPT_MISSING")
    if receipt.get("decision") != "PASS" or receipt.get("currentness") != "LIVE_CURRENT":
        raise GovernanceBindingError("INPUT_GOVERNANCE_RECEIPT_NOT_CURRENT_PASS")
    snapshot_hash = receipt.get("snapshot_hash")
    contract_snapshot_hash = receipt.get("contract_snapshot_hash")
    if not _is_sha256(snapshot_hash) or not _is_sha256(contract_snapshot_hash):
        raise GovernanceBindingError("INPUT_GOVERNANCE_SNAPSHOT_HASH_INVALID")
    if not isinstance(receipt.get("run_id"), int) or not isinstance(receipt.get("pantalla_id"), int):
        raise GovernanceBindingError("INPUT_GOVERNANCE_SUBJECT_INVALID")
    screen_code = receipt.get("screen_code")
    if not isinstance(screen_code, str) or not screen_code.strip():
        raise GovernanceBindingError("INPUT_GOVERNANCE_SCREEN_CODE_MISSING")
    if not request_id or not profile_code or not input_literal.strip():
        raise GovernanceBindingError("REQUEST_BINDING_INPUT_INVALID")

    bound = {
        "schema": SCHEMA,
        "request_id": request_id,
        "profile_code": profile_code,
        "governance_consumer": governance_consumer,
        "input_sha256": _sha256_text(input_literal),
        "source_snapshot_sha256": snapshot_hash,
        "contract_snapshot_sha256": contract_snapshot_hash,
        "run_id": receipt["run_id"],
        "pantalla_id": receipt["pantalla_id"],
        "screen_code": screen_code,
        "decision": "PASS",
        "currentness": "LIVE_CURRENT",
        "governance_receipt_sha256": _canonical_sha256(receipt),
        "governance_receipt": receipt,
    }
    bound["binding_sha256"] = _canonical_sha256(bound)
    return bound


def validate_bound_governance_receipt(
    bound: dict[str, Any], *, request_id: str, profile_code: str, input_literal: str,
    governance_consumer: str = "CONTEXT_PACK",
) -> dict[str, Any]:
    if governance_consumer not in ALLOWED_GOVERNANCE_CONSUMERS:
        raise GovernanceBindingError("INPUT_GOVERNANCE_CONSUMER_NOT_ALLOWED")
    if not isinstance(bound, dict) or bound.get("schema") != SCHEMA:
        raise GovernanceBindingError("INPUT_GOVERNANCE_BINDING_SCHEMA_INVALID")
    expected = {
        "request_id": request_id,
        "profile_code": profile_code,
        "governance_consumer": governance_consumer,
        "input_sha256": _sha256_text(input_literal),
        "decision": "PASS",
        "currentness": "LIVE_CURRENT",
    }
    for key, value in expected.items():
        if bound.get(key) != value:
            raise GovernanceBindingError(f"INPUT_GOVERNANCE_BINDING_{key.upper()}_MISMATCH")
    receipt = bound.get("governance_receipt")
    if not isinstance(receipt, dict):
        raise GovernanceBindingError("INPUT_GOVERNANCE_RECEIPT_MISSING")
    if bound.get("source_snapshot_sha256") != receipt.get("snapshot_hash"):
        raise GovernanceBindingError("INPUT_GOVERNANCE_SOURCE_SNAPSHOT_MISMATCH")
    if bound.get("contract_snapshot_sha256") != receipt.get("contract_snapshot_hash"):
        raise GovernanceBindingError("INPUT_GOVERNANCE_CONTRACT_SNAPSHOT_MISMATCH")
    if bound.get("governance_receipt_sha256") != _canonical_sha256(receipt):
        raise GovernanceBindingError("INPUT_GOVERNANCE_RECEIPT_HASH_MISMATCH")
    actual_binding_hash = bound.get("binding_sha256")
    if not _is_sha256(actual_binding_hash):
        raise GovernanceBindingError("INPUT_GOVERNANCE_BINDING_HASH_INVALID")
    unhashed = dict(bound)
    unhashed.pop("binding_sha256", None)
    if actual_binding_hash != _canonical_sha256(unhashed):
        raise GovernanceBindingError("INPUT_GOVERNANCE_BINDING_HASH_MISMATCH")
    return bound
