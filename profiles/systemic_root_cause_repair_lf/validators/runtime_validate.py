#!/usr/bin/env python3
"""Deterministic runtime validator for Systemic Root Cause Repair LF.

A SYSTEMIC_REPAIR_SPEC means the repair design is ready for governed
implementation. It does not require post-implementation evidence to exist.
Evidence gaps are classified by whether they can still change the design.
"""

try:
    from .closure_proof import FALSIFICATION_EVIDENCE_CLASSES, RECURRENCE_EVIDENCE_CLASSES, unwrap_runtime_input, validate_v03_closure
except (ImportError, ModuleNotFoundError):
    import importlib.util as _importlib_util
    from pathlib import Path as _Path
    _closure_path = _Path(__file__).with_name("closure_proof.py")
    _closure_spec = _importlib_util.spec_from_file_location("srcr_closure_proof", _closure_path)
    _closure_mod = _importlib_util.module_from_spec(_closure_spec)
    assert _closure_spec and _closure_spec.loader
    _closure_spec.loader.exec_module(_closure_mod)
    RECURRENCE_EVIDENCE_CLASSES = _closure_mod.RECURRENCE_EVIDENCE_CLASSES
    FALSIFICATION_EVIDENCE_CLASSES = _closure_mod.FALSIFICATION_EVIDENCE_CLASSES
    unwrap_runtime_input = _closure_mod.unwrap_runtime_input
    validate_v03_closure = _closure_mod.validate_v03_closure

try:
    from .incremental_value import validate_incremental_value
except (ImportError, ModuleNotFoundError):
    import importlib.util as _iv_importlib_util
    from pathlib import Path as _IVPath
    _iv_path = _IVPath(__file__).with_name("incremental_value.py")
    _iv_spec = _iv_importlib_util.spec_from_file_location("srcr_incremental_value", _iv_path)
    _iv_mod = _iv_importlib_util.module_from_spec(_iv_spec)
    assert _iv_spec and _iv_spec.loader
    _iv_spec.loader.exec_module(_iv_mod)
    validate_incremental_value = _iv_mod.validate_incremental_value

V04_PACK_ID = "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_4"

ALLOWED_PROFILE_PACK_IDS = {
    "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_2",
    "SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_3",
    V04_PACK_ID,
}

ALLOWED_STATUS = {
    "SYSTEMIC_REPAIR_SPEC",
    "NEEDS_MORE_EVIDENCE",
    "RETURN_TO_WORKER_FOR_SELF_REPAIR",
    "BLOCK_PIPELINE",
    "NO_REPAIR_REQUIRED",
}
CLAIM_STATUS = {"OBSERVED", "ESTABLISHED", "HYPOTHESIS", "UNRESOLVED"}
AUTHORITY_STATUS = {"RESOLVED", "UNRESOLVED"}
REPAIR_LEVELS = {"UNDETERMINED", "LOCAL", "SYSTEMIC_ORIGIN", "ARCHITECTURAL"}
IMPACTS = {
    "DESIGN_BLOCKING",
    "IMPLEMENTATION_PRECONDITION",
    "NON_BLOCKING_HISTORICAL",
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
OBSERVED_FALSIFICATION_EVIDENCE = FALSIFICATION_EVIDENCE_CLASSES - {"DESIGN_ONLY", "MISSING"}
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
    missing = value.get("missing_evidence")
    if status not in AUTHORITY_STATUS:
        errors.append(_error("AUTHORITY_REF_STATUS_INVALID", f"{path}.status"))
        return errors
    if not _string_list(missing):
        errors.append(_error("AUTHORITY_REF_MISSING_EVIDENCE_INVALID", f"{path}.missing_evidence"))
    if status == "RESOLVED":
        if not _nonempty_string(value.get("code")):
            errors.append(_error("RESOLVED_AUTHORITY_CODE_REQUIRED", f"{path}.code"))
        if not _nonempty_string(value.get("evidence_ref")):
            errors.append(_error("RESOLVED_AUTHORITY_EVIDENCE_REQUIRED", f"{path}.evidence_ref"))
        if missing:
            errors.append(_error("RESOLVED_AUTHORITY_WITH_MISSING_EVIDENCE", f"{path}.missing_evidence"))
    elif not missing:
        errors.append(_error("UNRESOLVED_AUTHORITY_MISSING_EVIDENCE_REQUIRED", f"{path}.missing_evidence"))
    return errors


def _uncertainty_errors(payload):
    errors = []
    rows = payload.get("current_uncertainties")
    if not isinstance(rows, list):
        return [_error("CURRENT_UNCERTAINTIES_INVALID", "$.current_uncertainties")]
    for idx, row in enumerate(rows):
        path = f"$.current_uncertainties[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("CURRENT_UNCERTAINTY_INVALID", path))
            continue
        impact = row.get("impact")
        if impact not in IMPACTS:
            errors.append(_error("CURRENT_UNCERTAINTY_IMPACT_INVALID", f"{path}.impact"))
        if not _nonempty_string(row.get("uncertainty")):
            errors.append(_error("CURRENT_UNCERTAINTY_TEXT_REQUIRED", f"{path}.uncertainty"))
        if not _string_list(row.get("evidence_needed"), allow_empty=False):
            errors.append(_error("CURRENT_UNCERTAINTY_EVIDENCE_NEEDED_INVALID", f"{path}.evidence_needed"))
        if not _nonempty_string(row.get("design_consequence")):
            errors.append(_error("CURRENT_UNCERTAINTY_DESIGN_CONSEQUENCE_REQUIRED", f"{path}.design_consequence"))
        containment = row.get("containment_ref")
        if impact in {"IMPLEMENTATION_PRECONDITION", "NON_BLOCKING_HISTORICAL"} and not _nonempty_string(containment):
            errors.append(_error("NONBLOCKING_UNCERTAINTY_CONTAINMENT_REQUIRED", f"{path}.containment_ref"))
    return errors


def _live_packet_errors(payload):
    errors = []
    packet = payload.get("live_authority_packet")
    blockers = payload.get("blocking_codes") if isinstance(payload.get("blocking_codes"), list) else []
    if not isinstance(packet, dict):
        return [_error("LIVE_AUTHORITY_PACKET_MISSING", "$.live_authority_packet")]

    status = packet.get("status")
    if status not in LIVE_PACKET_STATUS:
        return [_error("LIVE_AUTHORITY_PACKET_STATUS_INVALID", "$.live_authority_packet.status")]

    applicable = packet.get("applicable_surfaces")
    inspected = packet.get("inspected_surfaces")
    evidence_refs = packet.get("evidence_refs")
    unavailable = packet.get("unavailable_sources")
    assessments = packet.get("unavailable_source_assessments")
    if not _string_list(applicable, allow_empty=False):
        errors.append(_error("LIVE_AUTHORITY_APPLICABLE_SURFACES_MISSING", "$.live_authority_packet.applicable_surfaces"))
    if not _string_list(inspected):
        errors.append(_error("LIVE_AUTHORITY_INSPECTED_SURFACES_INVALID", "$.live_authority_packet.inspected_surfaces"))
    if not _string_list(evidence_refs):
        errors.append(_error("LIVE_AUTHORITY_EVIDENCE_REFS_INVALID", "$.live_authority_packet.evidence_refs"))
    if not _string_list(unavailable):
        errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_SOURCES_INVALID", "$.live_authority_packet.unavailable_sources"))
    if not isinstance(assessments, list):
        errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_ASSESSMENTS_INVALID", "$.live_authority_packet.unavailable_source_assessments"))
        assessments = []

    assessed_sources = []
    design_blocking = False
    for idx, row in enumerate(assessments):
        path = f"$.live_authority_packet.unavailable_source_assessments[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_ASSESSMENT_INVALID", path))
            continue
        source = row.get("source")
        impact = row.get("impact")
        assessed_sources.append(source)
        if not _nonempty_string(source):
            errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_SOURCE_REQUIRED", f"{path}.source"))
        if impact not in IMPACTS:
            errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_IMPACT_INVALID", f"{path}.impact"))
        if not _nonempty_string(row.get("rationale")):
            errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_RATIONALE_REQUIRED", f"{path}.rationale"))
        if impact == "DESIGN_BLOCKING":
            design_blocking = True
        elif not _nonempty_string(row.get("containment_ref")):
            errors.append(_error("LIVE_AUTHORITY_NONBLOCKING_CONTAINMENT_REQUIRED", f"{path}.containment_ref"))

    if isinstance(unavailable, list) and set(unavailable) != set(assessed_sources):
        errors.append(_error("LIVE_AUTHORITY_UNAVAILABLE_ASSESSMENT_MISMATCH", "$.live_authority_packet.unavailable_source_assessments"))

    if status == "COMPLETE":
        if not evidence_refs:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITHOUT_EVIDENCE", "$.live_authority_packet.evidence_refs"))
        if unavailable:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITH_UNAVAILABLE_SOURCE", "$.live_authority_packet.unavailable_sources"))
        if assessments:
            errors.append(_error("LIVE_AUTHORITY_COMPLETE_WITH_UNAVAILABLE_ASSESSMENT", "$.live_authority_packet.unavailable_source_assessments"))
        if isinstance(applicable, list) and isinstance(inspected, list) and set(applicable) != set(inspected):
            errors.append(_error("LIVE_AUTHORITY_SURFACE_COVERAGE_INCOMPLETE", "$.live_authority_packet"))
    elif status == "PARTIAL":
        if design_blocking and "LIVE_AUTHORITY_EVIDENCE_INCOMPLETE" not in blockers:
            errors.append(_error("LIVE_AUTHORITY_DESIGN_BLOCKER_WITHOUT_CODE", "$.blocking_codes"))
    elif status == "MISSING":
        if "LIVE_AUTHORITY_EVIDENCE_MISSING" not in blockers:
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
        impact = row.get("impact")
        producer_refs = row.get("observed_producer_refs")
        containment = row.get("containment_ref")
        if status not in RECONCILIATION_STATUS:
            errors.append(_error("EXECUTION_EFFECT_RECONCILIATION_STATUS_INVALID", f"{path}.reconciliation_status"))
            continue
        if impact not in {"NONE"} | IMPACTS:
            errors.append(_error("EXECUTION_EFFECT_IMPACT_INVALID", f"{path}.impact"))
        if not _nonempty_string(row.get("declared_producer_ref")):
            errors.append(_error("DECLARED_PRODUCER_AUTHORITY_REF_REQUIRED", f"{path}.declared_producer_ref"))
        if not _string_list(producer_refs):
            errors.append(_error("EXECUTION_EFFECT_PRODUCER_REFS_INVALID", f"{path}.observed_producer_refs"))

        if status == "MATCH":
            if row.get("blocking") is not False:
                errors.append(_error("MATCH_RECONCILIATION_MUST_NOT_BLOCK", f"{path}.blocking"))
            if not producer_refs:
                errors.append(_error("MATCH_REQUIRES_OBSERVED_PRODUCER", f"{path}.observed_producer_refs"))
            if impact != "NONE":
                errors.append(_error("MATCH_RECONCILIATION_IMPACT_MUST_BE_NONE", f"{path}.impact"))
            if containment is not None:
                errors.append(_error("MATCH_RECONCILIATION_CONTAINMENT_MUST_BE_NULL", f"{path}.containment_ref"))
        elif status == "UNRESOLVED_PRODUCER":
            if impact == "DESIGN_BLOCKING":
                if row.get("blocking") is not True:
                    errors.append(_error("DESIGN_BLOCKING_UNRESOLVED_PRODUCER_MUST_BLOCK", f"{path}.blocking"))
                if "EXECUTION_EFFECT_PRODUCER_UNRESOLVED" not in blockers:
                    errors.append(_error("UNRESOLVED_PRODUCER_WITHOUT_BLOCKER", "$.blocking_codes"))
            elif impact in {"IMPLEMENTATION_PRECONDITION", "NON_BLOCKING_HISTORICAL"}:
                if row.get("blocking") is not False:
                    errors.append(_error("CONTAINED_UNRESOLVED_PRODUCER_MUST_NOT_BLOCK_SPEC", f"{path}.blocking"))
                if not _nonempty_string(containment):
                    errors.append(_error("CONTAINED_UNRESOLVED_PRODUCER_REQUIRES_CONTAINMENT", f"{path}.containment_ref"))
            else:
                errors.append(_error("UNRESOLVED_PRODUCER_IMPACT_REQUIRED", f"{path}.impact"))
        else:
            if row.get("blocking") is not True:
                errors.append(_error("AUTHORITY_CONTRADICTION_RECONCILIATION_MUST_BLOCK", f"{path}.blocking"))
            if impact != "DESIGN_BLOCKING":
                errors.append(_error("AUTHORITY_CONTRADICTION_MUST_BE_DESIGN_BLOCKING", f"{path}.impact"))
    return errors


def _falsification_errors(payload, *, require_ready=False):
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
        path = f"$.falsification_results[{idx}]"
        if not isinstance(item, dict):
            errors.append(_error("FALSIFICATION_RESULT_INVALID", path))
            continue
        case = item.get("case")
        result = item.get("result")
        evidence_class = item.get("evidence_class")
        if case not in REQUIRED_FALSIFICATION_CASES:
            errors.append(_error("FALSIFICATION_CASE_UNKNOWN", f"{path}.case"))
        if not _nonempty_string(item.get("verification_method")):
            errors.append(_error("FALSIFICATION_VERIFICATION_METHOD_REQUIRED", f"{path}.verification_method"))
        if not _nonempty_string(item.get("expected_result")):
            errors.append(_error("FALSIFICATION_EXPECTED_RESULT_REQUIRED", f"{path}.expected_result"))
        if result == "PASS" and evidence_class not in OBSERVED_FALSIFICATION_EVIDENCE:
            errors.append(_error("FALSIFICATION_PASS_NOT_OBSERVED", f"{path}.evidence_class"))
        if result == "PLANNED" and evidence_class != "DESIGN_ONLY":
            errors.append(_error("FALSIFICATION_PLANNED_MUST_BE_DESIGN_ONLY", f"{path}.evidence_class"))
        if require_ready and case in REQUIRED_FALSIFICATION_CASES and result not in {"PASS", "PLANNED"}:
            errors.append(_error("SYSTEMIC_SPEC_FALSIFICATION_NOT_SPECIFIED", f"{path}.result"))
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
    for field in ("historical_regressions", "planned_regressions", "acceptance_criteria", "residual_risks", "implementation_delta"):
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
    for idx, row in enumerate(payload.get("residual_risks") or []):
        path = f"$.residual_risks[{idx}]"
        if not isinstance(row, dict) or not _nonempty_string(row.get("risk")) or not _string_list(row.get("evidence_refs"), allow_empty=False):
            errors.append(_error("RESIDUAL_RISK_INVALID", path))
    for idx, row in enumerate(payload.get("implementation_delta") or []):
        path = f"$.implementation_delta[{idx}]"
        if not isinstance(row, dict) or not all(_nonempty_string(row.get(key)) for key in ("target", "action", "rationale")) or not _string_list(row.get("evidence_refs"), allow_empty=False):
            errors.append(_error("IMPLEMENTATION_DELTA_INVALID", path))
    errors.extend(_uncertainty_errors(payload))
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
        state = invariant.get("validation_state")
        if state not in {"VERIFIED", "SPECIFIED", "PROPOSED", "UNRESOLVED"}:
            errors.append(_error("INVARIANT_STATUS_INVALID", "$.invariant.validation_state"))
        if state in {"VERIFIED", "SPECIFIED"}:
            if not _nonempty_string(invariant.get("statement")) or not _string_list(invariant.get("evidence_refs"), allow_empty=False) or invariant.get("missing_evidence"):
                errors.append(_error("FINAL_INVARIANT_EVIDENCE_INVALID", "$.invariant"))
        elif state in {"PROPOSED", "UNRESOLVED"} and not _string_list(invariant.get("missing_evidence"), allow_empty=False):
            errors.append(_error("NONFINAL_INVARIANT_MISSING_EVIDENCE_REQUIRED", "$.invariant.missing_evidence"))

    guard = payload.get("hard_guard")
    if not isinstance(guard, dict):
        errors.append(_error("HARD_GUARD_INVALID", "$.hard_guard"))
    else:
        state = guard.get("validation_state")
        if state not in {"VERIFIED", "SPECIFIED", "PROPOSED", "UNRESOLVED"}:
            errors.append(_error("HARD_GUARD_STATUS_INVALID", "$.hard_guard.validation_state"))
        if state in {"VERIFIED", "SPECIFIED"}:
            required = ("control", "enforcement_point_ref", "fail_closed_condition", "blocking_code", "observable_result")
            if not all(_nonempty_string(guard.get(key)) for key in required):
                errors.append(_error("FINAL_HARD_GUARD_NOT_EXECUTABLE", "$.hard_guard"))
            if not _string_list(guard.get("evidence_refs"), allow_empty=False) or guard.get("missing_evidence"):
                errors.append(_error("FINAL_HARD_GUARD_EVIDENCE_INVALID", "$.hard_guard"))
        elif state in {"PROPOSED", "UNRESOLVED"} and not _string_list(guard.get("missing_evidence"), allow_empty=False):
            errors.append(_error("NONFINAL_HARD_GUARD_MISSING_EVIDENCE_REQUIRED", "$.hard_guard.missing_evidence"))
    return errors


def _implementation_plan_errors(payload, *, require_ready=False):
    errors = []
    delta = payload.get("implementation_delta")
    transition = payload.get("transition_plan")
    rollback = payload.get("rollback_plan")
    if require_ready and (not isinstance(delta, list) or not delta):
        errors.append(_error("SYSTEMIC_SPEC_IMPLEMENTATION_DELTA_REQUIRED", "$.implementation_delta"))
    if transition is not None and not isinstance(transition, dict):
        errors.append(_error("TRANSITION_PLAN_INVALID", "$.transition_plan"))
    if rollback is not None and not isinstance(rollback, dict):
        errors.append(_error("ROLLBACK_PLAN_INVALID", "$.rollback_plan"))
    if require_ready:
        if not isinstance(transition, dict):
            errors.append(_error("SYSTEMIC_SPEC_TRANSITION_PLAN_REQUIRED", "$.transition_plan"))
        else:
            if not _nonempty_string(transition.get("strategy")) or not _nonempty_string(transition.get("compatibility_rule")):
                errors.append(_error("SYSTEMIC_SPEC_TRANSITION_PLAN_NOT_EXECUTABLE", "$.transition_plan"))
            stages = transition.get("stages")
            if not isinstance(stages, list) or not stages:
                errors.append(_error("SYSTEMIC_SPEC_TRANSITION_STAGES_REQUIRED", "$.transition_plan.stages"))
        if not isinstance(rollback, dict):
            errors.append(_error("SYSTEMIC_SPEC_ROLLBACK_PLAN_REQUIRED", "$.rollback_plan"))
        else:
            for key in ("trigger_conditions", "inverse_actions", "protected_history", "verification"):
                if not _string_list(rollback.get(key), allow_empty=False):
                    errors.append(_error("SYSTEMIC_SPEC_ROLLBACK_PLAN_NOT_EXECUTABLE", f"$.rollback_plan.{key}"))
    return errors



OMISSION_DIMENSIONS = {
    "ARCHITECTURE", "CONTROLS", "POLICIES_CONTRACTS", "CONTEXT_TRANSPORT",
    "WIRING", "COMPATIBILITY_TRANSITION", "RECOVERY_TERMINALITY", "OBSERVABILITY",
    "SECURITY_AUTHORITY", "COST_PERFORMANCE", "TESTING_ASSURANCE", "OPERABILITY_MAINTENANCE",
}

def _test_protocol_errors(path, protocol):
    errors = []
    if not isinstance(protocol, dict):
        return [_error("EXECUTABLE_TEST_PROTOCOL_REQUIRED", path)]
    for key in ("setup", "action", "assertions"):
        if not _string_list(protocol.get(key), allow_empty=False):
            errors.append(_error("EXECUTABLE_TEST_PROTOCOL_INCOMPLETE", f"{path}.{key}"))
    if not _nonempty_string(protocol.get("failure_signal")):
        errors.append(_error("EXECUTABLE_TEST_FAILURE_SIGNAL_REQUIRED", f"{path}.failure_signal"))
    return errors

def _solution_assurance_errors(payload, *, require_ready=False):
    errors = []
    depth = payload.get("solution_depth")
    if not isinstance(depth, dict) or depth.get("mode") not in {"LIGHTWEIGHT", "BOUNDED", "DEEP_ARCHITECTURE_RESEARCH"}:
        errors.append(_error("SOLUTION_DEPTH_INVALID", "$.solution_depth"))
        mode = None
    else:
        mode = depth.get("mode")
        if not _nonempty_string(depth.get("rationale")):
            errors.append(_error("SOLUTION_DEPTH_RATIONALE_REQUIRED", "$.solution_depth.rationale"))

    research = payload.get("research_assurance")
    if not isinstance(research, dict):
        errors.append(_error("RESEARCH_ASSURANCE_REQUIRED", "$.research_assurance"))
    else:
        if require_ready and research.get("research_complete") is not True:
            errors.append(_error("SYSTEMIC_SPEC_RESEARCH_NOT_COMPLETE", "$.research_assurance.research_complete"))
        if not _string_list(research.get("research_questions"), allow_empty=False):
            errors.append(_error("RESEARCH_QUESTIONS_REQUIRED", "$.research_assurance.research_questions"))
        if not _string_list(research.get("internal_evidence_refs"), allow_empty=False):
            errors.append(_error("RESEARCH_INTERNAL_EVIDENCE_REQUIRED", "$.research_assurance.internal_evidence_refs"))
        if research.get("current_practice_research_required") is True and not _string_list(research.get("external_evidence_refs"), allow_empty=False):
            errors.append(_error("CURRENT_PRACTICE_EVIDENCE_REQUIRED", "$.research_assurance.external_evidence_refs"))
        patterns = research.get("patterns_compared")
        if not isinstance(patterns, list) or not patterns:
            errors.append(_error("RESEARCH_PATTERNS_REQUIRED", "$.research_assurance.patterns_compared"))
        elif require_ready and mode == "DEEP_ARCHITECTURE_RESEARCH" and len(patterns) < 2:
            errors.append(_error("DEEP_RESEARCH_PATTERN_COMPARISON_INSUFFICIENT", "$.research_assurance.patterns_compared"))
        if research.get("first_solution_disposition") not in {"RETAINED_AFTER_CHALLENGE", "REVISED", "REJECTED"}:
            errors.append(_error("FIRST_SOLUTION_NOT_CHALLENGED", "$.research_assurance.first_solution_disposition"))

    challenges = payload.get("challenger_review")
    min_challenges = 3 if mode == "DEEP_ARCHITECTURE_RESEARCH" else (2 if mode == "BOUNDED" else 1)
    if not isinstance(challenges, list) or (require_ready and len(challenges) < min_challenges):
        errors.append(_error("CHALLENGER_REVIEW_INSUFFICIENT", "$.challenger_review", str(min_challenges)))
    elif isinstance(challenges, list):
        for idx, row in enumerate(challenges):
            if not isinstance(row, dict):
                errors.append(_error("CHALLENGER_REVIEW_INVALID", f"$.challenger_review[{idx}]"))
                continue
            if require_ready and row.get("outcome") == "BLOCKED":
                errors.append(_error("SYSTEMIC_SPEC_WITH_UNRESOLVED_CHALLENGE", f"$.challenger_review[{idx}].outcome"))
            if not _nonempty_string(row.get("resolution")) or not _string_list(row.get("evidence_refs"), allow_empty=False):
                errors.append(_error("CHALLENGER_REVIEW_NOT_EVIDENCE_BOUND", f"$.challenger_review[{idx}]"))

    omissions = payload.get("omission_discovery")
    if not isinstance(omissions, list):
        errors.append(_error("OMISSION_DISCOVERY_REQUIRED", "$.omission_discovery"))
    elif require_ready:
        dims = [x.get("dimension") for x in omissions if isinstance(x, dict)]
        missing = sorted(OMISSION_DIMENSIONS - set(dims))
        dup = sorted({x for x in dims if dims.count(x) > 1})
        if missing:
            errors.append(_error("SYSTEMIC_SPEC_OMISSION_DIMENSIONS_MISSING", "$.omission_discovery", ",".join(missing)))
        if dup:
            errors.append(_error("SYSTEMIC_SPEC_OMISSION_DIMENSIONS_DUPLICATED", "$.omission_discovery", ",".join(dup)))

    package = payload.get("implementation_package")
    if require_ready and not isinstance(package, dict):
        errors.append(_error("SYSTEMIC_SPEC_IMPLEMENTATION_PACKAGE_REQUIRED", "$.implementation_package"))
        return errors
    if not isinstance(package, dict):
        return errors

    for key in ("architecture_decisions", "control_matrix", "policy_contract_changes", "wiring", "deliverables", "observability_plan"):
        if require_ready and (not isinstance(package.get(key), list) or not package.get(key)):
            errors.append(_error("SYSTEMIC_SPEC_IMPLEMENTATION_PACKAGE_SECTION_REQUIRED", f"$.implementation_package.{key}"))

    context = package.get("context_transport")
    if not isinstance(context, dict):
        errors.append(_error("CONTEXT_TRANSPORT_ASSESSMENT_REQUIRED", "$.implementation_package.context_transport"))
    elif context.get("status") == "APPLIES":
        for key in ("compiler_ref", "delivery_strategy", "degradation_rule"):
            if not _nonempty_string(context.get(key)):
                errors.append(_error("CONTEXT_TRANSPORT_NOT_CLOSED", f"$.implementation_package.context_transport.{key}"))
        budget = context.get("token_budget")
        if not isinstance(budget, dict):
            errors.append(_error("CONTEXT_TOKEN_BUDGET_REQUIRED", "$.implementation_package.context_transport.token_budget"))
        else:
            soft, hard = budget.get("soft_limit_tokens"), budget.get("hard_limit_tokens")
            if not isinstance(soft, int) or not isinstance(hard, int) or soft < 1 or hard < soft:
                errors.append(_error("CONTEXT_TOKEN_BUDGET_INVALID", "$.implementation_package.context_transport.token_budget"))
    elif context.get("status") == "NOT_APPLICABLE":
        if not _nonempty_string(context.get("rationale")):
            errors.append(_error("CONTEXT_TRANSPORT_NA_RATIONALE_REQUIRED", "$.implementation_package.context_transport.rationale"))
    else:
        errors.append(_error("CONTEXT_TRANSPORT_STATUS_INVALID", "$.implementation_package.context_transport.status"))

    closure = package.get("decision_closure")
    if not isinstance(closure, dict):
        errors.append(_error("IMPLEMENTATION_DECISION_CLOSURE_REQUIRED", "$.implementation_package.decision_closure"))
    else:
        open_decisions = closure.get("open_design_decisions")
        if require_ready and open_decisions != []:
            errors.append(_error("SYSTEMIC_SPEC_OPEN_DESIGN_DECISIONS", "$.implementation_package.decision_closure.open_design_decisions"))
        if require_ready and closure.get("handoff_ready") is not True:
            errors.append(_error("SYSTEMIC_SPEC_HANDOFF_NOT_READY", "$.implementation_package.decision_closure.handoff_ready"))
        preconditions = closure.get("implementation_preconditions")
        if not isinstance(preconditions, list):
            errors.append(_error("IMPLEMENTATION_PRECONDITIONS_INVALID", "$.implementation_package.decision_closure.implementation_preconditions"))
            preconditions = []
        for idx, p in enumerate(preconditions):
            path = f"$.implementation_package.decision_closure.implementation_preconditions[{idx}]"
            if not isinstance(p, dict):
                errors.append(_error("IMPLEMENTATION_PRECONDITION_INVALID", path))
                continue
            for key in ("name", "resolver_ref", "expected_shape", "decision_rule", "stage"):
                if not _nonempty_string(p.get(key)):
                    errors.append(_error("IMPLEMENTATION_PRECONDITION_NOT_MECHANICAL", f"{path}.{key}"))
            if p.get("design_effect") != "NONE":
                errors.append(_error("IMPLEMENTATION_PRECONDITION_CAN_CHANGE_DESIGN", f"{path}.design_effect"))

        uncertainties = payload.get("current_uncertainties") if isinstance(payload.get("current_uncertainties"), list) else []
        implementation_uncertainties = [u for u in uncertainties if isinstance(u, dict) and u.get("impact") == "IMPLEMENTATION_PRECONDITION"]
        if require_ready and len(preconditions) < len(implementation_uncertainties):
            errors.append(_error("IMPLEMENTATION_PRECONDITION_NOT_MATERIALIZED", "$.implementation_package.decision_closure.implementation_preconditions"))
        for idx, u in enumerate(implementation_uncertainties):
            ref = u.get("containment_ref")
            if require_ready and (not _nonempty_string(ref) or not ref.startswith("$.implementation_package.decision_closure.implementation_preconditions")):
                errors.append(_error("IMPLEMENTATION_PRECONDITION_NOT_LINKED_TO_CLOSURE", f"$.current_uncertainties[{idx}].containment_ref"))

    return errors

def _v04_transversal_errors(payload):
    """V0.4 guards for no-repair disposition, quantitative grounding, and process depth."""
    if payload.get("profile_pack_id") != V04_PACK_ID:
        return []

    errors = []
    status = payload.get("status")
    disposition = payload.get("repair_disposition")
    if not isinstance(disposition, dict):
        errors.append(_error("V04_REPAIR_DISPOSITION_REQUIRED", "$.repair_disposition"))
        disposition = {}

    decision = disposition.get("decision")
    evidence_refs = disposition.get("evidence_refs")
    currentness_refs = disposition.get("currentness_refs")
    if decision not in {"REPAIR_REQUIRED", "ALREADY_RESOLVED", "NOT_MATERIAL"}:
        errors.append(_error("V04_REPAIR_DISPOSITION_INVALID", "$.repair_disposition.decision"))
    if not _string_list(evidence_refs, allow_empty=False):
        errors.append(_error("V04_REPAIR_DISPOSITION_EVIDENCE_REQUIRED", "$.repair_disposition.evidence_refs"))
    if not _string_list(currentness_refs, allow_empty=False):
        errors.append(_error("V04_REPAIR_DISPOSITION_CURRENTNESS_REQUIRED", "$.repair_disposition.currentness_refs"))

    if status == "NO_REPAIR_REQUIRED":
        if decision not in {"ALREADY_RESOLVED", "NOT_MATERIAL"}:
            errors.append(_error("V04_NO_REPAIR_DISPOSITION_MISMATCH", "$.repair_disposition.decision"))
        if decision == "ALREADY_RESOLVED" and disposition.get("active_failure_present") is not False:
            errors.append(_error("V04_ALREADY_RESOLVED_WITH_ACTIVE_FAILURE", "$.repair_disposition.active_failure_present"))
        if decision == "NOT_MATERIAL" and disposition.get("material_repair_justified") is not False:
            errors.append(_error("V04_NOT_MATERIAL_BUT_REPAIR_JUSTIFIED", "$.repair_disposition.material_repair_justified"))
        if payload.get("selected_alternative") is not None or payload.get("preferred_alternative") is not None:
            errors.append(_error("V04_NO_REPAIR_WITH_SELECTED_ALTERNATIVE", "$.selected_alternative"))
        for field in ("alternatives", "rejected_alternatives", "implementation_delta"):
            if payload.get(field):
                errors.append(_error("V04_NO_REPAIR_WITH_REPAIR_DELTA", f"$.{field}"))
        for field in ("implementation_package", "transition_plan", "rollback_plan"):
            if payload.get(field) is not None:
                errors.append(_error("V04_NO_REPAIR_WITH_IMPLEMENTATION_PLAN", f"$.{field}"))
        if payload.get("repair_level") != "UNDETERMINED":
            errors.append(_error("V04_NO_REPAIR_REPAIR_LEVEL_MUST_BE_UNDETERMINED", "$.repair_level"))
        if payload.get("blocking_codes"):
            errors.append(_error("V04_NO_REPAIR_WITH_BLOCKERS", "$.blocking_codes"))
    else:
        if decision != "REPAIR_REQUIRED":
            errors.append(_error("V04_READY_OR_BLOCKED_REQUIRES_REPAIR_DISPOSITION", "$.repair_disposition.decision"))
        if disposition.get("material_repair_justified") is not True:
            errors.append(_error("V04_REPAIR_NOT_JUSTIFIED", "$.repair_disposition.material_repair_justified"))

    quantitative = payload.get("quantitative_decisions")
    if not isinstance(quantitative, list):
        errors.append(_error("V04_QUANTITATIVE_DECISIONS_REQUIRED", "$.quantitative_decisions"))
        quantitative = []
    seen_q = set()
    for idx, row in enumerate(quantitative):
        p = f"$.quantitative_decisions[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("V04_QUANTITATIVE_DECISION_INVALID", p))
            continue
        did = row.get("decision_id")
        if not _nonempty_string(did) or did in seen_q:
            errors.append(_error("V04_QUANTITATIVE_DECISION_ID_INVALID", f"{p}.decision_id"))
        else:
            seen_q.add(did)
        if row.get("materiality") != "MATERIAL":
            continue
        state = row.get("closure_state")
        grounding = row.get("grounding_type")
        if state == "GROUNDED":
            if grounding not in {"EXISTING_AUTHORITY", "CALIBRATION_RULE"}:
                errors.append(_error("V04_MATERIAL_QUANT_GROUNDING_INVALID", f"{p}.grounding_type"))
            if not _nonempty_string(row.get("grounding_ref")):
                errors.append(_error("V04_MATERIAL_QUANT_GROUNDING_REF_REQUIRED", f"{p}.grounding_ref"))
            if not _string_list(row.get("evidence_refs"), allow_empty=False):
                errors.append(_error("V04_MATERIAL_QUANT_EVIDENCE_REQUIRED", f"{p}.evidence_refs"))
            if row.get("incident_specific_only") is not False:
                errors.append(_error("V04_MATERIAL_QUANT_INCIDENT_ONLY_CANNOT_CLOSE", f"{p}.incident_specific_only"))
            if row.get("precondition_ref") is not None:
                errors.append(_error("V04_GROUNDED_QUANT_WITH_PRECONDITION_REF", f"{p}.precondition_ref"))
        elif state == "PRECONDITION":
            if grounding != "IMPLEMENTATION_PRECONDITION":
                errors.append(_error("V04_QUANT_PRECONDITION_GROUNDING_MISMATCH", f"{p}.grounding_type"))
            ref = row.get("precondition_ref")
            if not _nonempty_string(ref) or not ref.startswith("$.implementation_package.decision_closure.implementation_preconditions"):
                errors.append(_error("V04_QUANT_PRECONDITION_NOT_LINKED", f"{p}.precondition_ref"))
            if row.get("proposed_value") is not None:
                errors.append(_error("V04_UNGROUNDED_QUANT_VALUE_MUST_REMAIN_OPEN", f"{p}.proposed_value"))
        else:
            errors.append(_error("V04_MATERIAL_QUANT_NOT_CLOSED", f"{p}.closure_state"))

    graph = payload.get("material_process_graph")
    if not isinstance(graph, dict):
        errors.append(_error("V04_MATERIAL_PROCESS_GRAPH_REQUIRED", "$.material_process_graph"))
        graph = {}
    applies = graph.get("applies")
    if not isinstance(applies, bool):
        errors.append(_error("V04_MATERIAL_PROCESS_GRAPH_APPLICABILITY_REQUIRED", "$.material_process_graph.applies"))
    nodes = graph.get("nodes")
    if not isinstance(nodes, list):
        errors.append(_error("V04_MATERIAL_PROCESS_GRAPH_NODES_INVALID", "$.material_process_graph.nodes"))
        nodes = []
    if applies is True and not nodes:
        errors.append(_error("V04_MATERIAL_PROCESS_GRAPH_EMPTY", "$.material_process_graph.nodes"))
    seen_nodes = set()
    for idx, row in enumerate(nodes):
        p = f"$.material_process_graph.nodes[{idx}]"
        if not isinstance(row, dict):
            errors.append(_error("V04_MATERIAL_PROCESS_NODE_INVALID", p))
            continue
        node_id = row.get("node_id")
        if not _nonempty_string(node_id) or node_id in seen_nodes:
            errors.append(_error("V04_MATERIAL_PROCESS_NODE_ID_INVALID", f"{p}.node_id"))
        else:
            seen_nodes.add(node_id)
        if status == "SYSTEMIC_REPAIR_SPEC" and row.get("disposition") == "DESIGN_BLOCKING":
            errors.append(_error("V04_SYSTEMIC_SPEC_WITH_BLOCKED_PROCESS_NODE", f"{p}.disposition"))

    return errors


def validate(payload, evidence_manifest=None):
    if evidence_manifest is None:
        candidate, embedded_manifest = unwrap_runtime_input(payload)
        if embedded_manifest is not None:
            payload, evidence_manifest = candidate, embedded_manifest
    errors = []
    closure_summary = {"applies": False}
    if not isinstance(payload, dict):
        return {"valid": False, "status": "FAIL", "errors": [_error("NOT_OBJECT")], "blocking_codes": ["NOT_OBJECT"]}

    status = payload.get("status")
    if status not in ALLOWED_STATUS:
        errors.append(_error("STATUS_INVALID", "$.status"))
    if payload.get("profile_pack_id") not in ALLOWED_PROFILE_PACK_IDS:
        errors.append(_error("PROFILE_PACK_ID_MISMATCH", "$.profile_pack_id"))

    errors.extend(_claim_errors("symptom", payload.get("symptom"), required_status="OBSERVED"))
    for field in ("immediate_cause", "systemic_root_cause", "first_bad_control", "escape_control"):
        errors.extend(_claim_errors(field, payload.get(field)))

    chain = payload.get("causal_chain")
    if not isinstance(chain, list) or len(chain) < 3:
        errors.append(_error("CAUSAL_CHAIN_INSUFFICIENT", "$.causal_chain"))
    else:
        for idx, item in enumerate(chain):
            errors.extend(_claim_errors(f"causal_chain[{idx}]", item))

    for field in ("origin_asset", "origin_operation", "owner"):
        errors.extend(_authority_ref_errors(field, payload.get(field)))

    if payload.get("repair_level") not in REPAIR_LEVELS:
        errors.append(_error("REPAIR_LEVEL_INVALID", "$.repair_level"))

    errors.extend(_live_packet_errors(payload))
    errors.extend(_reconciliation_errors(payload))
    errors.extend(_falsification_errors(payload, require_ready=status == "SYSTEMIC_REPAIR_SPEC"))
    errors.extend(_evidence_map_errors(payload))
    errors.extend(_structured_list_errors(payload))
    errors.extend(_decision_errors(payload))
    errors.extend(_proposal_errors(payload))
    errors.extend(_implementation_plan_errors(payload, require_ready=status == "SYSTEMIC_REPAIR_SPEC"))
    errors.extend(_v04_transversal_errors(payload))

    closure_errors, closure_summary = validate_v03_closure(payload, evidence_manifest)
    errors.extend(closure_errors)
    errors.extend(_solution_assurance_errors(payload, require_ready=status == "SYSTEMIC_REPAIR_SPEC"))
    incremental_errors, incremental_summary = validate_incremental_value(payload, require_ready=status == "SYSTEMIC_REPAIR_SPEC")
    errors.extend(incremental_errors)

    contradictions = payload.get("authority_contradictions")
    if not isinstance(contradictions, list):
        errors.append(_error("AUTHORITY_CONTRADICTIONS_INVALID", "$.authority_contradictions"))

    recurrence = payload.get("recurrence_evidence")
    if not isinstance(recurrence, list) or not recurrence:
        errors.append(_error("RECURRENCE_EVIDENCE_INVALID", "$.recurrence_evidence"))
    else:
        for idx, item in enumerate(recurrence):
            if not isinstance(item, dict) or item.get("evidence_class") not in RECURRENCE_EVIDENCE_CLASSES or not _nonempty_string(item.get("scope")):
                errors.append(_error("RECURRENCE_EVIDENCE_NOT_TYPED", f"$.recurrence_evidence[{idx}]"))

    existence = payload.get("should_exist_assessment")
    if not isinstance(existence, dict):
        errors.append(_error("SHOULD_EXIST_ASSESSMENT_MISSING", "$.should_exist_assessment"))
    elif existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
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
    if root.get("status") != "ESTABLISHED" and payload.get("repair_level") != "UNDETERMINED":
        errors.append(_error("REPAIR_LEVEL_PREMATURE", "$.repair_level"))

    if status != "SYSTEMIC_REPAIR_SPEC":
        if payload.get("selected_alternative") is not None:
            errors.append(_error("FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS", "$.selected_alternative"))
        if payload.get("residual_risks"):
            errors.append(_error("RESIDUAL_RISK_BEFORE_READY_SPEC", "$.residual_risks"))

    uncertainties = payload.get("current_uncertainties") if isinstance(payload.get("current_uncertainties"), list) else []
    design_uncertainties = [u for u in uncertainties if isinstance(u, dict) and u.get("impact") == "DESIGN_BLOCKING"]

    if status == "NEEDS_MORE_EVIDENCE":
        if not payload.get("blocking_codes"):
            errors.append(_error("NEEDS_MORE_EVIDENCE_WITHOUT_BLOCKER", "$.blocking_codes"))
        if not design_uncertainties:
            errors.append(_error("NEEDS_MORE_EVIDENCE_WITHOUT_DESIGN_BLOCKER", "$.current_uncertainties"))

    if status == "SYSTEMIC_REPAIR_SPEC":
        packet = payload.get("live_authority_packet") if isinstance(payload.get("live_authority_packet"), dict) else {}
        if packet.get("status") == "MISSING":
            errors.append(_error("SYSTEMIC_SPEC_WITH_MISSING_LIVE_AUTHORITY", "$.live_authority_packet.status"))
        assessments = packet.get("unavailable_source_assessments") if isinstance(packet.get("unavailable_source_assessments"), list) else []
        if any(isinstance(x, dict) and x.get("impact") == "DESIGN_BLOCKING" for x in assessments):
            errors.append(_error("SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_LIVE_AUTHORITY_GAP", "$.live_authority_packet.unavailable_source_assessments"))

        rows = payload.get("execution_effect_reconciliation") if isinstance(payload.get("execution_effect_reconciliation"), list) else []
        for idx, row in enumerate(rows):
            if not isinstance(row, dict):
                continue
            rstatus = row.get("reconciliation_status")
            impact = row.get("impact")
            if rstatus in {"UNDECLARED_EXECUTION", "SILENT_DROP", "SOURCE_LIVE_DIVERGENCE", "OTHER_CONTRADICTION"}:
                errors.append(_error("SYSTEMIC_SPEC_WITH_EXECUTION_CONTRADICTION", f"$.execution_effect_reconciliation[{idx}]"))
            if rstatus == "UNRESOLVED_PRODUCER" and impact == "DESIGN_BLOCKING":
                errors.append(_error("SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_UNRESOLVED_PRODUCER", f"$.execution_effect_reconciliation[{idx}]"))

        if payload.get("authority_contradictions"):
            errors.append(_error("UNRESOLVED_AUTHORITY_CONTRADICTION", "$.authority_contradictions"))
        if payload.get("blocking_codes"):
            errors.append(_error("SYSTEMIC_SPEC_WITH_BLOCKERS", "$.blocking_codes"))
        if design_uncertainties:
            errors.append(_error("SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_UNCERTAINTY", "$.current_uncertainties"))
        if (packet.get("status") == "PARTIAL" or any(isinstance(x, dict) and x.get("reconciliation_status") != "MATCH" for x in rows)) and not uncertainties:
            errors.append(_error("SYSTEMIC_SPEC_NONCOMPLETE_EVIDENCE_WITHOUT_CLASSIFIED_UNCERTAINTY", "$.current_uncertainties"))

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
        if not isinstance(payload.get("invariant"), dict) or payload["invariant"].get("validation_state") not in {"SPECIFIED", "VERIFIED"}:
            errors.append(_error("SYSTEMIC_SPEC_INVARIANT_NOT_SPECIFIED", "$.invariant.validation_state"))
        if not isinstance(payload.get("hard_guard"), dict) or payload["hard_guard"].get("validation_state") not in {"SPECIFIED", "VERIFIED"}:
            errors.append(_error("SYSTEMIC_SPEC_HARD_GUARD_NOT_SPECIFIED", "$.hard_guard.validation_state"))
        if len(payload.get("historical_regressions") or []) < 1:
            errors.append(_error("SYSTEMIC_SPEC_HISTORICAL_REGRESSION_REQUIRED", "$.historical_regressions"))
        if len(payload.get("planned_regressions") or []) < 3:
            errors.append(_error("SYSTEMIC_SPEC_PLANNED_REGRESSIONS_INSUFFICIENT", "$.planned_regressions"))
        if len(payload.get("acceptance_criteria") or []) < 3:
            errors.append(_error("SYSTEMIC_SPEC_ACCEPTANCE_CRITERIA_INSUFFICIENT", "$.acceptance_criteria"))
        for idx, item in enumerate(payload.get("falsification_results") or []):
            if isinstance(item, dict):
                errors.extend(_test_protocol_errors(f"$.falsification_results[{idx}].test_protocol", item.get("test_protocol")))
        for idx, item in enumerate(payload.get("planned_regressions") or []):
            if isinstance(item, dict):
                errors.extend(_test_protocol_errors(f"$.planned_regressions[{idx}].test_protocol", item.get("test_protocol")))

    next_gate = payload.get("next_gate")
    if not isinstance(next_gate, dict) or not all(_nonempty_string(next_gate.get(key)) for key in ("gate", "entry_condition", "exit_condition")):
        errors.append(_error("NEXT_GATE_NOT_STRUCTURED", "$.next_gate"))

    codes = sorted({item["code"] for item in errors})
    result = {
        "valid": not errors,
        "status": "PASS" if not errors else "FAIL",
        "errors": errors,
        "blocking_codes": codes,
        "validation_role": "PRE_QUALITY_STRUCTURAL_FLOOR",
        "canonical_quality_accepted": False,
    }
    if closure_summary.get("applies"):
        result["closure_summary"] = closure_summary
    result["incremental_value_summary"] = incremental_summary
    return result


if __name__ == "__main__":
    import json
    import sys
    try:
        value = json.load(sys.stdin)
    except Exception:
        value = None
    print(json.dumps(validate(value), ensure_ascii=False, indent=2))
