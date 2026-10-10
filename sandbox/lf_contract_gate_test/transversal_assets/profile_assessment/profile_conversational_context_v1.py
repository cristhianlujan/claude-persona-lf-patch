"""Read-only conversational context routing using LF's existing evidence planner.

Semantic identification of requirements/questions is done by the profile.
Actual retrieval is done by the authorized LF resolver. This code never
claims it has fetched a source, performed a model call or verified a user.
"""
from __future__ import annotations

from typing import Any

SCHEMA = "PROFILE_CONVERSATIONAL_CONTEXT_V1"
ACQUISITION_SCHEMA = "LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1"
LEVELS = {"USER_CONTEXT", "TRUSTED_READBACK"}
DEPTHS = {"ORIENT", "DIAGNOSE", "DESIGN", "VERIFY"}


def _out(action: str, missing: list[str], code: str, **other: Any) -> dict:
    return {"schema": SCHEMA, "action": action, "code": code,
            "context_sufficient": not missing, "missing_reasons": missing,
            "write_authorized": False, "production_activation": False, **other}


def _block(code: str) -> dict:
    return _out("BLOCKED", [], code, context_sufficient=False)


def route_context_turn(task: dict, acquisition_result: dict | None = None) -> dict:
    """Decide whether to proceed, query sources, ask a question or disclose limits.

    The external provider result MUST originate from
    public.lf_targeted_evidence_acquisition_plan_v1 via governed dispatch;
    this function validates its shape but does not independently authenticate
    its sender. The caller must enforce authorization and receipt provenance.
    """
    if not isinstance(task, dict) or task.get("schema") != SCHEMA:
        return _block("INPUT_SCHEMA_INVALID")
    if not str(task.get("request_text") or "").strip():
        return _block("NATURAL_REQUEST_REQUIRED")
    if task.get("requested_depth") not in DEPTHS:
        return _block("DEPTH_INVALID")
    requirements = task.get("requirements")
    facts = task.get("facts", [])
    acquisitions = task.get("acquisitions", [])
    questions = task.get("questions", [])
    asked = task.get("asked_question_ids", [])
    budget = task.get("question_budget", 2)
    if (not isinstance(requirements, list) or not isinstance(facts, list) or
        not isinstance(acquisitions, list) or not isinstance(questions, list) or
        not isinstance(asked, list) or type(budget) is not int or
        budget < 0 or budget > 8 or len(asked) != len(set(asked))):
        return _block("INPUT_COLLECTION_INVALID")
    if (not all(isinstance(r, dict) and isinstance(r.get("reason"), str)
                and r["reason"] and r.get("min_source_level") in LEVELS
                for r in requirements) or
        len({r["reason"] for r in requirements}) != len(requirements)):
        return _block("REQUIREMENTS_INVALID")
    if not all(isinstance(x, dict) for x in facts + acquisitions + questions):
        return _block("ITEM_SHAPE_INVALID")
    levels = {r["reason"]: r["min_source_level"] for r in requirements}
    known = {r: [] for r in levels}
    for f in facts:
        reason = f.get("reason")
        if (reason not in levels or "value" not in f or
            not isinstance(f.get("source_ref"), str) or not f["source_ref"] or
            f.get("source_type") not in LEVELS or
            f.get("evidence_status") not in ("DECLARED", "VERIFIED", "UNVERIFIED")):
            return _block("FACT_PROVENANCE_INVALID")
        if (levels[reason] == "USER_CONTEXT" and
            f["evidence_status"] in ("DECLARED", "VERIFIED")):
            known[reason].append(f)
        elif (levels[reason] == "TRUSTED_READBACK" and
              f["source_type"] == "TRUSTED_READBACK" and
              f["evidence_status"] == "VERIFIED" and
              isinstance(f.get("independent_readback_ref"), str) and
              f["independent_readback_ref"]):
            known[reason].append(f)
    conflicting = sorted(k for k, vals in known.items()
                         if len({repr(f["value"]) for f in vals}) > 1)
    missing = sorted(k for k, vals in known.items() if not vals or k in conflicting)
    if not missing:
        return _out("PROCEED", [], "SUFFICIENT_FOR_REQUESTED_DEPTH",
                    supported_depth=task["requested_depth"])
    for a in acquisitions:
        if (not isinstance(a.get("candidate_ref"), str) or
            not isinstance(a.get("source_ref"), str) or
            not isinstance(a.get("covers_reasons"), list) or
            not all(isinstance(x, str) for x in a["covers_reasons"]) or
            type(a.get("acquisition_cost_rank")) is not int or
            type(a.get("available")) is not bool or
            type(a.get("material")) is not bool):
            return _block("ACQUISITION_CANDIDATE_INVALID")
    if len({a["candidate_ref"] for a in acquisitions}) != len(acquisitions):
        return _block("DUPLICATE_ACQUISITION")
    request = {"consumer_ref": task.get("consumer_ref", "PROFILE_EVOLUTION"),
               "unresolved_reasons": missing, "candidates": acquisitions,
               "current_evidence": []}
    if acquisitions and acquisition_result is None:
        return _out("RESOLVE_EVIDENCE_PLAN", missing, "TARGETED_ACQUISITION_REUSE",
                    acquisition_request=request, conflicting_reasons=conflicting)
    if acquisition_result is not None:
        if (not isinstance(acquisition_result, dict) or
            acquisition_result.get("schema_version") != ACQUISITION_SCHEMA or
            acquisition_result.get("consumer_ref") != request["consumer_ref"] or
            acquisition_result.get("remaining_reasons") != missing):
            return _block("PROVIDER_RESULT_MISMATCH")
        if (acquisition_result.get("state") == "CONTINUE" and
            acquisition_result.get("code") == "NEXT_MINIMAL_EVIDENCE_SELECTED"):
            selected = acquisition_result.get("next_evidence")
            if (selected not in acquisitions or not isinstance(selected, dict) or
                selected.get("available") is not True or
                selected.get("material") is not True or
                not set(selected.get("covers_reasons", [])) & set(missing)):
                return _block("PROVIDER_SELECTION_INVALID")
            return _out("RETRIEVE", missing, "RETRIEVE_BEFORE_ASK",
                        next_evidence=selected, execution_performed=False)
        if (acquisition_result.get("state") != "STOP" or
            acquisition_result.get("code") != "STOP_NO_DECISION_CHANGING_EVIDENCE" or
            acquisition_result.get("automation_options_exhausted") is not True):
            return _block("PROVIDER_ERROR_NOT_HUMAN_ESCALATION")
    viable = []
    for q in questions:
        if (not isinstance(q.get("question_id"), str) or
            not isinstance(q.get("question"), str) or not q["question"].strip() or
            not isinstance(q.get("covers_reasons"), list) or
            type(q.get("cost_rank")) is not int):
            return _block("QUESTION_INVALID")
        covered = set(q["covers_reasons"]) & set(missing)
        if (covered and q["question_id"] not in asked and
            all(levels[k] == "USER_CONTEXT" for k in covered)):
            viable.append((q["cost_rank"], -len(covered), q["question_id"], q))
    if len(asked) < budget and viable:
        q = sorted(viable, key=lambda t: t[:3])[0][3]
        return _out("ASK_USER", missing, "DECISION_CHANGING_CLARIFICATION",
                    question={"id": q["question_id"], "text": q["question"]})
    return _out("LIMITED_RESPONSE", missing,
                "NO_RECOVERABLE_CONTEXT_OR_QUESTION_EXHAUSTED",
                supported_depth="ORIENT", disclose_limits=True,
                conflicting_reasons=conflicting)
