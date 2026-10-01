#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
CAPABILITY_CODE = "AUTHORITY_READBACK"
ENTRY_ACCEPTED = "ORCHESTRATOR_ENTRY_ACCEPTED"
CURRENTNESS_SCHEMA = "LF_CURRENTNESS_AUTHORITY_RECEIPT_V1"
CURRENTNESS_LAYER = "CURRENTNESS_AUTHORITY"
CURRENTNESS_READY_DECISIONS = {"CURRENT", "CURRENT_REBOUND"}
FORBIDDEN_OBSERVATION_KEYS = {
    "next_gate",
    "post_merge_next_gate",
    "promotion",
    "promotion_result",
    "mutation_result",
    "rebind_result",
}


def canonical_sha256(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()


def scope_digest(scope: dict[str, Any]) -> str:
    return canonical_sha256({k: v for k, v in scope.items() if k != "scope_digest"})


def observation_digest(observation: dict[str, Any]) -> str:
    return canonical_sha256({k: v for k, v in observation.items() if k != "receipt_digest"})


def currentness_digest(receipt: dict[str, Any]) -> str:
    return canonical_sha256({k: v for k, v in receipt.items() if k != "receipt_sha256"})


def _receipt(
    decision: str,
    ready: bool,
    reason: str,
    *,
    request: dict[str, Any],
    scope: dict[str, Any],
    failures: list[dict[str, Any]],
    check_results: list[dict[str, Any]],
) -> dict[str, Any]:
    out = {
        "schema_version": "LF_AUTHORITY_READBACK_RECEIPT_V1",
        "capability_code": CAPABILITY_CODE,
        "decision": decision,
        "ready": ready,
        "reason": reason,
        "plan_digest": request.get("plan_digest"),
        "scope_digest": scope.get("scope_digest"),
        "target": scope.get("target"),
        "check_count": len(scope.get("checks") or []),
        "check_results": check_results,
        "failures": failures,
        "mutation_performed": False,
        "promotion_performed": False,
        "next_gate_selected": False,
    }
    out["receipt_digest"] = canonical_sha256(out)
    return out


def _validate_request(request: dict[str, Any]) -> str | None:
    if request.get("capability_code") != CAPABILITY_CODE:
        return "CAPABILITY_CODE_MISMATCH"
    entry = request.get("entry_guard_readback")
    if not isinstance(entry, dict) or entry.get("decision") != ENTRY_ACCEPTED:
        return "ORCHESTRATOR_ENTRY_REQUIRED"
    for field in (
        "orchestrator_execution_id",
        "consumer_execution_id",
        "plan_digest",
        "dispatch_receipt_id",
        "request_digest",
        "source_revision",
    ):
        if not isinstance(request.get(field), str) or not request[field]:
            return f"REQUEST_FIELD_MISSING:{field}"
    return None


def _validate_scope(scope: dict[str, Any], request: dict[str, Any]) -> str | None:
    if scope.get("schema_version") != "LF_AUTHORITY_READBACK_SCOPE_V1":
        return "SCOPE_SCHEMA_MISMATCH"
    if request.get("plan_digest") != scope.get("plan_digest"):
        return "REQUEST_PLAN_DIGEST_MISMATCH"
    if request.get("source_revision") != scope.get("source_revision"):
        return "REQUEST_SOURCE_REVISION_MISMATCH"
    if scope.get("scope_digest") != scope_digest(scope):
        return "SCOPE_DIGEST_MISMATCH"
    target = scope.get("target")
    if not isinstance(target, dict):
        return "TARGET_REQUIRED"
    if not isinstance(target.get("target_type"), str) or not target["target_type"]:
        return "TARGET_TYPE_REQUIRED"
    if not isinstance(target.get("target_code"), str) or not target["target_code"]:
        return "TARGET_CODE_REQUIRED"
    checks = scope.get("checks")
    if not isinstance(checks, list) or not checks:
        return "CHECKS_REQUIRED"
    ids: list[str] = []
    for row in checks:
        if not isinstance(row, dict):
            return "CHECK_INVALID"
        for field in ("check_id", "adapter_code", "subject_ref", "authority_ref", "expected_source_revision"):
            if not isinstance(row.get(field), str) or not row[field]:
                return f"CHECK_FIELD_MISSING:{field}"
        if not isinstance(row.get("currentness_required"), bool):
            return "CHECK_CURRENTNESS_FLAG_REQUIRED"
        ids.append(row["check_id"])
    if len(ids) != len(set(ids)):
        return "CHECK_ID_DUPLICATE"
    return None


def _validate_currentness(receipt: Any, expected_revision: str) -> str | None:
    if not isinstance(receipt, dict):
        return "CURRENTNESS_RECEIPT_REQUIRED"
    if receipt.get("schema_version") != CURRENTNESS_SCHEMA:
        return "CURRENTNESS_SCHEMA_MISMATCH"
    if receipt.get("authority_layer") != CURRENTNESS_LAYER:
        return "CURRENTNESS_LAYER_MISMATCH"
    if receipt.get("ready") is not True or receipt.get("decision") not in CURRENTNESS_READY_DECISIONS:
        return "CURRENTNESS_NOT_READY"
    if receipt.get("current_revision") != expected_revision:
        return "CURRENTNESS_REVISION_MISMATCH"
    digest = receipt.get("receipt_sha256")
    if not isinstance(digest, str) or not HEX64.fullmatch(digest):
        return "CURRENTNESS_DIGEST_INVALID"
    if digest != currentness_digest(receipt):
        return "CURRENTNESS_DIGEST_MISMATCH"
    return None


def evaluate_authority_readback(
    *,
    request: dict[str, Any],
    scope: dict[str, Any],
    observations: list[dict[str, Any]],
) -> dict[str, Any]:
    err = _validate_request(request)
    if err:
        return _receipt("READBACK_FAILED", False, err, request=request, scope=scope, failures=[{"reason": err}], check_results=[])
    err = _validate_scope(scope, request)
    if err:
        return _receipt("READBACK_FAILED", False, err, request=request, scope=scope, failures=[{"reason": err}], check_results=[])

    if not isinstance(observations, list):
        return _receipt(
            "READBACK_FAILED",
            False,
            "OBSERVATIONS_REQUIRED",
            request=request,
            scope=scope,
            failures=[{"reason": "OBSERVATIONS_REQUIRED"}],
            check_results=[],
        )

    declared = {row["check_id"]: row for row in scope["checks"]}
    observed: dict[str, dict[str, Any]] = {}
    failures: list[dict[str, Any]] = []
    results: list[dict[str, Any]] = []

    for row in observations:
        if not isinstance(row, dict) or not isinstance(row.get("check_id"), str):
            failures.append({"reason": "OBSERVATION_INVALID"})
            continue
        cid = row["check_id"]
        if cid in observed:
            failures.append({"reason": "OBSERVATION_DUPLICATE", "check_id": cid})
            continue
        observed[cid] = row

    for cid in sorted(set(observed) - set(declared)):
        failures.append({"reason": "UNDECLARED_OBSERVATION", "check_id": cid})

    for cid, expected in declared.items():
        row = observed.get(cid)
        check_failures: list[str] = []
        if row is None:
            failures.append({"reason": "DECLARED_OBSERVATION_MISSING", "check_id": cid})
            results.append({"check_id": cid, "decision": "MISSING", "ready": False})
            continue

        if row.get("schema_version") != "LF_AUTHORITY_ADAPTER_OBSERVATION_V1":
            check_failures.append("OBSERVATION_SCHEMA_MISMATCH")
        if row.get("adapter_code") != expected["adapter_code"]:
            check_failures.append("ADAPTER_CODE_MISMATCH")
        if row.get("subject_ref") != expected["subject_ref"]:
            check_failures.append("SUBJECT_REF_MISMATCH")
        if row.get("authority_ref") != expected["authority_ref"]:
            check_failures.append("AUTHORITY_REF_MISMATCH")
        if row.get("source_revision") != expected["expected_source_revision"]:
            check_failures.append("SOURCE_REVISION_MISMATCH")
        if row.get("read_only") is not True:
            check_failures.append("READ_ONLY_REQUIRED")
        if row.get("mutation_performed") is not False:
            check_failures.append("MUTATION_FORBIDDEN")
        if row.get("decision") != "AUTHORITY_MATCH":
            check_failures.append("AUTHORITY_MATCH_REQUIRED")
        if any(key in row for key in FORBIDDEN_OBSERVATION_KEYS):
            check_failures.append("ROUTING_PROMOTION_MUTATION_FIELD_FORBIDDEN")

        digest = row.get("receipt_digest")
        if not isinstance(digest, str) or not HEX64.fullmatch(digest):
            check_failures.append("ADAPTER_RECEIPT_DIGEST_INVALID")
        elif digest != observation_digest(row):
            check_failures.append("ADAPTER_RECEIPT_DIGEST_MISMATCH")

        if expected["currentness_required"]:
            current_err = _validate_currentness(row.get("currentness_receipt"), expected["expected_source_revision"])
            if current_err:
                check_failures.append(current_err)

        if check_failures:
            for reason in check_failures:
                failures.append({"reason": reason, "check_id": cid})
            results.append({"check_id": cid, "decision": "MISMATCH", "ready": False, "reasons": sorted(check_failures)})
        else:
            results.append({
                "check_id": cid,
                "adapter_code": expected["adapter_code"],
                "subject_ref": expected["subject_ref"],
                "authority_ref": expected["authority_ref"],
                "decision": "MATCH",
                "ready": True,
            })

    if failures:
        return _receipt(
            "READBACK_FAILED",
            False,
            "DECLARED_AUTHORITY_SCOPE_MISMATCH",
            request=request,
            scope=scope,
            failures=failures,
            check_results=results,
        )
    return _receipt(
        "READBACK_VERIFIED",
        True,
        "DECLARED_AUTHORITY_SCOPE_VERIFIED",
        request=request,
        scope=scope,
        failures=[],
        check_results=results,
    )
