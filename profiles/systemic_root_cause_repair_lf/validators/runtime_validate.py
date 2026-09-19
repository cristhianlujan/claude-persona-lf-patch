#!/usr/bin/env python3
"""Deterministic runtime validator for Systemic Root Cause Repair LF.

This validator enforces profile-local evidence and causal invariants. It does not
replace the canonical semantic judge, but it prevents a producer from claiming a
ready systemic repair while live execution authority or observed effect ownership
is unresolved.
"""

ALLOWED_STATUS = {
    "SYSTEMIC_REPAIR_SPEC",
    "NEEDS_MORE_EVIDENCE",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "BLOCK_PIPELINE",
}
REQUIRED_FALSIFICATION_CASES = {
    "bypass",
    "retry",
    "concurrency",
    "partial_failure",
    "stale_state",
    "interrupted_execution",
    "replay_or_duplicate",
    "undeclared_or_unversioned_caller",
}
LIVE_PACKET_STATUS = {"COMPLETE", "PARTIAL", "MISSING"}
RECONCILIATION_STATUS = {
    "MATCH",
    "UNRESOLVED_PRODUCER",
    "UNDECLARED_EXECUTION",
    "SILENT_DROP",
    "SOURCE_LIVE_DIVERGENCE",
    "OTHER_CONTRADICTION",
}
CONTRADICTION_RECONCILIATIONS = {
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


def _error(code, path="$", message=""):
    return {"code": code, "path": path, "message": message}


def _nonempty_strings(value):
    return isinstance(value, list) and all(isinstance(v, str) and v.strip() for v in value)


def _live_packet_errors(payload):
    errors = []
    packet = payload.get("live_authority_packet")
    blockers = payload.get("blocking_codes") if isinstance(payload.get("blocking_codes"), list) else []
    if not isinstance(packet, dict):
        return [_error("LIVE_AUTHORITY_PACKET_MISSING", "$.live_authority_packet")]

    packet_status = packet.get("status")
    if packet_status not in LIVE_PACKET_STATUS:
        errors.append(_error("LIVE_AUTHORITY_PACKET_STATUS_INVALID", "$.live_authority_packet.status"))
        return errors

    applicable = packet.get("applicable_surfaces")
    inspected = packet.get("inspected_surfaces")
    evidence_refs = packet.get("evidence_refs")
    unavailable = packet.get("unavailable_sources")
    if not _nonempty_strings(applicable):
        errors.append(_error("LIVE_AUTHORITY_APPLICABLE_SURFACES_MISSING", "$.live_authority_packet.applicable_surfaces"))
    if not isinstance(inspected, list) or any(not isinstance(v, str) or not v.strip() for v in inspected):
        errors.append(_error("LIVE_AUTHORITY_INSPECTED_SURFACES_INVALID", "$.live_authority_packet.inspected_surfaces"))
    if not isinstance(evidence_refs, list) or any(not isinstance(v, str) or not v.strip() for v in evidence_refs):
        errors.append(_error("LIVE_AUTHORITY_EVIDENCE_REFS_INVALID", "$.live_authority_packet.evidence_refs"))
    if not isinstance(unavailable, list) or any(not isinstance(v, str) or not v.strip() for v in unavailable):
        errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_SOURCES_INVALID", "$.live_authority_packet.unavailable_sources"))

    if packet_status == "COMPLETE":
        if not evidence_refs:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITHOUT_EVIDENCE", "$.live_authority_packet.evidence_refs"))
        if unavailable:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITH_UNAVAILABLE_SOURCE", "$.live_authority_packet.unavailable_sources"))
        if isinstance(applicable, list) and isinstance(inspected, list) and set(applicable) != set(inspected):
            errors.append(_error("LIVE_AUTHORITY_SURFACE_COVERAGE_INCOMPLETE", "$.live_authority_packet"))
    elif packet_status == "PARTIAL":
        if "LIVE_AUTHORITY_EVIDENCE_INCOMPLETE" not in blockers:
            errors.append(_error("LIVE_AUTHORITY_PARTIAL_WITHOUT_BLOCKER", "$.blocking_codes"))
    elif packet_status == "MISSING":
        if "LIVE_AUTHORITY_EVIDENCE_MISSING" not in blockers:
            errors.append(_error("LIVE_AUTHORITY_MISSING_WITHOUT_BLOCKER", "$.blocking_codes"))

    return errors


def _reconciliation_errors(payload):
    errors = []
    packet = payload.get("live_authority_packet") if isinstance(payload.get("live_authority_packet"), dict) else {}
    material_effects = packet.get("material_effects_observed")
    rows = payload.get("execution_effect_reconciliation")
    blockers = payload.get("blocking_codes") if isinstance(payload.get("blocking_codes"), list) else []
    if not isinstance(rows, list):
        return [_error("EXECUTION_EFFECT_RECONCILIATION_MISSING", "$.execution_effect_reconciliation")]
    if material_effects is True and not rows:
        errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_EMPTY_WITH_OBSERVED_EFFECTS", "$.execution_effect_reconciliation"))

    for idx, row in enumerate(rows):
        path = f"$.execution_effect_reconciliation[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_INVALID", path))
            continue
        status = row.get("reconciliation_status")
        blocking = row.get("blocking")
        producer_refs = row.get("observed_producer_refs")
        if status not in RECONCILIATION_STATUS:
            errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_STATUS_INVALID", f"{path}.reconciliation_status"))
            continue
        if not isinstance(producer_refs, list) or any(not isinstance(v, str) or not v.strip() for v in producer_refs):
            errors.append(_error("EXECUTION_EFFECT_PRODUCER_REFS_INVALID", f"{path}.observed_producer_refs"))
        if status == "MATCH":
            if blocking is not False:
                errors.append(_error("MATCH_RECONCILIATION_MUST_NOT_BLOCK", f"{path}.blocking"))
            if not producer_refs:
                errors.append(_error("MATCH_REQUIRES_OBSERVED_PRODUCER", f"{path}.observed_producer_refs"))
        elif status == "UNRESOLVED_PRODUCER":
            if blocking is not True:
                errors.append(_error("UNRESOLVED_PRODUCER_MUST_BLOCK", f"{path}.blocking"))
            if "EXECUTION_EFFECT_PRODUCER_UNRESOLVED" not in blockers:
                errors.append(_error("UNRESOLVED_PRODUCER_WITHOUT_BLOCKER", "$.blocking_codes"))
        else:
            if blocking is not True:
                errors.append(_error("AUTHORITY_CONTRADICTION_RECONCILIATION_MUST_BLOCK", f"{path}.blocking"))

    return errors


def _falsification_errors(payload, *, require_complete=False):
    errors = []
    falsifications = payload.get("falsification_results")
    if not isinstance(falsifications, list):
        return [_error("FALSIFICATION_RESULTS_INVALID", "$.falsification_results")]
    cases = {str(item.get("case")) for item in falsifications if isinstance(item, dict)}
    missing = sorted(REQUIRED_FALSIFICATION_CASES - cases)
    if missing:
        errors.append(_error("FALSIFICATION_FAMILIES_MISSING", "$.falsification_results", ",".join(missing)))
    for idx, item in enumerate(falsifications):
        if not isinstance(item, dict):
            continue
        result = item.get("result")
        evidence_class = item.get("evidence_class")
        if result == "PASS" and evidence_class not in OBSERVED_FALSIFICATION_EVIDENCE:
            errors.append(_error("FALSIFICATION_PASS_NOT_OBSERVED", f"$.falsification_results[{idx}].evidence_class"))
        if require_complete and item.get("case") in REQUIRED_FALSIFICATION_CASES and result != "PASS":
            errors.append(_error("SYSTEMIC_SPEC_FALSIFICATION_NOT_PASS", f"$.falsification_results[{idx}].result"))
    return errors


def validate(payload):
    errors = []
    if not isinstance(payload, dict):
        return {"valid": False, "status": "FAIL", "errors": [_error("NOT_OBJECT")], "blocking_codes": ["NOT_OBJECT"]}

    status = payload.get("status")
    if status not in ALLOWED_STATUS:
        errors.append(_error("STATUS_INVALID", "$.status"))
    if payload.get("profile_pack_id") != "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2":
        errors.append(_error("PROFILE_PACK_ID_MISMATCH", "$.profile_pack_id"))

    errors.extend(_live_packet_errors(payload))
    errors.extend(_reconciliation_errors(payload))
    errors.extend(_falsification_errors(payload, require_complete=status == "SYSTEMIC_REPAIR_SPEC"))

    contradictions = payload.get("authority_contradictions")
    if not isinstance(contradictions, list):
        errors.append(_error("AUTHORITY_CONTRADICTIONS_INVALID", "$.authority_contradictions"))

    if status == "SYSTEMIC_REPAIR_SPEC":
        packet = payload.get("live_authority_packet") or {}
        if packet.get("status") != "COMPLETE":
            errors.append(_error("SYSTEMIC_SPEC_WITHOUT_COMPLETE_LIVE_AUTHORITY", "$.live_authority_packet.status"))

        rows = payload.get("execution_effect_reconciliation") or []
        non_matches = [row for row in rows if isinstance(row, dict) and row.get("reconciliation_status") != "MATCH"]
        if non_matches:
            errors.append(_error("SYSTEMIC_SPEC_WITH_UNRESOLVED_EFFECT_RECONCILIATION", "$.execution_effect_reconciliation"))

        if contradictions:
            errors.append(_error("UNRESOLVED_AUTHORITY_CONTRADICTION", "$.authority_contradictions"))

        blockers = payload.get("blocking_codes")
        if not isinstance(blockers, list):
            errors.append(_error("BLOCKING_CODES_INVALID", "$.blocking_codes"))
        elif blockers:
            errors.append(_error("SYSTEMIC_SPEC_WITH_BLOCKERS", "$.blocking_codes"))

        existence = payload.get("should_exist_assessment")
        if not isinstance(existence, dict):
            errors.append(_error("SHOULD_EXIST_ASSESSMENT_MISSING", "$.should_exist_assessment"))
        elif existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            errors.append(_error("SHOULD_EXIST_ASSESSMENT_UNRESOLVED", "$.should_exist_assessment.verdict"))

        alternatives = payload.get("alternatives")
        if not isinstance(alternatives, list) or len(alternatives) < 3:
            errors.append(_error("ALTERNATIVES_INSUFFICIENT", "$.alternatives"))

        rejected = payload.get("rejected_alternatives")
        if not isinstance(rejected, list) or len(rejected) < 2:
            errors.append(_error("REJECTED_ALTERNATIVES_INSUFFICIENT", "$.rejected_alternatives"))

        guard = payload.get("hard_guard")
        if not isinstance(guard, dict) or not all(isinstance(guard.get(k), str) and guard.get(k).strip() for k in ("control", "fail_closed_condition", "observable_result")):
            errors.append(_error("HARD_GUARD_NOT_TESTABLE", "$.hard_guard"))

        if not isinstance(payload.get("evidence_map"), list) or not payload.get("evidence_map"):
            errors.append(_error("EVIDENCE_MAP_EMPTY", "$.evidence_map"))

    codes = sorted({e["code"] for e in errors})
    return {"valid": not errors, "status": "PASS" if not errors else "FAIL", "errors": errors, "blocking_codes": codes}


if __name__ == "__main__":
    import json
    import sys

    try:
        value = json.load(sys.stdin)
    except Exception:
        value = None
    print(json.dumps(validate(value), ensure_ascii=False, indent=2))
