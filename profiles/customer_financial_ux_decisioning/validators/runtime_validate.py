#!/usr/bin/env python3
"""Deterministic cross-field contract check for Customer Financial UX Decisioning output.

Structural only: it does not prove that any monetary figure or source claim is true.
"""
from __future__ import annotations

OUTPUT_TYPES = {"CUSTOMER_FINANCIAL_DECISION_SPEC", "MISSING_MATERIAL_FINANCIAL_INPUT", "BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM"}
STATUSES = {"READY_FOR_REVIEW", "NEEDS_INPUT", "BLOCKED", "NEEDS_REPAIR"}
SPEC_REQUIRED = ("decision_id", "decision_question", "comparison_basis", "options", "must_understand",
                 "uncertainties", "claim_guardrails", "handoff_to_next")
OPTION_REQUIRED = ("option_id", "terms", "customer_consequence", "timing", "monetary_basis", "key_tradeoff", "authority_refs")


def _nonempty_str(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate(payload):
    errors: list[dict[str, str]] = []

    def reject(code, path="$"):
        errors.append({"code": code, "path": path})

    if not isinstance(payload, dict):
        return {"status": "FAIL", "errors": [{"code": "CFUX_PAYLOAD_NOT_OBJECT", "path": "$"}]}
    kind = payload.get("output_type")
    if kind not in OUTPUT_TYPES:
        reject("CFUX_OUTPUT_TYPE_INVALID", "$.output_type")
    if payload.get("status") not in STATUSES:
        reject("CFUX_STATUS_INVALID", "$.status")
    if payload.get("self_verdict") != payload.get("status"):
        reject("CFUX_SELF_VERDICT_STATUS_MISMATCH", "$.self_verdict")

    evidence = payload.get("evidence_map")
    if not isinstance(evidence, list) or not evidence:
        reject("CFUX_EVIDENCE_MAP_REQUIRED", "$.evidence_map")
    else:
        for i, item in enumerate(evidence):
            if not isinstance(item, dict) or not _nonempty_str(item.get("source_ref")) or not isinstance(item.get("supports"), list) or not item["supports"]:
                reject("CFUX_EVIDENCE_ITEM_INVALID", f"$.evidence_map[{i}]")

    if kind == "CUSTOMER_FINANCIAL_DECISION_SPEC":
        for key in SPEC_REQUIRED:
            if key not in payload:
                reject("CFUX_SPEC_FIELD_MISSING", f"$.{key}")
        if payload.get("status") == "READY_FOR_REVIEW" and payload.get("blocked") is True:
            reject("CFUX_READY_BUT_BLOCKED", "$.blocked")
        options = payload.get("options")
        if not isinstance(options, list) or not options:
            reject("CFUX_OPTIONS_REQUIRED", "$.options")
        else:
            ids = [o.get("option_id") if isinstance(o, dict) else None for o in options]
            if len(set(ids)) != len(ids) or None in ids:
                reject("CFUX_OPTION_ID_DUPLICATE_OR_MISSING", "$.options")
            for i, option in enumerate(options):
                if not isinstance(option, dict):
                    reject("CFUX_OPTION_NOT_OBJECT", f"$.options[{i}]")
                    continue
                for key in OPTION_REQUIRED:
                    if key not in option:
                        reject("CFUX_OPTION_FIELD_MISSING", f"$.options[{i}].{key}")
                refs = option.get("authority_refs")
                if not isinstance(refs, list) or not refs or not all(_nonempty_str(r) for r in refs):
                    reject("CFUX_OPTION_WITHOUT_AUTHORITY", f"$.options[{i}].authority_refs")
    elif kind == "MISSING_MATERIAL_FINANCIAL_INPUT":
        if payload.get("blocked") is not True or not isinstance(payload.get("missing_inputs"), list) or not payload["missing_inputs"]:
            reject("CFUX_MISSING_INPUT_CONTRACT", "$.missing_inputs")
        if payload.get("status") == "READY_FOR_REVIEW":
            reject("CFUX_MISSING_INPUT_CANNOT_BE_READY", "$.status")
    elif kind == "BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM":
        if payload.get("blocked") is not True or not _nonempty_str(payload.get("blocking_reason")):
            reject("CFUX_BLOCKED_CLAIM_CONTRACT", "$.blocking_reason")
        if payload.get("status") == "READY_FOR_REVIEW":
            reject("CFUX_BLOCKED_CLAIM_CANNOT_BE_READY", "$.status")

    return {"status": "FAIL" if errors else "PASS", "errors": errors}
