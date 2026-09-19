#!/usr/bin/env python3
"""Deterministic semantic-utility floor for SRCR."""

CONTRADICTORY_RECONCILIATIONS = {
    "UNDECLARED_EXECUTION",
    "SILENT_DROP",
    "SOURCE_LIVE_DIVERGENCE",
    "OTHER_CONTRADICTION",
}
OBSERVED_FALSIFICATION_EVIDENCE = {
    "OBSERVED_TEST",
    "OBSERVED_RUNTIME",
    "OBSERVED_READBACK",
}


def evaluate(payload, contract_gate):
    codes = []
    if not isinstance(payload, dict):
        codes.append("PAYLOAD_NOT_OBJECT")
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        codes.append("PROFILE_CONTRACT_INVALID")
    if codes:
        return {"status": "FAIL", "blocking_codes": sorted(set(codes))}

    status = payload.get("status")
    packet = payload.get("live_authority_packet")
    reconciliations = payload.get("execution_effect_reconciliation")
    if not isinstance(packet, dict):
        codes.append("LIVE_AUTHORITY_PACKET_MISSING")
    if not isinstance(reconciliations, list):
        codes.append("EXECUTION_EFFECT_RECONCILIATION_MISSING")

    if isinstance(reconciliations, list):
        unresolved = [r for r in reconciliations if isinstance(r, dict) and r.get("reconciliation_status") == "UNRESOLVED_PRODUCER"]
        contradictions = [r for r in reconciliations if isinstance(r, dict) and r.get("reconciliation_status") in CONTRADICTORY_RECONCILIATIONS]
        if unresolved and status == "SYSTEMIC_REPAIR_SPEC":
            codes.append("SYSTEMIC_SPEC_WITH_UNRESOLVED_PRODUCER")
        if contradictions and status == "SYSTEMIC_REPAIR_SPEC":
            codes.append("SYSTEMIC_SPEC_WITH_EXECUTION_CONTRADICTION")

    falsifications = payload.get("falsification_results")
    if isinstance(falsifications, list):
        for item in falsifications:
            if isinstance(item, dict) and item.get("result") == "PASS" and item.get("evidence_class") not in OBSERVED_FALSIFICATION_EVIDENCE:
                codes.append("FALSIFICATION_PASS_NOT_OBSERVED")

    if status == "SYSTEMIC_REPAIR_SPEC":
        if not isinstance(packet, dict) or packet.get("status") != "COMPLETE":
            codes.append("SYSTEMIC_SPEC_WITHOUT_COMPLETE_LIVE_AUTHORITY")
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
