#!/usr/bin/env python3
"""Read-only pre-dispatch handoff for an unresolved ACT-0001 request.

This is NOT a selector, operational queue, profile runner, authorizer or
second Router. It freezes the exact input and canonical references for a
separately governed semantic/authority consumer. No execution is permitted.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping


SCHEMA = "LF_ROUTER_LEVEL2_ADVISORY_HANDOFF_V1"
BLOCK_CODE = "BLOCK_EXECUTOR_CAPABILITY_UNATTESTED"


def _digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _canonical_digest(value: Any) -> str:
    return _digest(json.dumps(value, ensure_ascii=False, sort_keys=True,
                              separators=(",", ":")))


def prepare_handoff(
    input_literal: str,
    router_receipt: Mapping[str, Any],
    current_catalog: Mapping[str, Any],
    *,
    capability_selection: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Freeze discovery-only material; fail closed on missing or stale bindings.

    Caller must supply the actual ACT-0001 receipt and a trusted catalog
    readback; this function cannot authenticate the supplier. It must never
    be used to bypass ACT-0001 or convert a candidate into an executor.
    """
    def blocked(code: str) -> dict[str, Any]:
        return {"status": "BLOCKED", "blocking_code": code,
                "profile_execution_authorized": False,
                "downstream_execution_allowed": False}

    if not isinstance(input_literal, str) or not input_literal.strip():
        return blocked("BLOCK_EMPTY_REQUEST")
    if not isinstance(router_receipt, Mapping):
        return blocked("BLOCK_ROUTER_RECEIPT_MISSING")
    if (router_receipt.get("router") != "ACT-0001"
            or router_receipt.get("source") != "SUPABASE"
            or router_receipt.get("status") != "BLOCKED"
            or router_receipt.get("blocking_code") != BLOCK_CODE
            or router_receipt.get("operation_code") is not None
            or router_receipt.get("downstream_execution_allowed") is not False):
        return blocked("BLOCK_ROUTER_RECEIPT_NOT_ADVISORY")
    sha = _digest(input_literal)
    if router_receipt.get("request_sha256") != sha:
        return blocked("BLOCK_ORIGINAL_REQUEST_DRIFT")

    if not isinstance(current_catalog, Mapping):
        return blocked("BLOCK_CATALOG_READBACK_MISSING")
    revision = current_catalog.get("revision_sha256")
    if not isinstance(revision, str) or len(revision) != 64 or any(
            c not in "0123456789abcdef" for c in revision):
        return blocked("BLOCK_CATALOG_CURRENTNESS_MISSING")
    subjects = current_catalog.get("subjects")
    executors = current_catalog.get("executors")
    if not isinstance(subjects, Mapping) or not isinstance(executors, Mapping):
        return blocked("BLOCK_CATALOG_SHAPE_INVALID")

    incoming_subjects = router_receipt.get("subject_candidates", [])
    subject_state = router_receipt.get("subject_binding_state")
    if not isinstance(incoming_subjects, list) or subject_state not in (
            "UNRESOLVED", "RESOLVED", "AMBIGUOUS"):
        return blocked("BLOCK_SUBJECT_BINDING_INVALID")
    if (subject_state == "RESOLVED" and len(incoming_subjects) != 1) or (
            subject_state == "AMBIGUOUS" and len(incoming_subjects) < 2) or (
            subject_state == "UNRESOLVED" and incoming_subjects):
        return blocked("BLOCK_SUBJECT_CARDINALITY_DRIFT")

    subject_refs: list[dict[str, Any]] = []
    seen_subjects: set[str] = set()
    for item in incoming_subjects:
        if not isinstance(item, Mapping):
            return blocked("BLOCK_SUBJECT_CANDIDATE_INVALID")
        code = item.get("screen_code")
        canonical = subjects.get(code) if isinstance(code, str) else None
        if (not isinstance(code, str) or code in seen_subjects
                or not isinstance(canonical, Mapping)
                or canonical.get("type") != "PANTALLA"
                or canonical.get("active") is not True
                or canonical.get("state") != item.get("screen_state")
                or canonical.get("module_code") != item.get("module_code")):
            return blocked("BLOCK_SUBJECT_CURRENTNESS_DRIFT")
        seen_subjects.add(code)
        subject_refs.append({"code": code, "type": "PANTALLA",
                             "state": canonical["state"],
                             "module_code": canonical["module_code"]})

    incoming_executors = router_receipt.get("executor_candidates")
    if not isinstance(incoming_executors, list):
        return blocked("BLOCK_EXECUTOR_CANDIDATES_MISSING")
    executor_refs: list[dict[str, Any]] = []
    seen_executors: set[str] = set()
    for item in incoming_executors:
        if not isinstance(item, Mapping):
            return blocked("BLOCK_EXECUTOR_CANDIDATE_INVALID")
        code = item.get("asset_code")
        kind = item.get("asset_type")
        canonical = executors.get(code) if isinstance(code, str) else None
        if (kind not in ("PERFIL", "SKILL") or not isinstance(code, str)
                or code in seen_executors or not isinstance(canonical, Mapping)
                or canonical.get("type") != kind
                or canonical.get("operational_status") != item.get("operational_status")):
            return blocked("BLOCK_EXECUTOR_CURRENTNESS_DRIFT")
        seen_executors.add(code)
        executor_refs.append({"code": code, "type": kind,
                              "operational_status": canonical["operational_status"],
                              "runtime_enabled": canonical.get("runtime_enabled") is True})

    capability_refs: list[str] = []
    if capability_selection is not None:
        if not isinstance(capability_selection, Mapping):
            return blocked("BLOCK_CAPABILITY_SELECTION_INVALID")
        selected = capability_selection.get("selected_capabilities")
        state = capability_selection.get("fallback_state")
        if (state not in ("CLEAR", "MULTI", "NO_SIGNAL", "CONTRADICTORY", "CAPABILITY_FAILURE")
                or not isinstance(selected, list)
                or any(not isinstance(c, str) for c in selected)
                or len(selected) != len(set(selected))):
            return blocked("BLOCK_CAPABILITY_SELECTION_INVALID")
        released = current_catalog.get("released_capabilities")
        if not isinstance(released, Mapping) or any(
                not isinstance(released.get(code), Mapping)
                or released[code].get("release_state") != "RELEASED"
                or not released[code].get("manifest_sha256")
                for code in selected):
            return blocked("BLOCK_CAPABILITY_RELEASE_NOT_CURRENT")
        capability_refs = list(selected)

    packet = {
        "schema": SCHEMA,
        "status": "ADVISORY_ONLY",
        "input_literal": input_literal,
        "request_sha256": sha,
        "router": "ACT-0001",
        "router_status": "BLOCKED",
        "router_blocking_code": BLOCK_CODE,
        "catalog_revision_sha256": revision,
        "subject_binding_state": subject_state,
        "subject_candidates": subject_refs,
        "executor_candidates": executor_refs,
        "selected_capability_candidates": capability_refs,
        "next": "RESOLVE_CANONICAL_EXECUTOR_AND_OPERATION",
        "profile_execution_authorized": False,
        "downstream_execution_allowed": False,
        "execution_receipt": None,
        "native_runtime_executed": False,
    }
    packet["handoff_sha256"] = _canonical_digest(packet)
    return packet
