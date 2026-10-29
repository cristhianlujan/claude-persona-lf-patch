#!/usr/bin/env python3
"""Deterministic cross-field contract check for Customer Financial UX Decisioning output.

Structural only: it does not prove that any monetary figure or source claim is true.
"""
from __future__ import annotations

import re

OUTPUT_TYPES = {"CUSTOMER_FINANCIAL_DECISION_SPEC", "MISSING_MATERIAL_FINANCIAL_INPUT", "BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM"}
STATUSES = {"READY_FOR_REVIEW", "NEEDS_INPUT", "BLOCKED", "NEEDS_REPAIR"}
SPEC_REQUIRED = ("decision_id", "decision_question", "comparison_basis", "options", "must_understand",
                 "uncertainties", "claim_guardrails", "handoff_to_next")
OPTION_REQUIRED = ("option_id", "terms", "customer_consequence", "timing", "monetary_basis", "key_tradeoff", "authority_refs")


ALLOWED_KEYS = {"output_type", "status", "evidence_map", "decision_id", "decision_question", "comparison_basis",
                "options", "must_understand", "uncertainties", "claim_guardrails", "recommended_presentation_priority",
                "handoff_to_next", "blocked", "missing_inputs", "blocking_reason", "self_verdict"}
SPEC_STATUSES = {"READY_FOR_REVIEW", "NEEDS_REPAIR"}
SPEC_FORBIDDEN = ("missing_inputs", "blocking_reason")


_INVISIBLE = re.compile("[\u200b-\u200f\u2060\ufeff\u00a0]")


def _nonempty_str(value) -> bool:
    return isinstance(value, str) and bool(_INVISIBLE.sub("", value).strip())


def _key(value) -> str:
    """Identity key for ids/refs: case, surrounding spaces and invisible characters do not make a new identity."""
    return _INVISIBLE.sub("", value).strip().casefold() if isinstance(value, str) else ""


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
    for key in payload:
        if key not in ALLOWED_KEYS:
            reject("CFUX_UNKNOWN_FIELD", f"$.{key}")
    if payload.get("self_verdict") != payload.get("status"):
        reject("CFUX_SELF_VERDICT_STATUS_MISMATCH", "$.self_verdict")

    evidence = payload.get("evidence_map")
    if not isinstance(evidence, list) or not evidence:
        reject("CFUX_EVIDENCE_MAP_REQUIRED", "$.evidence_map")
    else:
        for i, item in enumerate(evidence):
            if isinstance(item, dict) and set(item) - {"source_ref", "supports"}:
                reject("CFUX_EVIDENCE_ITEM_UNKNOWN_FIELD", f"$.evidence_map[{i}]")
            if (not isinstance(item, dict) or not _nonempty_str(item.get("source_ref"))
                    or not isinstance(item.get("supports"), list) or not item["supports"]
                    or not all(_nonempty_str(x) for x in item["supports"])):
                reject("CFUX_EVIDENCE_ITEM_INVALID", f"$.evidence_map[{i}]")

        keys = [_key(i.get("source_ref")) for i in evidence if isinstance(i, dict) and _nonempty_str(i.get("source_ref"))]
        if len(set(keys)) != len(keys):
            reject("CFUX_EVIDENCE_SOURCE_REF_DUPLICATE", "$.evidence_map")

    if kind == "CUSTOMER_FINANCIAL_DECISION_SPEC":
        for key in SPEC_REQUIRED:
            if key not in payload:
                reject("CFUX_SPEC_FIELD_MISSING", f"$.{key}")
        if payload.get("status") not in SPEC_STATUSES:
            reject("CFUX_SPEC_STATUS_INVALID", "$.status")
        if payload.get("blocked") is True:
            reject("CFUX_SPEC_CANNOT_BE_BLOCKED", "$.blocked")
        for key in SPEC_FORBIDDEN:
            if key in payload:
                reject("CFUX_MULTIPLE_OUTPUT_MODES", f"$.{key}")
        for key in ("must_understand", "uncertainties", "claim_guardrails"):
            if key in payload and not isinstance(payload[key], list):
                reject("CFUX_FIELD_NOT_LIST", f"$.{key}")
        if "handoff_to_next" in payload and not isinstance(payload["handoff_to_next"], dict):
            reject("CFUX_HANDOFF_NOT_OBJECT", "$.handoff_to_next")
        elif payload.get("handoff_to_next") == {}:
            reject("CFUX_HANDOFF_EMPTY", "$.handoff_to_next")
        for key in ("decision_id", "decision_question"):
            if not _nonempty_str(payload.get(key)):
                reject("CFUX_DECISION_ID_EMPTY" if key == "decision_id" else "CFUX_DECISION_QUESTION_EMPTY", f"$.{key}")
        if "comparison_basis" in payload and not isinstance(payload["comparison_basis"], str):
            reject("CFUX_FIELD_NOT_STRING", "$.comparison_basis")
        prio = payload.get("recommended_presentation_priority")
        if prio is not None and (not isinstance(prio, list) or not all(_nonempty_str(x) for x in prio)):
            reject("CFUX_FIELD_NOT_STRING_LIST", "$.recommended_presentation_priority")
        evidence_refs = {e.get("source_ref") for e in (evidence or []) if isinstance(e, dict)}
        options = payload.get("options")
        if not isinstance(options, list) or not options:
            reject("CFUX_OPTIONS_REQUIRED", "$.options")
        else:
            ids = [o.get("option_id") if isinstance(o, dict) else None for o in options]
            if not all(_nonempty_str(i) for i in ids) or len({_key(i) for i in ids}) != len(ids):
                reject("CFUX_OPTION_ID_DUPLICATE_OR_MISSING", "$.options")
            for i, option in enumerate(options):
                if not isinstance(option, dict):
                    reject("CFUX_OPTION_NOT_OBJECT", f"$.options[{i}]")
                    continue
                for key in OPTION_REQUIRED:
                    if key not in option:
                        reject("CFUX_OPTION_FIELD_MISSING", f"$.options[{i}].{key}")
                for key in ("customer_consequence", "timing", "monetary_basis", "key_tradeoff"):
                    if key in option and not _nonempty_str(option[key]):
                        reject("CFUX_OPTION_TEXT_EMPTY_OR_NOT_STRING", f"$.options[{i}].{key}")
                if "terms" in option and not isinstance(option["terms"], dict):
                    reject("CFUX_OPTION_TERMS_NOT_OBJECT", f"$.options[{i}].terms")
                refs = option.get("authority_refs")
                if not isinstance(refs, list) or not refs or not all(_nonempty_str(r) for r in refs):
                    reject("CFUX_OPTION_WITHOUT_AUTHORITY", f"$.options[{i}].authority_refs")
                elif any(r not in evidence_refs for r in refs):
                    reject("CFUX_AUTHORITY_REF_NOT_IN_EVIDENCE_MAP", f"$.options[{i}].authority_refs")
    elif kind == "MISSING_MATERIAL_FINANCIAL_INPUT":
        missing = payload.get("missing_inputs")
        if (payload.get("blocked") is not True or not isinstance(missing, list) or not missing
                or not all(_nonempty_str(x) for x in missing)):
            reject("CFUX_MISSING_INPUT_CONTRACT", "$.missing_inputs")
        if payload.get("status") != "NEEDS_INPUT":
            reject("CFUX_MISSING_INPUT_STATUS_INVALID", "$.status")
        if "options" in payload or "blocking_reason" in payload:
            reject("CFUX_MULTIPLE_OUTPUT_MODES", "$")
    elif kind == "BLOCKED_UNSUPPORTED_FINANCIAL_CLAIM":
        if payload.get("blocked") is not True or not _nonempty_str(payload.get("blocking_reason")):
            reject("CFUX_BLOCKED_CLAIM_CONTRACT", "$.blocking_reason")
        if payload.get("status") != "BLOCKED":
            reject("CFUX_BLOCKED_CLAIM_STATUS_INVALID", "$.status")
        if "options" in payload or "missing_inputs" in payload:
            reject("CFUX_MULTIPLE_OUTPUT_MODES", "$")

    return {"status": "FAIL" if errors else "PASS", "errors": errors}
