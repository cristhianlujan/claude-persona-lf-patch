#!/usr/bin/env python3
"""Deterministic runtime validator for Systemic Root Cause Repair LF.

The validator keeps causal claims, evidence gaps and final repair decisions
separate. A non-ready output may preserve hypotheses, but it may not present
unresolved causality as a final repair specification.
"""

ALLOWED_STATUS = {
    "SYSTEMIC_REPAIR_SPEC",
    "NEEDS_MORE_EVIDENCE",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "BLOCK_PIPELINE",
}
CLAIM_STATUS = {"OBSERVED", "ESTABLISHED", "HYPOTHESIS", "UNRESOLVED"}
AUTHORITY_STATUS = {"RESOLVED", "UNRESOLVED"}
REPAIR_LEVELS = {"UNDETERMINED", "LOCAL", "SYSTEMIC_ORIGIN", "ARCHITECTURAL"}
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


def _error(code, path="$", message=""):
    return {"code": code, "path": path, "message": message}


def _nonempty_string(value):
    return isinstance(value, str) and bool(value.strip())


def _string_list(value, *, allow_empty=True):
    if not isinstance(value, list):
        return False
    if not allow_empty and not value:
        return False
    return all(_nonempty_string(item) for item in value)


def _claim_errors(name, value, *, required_status=None):
    path = f"$.{name}"
    errors = []
    if not isinstance(value, dict):
        return [_error("CLAIM_INVALID", path)]
    status = value.get("status")
    statement = value.get("statement")
    refs = value.get("evidence_refs")
    missing = value.get("missing_evidence")
    if status not in CLAIM_STATUS:
        errors.append(_error("CLAIM_STATUS_INVALID", f"{path}.status"))
        return errors
    if required_status and status != required_status:
        errors.append(_error("CLAIM_STATUS_REQUIRED", f"{path}.status", required_status))
    if not _string_list(refs):
        errors.append(_error("CLAIM_EVIDENCE_REFS_INVALID", f"{path}.evidence_refs"))
    if not _string_list(missing):
        errors.append(_error("CLAIM_MISSING_EVIDENCE_INVALID", f"{path}.missing_evidence"))

    if status in {"OBSERVED", "ESTABLISHED"}:
        if not _nonempty_string(statement):
            errors.append(_error("SUPPORTED_CLAIM_STATEMENT_REQUIRED", f"{path}.statement"))
        if not refs:
            errors.append(_error("SUPPORTED_CLAIM_EVIDENCE_REQUIRED", f"{path}.evidence_refs"))
        if missing:
            errors.append(_error("SUPPORTED_CLAIM_WITH_MISSING_EVIDENCE", f"{path}.missing_evidence"))
    elif status == "HYPOTHESIS":
        if not _nonempty_string(statement):
            errors.append(_error("HYPOTHESIS_STATEMENT_REQUIRED", f"{path}.statement"))
        if not missing:
            errors.append(_error("HYPOTHESIS_MISSING_EVIDENCE_REQUIRED", f"{path}.missing_evidence"))
    elif status == "UNRESOLVED":
        if statement is not None and not _nonempty_string(statement):
            errors.append(_error("UNRESOLVED_CLAIM_STATEMENT_INVALID", f"{path}.statement"))
        if not missing:
            errors.append(_error("UNRESOLVED_CLAIM_MISSING_EVIDENCE_REQUIRED", f"{path}.missing_evidence"))
    return errors


def _authority_ref_errors(name, value):
    path = f"$.{name}"
    errors = []
    if not isinstance(value, dict):
        return [_error("AUTHORITY_REF_INVALID", path)]
    status = value.get("status")
    code = value.get("code")
    ref = value.get("evidence_ref")
    missing = value.get("missing_evidence")
    if status not in AUTHORITY_STATUS:
        errors.append(_error("AUTHORITY_REF_STATUS_INVALID", f"{path}.status"))
        return errors
    if not _string_list(missing):
        errors.append(_error("AUTHORITY_REF_MISSING_EVIDENCE_INVALID", f"{path}.missing_evidence"))
    if status == "RESOLVED":
        if not _nonempty_string(code):
            errors.append(_error("RESOLVED_AUTHORITY_CODE_REQUIRED", f"{path}.code"))
        if not _nonempty_string(ref):
            errors.append(_error("RESOLVED_AUTHORITY_EVIDENCE_REQUIRED", f"{path}.evidence_ref"))
        if missing:
            errors.append(_error("RESOLVED_AUTHORITY_WITH_MISSING_EVIDENCE", f"{path}.missing_evidence"))
    else:
        if not missing:
            errors.append(_error("UNRESOLVED_AUTHORITY_MISSING_EVIDENCE_REQUIRED", f"{path}.missing_evidence"))
    return errors


def _live_packet_errors(payload):
    errors = []
    packet = payload.get("live_authority_packet")
    blockers = payload.get("blocking_codes") if isinstance(payload.get("blocking_codes"), list) else []
    if not isinstance(packet, dict):
        return [_error("LIVE_AUTHORITY_PACKET_MISSING", "$.live_authority_packet")]

    packet_status = packet.get("status")
    if packet_status not in LIVE_PACKET_STATUS:
        return [_error("LIVE_AUTHORITY_PACKET_STATUS_INVALID", "$.live_authority_packet.status")]

    applicable = packet.get("applicable_surfaces")
    inspected = packet.get("inspected_surfaces")
    evidence_refs = packet.get("evidence_refs")
    unavailable = packet.get("unavailable_sources")
    if not _string_list(applicable, allow_empty=False):
        errors.append(_error("LIVE_AUTHORITY_APPLICABLE_SURFACES_MISSING", "$.live_authority_packet.applicable_surfaces"))
    if not _string_list(inspected):
        errors.append(_error("LIVE_AUTHORITY_INSPECTED_SURFACES_INVALID", "$.live_authority_packet.inspected_surfaces"))
    if not _string_list(evidence_refs):
        errors.append(_error("LIVE_AUTHORITY_EVIDENCE_REFS_INVALID", "$.live_authority_packet.evidence_refs"))
    if not _string_list(unavailable):
        errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_SOURCES_INVALID", "$.live_authority_packet.unavailable_sources"))

    if packet_status == "COMPLETE":
        if not evidence_refs:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITHOUT_EVIDENCE", "$.live_authority_packet.evidence_refs"))
        if unavailable:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITH_UNAVAILABLE_SOURCE", "$.live_authority_packet.unavailable_sources"))
        if isinstance(applicable, list) and isinstance(inspected, list) and set(applicable) != set(inspected):
            errors.append(_error("LIVE_AUTHORITY_SURFACE_COVERAGE_INCOMPLETE", "$.live_authority_packet"))
    elif packet_status == "PARTIAL" and "LIVE_AUTHORITY_EVIDENCE_INCOMPLETE" not in blockers:
        errors.append(_error("LIVE_AUTHORITY_PARTIAL_WITHOUT_BLOCKER", "$.blocking_codes"))
    elif packet_status == "MISSING" and "LIVE_AUTHORITY_EVIDENCE_MISSING" not in blockers:
        errors.append(_error("LIVE_AUTHORITY_MISSING_WITHOUT_BLOCKER", "$.blocking_codes"))
    return errors


def _reconciliation_errors(payload):
    errors = []
    packet = payload.get("live_authority_packet") if isinstance(payload.get("live_authority_packet"), dict) else {}
    rows = payload.get("execution_effect_reconciliation")
    blockers = payload.get("blocking_codes") if isinstance(payload.get("blocking_codes"), list) else []
    if not isinstance(rows, list):
        return [_error("EXECUTION_EFFECT_RECONCILIATION_MISSING", "$.execution_effect_reconciliation")]
    if packet.get("material_effects_observed") is True and not rows:
        errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_EMPTY_WITH_OBSERVED_EFFECTS", "$.execution_effect_reconciliation"))

    for idx, row in enumerate(rows):
        path = f"$.execution_effect_reconciliation[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_INVALID", path))
            continue
        status = row.get("reconciliation_status")
        producer_refs = row.get("observed_producer_refs")
        if status not in RECONCILIATION_STATUS:
            errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_STATUS_INVALID", f"{path}.reconciliation_status"))
            continue
        if not _nonempty_string(row.get("declared_producer_ref")):
            errors.append(_error("DECLARED_PRODUCER_AUTHORITY_REF_REQUIRED", f"{path}.declared_producer_ref"))
        if not _string_list(producer_refs):
            errors.append(_error("EXECUTION_EFFECT_PRODUCER_REFS_INVALID", f"{path}.observed_producer_refs"))
        if status == "MATCH":
            if row.get("blocking") is not False:
                errors.append(_error("MATCH_RECONCILIATION_MUST_NOT_BLOCK", f"{path}.blocking"))
            if not producer_refs:
                errors.append(_error("MATCH_REQUIRES_OBSERVED_PRODUCER", f"{path}.observed_producer_refs"))
        elif status == "UNRESOLVED_PRODUCER":
            if row.get("blocking") is not True:
                errors.append(_error("UNRESOLVED_PRODUCER_MUST_BLOCK", f"{path}.blocking"))
            if "EXECUTION_EFFECT_PRODUCER_UNRESOLVED" not in blockers:
                errors.append(_error("UNRESOLVED_PRODUCER_WITHOUT_BLOCKER", "$.blocking_codes"))
        elif row.get("blocking") is not True:
            errors.append(_error("AUTHORITY_CONTRADICTION_RECONCILIATION_MUST_BLOCK", f"{path}.blocking"))
    return errors


def _falsification_errors(payload, *, require_complete=False):
    errors = []
    rows = payload.get("falsification_results")
    if not isinstance(rows, list):
        return [_error("FALSIFICATION_RESULTS_INVALID", "$.falsification_results")]
    cases = [item.get("case") for item in rows if isinstance(item, dict)]
    missing = sorted(REQUIRED_FALSIFICATION_CASES - set(cases))
    duplicates = sorted({case for case in cases if cases.count(case) > 1 and case is not None})
    if missing:
        errors.append(_error("FALSIFICATION_FAMILIES_MISSING", "$.falsification_results", ",".join(missing)))
    if duplicates:
        errors.append(_error("FALSIFICATION_FAMILIES_DUPLICATED", "$.falsification_results", ",".join(duplicates)))
    for idx, item in enumerate(rows):
        if not isinstance(item, dict):
            errors.append(_error("FALSIFICATION_RESULT_INVALID", f"$.falsification_results[{idx}]"))
            continue
        result = item.get("result")
        evidence_class = item.get("evidence_class")
        if item.get("case") not in REQUIRED_FALSIFICATION_CASES:
            errors.append(_error("FALSIFICATION_CASE_UNKNOWN", f"$.falsification_results[{idx}].case"))
        if result == "PASS" and evidence_class not in OBSERVED_FALSIFICATION_EVIDENCE:
            errors.append(_error("FALSIFICATION_PASS_NOT_OBSERVED", f"$.falsification_results[{idx}].evidence_class"))
        if require_complete and item.get("case") in REQUIRED_FALSIFICATION_CASES and result != "PASS":
            errors.append(_error("SYSTEMIC_SPEC_FALSIFICATION_NOT_PASS", f"$.falsification_results[{idx}].result"))
    return errors


def _evidence_map_errors(payload):
    errors = []
    rows = payload.get("evidence_map")
    if not isinstance(rows, list) or not rows:
        return [_error("EVIDENCE_MAP_EMPTY", "$.evidence_map")]
    paths = set()
    for idx, row in enumerate(rows):
        path = f"$.evidence_map[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("EVIDENCE_MAP_ENTRY_INVALID", path))
            continue
        claim_path = row.get("claim_path")
        refs = row.get("evidence_refs")
        if not _nonempty_string(claim_path) or not claim_path.startswith("$."):
            errors.append(_error("EVIDENCE_MAP_CLAIM_PATH_INVALID", f"{path}.claim_path"))
        else:
            paths.add(claim_path)
        if not _string_list(refs, allow_empty=False):
            errors.append(_error("EVIDENCE_MAP_REFS_REQUIRED", f"{path}.evidence_refs"))
    missing = sorted(CRITICAL_EVIDENCE_PATHS - paths)
    if missing:
        errors.append(_error("EVIDENCE_MAP_CRITICAL_CLAIMS_MISSING", "$.evidence_map", ",".join(missing)))
    return errors


def _structured_list_errors(payload):
    errors = []
    for field in ("historical_regressions", "planned_regressions", "acceptance_criteria", "current_uncertainties", "residual_risks"):
        if not isinstance(payload.get(field), list):
            errors.append(_error(f"{field.upper()}_INVALID", f"$.{field}"))

    for idx, row in enumerate(payload.get("historical_regressions") or []):
        path = f"$.historical_regressions[{idx}]"
        if not isinstance(row, dict) or not _nonempty_string(row.get("occurrence_ref")) or not _string_list(row.get("evidence_refs"), allow_empty=False):
            errors.append(_error("HISTORICAL_REGRESSION_REQUIRES_OBSERVED_OCCURRENCE", path))
    for idx, row in enumerate(payload.get("planned_regressions") or []):
        path = f"$.planned_regressions[{idx}]"
        if not isinstance(row, dict) or not all(_nonempty_string(row.get(key)) for key in ("case_id", "scenario", "verification_method", "expected_result")):
            errors.append(_error("PLANNED_REGRESSION_INVALID", path))
    for idx, row in enumerate(payload.get("acceptance_criteria") or []):
        path = f"$.acceptance_criteria[{idx}]"
        if not isinstance(row, dict) or not all(_nonempty_string(row.get(key)) for key in ("criterion", "verification_method", "expected_result")):
            errors.append(_error("ACCEPTANCE_CRITERION_NOT_EXECUTABLE", path))
    for idx, row in enumerate(payload.get("current_uncertainties") or []):
        path = f"$.current_uncertainties[{idx}]"
        if not isinstance(row, dict) or not _nonempty_string(row.get("uncertainty")) or not _string_list(row.get("evidence_needed"), allow_empty=False):
            errors.append(_error("CURRENT_UNCERTAINTY_INVALID", path))
    for idx, row in enumerate(payload.get("residual_risks") or []):
        path = f"$.residual_risks[{idx}]"
        if not isinstance(row, dict) or not _nonempty_string(row.get("risk")) or not _string_list(row.get("evidence_refs"), allow_empty=False):
            errors.append(_error("RESIDUAL_RISK_INVALID", path))
    return errors


def _decision_errors(payload):
    errors = []
    alternatives = payload.get("alternatives")
    if not isinstance(alternatives, list):
        return [_error("ALTERNATIVES_INVALID", "$.alternatives")]
    ids = []
    for idx, row in enumerate(alternatives):
        path = f"$.alternatives[{idx}]"
        if not isinstance(row, dict) or not _nonempty_string(row.get("id")):
            errors.append(_error("ALTERNATIVE_INVALID", path))
            continue
        ids.append(row["id"])
        if not _string_list(row.get("basis_refs"), allow_empty=False):
            errors.append(_error("ALTERNATIVE_BASIS_REQUIRED", f"{path}.basis_refs"))
    if len(ids) != len(set(ids)):
        errors.append(_error("ALTERNATIVE_IDS_DUPLICATED", "$.alternatives"))

    preferred = payload.get("preferred_alternative")
    selected = payload.get("selected_alternative")
    if preferred is not None and preferred not in set(ids):
        errors.append(_error("PREFERRED_ALTERNATIVE_NOT_DECLARED", "$.preferred_alternative"))
    if selected is not None and selected not in set(ids):
        errors.append(_error("SELECTED_ALTERNATIVE_NOT_DECLARED", "$.selected_alternative"))

    rejected = payload.get("rejected_alternatives")
    if not isinstance(rejected, list):
        errors.append(_error("REJECTED_ALTERNATIVES_INVALID", "$.rejected_alternatives"))
    else:
        for idx, row in enumerate(rejected):
            path = f"$.rejected_alternatives[{idx}]"
            if not isinstance(row, dict) or row.get("id") not in set(ids) or not _string_list(row.get("evidence_refs"), allow_empty=False):
                errors.append(_error("REJECTED_ALTERNATIVE_NOT_EVIDENCE_BOUND", path))
    return errors


def _proposal_errors(payload):
    errors = []
    invariant = payload.get("invariant")
    if not isinstance(invariant, dict):
        errors.append(_error("INVARIANT_INVALID", "$.invariant"))
    else:
        status = invariant.get("status")
        if status not in {"VALIDATED", "PROPOSED", "UNRESOLVED"}:
            errors.append(_error("INVARIANT_STATUS_INVALID", "$.invariant.status"))
        if status == "VALIDATED":
            if not _nonempty_string(invariant.get("statement")) or not _string_list(invariant.get("evidence_refs"), allow_empty=False) or invariant.get("missing_evidence"):
                errors.append(_error("VALIDATED_INVARIANT_EVIDENCE_INVALID", "$.invariant"))
        elif status in {"PROPOSED", "UNRESOLVED"} and not _string_list(invariant.get("missing_evidence"), allow_empty=False):
            errors.append(_error("NONFINAL_INVARIANT_MISSING_EVIDENCE_REQUIRED", "$.invariant.missing_evidence"))

    guard = payload.get("hard_guard")
    if not isinstance(guard, dict):
        errors.append(_error("HARD_GUARD_INVALID", "$.hard_guard"))
    else:
        status = guard.get("status")
        if status not in {"VALIDATED", "PROPOSED", "UNRESOLVED"}:
            errors.append(_error("HARD_GUARD_STATUS_INVALID", "$.hard_guard.status"))
        if status == "VALIDATED":
            required = ("control", "enforcement_point_ref", "fail_closed_condition", "blocking_code", "observable_result")
            if not all(_nonempty_string(guard.get(key)) for key in required):
                errors.append(_error("VALIDATED_HARD_GUARD_NOT_EXECUTABLE", "$.hard_guard"))
            if not _string_list(guard.get("evidence_refs"), allow_empty=False) or guard.get("missing_evidence"):
                errors.append(_error("VALIDATED_HARD_GUARD_EVIDENCE_INVALID", "$.hard_guard"))
        elif status in {"PROPOSED", "UNRESOLVED"} and not _string_list(guard.get("missing_evidence"), allow_empty=False):
            errors.append(_error("NONFINAL_HARD_GUARD_MISSING_EVIDENCE_REQUIRED", "$.hard_guard.missing_evidence"))
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

    errors.extend(_claim_errors("symptom", payload.get("symptom"), required_status="OBSERVED"))
    for field in ("immediate_cause", "systemic_root_cause", "first_bad_control", "escape_control"):
        errors.extend(_claim_errors(field, payload.get(field)))

    chain = payload.get("causal_chain")
    if not isinstance(chain, list) or len(chain) < 3:
        errors.append(_error("CAUSAL_CHAIN_INSUFFICIENT", "$.causal_chain"))
    else:
        for idx, item in enumerate(chain):
            for err in _claim_errors(f"causal_chain[{idx}]", item):
                err["path"] = err["path"].replace("$.causal_chain[", "$.causal_chain[")
                errors.append(err)

    for field in ("origin_asset", "origin_operation", "owner"):
        errors.extend(_authority_ref_errors(field, payload.get(field)))

    if payload.get("repair_level") not in REPAIR_LEVELS:
        errors.append(_error("REPAIR_LEVEL_INVALID", "$.repair_level"))

    errors.extend(_live_packet_errors(payload))
    errors.extend(_reconciliation_errors(payload))
    errors.extend(_falsification_errors(payload, require_complete=status == "SYSTEMIC_REPAIR_SPEC"))
    errors.extend(_evidence_map_errors(payload))
    errors.extend(_structured_list_errors(payload))
    errors.extend(_decision_errors(payload))
    errors.extend(_proposal_errors(payload))

    contradictions = payload.get("authority_contradictions")
    if not isinstance(contradictions, list):
        errors.append(_error("AUTHORITY_CONTRADICTIONS_INVALID", "$.authority_contradictions"))

    recurrence = payload.get("recurrence_evidence")
    if not isinstance(recurrence, list) or not recurrence:
        errors.append(_error("RECURRENCE_EVIDENCE_INVALID", "$.recurrence_evidence"))
    else:
        for idx, item in enumerate(recurrence):
            if not isinstance(item, dict) or item.get("evidence_class") not in {"DECLARED_INPUT", "OBSERVED_HISTORY", "OBSERVED_LIVE"} or not _nonempty_string(item.get("scope")):
                errors.append(_error("RECURRENCE_EVIDENCE_NOT_TYPED", f"$.recurrence_evidence[{idx}]"))

    existence = payload.get("should_exist_assessment")
    if not isinstance(existence, dict):
        errors.append(_error("SHOULD_EXIST_ASSESSMENT_MISSING", "$.should_exist_assessment"))
    else:
        if existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            if not _string_list(existence.get("missing_evidence"), allow_empty=False):
                errors.append(_error("SHOULD_EXIST_MISSING_EVIDENCE_REQUIRED", "$.should_exist_assessment.missing_evidence"))
        else:
            if not _string_list(existence.get("evidence_refs"), allow_empty=False):
                errors.append(_error("SHOULD_EXIST_EVIDENCE_REQUIRED", "$.should_exist_assessment.evidence_refs"))
            consumers = existence.get("real_consumers")
            if not isinstance(consumers, list):
                errors.append(_error("SHOULD_EXIST_REAL_CONSUMERS_INVALID", "$.should_exist_assessment.real_consumers"))
            else:
                for idx, consumer in enumerate(consumers):
                    if not isinstance(consumer, dict) or not _nonempty_string(consumer.get("consumer")) or not _nonempty_string(consumer.get("evidence_ref")):
                        errors.append(_error("SHOULD_EXIST_CONSUMER_NOT_EVIDENCE_BOUND", f"$.should_exist_assessment.real_consumers[{idx}]"))

    root = payload.get("systemic_root_cause") if isinstance(payload.get("systemic_root_cause"), dict) else {}
    packet = payload.get("live_authority_packet") if isinstance(payload.get("live_authority_packet"), dict) else {}
    reconciliations = payload.get("execution_effect_reconciliation") if isinstance(payload.get("execution_effect_reconciliation"), list) else []
    authority_incomplete = packet.get("status") != "COMPLETE"
    effect_incomplete = any(isinstance(row, dict) and row.get("reconciliation_status") != "MATCH" for row in reconciliations)

    if root.get("status") != "ESTABLISHED" and payload.get("repair_level") != "UNDETERMINED":
        errors.append(_error("REPAIR_LEVEL_PREMATURE", "$.repair_level"))

    if status != "SYSTEMIC_REPAIR_SPEC":
        if payload.get("selected_alternative") is not None:
            errors.append(_error("FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS", "$.selected_alternative"))
        if payload.get("residual_risks"):
            errors.append(_error("RESIDUAL_RISK_BEFORE_READY_SPEC", "$.residual_risks"))

    if status == "NEEDS_MORE_EVIDENCE":
        blockers = payload.get("blocking_codes")
        uncertainties = payload.get("current_uncertainties")
        if not isinstance(blockers, list) or not blockers:
            errors.append(_error("NEEDS_MORE_EVIDENCE_WITHOUT_BLOCKER", "$.blocking_codes"))
        if not isinstance(uncertainties, list) or not uncertainties:
            errors.append(_error("NEEDS_MORE_EVIDENCE_WITHOUT_UNCERTAINTY", "$.current_uncertainties"))
        elif not any(isinstance(item, dict) and item.get("blocking") is True for item in uncertainties):
            errors.append(_error("NEEDS_MORE_EVIDENCE_WITHOUT_BLOCKING_UNCERTAINTY", "$.current_uncertainties"))
        if authority_incomplete or effect_incomplete:
            if root.get("status") == "ESTABLISHED":
                errors.append(_error("PREMATURE_SYSTEMIC_ROOT_CAUSE", "$.systemic_root_cause.status"))
            if payload.get("repair_level") != "UNDETERMINED":
                errors.append(_error("PREMATURE_REPAIR_LEVEL", "$.repair_level"))
            if payload.get("rejected_alternatives"):
                errors.append(_error("PREMATURE_REJECTED_ALTERNATIVES", "$.rejected_alternatives"))

    if status == "SYSTEMIC_REPAIR_SPEC":
        if authority_incomplete:
            errors.append(_error("SYSTEMIC_SPEC_WITHOUT_COMPLETE_LIVE_AUTHORITY", "$.live_authority_packet.status"))
        if effect_incomplete:
            errors.append(_error("SYSTEMIC_SPEC_WITH_UNRESOLVED_EFFECT_RECONCILIATION", "$.execution_effect_reconciliation"))
        if contradictions:
            errors.append(_error("UNRESOLVED_AUTHORITY_CONTRADICTION", "$.authority_contradictions"))
        if payload.get("blocking_codes"):
            errors.append(_error("SYSTEMIC_SPEC_WITH_BLOCKERS", "$.blocking_codes"))
        if payload.get("current_uncertainties"):
            errors.append(_error("SYSTEMIC_SPEC_WITH_CURRENT_UNCERTAINTIES", "$.current_uncertainties"))
        for field in ("immediate_cause", "systemic_root_cause", "first_bad_control", "escape_control"):
            item = payload.get(field)
            if not isinstance(item, dict) or item.get("status") != "ESTABLISHED":
                errors.append(_error("SYSTEMIC_SPEC_CAUSAL_CLAIM_NOT_ESTABLISHED", f"$.{field}.status"))
        if payload.get("repair_level") == "UNDETERMINED":
            errors.append(_error("SYSTEMIC_SPEC_REPAIR_LEVEL_UNDETERMINED", "$.repair_level"))
        alternatives = payload.get("alternatives") or []
        if len(alternatives) < 3:
            errors.append(_error("ALTERNATIVES_INSUFFICIENT", "$.alternatives"))
        selected = payload.get("selected_alternative")
        if not _nonempty_string(selected):
            errors.append(_error("SYSTEMIC_SPEC_SELECTED_ALTERNATIVE_REQUIRED", "$.selected_alternative"))
        if payload.get("preferred_alternative") != selected:
            errors.append(_error("SYSTEMIC_SPEC_PREFERRED_SELECTED_MISMATCH", "$.preferred_alternative"))
        rejected = payload.get("rejected_alternatives") or []
        if len(rejected) < 2:
            errors.append(_error("REJECTED_ALTERNATIVES_INSUFFICIENT", "$.rejected_alternatives"))
        if any(isinstance(item, dict) and item.get("id") == selected for item in rejected):
            errors.append(_error("SELECTED_ALTERNATIVE_ALSO_REJECTED", "$.rejected_alternatives"))
        if not isinstance(existence, dict) or existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            errors.append(_error("SHOULD_EXIST_ASSESSMENT_UNRESOLVED", "$.should_exist_assessment.verdict"))
        for field in ("origin_asset", "origin_operation", "owner"):
            item = payload.get(field)
            if not isinstance(item, dict) or item.get("status") != "RESOLVED":
                errors.append(_error("SYSTEMIC_SPEC_AUTHORITY_REF_UNRESOLVED", f"$.{field}.status"))
        if not isinstance(payload.get("invariant"), dict) or payload["invariant"].get("status") != "VALIDATED":
            errors.append(_error("SYSTEMIC_SPEC_INVARIANT_NOT_VALIDATED", "$.invariant.status"))
        if not isinstance(payload.get("hard_guard"), dict) or payload["hard_guard"].get("status") != "VALIDATED":
            errors.append(_error("SYSTEMIC_SPEC_HARD_GUARD_NOT_VALIDATED", "$.hard_guard.status"))
        if len(payload.get("historical_regressions") or []) < 1:
            errors.append(_error("SYSTEMIC_SPEC_HISTORICAL_REGRESSION_REQUIRED", "$.historical_regressions"))
        if len(payload.get("planned_regressions") or []) < 3:
            errors.append(_error("SYSTEMIC_SPEC_PLANNED_REGRESSIONS_INSUFFICIENT", "$.planned_regressions"))
        if len(payload.get("acceptance_criteria") or []) < 3:
            errors.append(_error("SYSTEMIC_SPEC_ACCEPTANCE_CRITERIA_INSUFFICIENT", "$.acceptance_criteria"))

    next_gate = payload.get("next_gate")
    if not isinstance(next_gate, dict) or not all(_nonempty_string(next_gate.get(key)) for key in ("gate", "entry_condition", "exit_condition")):
        errors.append(_error("NEXT_GATE_NOT_STRUCTURED", "$.next_gate"))

    codes = sorted({item["code"] for item in errors})
    return {"valid": not errors, "status": "PASS" if not errors else "FAIL", "errors": errors, "blocking_codes": codes}


if __name__ == "__main__":
    import json
    import sys

    try:
        value = json.load(sys.stdin)
    except Exception:
        value = None
    print(json.dumps(validate(value), ensure_ascii=False, indent=2))
