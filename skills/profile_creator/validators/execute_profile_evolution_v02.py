"""Operational dispatcher for the SINGLE dynamic Profile Updater v0.2.

Selection is advice; execution is performed only by an already authorized,
provider-bound method executor and independently verified method receipts.
No parallel method engine, runtime policy mutator, automatic profile writes,
synthetic receipts, or production activation. The OIDC caller/step recorder
remain the canonical operation transport.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Callable

UPDATE_MODES = frozenset({"PATCH", "SPECIALIZE", "ADAPT", "REARCHITECT", "OPTIMIZE"})
_SHA = set("0123456789abcdef")


def _digest(payload: Any) -> str:
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()


def _sha(value: Any, length: int) -> bool:
    return isinstance(value, str) and len(value) == length and set(value) <= _SHA


def _block(code: str, **details: Any) -> dict[str, Any]:
    return {"status": "BLOCKED", "code": code,
            "executed_method_ids": [], "step_recorded": False,
            "production_activated": False, **details}


def execute_profile_evolution_v02(
    plan: dict[str, Any],
    *,
    operation_binding: dict[str, Any],
    trusted_method_readback: Callable[[str, str, str], dict[str, Any] | None],
    invoke_governed_method: Callable[[str, dict[str, Any]], dict[str, Any]],
    verify_method_output: Callable[[dict[str, Any], str, str, str], bool],
    record_evolution_steps: Callable[[str, dict[str, Any], dict[str, Any]], dict[str, Any]],
) -> dict[str, Any]:
    """Execute selected/qualified methods, then record both canonical steps.

    Injected collaborators MUST be host-owned authenticated providers, never
    aliases for untrusted request payload or model output. The planner emits
    advisory candidates only. An untrusted candidate without verified current
    source or verified qualification cannot reach a method executor.
    """
    if not isinstance(plan, dict) or plan.get("schema") != "PROFILE_EVOLUTION_PLAN_V1":
        return _block("PLAN_SCHEMA_INVALID")
    if not isinstance(operation_binding, dict) or not all(callable(x) for x in (
        trusted_method_readback, invoke_governed_method,
        verify_method_output, record_evolution_steps,
    )):
        return _block("TRUSTED_EXECUTION_BINDING_MISSING")
    assessment = plan.get("profile_assessment")
    selection = plan.get("selection")
    readback = plan.get("source_readback")
    candidates = plan.get("step_candidates")
    if not all(isinstance(x, dict) for x in (assessment, selection, readback, candidates)):
        return _block("PLANNER_OUTPUT_INCOMPLETE")
    execution_id = operation_binding.get("execution_id")
    profile_slug = operation_binding.get("profile_slug")
    source_sha = operation_binding.get("source_head_sha")
    if not (isinstance(execution_id, str) and execution_id.strip()
            and isinstance(profile_slug, str) and profile_slug
            and _sha(source_sha, 40)
            and operation_binding.get("operation_code") == "ACTUALIZACION_PERFIL_LF"
            and operation_binding.get("operation_version") == "v0.2"
            and operation_binding.get("authenticated_oidc") is True
            and plan.get("profile_slug") == profile_slug):
        return _block("OPERATION_BINDING_UNVERIFIED")
    if (assessment.get("assessment_status") != "EVIDENCE_SUFFICIENT"
            or readback.get("status") != "VERIFIED_CURRENT"
            or not isinstance(readback.get("qualified_method_ids"), list)
            or plan.get("blocking_codes") != []
            or selection.get("fallback_state") in {"CONTRADICTORY", "CAPABILITY_FAILURE"}
            or selection.get("execution_authorized") is not False):
        return _block("ASSESSMENT_OR_AUTHORITY_UNRESOLVED")
    mode = plan.get("evolution_mode")
    if mode not in UPDATE_MODES | {"NO_CHANGE"}:
        return _block("EVOLUTION_MODE_UNRESOLVED")
    requirements = selection.get("method_requirements")
    if not isinstance(requirements, list):
        return _block("METHOD_COMPOSITION_INVALID")
    selected = [m for m in requirements
                if isinstance(m, dict) and m.get("eligible_for_composition") is True]
    selected_ids = [m.get("method_id") for m in selected]
    if (not all(isinstance(mid, str) and mid for mid in selected_ids)
            or len(set(selected_ids)) != len(selected_ids)
            or any(m.get("within_budget") is not True for m in selected)):
        return _block("METHOD_COMPOSITION_DUPLICATE_OR_BUDGET")
    method_candidate = candidates.get("method_selection")
    decision_candidate = candidates.get("evolution_decision")
    if not all(isinstance(x, dict) for x in (method_candidate, decision_candidate)):
        return _block("EVIDENCE_STEP_CANDIDATES_MISSING")
    if method_candidate.get("selected_method_ids") != selected_ids:
        return _block("METHOD_SELECTION_CANDIDATE_MISMATCH")
    assessment_receipt_id = readback.get("assessment_receipt_ref")
    assessment_sha = readback.get("assessment_sha256")
    selector_version = operation_binding.get("selector_version")
    if (not isinstance(assessment_receipt_id, str) or not assessment_receipt_id
            or not _sha(assessment_sha, 64)
            or not isinstance(selector_version, str) or not selector_version
            or operation_binding.get("method_registry_version") != readback.get("registry_version")):
        return _block("BOUND_ASSESSMENT_SELECTOR_RECEIPTS_MISSING")
    qualified = readback.get("qualified_method_ids")
    if len(set(qualified)) != len(qualified):
        return _block("QUALIFIED_METHOD_PORTFOLIO_INVALID")
    unqualified = [mid for mid in selected_ids if mid not in qualified]
    if unqualified:
        return _block("SELECTED_METHOD_NOT_QUALIFIED", method_ids=unqualified)
    if mode == "NO_CHANGE" and selected_ids:
        return _block("NO_CHANGE_CANNOT_EXECUTE_METHODS")
    if (method_candidate.get("method_execution_permitted") is not False
            or decision_candidate.get("github_write_permitted") is not False):
        return _block("PLANNER_FORGED_EXECUTION_PERMISSION")
    if plan.get("profile_source_write_allowed") is not False:
        return _block("PROFILE_MUTATION_NOT_AUTHORIZED")

    # Qualify EVERY selected method with a trusted resolver before invoking ANY.
    # A single unqualified/expired method aborts the whole dispatch.
    verified_methods = []
    for mid in selected_ids:
        method_info = trusted_method_readback(mid, execution_id, source_sha)
        if (not isinstance(method_info, dict)
                or method_info.get("method_id") != mid
                or method_info.get("qualification_state") != "QUALIFIED"
                or method_info.get("verification_state") != "VERIFIED"
                or method_info.get("current_source_sha") != source_sha
                or not isinstance(method_info.get("exact_version"), str)
                or not isinstance(method_info.get("qualification_receipt_id"), str)
                or not method_info["qualification_receipt_id"]
                or not _sha(method_info.get("method_subject_sha256"), 64)):
            return _block("METHOD_QUALIFICATION_RECEIPT_INVALID", method_id=mid)
        verified_methods.append(method_info)

    # Caller never supplies permission. The trusted operation host does not
    # call this function unless its OIDC dispatch and frozen v0.2 route pass.
    # Every result is checked independently; no success from a provider string.
    completed: list[dict[str, Any]] = []
    for method in verified_methods:
        mid = method["method_id"]
        try:
            result = invoke_governed_method(mid, {
                "execution_id": execution_id,
                "profile_slug": profile_slug,
                "source_head_sha": source_sha,
                "method_version": method["exact_version"],
                "qualification_receipt_id": method["qualification_receipt_id"],
                "evidence_context_digest": _digest(assessment),
                "prior_method_receipts": [x["receipt_id"] for x in completed],
            })
        except Exception:
            return _block("GOVERNED_METHOD_PROVIDER_FAILED", method_id=mid,
                          completed_uncommitted=[x["method_id"] for x in completed])
        if (not isinstance(result, dict)
                or result.get("method_id") != mid
                or result.get("execution_id") != execution_id
                or result.get("source_head_sha") != source_sha
                or result.get("status") != "COMPLETED"
                or not isinstance(result.get("receipt_id"), str)
                or not result["receipt_id"]
                or not _sha(result.get("output_sha256"), 64)
                or not verify_method_output(result, mid, execution_id, source_sha)):
            return _block("METHOD_OUTPUT_NOT_PROVIDER_VERIFIED", method_id=mid,
                          completed_uncommitted=[x["method_id"] for x in completed])
        completed.append({"method_id": mid, "receipt_id": result["receipt_id"],
                          "output_sha256": result["output_sha256"]})
    decision = "NO_CHANGE" if mode == "NO_CHANGE" else "UPDATE"
    # No write is initiated here. The canonical OIDC caller and step recorder
    # decide the next route from immutable PASS_POLICY after recording.
    selected_methods = [
        {"method_id": method["method_id"], "exact_version": method["exact_version"],
         "receipt_id": method["qualification_receipt_id"],
         "subject_sha256": method["method_subject_sha256"],
         "source_head_sha": source_sha}
        for method in verified_methods
    ]
    method_step = {"profile_slug": profile_slug, "source_head_sha": source_sha,
                   "profile_assessment_receipt_id": assessment_receipt_id,
                   "profile_assessment_sha256": assessment_sha,
                   "selector_version": selector_version,
                   "selected_methods": selected_methods,
                   "no_additional_method_needed": not bool(selected_methods),
                   "empty_selection_reason": "NO_ADDITIONAL_METHOD_NEEDED_WITH_EVIDENCE"
                   if not selected_methods else None,
                   "method_execution_permitted": False,
                   "execution_receipts": completed,
                   "selection_digest": _digest(selection)}
    decision_step = {"profile_slug": profile_slug, "source_head_sha": source_sha,
                     "profile_assessment_receipt_id": assessment_receipt_id,
                     "profile_assessment_sha256": assessment_sha,
                     "decision": decision, "evolution_mode": mode,
                     "decision_evidence_ref": assessment_receipt_id,
                     "github_write_permitted": False,
                     "execution_receipts": completed}
    try:
        step_result = record_evolution_steps(execution_id, method_step, decision_step)
    except Exception:
        return _block("CANONICAL_STEP_RECORDER_FAILED")
    if (not isinstance(step_result, dict)
            or step_result.get("method_selection") != "STEP_PASS_WITH_EVIDENCE"
            or step_result.get("evolution_decision") != "STEP_PASS_WITH_EVIDENCE"
            or step_result.get("execution_id") != execution_id):
        return _block("CANONICAL_STEP_RECEIPTS_UNVERIFIED")
    return {"status": "STEPS_RECORDED", "decision": decision, "evolution_mode": mode,
            "executed_method_ids": selected_ids, "method_receipts": completed,
            "step_recorded": True, "production_activated": False,
            "next_action": "CANONICAL_PROFILE_UPDATER_FROZEN_ROUTE"}
