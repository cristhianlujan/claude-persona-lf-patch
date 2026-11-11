#!/usr/bin/env python3
"""PG-01_C3 deterministic scope/front admission candidate; NO runtime authority.

The established A9->PG01 snapshot validator owns matrix consistency. This thin
boundary checks its result against the handoff receipt's material-path coverage
and an exact requested scope subset; it never replaces the receipt verifier.
"""
import json
from pathlib import Path

from validate_wave1_boundary_contracts_v1 import ContractError, validate_programming_snapshot_payload_v1

CONTRACT = json.loads(
    Path(__file__).with_name("programming_entry_contract_v1.json").read_text(encoding="utf-8")
)
ROOT = "extensions.programming_context_snapshot."


def _blocked(reason):
    return {"admissible": False, "reason": reason, "authority": "NONE"}


def assess_scope_front_clean(snapshot, receipt, requested_scope_ids):
    """Fail closed; a candidate admission, not a PG-01 execution receipt."""
    if not isinstance(snapshot, dict):
        return _blocked("PG01_C3_SNAPSHOT_INVALID")
    try:
        validate_programming_snapshot_payload_v1(snapshot)
    except (ContractError, TypeError, ValueError, KeyError) as exc:
        return _blocked("PG01_C3_MATRIX_INVALID:" + str(exc))
    if snapshot.get("package_readiness") not in {"READY", "PARTIAL_READY"}:
        return _blocked("PG01_C3_PACKAGE_NOT_READY")
    if not isinstance(receipt, dict) or receipt.get("verdict") != "ACCEPT":
        return _blocked("PG01_C3_RECEIPT_NOT_ACCEPTED")
    raw_paths = receipt.get("validated_material_paths")
    if not isinstance(raw_paths, list) or any(not isinstance(p, str) for p in raw_paths):
        return _blocked("PG01_C3_MATERIAL_PATHS_INVALID")
    required = CONTRACT["programming_context_snapshot"]["required_fields"]
    expected = {ROOT + field.removesuffix("[]") for field in required}
    if len(raw_paths) != len(set(raw_paths)) or set(raw_paths) != expected:
        return _blocked("PG01_C3_MATERIAL_PATHS_INCOMPLETE_OR_EXTRA")
    if not isinstance(requested_scope_ids, list) or not requested_scope_ids or any(
        not isinstance(scope, str) or not scope.strip() for scope in requested_scope_ids
    ):
        return _blocked("PG01_C3_REQUESTED_SCOPES_INVALID")
    if len(requested_scope_ids) != len(set(requested_scope_ids)):
        return _blocked("PG01_C3_REQUESTED_SCOPES_DUPLICATE")
    allowed = {
        scope["scope_id"]
        for scope in snapshot["scope_readiness"]
        if scope["status"] == "READY"
    }
    if not set(requested_scope_ids).issubset(allowed):
        return _blocked("PG01_C3_REQUESTED_SCOPE_NOT_READY")
    return {
        "admissible": True,
        "reason": "PG01_C3_CLEAN_READY_SCOPE_CANDIDATE",
        "scope_ids": sorted(requested_scope_ids),
        "matrix_pairs": len(snapshot["scope_front_matrix"]),
        "authority": "NONE",
        "runtime_verified": False,
    }
