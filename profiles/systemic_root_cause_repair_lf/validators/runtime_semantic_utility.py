#!/usr/bin/env python3
"""Deterministic semantic-utility floor for SRCR specification readiness."""

try:
    from .closure_proof import CLOSURE_PACK_IDS, FALSIFICATION_EVIDENCE_CLASSES, OMISSION_DIMENSIONS, V03_PACK_ID, unwrap_runtime_input
except (ImportError, ModuleNotFoundError):
    import importlib.util as _importlib_util
    from pathlib import Path as _Path
    _closure_path = _Path(__file__).with_name("closure_proof.py")
    _closure_spec = _importlib_util.spec_from_file_location("srcr_closure_proof_semantic", _closure_path)
    _closure_mod = _importlib_util.module_from_spec(_closure_spec)
    assert _closure_spec and _closure_spec.loader
    _closure_spec.loader.exec_module(_closure_mod)
    OMISSION_DIMENSIONS = _closure_mod.OMISSION_DIMENSIONS
    FALSIFICATION_EVIDENCE_CLASSES = _closure_mod.FALSIFICATION_EVIDENCE_CLASSES
    V03_PACK_ID = _closure_mod.V03_PACK_ID
    CLOSURE_PACK_IDS = _closure_mod.CLOSURE_PACK_IDS
    unwrap_runtime_input = _closure_mod.unwrap_runtime_input

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
CONTRADICTIONS = {"UNDECLARED_EXECUTION", "SILENT_DROP", "SOURCE_LIVE_DIVERGENCE", "OTHER_CONTRADICTION"}


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


def evaluate(payload, contract_gate, evidence_manifest=None):
    if evidence_manifest is None:
        candidate, embedded_manifest = unwrap_runtime_input(payload)
        if embedded_manifest is not None:
            payload, evidence_manifest = candidate, embedded_manifest
    codes = []
    if not isinstance(payload, dict):
        codes.append("PAYLOAD_NOT_OBJECT")
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        codes.append("PROFILE_CONTRACT_INVALID")
    if codes:
        return {"status": "FAIL", "blocking_codes": sorted(set(codes))}

    status = payload.get("status")
    is_closure_pack = payload.get("profile_pack_id") in CLOSURE_PACK_IDS
    closure_summary = contract_gate.get("closure_summary") if isinstance(contract_gate, dict) else None
    if is_closure_pack:
        if contract_gate.get("validation_role") != "PRE_QUALITY_STRUCTURAL_FLOOR":
            codes.append("V03_STRUCTURAL_FLOOR_ROLE_MISSING")
        if not isinstance(closure_summary, dict) or closure_summary.get("applies") is not True:
            codes.append("V03_CLOSURE_SUMMARY_MISSING")
        if contract_gate.get("canonical_quality_accepted") is not False:
            codes.append("UTILITY_FLOOR_CANNOT_INHERIT_QUALITY_ACCEPTANCE")
        proof = payload.get("closure_proof") if isinstance(payload.get("closure_proof"), dict) else {}
        derived = proof.get("derived_decision_closure") if isinstance(proof.get("derived_decision_closure"), dict) else {}
        if status == "SYSTEMIC_REPAIR_SPEC":
            if derived.get("quality_state") != "QUALITY_PENDING":
                codes.append("V03_QUALITY_STATE_MUST_BE_PENDING")
            if not isinstance(closure_summary, dict) or closure_summary.get("computed_handoff_ready") is not True:
                codes.append("V03_UTILITY_WITHOUT_DERIVED_READINESS")
        for field in ("origin_asset", "origin_operation", "owner"):
            value = payload.get(field)
            if not isinstance(value, dict) or value.get("authority_kind") != "EXISTING_AUTHORITY":
                codes.append("V03_EXISTING_AUTHORITY_KIND_REQUIRED")
                break
        if "quality_receipt" in payload:
            codes.append("V03_CANDIDATE_MUST_NOT_SELF_ISSUE_QUALITY_RECEIPT")
    packet = payload.get("live_authority_packet") if isinstance(payload.get("live_authority_packet"), dict) else {}
    reconciliations = payload.get("execution_effect_reconciliation")
    if not isinstance(reconciliations, list):
        reconciliations = []
        codes.append("EXECUTION_EFFECT_RECONCILIATION_MISSING")

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

    falsifications = payload.get("falsification_results")
    if isinstance(falsifications, list):
        for item in falsifications:
            if not isinstance(item, dict):
                continue
            if item.get("result") == "PASS" and item.get("evidence_class") not in OBSERVED_FALSIFICATION_EVIDENCE:
                codes.append("FALSIFICATION_PASS_NOT_OBSERVED")
            if item.get("result") == "PLANNED" and item.get("evidence_class") != "DESIGN_ONLY":
                codes.append("FALSIFICATION_PLANNED_NOT_DESIGN_ONLY")

    uncertainties = payload.get("current_uncertainties") if isinstance(payload.get("current_uncertainties"), list) else []
    design_uncertainties = [
        item for item in uncertainties
        if isinstance(item, dict) and item.get("impact") == "DESIGN_BLOCKING"
    ]
    for item in uncertainties:
        if not isinstance(item, dict):
            continue
        if item.get("impact") in {"IMPLEMENTATION_PRECONDITION", "NON_BLOCKING_HISTORICAL"} and not item.get("containment_ref"):
            codes.append("NONBLOCKING_UNCERTAINTY_WITHOUT_CONTAINMENT")

    assessments = packet.get("unavailable_source_assessments") if isinstance(packet.get("unavailable_source_assessments"), list) else []
    unavailable = packet.get("unavailable_sources") if isinstance(packet.get("unavailable_sources"), list) else []
    assessed_sources = [item.get("source") for item in assessments if isinstance(item, dict)]
    if set(unavailable) != set(assessed_sources):
        codes.append("LIVE_AUTHORITY_UNAVAILABLE_ASSESSMENT_MISMATCH")
    design_authority_gaps = [
        item for item in assessments
        if isinstance(item, dict) and item.get("impact") == "DESIGN_BLOCKING"
    ]

    unresolved_design_effects = []
    contained_unresolved_effects = []
    contradictions = []
    for item in reconciliations:
        if not isinstance(item, dict):
            continue
        rstatus = item.get("reconciliation_status")
        impact = item.get("impact")
        if rstatus in CONTRADICTIONS:
            contradictions.append(item)
        elif rstatus == "UNRESOLVED_PRODUCER":
            if impact == "DESIGN_BLOCKING":
                unresolved_design_effects.append(item)
            elif impact in {"IMPLEMENTATION_PRECONDITION", "NON_BLOCKING_HISTORICAL"}:
                contained_unresolved_effects.append(item)
                if not item.get("containment_ref"):
                    codes.append("CONTAINED_UNRESOLVED_PRODUCER_WITHOUT_CONTAINMENT")

    root_status = _claim_status(payload, "systemic_root_cause")
    if root_status != "ESTABLISHED" and payload.get("repair_level") != "UNDETERMINED":
        codes.append("PREMATURE_REPAIR_LEVEL")

    if status != "SYSTEMIC_REPAIR_SPEC":
        if selected is not None:
            codes.append("FINAL_SELECTION_NOT_ALLOWED_FOR_NONREADY_STATUS")
        if payload.get("residual_risks"):
            codes.append("RESIDUAL_RISK_BEFORE_READY_SPEC")

    if status == "NEEDS_MORE_EVIDENCE":
        if not design_uncertainties:
            codes.append("NEEDS_MORE_EVIDENCE_WITHOUT_DESIGN_BLOCKER")
        if not payload.get("blocking_codes"):
            codes.append("NEEDS_MORE_EVIDENCE_WITHOUT_BLOCKER")

    if status == "SYSTEMIC_REPAIR_SPEC":
        if packet.get("status") == "MISSING":
            codes.append("SYSTEMIC_SPEC_WITH_MISSING_LIVE_AUTHORITY")
        if design_authority_gaps:
            codes.append("SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_LIVE_AUTHORITY_GAP")
        if unresolved_design_effects:
            codes.append("SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_UNRESOLVED_PRODUCER")
        if contradictions:
            codes.append("SYSTEMIC_SPEC_WITH_EXECUTION_CONTRADICTION")
        if payload.get("authority_contradictions"):
            codes.append("UNRESOLVED_AUTHORITY_CONTRADICTION")
        if design_uncertainties:
            codes.append("SYSTEMIC_SPEC_WITH_DESIGN_BLOCKING_UNCERTAINTY")
        if payload.get("blocking_codes"):
            codes.append("SYSTEMIC_SPEC_WITH_BLOCKERS")
        if (packet.get("status") == "PARTIAL" or contained_unresolved_effects) and not uncertainties:
            codes.append("SYSTEMIC_SPEC_NONCOMPLETE_EVIDENCE_WITHOUT_CLASSIFIED_UNCERTAINTY")

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
        if len(rejected_ids) < 2:
            codes.append("REJECTED_ALTERNATIVES_INSUFFICIENT")
        if selected in rejected_ids:
            codes.append("SELECTED_ALTERNATIVE_ALSO_REJECTED")

        existence = payload.get("should_exist_assessment")
        if not isinstance(existence, dict) or existence.get("verdict") == "INSUFFICIENT_EVIDENCE":
            codes.append("SHOULD_EXIST_ASSESSMENT_UNRESOLVED")

        for field in ("origin_asset", "origin_operation", "owner"):
            if _authority_status(payload, field) != "RESOLVED":
                codes.append("SYSTEMIC_SPEC_AUTHORITY_REF_UNRESOLVED")

        invariant = payload.get("invariant")
        if not isinstance(invariant, dict) or invariant.get("validation_state") not in {"SPECIFIED", "VERIFIED"}:
            codes.append("SYSTEMIC_SPEC_INVARIANT_NOT_SPECIFIED")
        guard = payload.get("hard_guard")
        if not isinstance(guard, dict) or guard.get("validation_state") not in {"SPECIFIED", "VERIFIED"}:
            codes.append("SYSTEMIC_SPEC_HARD_GUARD_NOT_SPECIFIED")

        depth = payload.get("solution_depth") if isinstance(payload.get("solution_depth"), dict) else {}
        research = payload.get("research_assurance") if isinstance(payload.get("research_assurance"), dict) else {}
        challenges = payload.get("challenger_review") if isinstance(payload.get("challenger_review"), list) else []
        omissions = payload.get("omission_discovery") if isinstance(payload.get("omission_discovery"), list) else []
        package = payload.get("implementation_package") if isinstance(payload.get("implementation_package"), dict) else {}
        closure = package.get("decision_closure") if isinstance(package.get("decision_closure"), dict) else {}
        if research.get("research_complete") is not True:
            codes.append("SYSTEMIC_SPEC_RESEARCH_NOT_COMPLETE")
        if research.get("current_practice_research_required") is True and not research.get("external_evidence_refs"):
            codes.append("CURRENT_PRACTICE_EVIDENCE_REQUIRED")
        if not research.get("first_solution_disposition"):
            codes.append("FIRST_SOLUTION_NOT_CHALLENGED")
        if depth.get("mode") == "DEEP_ARCHITECTURE_RESEARCH" and len(challenges) < 3:
            codes.append("DEEP_CHALLENGER_REVIEW_INSUFFICIENT")
        if any(isinstance(x, dict) and x.get("outcome") == "BLOCKED" for x in challenges):
            codes.append("SYSTEMIC_SPEC_WITH_UNRESOLVED_CHALLENGE")
        required_omissions = set(OMISSION_DIMENSIONS)
        observed_omissions = {x.get("dimension") for x in omissions if isinstance(x, dict)}
        if required_omissions - observed_omissions:
            codes.append("SYSTEMIC_SPEC_OMISSION_DISCOVERY_INCOMPLETE")
        if not package:
            codes.append("SYSTEMIC_SPEC_IMPLEMENTATION_PACKAGE_REQUIRED")
        if closure.get("open_design_decisions") != []:
            codes.append("SYSTEMIC_SPEC_OPEN_DESIGN_DECISIONS")
        if closure.get("handoff_ready") is not True:
            codes.append("SYSTEMIC_SPEC_HANDOFF_NOT_READY")
        for p in closure.get("implementation_preconditions") or []:
            if not isinstance(p, dict) or p.get("design_effect") != "NONE" or not all(p.get(k) for k in ("resolver_ref","expected_shape","decision_rule","stage")):
                codes.append("IMPLEMENTATION_PRECONDITION_NOT_MECHANICAL")
                break
        context_transport = package.get("context_transport") if isinstance(package.get("context_transport"), dict) else {}
        if context_transport.get("status") == "APPLIES" and not all(context_transport.get(k) for k in ("compiler_ref","delivery_strategy","token_budget","degradation_rule")):
            codes.append("CONTEXT_TRANSPORT_NOT_CLOSED")

        if not payload.get("implementation_delta"):
            codes.append("SYSTEMIC_SPEC_IMPLEMENTATION_DELTA_REQUIRED")
        if not isinstance(payload.get("transition_plan"), dict):
            codes.append("SYSTEMIC_SPEC_TRANSITION_PLAN_REQUIRED")
        if not isinstance(payload.get("rollback_plan"), dict):
            codes.append("SYSTEMIC_SPEC_ROLLBACK_PLAN_REQUIRED")

        if isinstance(falsifications, list):
            if any(isinstance(item, dict) and item.get("result") not in {"PASS", "PLANNED"} for item in falsifications):
                codes.append("SYSTEMIC_SPEC_FALSIFICATION_NOT_SPECIFIED")
            for item in falsifications:
                if not isinstance(item, dict):
                    continue
                protocol = item.get("test_protocol")
                if not isinstance(protocol, dict) or not all(isinstance(protocol.get(k), list) and len(protocol.get(k)) > 0 for k in ("setup", "action", "assertions")) or not protocol.get("failure_signal"):
                    codes.append("EXECUTABLE_TEST_PROTOCOL_INCOMPLETE")
                    break
        for item in payload.get("planned_regressions") or []:
            if not isinstance(item, dict):
                continue
            protocol = item.get("test_protocol")
            if not isinstance(protocol, dict) or not all(isinstance(protocol.get(k), list) and len(protocol.get(k)) > 0 for k in ("setup", "action", "assertions")) or not protocol.get("failure_signal"):
                codes.append("EXECUTABLE_TEST_PROTOCOL_INCOMPLETE")
                break

    historical = payload.get("historical_regressions")
    if not isinstance(historical, list):
        codes.append("HISTORICAL_REGRESSIONS_INVALID")
    else:
        for item in historical:
            if not isinstance(item, dict) or not item.get("occurrence_ref") or not item.get("evidence_refs"):
                codes.append("HISTORICAL_REGRESSION_NOT_OBSERVED")
                break

    result = {
        "status": "PASS" if not codes else "FAIL",
        "blocking_codes": sorted(set(codes)),
        "semantic_role": "PRE_QUALITY_SEMANTIC_UTILITY_FLOOR",
        "canonical_quality_accepted": False,
        "canonical_quality_receipt_required": status == "SYSTEMIC_REPAIR_SPEC",
    }
    if is_closure_pack and isinstance(closure_summary, dict):
        result["closure_summary"] = closure_summary
    incremental_summary = contract_gate.get("incremental_value_summary") if isinstance(contract_gate, dict) else None
    if isinstance(incremental_summary, dict):
        result["incremental_value_summary"] = incremental_summary
    return result
