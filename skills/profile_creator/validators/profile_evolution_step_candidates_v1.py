"""Typed *candidate* receipts for the two proposed Updater steps.

Consumed only by the existing plan_profile_evolution.py. This module is NOT a
selector, method executor, judge, policy authority, or Profile Runtime binding.
The authorized step recorder must independently validate sources and binding.
"""
from __future__ import annotations

from typing import Any


def derive_step_candidates(plan: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Prepare fail-closed method_selection and evolution_decision evidence.

    A plan is advice, even when it embeds a verified readback. A caller-supplied
    copy of these receipts cannot prove method qualification or execution.
    """
    if not isinstance(plan, dict) or plan.get("schema") != "PROFILE_EVOLUTION_PLAN_V1":
        raise ValueError("PROFILE_EVOLUTION_PLAN_SCHEMA_INVALID")
    assessment = plan.get("profile_assessment")
    selection = plan.get("selection")
    source = plan.get("source_readback")
    if not all(isinstance(x, dict) for x in (assessment, selection, source)):
        raise ValueError("PROFILE_EVOLUTION_STEP_INPUT_INVALID")
    mode = plan.get("evolution_mode")
    valid_modes = {"NO_CHANGE", "PATCH", "SPECIALIZE", "ADAPT", "REARCHITECT", "OPTIMIZE"}
    if mode is not None and mode not in valid_modes:
        raise ValueError("PROFILE_EVOLUTION_MODE_INVALID")
    requirements = selection.get("method_requirements")
    capabilities = selection.get("selected_capabilities")
    if not isinstance(requirements, list) or not isinstance(capabilities, list):
        raise ValueError("PROFILE_EVOLUTION_SELECTION_INVALID")
    chosen: list[str] = []
    for item in requirements:
        if not isinstance(item, dict) or not isinstance(item.get("method_id"), str):
            raise ValueError("PROFILE_EVOLUTION_METHOD_RECORD_INVALID")
        if item.get("eligible_for_composition") is True:
            if not item.get("within_budget"):
                raise ValueError("PROFILE_EVOLUTION_METHOD_BUDGET_CONFLICT")
            chosen.append(item["method_id"])
    if len(set(chosen)) != len(chosen):
        raise ValueError("PROFILE_EVOLUTION_METHOD_DUPLICATE")
    blockers = plan.get("blocking_codes")
    if not isinstance(blockers, list) or not all(isinstance(x, str) for x in blockers):
        raise ValueError("PROFILE_EVOLUTION_BLOCKERS_INVALID")
    authority_verified = source.get("status") == "VERIFIED_CURRENT"
    sufficient = assessment.get("assessment_status") == "EVIDENCE_SUFFICIENT"
    unresolved = selection.get("fallback_state") in {"CONTRADICTORY", "CAPABILITY_FAILURE"}
    if unresolved:
        disposition = "SELECTOR_UNRESOLVED"
    elif not authority_verified:
        disposition = "AUTHORITY_READBACK_REQUIRED"
    elif not sufficient:
        disposition = "ASSESSMENT_EVIDENCE_REQUIRED"
    elif not chosen:
        disposition = "NO_ADDITIONAL_METHOD_SELECTED"
    else:
        disposition = "METHODS_CANDIDATE_ONLY"
    method_step = {
        "schema": "PROFILE_METHOD_SELECTION_CANDIDATE_V1",
        "status": disposition,
        "selected_method_ids": chosen,
        "selected_capabilities": capabilities,
        "fallback_state": selection.get("fallback_state"),
        "selection_source": "CAPABILITY_SELECTOR_COMPOSITION_V2",
        "source_readback_status": source.get("status", "UNRESOLVED"),
        "method_execution_permitted": False,
        "judge_pass_declared": False,
    }
    if blockers or not sufficient or not authority_verified or unresolved or mode is None:
        decision = "NEEDS_MORE_EVIDENCE"
    elif mode == "NO_CHANGE":
        decision = "NO_CHANGE_CANDIDATE"
    elif plan.get("candidate_materialization_allowed") is True:
        decision = "UPDATE_CANDIDATE"
    else:
        decision = "NEEDS_MORE_EVIDENCE"
    decision_step = {
        "schema": "PROFILE_EVOLUTION_DECISION_CANDIDATE_V1",
        "decision": decision,
        "evolution_mode": mode,
        "blocking_codes": list(blockers),
        "evidence_sufficient": sufficient,
        "trusted_source_resolved": authority_verified,
        "selection_state": disposition,
        "github_write_permitted": False,
        "operational_decision_recorded": False,
        "requires_independent_step_judge": True,
    }
    return {"method_selection": method_step, "evolution_decision": decision_step}
