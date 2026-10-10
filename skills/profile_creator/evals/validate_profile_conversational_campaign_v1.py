"""Structural admission checks for natural-language, multi-turn benchmark traces.

Reuses the existing expert behavior scorer's independent evaluator receipts.
It cannot prove a model actually ran: producer/receipt verification remains
mandatory outside this checker, and no fixture is expert evidence.
"""
from __future__ import annotations

ARMS = ("A_ORIGINAL", "B_UPDATER_V01", "C_EVOLUTION_CURRENT", "D_EVOLUTION_TARGET")
KINDS = {"USER_INITIAL", "TOOL_READBACK", "QUESTION", "USER_REPLY",
         "REASSESSMENT", "FINAL_RESPONSE"}

def validate_conversational_subcampaign(raw: dict, holdout: dict, protocol: dict) -> list[str]:
    cfg = protocol.get("conversational_subcampaign", {})
    if not cfg.get("mandatory_for_expertise_admission"):
        return []
    cases = raw.get("cases", [])
    if not isinstance(cases, list):
        return ["CONVERSATION_CASES_INVALID"]
    holdout_ids = set(holdout.get("holdout_case_ids", []))
    interactive = [c for c in cases if isinstance(c, dict)
                   and c.get("interaction_mode") == "STAGED_NATURAL_CONVERSATION"]
    errors = []
    if len(interactive) < cfg["minimum_scenarios"]:
        errors.append("CONVERSATION_MINIMUM_SCENARIOS_NOT_MET")
    if sum(c.get("case_id") in holdout_ids for c in interactive) < cfg["minimum_blind_holdout_scenarios"]:
        errors.append("CONVERSATION_HOLDOUT_MINIMUM_NOT_MET")
    for case in interactive:
        cid = str(case.get("case_id", "?"))
        first = case.get("initial_user_request")
        if not isinstance(first, str) or not first.strip() or len(first) > 600:
            errors.append(cid + ":NATURAL_REQUEST_INVALID")
        if case.get("complete_handoff_preloaded") is not False:
            errors.append(cid + ":COMPLETE_HANDOFF_FORBIDDEN")
        for arm in ARMS:
            arms = case.get("arms") if isinstance(case.get("arms"), dict) else {}
            a = arms.get(arm, {})
            trace = a.get("dialogue_trace") if isinstance(a, dict) else None
            if not isinstance(trace, dict):
                errors.append(cid + ":" + arm + ":DIALOGUE_TRACE_MISSING")
                continue
            if trace.get("initial_user_request") != first:
                errors.append(cid + ":" + arm + ":INITIAL_REQUEST_MISMATCH")
            if (trace.get("independent_evaluator_receipt_ref") != a.get("evaluator_receipt_ref")
                or trace.get("producer_execution_id") != a.get("producer_execution_id")):
                errors.append(cid + ":" + arm + ":DIALOGUE_RECEIPT_IDENTITY_MISMATCH")
            if trace.get("evaluation_status") != "VERIFIED":
                errors.append(cid + ":" + arm + ":DIALOGUE_NOT_INDEPENDENTLY_EVALUATED")
            events = trace.get("events")
            if not isinstance(events, list) or len(events) < 2:
                errors.append(cid + ":" + arm + ":DIALOGUE_TOO_SHORT")
                continue
            if (not isinstance(events[0], dict) or not isinstance(events[-1], dict) or
                events[0].get("kind") != "USER_INITIAL" or events[-1].get("kind") != "FINAL_RESPONSE"):
                errors.append(cid + ":" + arm + ":DIALOGUE_BOUNDARIES_INVALID")
            pending = set()
            for i, e in enumerate(events):
                if not isinstance(e, dict) or e.get("kind") not in KINDS or not e.get("event_ref"):
                    errors.append(cid + ":" + arm + ":EVENT_INVALID")
                    continue
                if e["kind"] == "QUESTION":
                    qid = e.get("question_id")
                    if not qid or qid in pending or e.get("decision_changing") is not True or e.get("recoverable_from_authorized_source") is not False:
                        errors.append(cid + ":" + arm + ":UNNECESSARY_OR_DUPLICATE_QUESTION")
                    pending.add(qid)
                if e["kind"] == "USER_REPLY":
                    qid = e.get("question_id")
                    if qid not in pending:
                        errors.append(cid + ":" + arm + ":UNSOLICITED_OR_UNBOUND_REPLY")
                    else:
                        pending.remove(qid)
                if e["kind"] == "TOOL_READBACK" and (not e.get("source_ref") or not e.get("verification_receipt_ref")):
                    errors.append(cid + ":" + arm + ":TOOL_READBACK_UNVERIFIED")
            if pending:
                errors.append(cid + ":" + arm + ":UNRESOLVED_QUESTION")
            if trace.get("premature_unsupported_conclusion") is not False:
                errors.append(cid + ":" + arm + ":PREMATURE_CONCLUSION_NOT_EXCLUDED")
    return sorted(set(errors))
