#!/usr/bin/env python3
"""Deterministic semantic-utility floor.

This is deliberately narrower than the canonical semantic quality gate.
"""


def evaluate(payload, contract_gate):
    codes = []
    if not isinstance(payload, dict):
        codes.append("PAYLOAD_NOT_OBJECT")
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        codes.append("PROFILE_CONTRACT_INVALID")
    if codes:
        return {"status": "FAIL", "blocking_codes": sorted(set(codes))}

    status = payload.get("status")
    if status == "SYSTEMIC_REPAIR_SPEC":
        if payload.get("authority_contradictions"):
            codes.append("UNRESOLVED_AUTHORITY_CONTRADICTION")
        if payload.get("blocking_codes"):
            codes.append("SYSTEMIC_SPEC_WITH_BLOCKERS")

        existence = payload.get("should_exist_assessment")
        if not isinstance(existence, dict) or existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            codes.append("SHOULD_EXIST_ASSESSMENT_UNRESOLVED")

        alternatives = payload.get("alternatives")
        selected = payload.get("selected_alternative")
        alternative_ids = {
            item.get("id") for item in alternatives or []
            if isinstance(item, dict) and isinstance(item.get("id"), str)
        }
        if selected not in alternative_ids:
            codes.append("SELECTED_ALTERNATIVE_NOT_DECLARED")

        rejected = payload.get("rejected_alternatives")
        rejected_ids = {
            item.get("id") for item in rejected or []
            if isinstance(item, dict) and isinstance(item.get("id"), str)
        }
        if selected in rejected_ids:
            codes.append("SELECTED_ALTERNATIVE_ALSO_REJECTED")


        root = payload.get("systemic_root_cause")
        symptom = payload.get("symptom")
        immediate = payload.get("immediate_cause")
        if isinstance(root, str) and root in {symptom, immediate}:
            codes.append("CAUSAL_COLLAPSE")

    return {"status": "PASS" if not codes else "FAIL", "blocking_codes": sorted(set(codes))}
