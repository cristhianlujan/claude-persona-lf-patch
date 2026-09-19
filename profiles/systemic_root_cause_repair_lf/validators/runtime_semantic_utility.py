#!/usr/bin/env python3
"""Deterministic semantic-utility floor for SRCR.

This layer rejects semantically premature conclusions even when the JSON shape is
otherwise valid.
"""

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
CRITICAL_EVIDENCE_PATHS = {
    "$.symptom",
    "$.immediate_cause",
    "$.systemic_root_cause",
    "$.first_bad_control",
    "$.escape_control",
    "$.origin_asset",
    "$.origin_operation",
    "$.owner",
}


def _claim_status(payload, field):
    value = payload.get(field)
    return value.get("status") if isinstance(value, dict) else None


def _authority_status(payload, field):
    value = payload.get(field)
    return value.get("status") if isinstance(value, dict) else None


def _alternative_ids(payload):
    return {
        item.get("id")
        for item in payload.get("alternatives") or []
        if isinstance(item, dict) and isinstance(item.get("id"), str)
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
    packet_status = packet.get("status") if isinstance(packet, dict) else None

    if not isinstance(packet, dict):
        codes.append("LIVE_AUTHORITY_PACKET_MISSING")
    if not isinstance(reconciliations, list):
        codes.append("EXECUTION_EFFECT_RECONCILIATION_MISSING")
        reconciliations = []

    unresolved_effects = [
        item for item in reconciliations
        if isinstance(item, dict) and item.get("reconciliation_status") != "MATCH"
    ]
    contradictions = [
        item for item in reconciliations
        if isinstance(item, dict) and item.get("reconciliation_status") in CONTRADICTORY_RECONCILIATIONS
    ]

    falsifications = payload.get("falsification_results")
    if isinstance(falsifications, list):
        for item in falsifications:
            if isinstance(item, dict) and item.get("result") == "PASS" and item.get("evidence_class") not in OBSERVED_FALSIFICATION_EVIDENCE:
                codes.append("FALSIFICATION_PASS_NOT_OBSERVED")

    evidence_map = payload.get("evidence_map")
    if not isinstance(evidence_map, list) or any(not isinstance(item, dict) for item in evidence_map):
        codes.append("CLAIM_EVIDENCE_MAP_INVALID")
    else:
        mapped = {item.get("claim_path") for item in evidence_map}
        if not CRITICAL_EVIDENCE_PATHS.issubset(mapped):
            codes.append("CLAIM_EVIDENCE_MAP_INCOMPLETE")

    selected = payload.get("selected_alternative")
    preferred = payload.get("preferred_alternative")
    alternative_ids = _alternative_ids(payload)

    if preferred is not None and preferred not in alternative_ids:
        codes.append("PREFERRED_ALTERNATIVE_NOT_DECLARED")
    if selected is not None and selected not in alternative_ids:
        codes.append("SELECTED_ALTERNATIVE_NOT_DECLARED")

    root_status = _claim_status(payload, "systemic_root_cause")
    authority_incomplete = packet_status != "COMPLETE"
    effect_incomplete = bool(unresolved_effects)

    if root_status != "ESTABLISHED" and payload.get("repair_level") != "UNDETERMINED":
        codes.append("PREMATURE_REPAIR_LEVEL")

    if status != "SYSTEMIC_REPAIR_SPEC":
        if selected is not None:
            codes.append("FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS")
        if payload.get("residual_risks"):
            codes.append("RESIDUAL_RISK_BEFORE_READY_SPEC")

    if status == "NEEDS_MORE_EVIDENCE":
        if not payload.get("blocking_codes"):
            codes.append("NEEDS_MORE_EVIDENCE_WITHOUT_BLOCKER")
        uncertainties = payload.get("current_uncertainties")
        if not isinstance(uncertainties, list) or not uncertainties:
            codes.append("NEEDS_MORE_EVIDENCE_WITHOUT_UNCERTAINTY")
        elif not any(isinstance(item, dict) and item.get("blocking") is True for item in uncertainties):
            codes.append("NEEDS_MORE_EVIDENCE_WITHOUT_BLOCKING_UNCERTAINTY")

        if authority_incomplete or effect_incomplete:
            if root_status == "ESTABLISHED":
                codes.append("PREMATURE_SYSTEMIC_ROOT_CAUSE")
            if payload.get("repair_level") != "UNDETERMINED":
                codes.append("PREMATURE_REPAIR_LEVEL")
            if payload.get("rejected_alternatives"):
                codes.append("PREMATURE_REJECTED_ALTERNATIVES")

    if status == "SYSTEMIC_REPAIR_SPEC":
        if packet_status != "COMPLETE":
            codes.append("SYSTEMIC_SPEC_WITHOUT_COMPLETE_LIVE_AUTHORITY")
        if unresolved_effects:
            codes.append("SYSTEMIC_SPEC_WITH_UNRESOLVED_EFFECT_RECONCILIATION")
        if contradictions:
            codes.append("SYSTEMIC_SPEC_WITH_EXECUTION_CONTRADICTION")
        if payload.get("authority_contradictions"):
            codes.append("UNRESOLVED_AUTHORITY_CONTRADICTION")
        if payload.get("blocking_codes"):
            codes.append("SYSTEMIC_SPEC_WITH_BLOCKERS")
        if payload.get("current_uncertainties"):
            codes.append("SYSTEMIC_SPEC_WITH_CURRENT_UNCERTAINTIES")

        for field in ("immediate_cause", "systemic_root_cause", "first_bad_control", "escape_control"):
            if _claim_status(payload, field) != "ESTABLISHED":
                codes.append("SYSTEMIC_SPEC_CAUSAL_CLAIM_NOT_ESTABLISHED")

        if payload.get("repair_level") == "UNDETERMINED":
            codes.append("SYSTEMIC_SPEC_REPAIR_LEVEL_UNDETERMINED")
        if selected is None:
            codes.append("SYSTEMIC_SPEC_SELECTED_ALTERNATIVE_REQUIRED")
        if preferred != selected:
            codes.append("SYSTEMIC_SPEC_PREFERRED_SELECTED_MISMATCH")

        rejected_ids = {
            item.get("id")
            for item in payload.get("rejected_alternatives") or []
            if isinstance(item, dict)
        }
        if selected in rejected_ids:
            codes.append("SELECTED_ALTERNATIVE_ALSO_REJECTED")

        existence = payload.get("should_exist_assessment")
        if not isinstance(existence, dict) or existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            codes.append("SHOULD_EXIST_ASSESSMENT_UNRESOLVED")

        for field in ("origin_asset", "origin_operation", "owner"):
            if _authority_status(payload, field) != "RESOLVED":
                codes.append("SYSTEMIC_SPEC_AUTHORITY_REF_UNRESOLVED")

        invariant = payload.get("invariant")
        if not isinstance(invariant, dict) or invariant.get("status") != "VALIDATED":
            codes.append("SYSTEMIC_SPEC_INVARIANT_NOT_VALIDATED")
        guard = payload.get("hard_guard")
        if not isinstance(guard, dict) or guard.get("status") != "VALIDATED":
            codes.append("SYSTEMIC_SPEC_HARD_GUARD_NOT_VALIDATED")

    historical = payload.get("historical_regressions")
    if isinstance(historical, list):
        for item in historical:
            if not isinstance(item, dict) or not item.get("occurrence_ref") or not item.get("evidence_refs"):
                codes.append("HISTORICAL_REGRESSION_NOT_OBSERVED")
                break
    else:
        codes.append("HISTORICAL_REGRESSIONS_INVALID")

    return {"status": "PASS" if not codes else "FAIL", "blocking_codes": sorted(set(codes))}
