#!/usr/bin/env python3
"""SRCR pre-quality semantic utility floor.

Control ownership is intentionally exclusive:
- runtime_validate.py owns structural/schema/closure invariants;
- this module runs only after that contract gate passed and adds utility checks
  that are not already deterministic-validator controls;
- the independent semantic judge remains the final semantic authority.

Do not duplicate a runtime_validate blocking code here.
"""

try:
    from .closure_proof import (
        CLOSURE_PACK_IDS,
        FALSIFICATION_EVIDENCE_CLASSES,
        OMISSION_DIMENSIONS,
        unwrap_runtime_input,
    )
except (ImportError, ModuleNotFoundError):
    import importlib.util as _importlib_util
    from pathlib import Path as _Path

    _closure_path = _Path(__file__).with_name("closure_proof.py")
    _closure_spec = _importlib_util.spec_from_file_location(
        "srcr_closure_proof_semantic", _closure_path
    )
    _closure_mod = _importlib_util.module_from_spec(_closure_spec)
    assert _closure_spec and _closure_spec.loader
    _closure_spec.loader.exec_module(_closure_mod)
    OMISSION_DIMENSIONS = _closure_mod.OMISSION_DIMENSIONS
    FALSIFICATION_EVIDENCE_CLASSES = _closure_mod.FALSIFICATION_EVIDENCE_CLASSES
    CLOSURE_PACK_IDS = _closure_mod.CLOSURE_PACK_IDS
    unwrap_runtime_input = _closure_mod.unwrap_runtime_input


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


def evaluate(payload, contract_gate, evidence_manifest=None):
    if evidence_manifest is None:
        candidate, embedded_manifest = unwrap_runtime_input(payload)
        if embedded_manifest is not None:
            payload, evidence_manifest = candidate, embedded_manifest

    codes: list[str] = []
    if not isinstance(payload, dict):
        codes.append("PAYLOAD_NOT_OBJECT")
    if not isinstance(contract_gate, dict) or contract_gate.get("status") != "PASS":
        codes.append("PROFILE_CONTRACT_INVALID")
    if codes:
        return {"status": "FAIL", "blocking_codes": sorted(set(codes))}

    status = payload.get("status")
    is_closure_pack = payload.get("profile_pack_id") in CLOSURE_PACK_IDS
    closure_summary = contract_gate.get("closure_summary")

    if is_closure_pack:
        if contract_gate.get("validation_role") != "PRE_QUALITY_STRUCTURAL_FLOOR":
            codes.append("V03_STRUCTURAL_FLOOR_ROLE_MISSING")
        if not isinstance(closure_summary, dict) or closure_summary.get("applies") is not True:
            codes.append("V03_CLOSURE_SUMMARY_MISSING")
        if contract_gate.get("canonical_quality_accepted") is not False:
            codes.append("UTILITY_FLOOR_CANNOT_INHERIT_QUALITY_ACCEPTANCE")

        proof = (
            payload.get("closure_proof")
            if isinstance(payload.get("closure_proof"), dict)
            else {}
        )
        derived = (
            proof.get("derived_decision_closure")
            if isinstance(proof.get("derived_decision_closure"), dict)
            else {}
        )
        if status == "SYSTEMIC_REPAIR_SPEC":
            if derived.get("quality_state") != "QUALITY_PENDING":
                codes.append("V03_QUALITY_STATE_MUST_BE_PENDING")
            if (
                not isinstance(closure_summary, dict)
                or closure_summary.get("computed_handoff_ready") is not True
            ):
                codes.append("V03_UTILITY_WITHOUT_DERIVED_READINESS")

        for field in ("origin_asset", "origin_operation", "owner"):
            value = payload.get(field)
            if (
                not isinstance(value, dict)
                or value.get("authority_kind") != "EXISTING_AUTHORITY"
            ):
                codes.append("V03_EXISTING_AUTHORITY_KIND_REQUIRED")
                break

        if "quality_receipt" in payload:
            codes.append("V03_CANDIDATE_MUST_NOT_SELF_ISSUE_QUALITY_RECEIPT")

    evidence_map = payload.get("evidence_map")
    if not isinstance(evidence_map, list) or any(
        not isinstance(item, dict) for item in evidence_map
    ):
        codes.append("CLAIM_EVIDENCE_MAP_INVALID")
    else:
        mapped = {item.get("claim_path") for item in evidence_map}
        if not CRITICAL_EVIDENCE_PATHS.issubset(mapped):
            codes.append("CLAIM_EVIDENCE_MAP_INCOMPLETE")

    falsifications = payload.get("falsification_results")
    if isinstance(falsifications, list):
        for item in falsifications:
            if not isinstance(item, dict):
                continue
            if (
                item.get("result") == "PLANNED"
                and item.get("evidence_class") != "DESIGN_ONLY"
            ):
                codes.append("FALSIFICATION_PLANNED_NOT_DESIGN_ONLY")

    uncertainties = (
        payload.get("current_uncertainties")
        if isinstance(payload.get("current_uncertainties"), list)
        else []
    )
    for item in uncertainties:
        if not isinstance(item, dict):
            continue
        if (
            item.get("impact")
            in {"IMPLEMENTATION_PRECONDITION", "NON_BLOCKING_HISTORICAL"}
            and not item.get("containment_ref")
        ):
            codes.append("NONBLOCKING_UNCERTAINTY_WITHOUT_CONTAINMENT")

    reconciliations = (
        payload.get("execution_effect_reconciliation")
        if isinstance(payload.get("execution_effect_reconciliation"), list)
        else []
    )
    for item in reconciliations:
        if not isinstance(item, dict):
            continue
        if (
            item.get("reconciliation_status") == "UNRESOLVED_PRODUCER"
            and item.get("impact")
            in {"IMPLEMENTATION_PRECONDITION", "NON_BLOCKING_HISTORICAL"}
            and not item.get("containment_ref")
        ):
            codes.append("CONTAINED_UNRESOLVED_PRODUCER_WITHOUT_CONTAINMENT")

    if (
        _claim_status(payload, "systemic_root_cause") != "ESTABLISHED"
        and payload.get("repair_level") != "UNDETERMINED"
    ):
        codes.append("PREMATURE_REPAIR_LEVEL")

    if status == "SYSTEMIC_REPAIR_SPEC":
        depth = (
            payload.get("solution_depth")
            if isinstance(payload.get("solution_depth"), dict)
            else {}
        )
        challenges = (
            payload.get("challenger_review")
            if isinstance(payload.get("challenger_review"), list)
            else []
        )
        if depth.get("mode") == "DEEP_ARCHITECTURE_RESEARCH" and len(challenges) < 3:
            codes.append("DEEP_CHALLENGER_REVIEW_INSUFFICIENT")

        omissions = (
            payload.get("omission_discovery")
            if isinstance(payload.get("omission_discovery"), list)
            else []
        )
        observed_omissions = {
            item.get("dimension") for item in omissions if isinstance(item, dict)
        }
        if set(OMISSION_DIMENSIONS) - observed_omissions:
            codes.append("SYSTEMIC_SPEC_OMISSION_DISCOVERY_INCOMPLETE")

    historical = payload.get("historical_regressions")
    if historical is None:
        if status != "NO_REPAIR_REQUIRED":
            codes.append("HISTORICAL_REGRESSIONS_INVALID")
    elif not isinstance(historical, list):
        codes.append("HISTORICAL_REGRESSIONS_INVALID")
    else:
        for item in historical:
            if (
                not isinstance(item, dict)
                or not item.get("occurrence_ref")
                or not item.get("evidence_refs")
            ):
                codes.append("HISTORICAL_REGRESSION_NOT_OBSERVED")
                break

    result = {
        "status": "PASS" if not codes else "FAIL",
        "blocking_codes": sorted(set(codes)),
        "semantic_role": "PRE_QUALITY_SEMANTIC_UTILITY_FLOOR",
        "control_ownership": "SEMANTIC_UTILITY_ONLY_NO_STRUCTURAL_DUPLICATION",
        "canonical_quality_accepted": False,
        "canonical_quality_receipt_required": status == "SYSTEMIC_REPAIR_SPEC",
    }
    if is_closure_pack and isinstance(closure_summary, dict):
        result["closure_summary"] = closure_summary
    incremental_summary = contract_gate.get("incremental_value_summary")
    if isinstance(incremental_summary, dict):
        result["incremental_value_summary"] = incremental_summary
    return result
