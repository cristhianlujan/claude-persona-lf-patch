"""Executable conversational context tests; no simulated retrieval is called 'observed'."""
from __future__ import annotations
import copy
from profile_conversational_context_v1 import route_context_turn as route

BASE = {
    "schema": "PROFILE_CONVERSATIONAL_CONTEXT_V1",
    "request_text": "La carga no terminó, revisa qué pasó",
    "requested_depth": "DIAGNOSE",
    "consumer_ref": "PE-CONTEXT-DEMO-001",
    "requirements": [
        {"reason": "load_identity", "min_source_level": "USER_CONTEXT"},
        {"reason": "load_state", "min_source_level": "TRUSTED_READBACK"}],
    "facts": [],
    "acquisitions": [
        {"candidate_ref": "recent_loads", "source_ref": "supabase://lf_ops/recent_loads",
         "covers_reasons": ["load_identity", "load_state"],
         "acquisition_cost_rank": 1, "available": True, "material": True}],
    "questions": [
        {"question_id": "which_load", "question": "¿Cuál carga o a qué hora se hizo?",
         "covers_reasons": ["load_identity"], "cost_rank": 1}],
    "question_budget": 2,
    "asked_question_ids": []}
ACQ = {
    "schema_version": "LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1",
    "state": "CONTINUE", "code": "NEXT_MINIMAL_EVIDENCE_SELECTED",
    "consumer_ref": "PE-CONTEXT-DEMO-001",
    "remaining_reasons": ["load_identity", "load_state"],
    "next_evidence": BASE["acquisitions"][0],
    "automation_options_exhausted": False}
STOP = {
    "schema_version": "LF_TARGETED_EVIDENCE_ACQUISITION_RESULT_V1",
    "state": "STOP", "code": "STOP_NO_DECISION_CHANGING_EVIDENCE",
    "consumer_ref": "PE-CONTEXT-DEMO-001",
    "remaining_reasons": ["load_identity", "load_state"],
    "automation_options_exhausted": True}

def checked(task, expected, provider=None):
    r = route(task, provider, verify_source=lambda fact: fact.get('independent_readback_ref', '').startswith('supabase://receipt/'))
    assert r["action"] == expected, r
    assert r["write_authorized"] is False
    assert r["production_activation"] is False
    return r

def run():
    # A short user request -> use authorized source before bothering user.
    task = copy.deepcopy(BASE)
    r = checked(task, "RESOLVE_EVIDENCE_PLAN")
    assert r["acquisition_request"]["unresolved_reasons"] == ["load_identity", "load_state"]
    r = checked(task, "RETRIEVE", ACQ)
    assert r["execution_performed"] is False
    # No claimed source until actual independently checked readback supplied.
    task["facts"] = [
        {"reason": "load_identity", "value": "LOAD-1", "source_type": "USER_CONTEXT",
         "source_ref": "conversation://turn-2", "evidence_status": "DECLARED"},
        {"reason": "load_state", "value": "FAILED", "source_type": "TRUSTED_READBACK",
         "source_ref": "supabase://load-1", "evidence_status": "VERIFIED",
         "independent_readback_ref": "supabase://receipt/load-1"}]
    checked(task, "PROCEED")
    # A declared receipt string is not enough without independent verifier.
    assert route(task)["action"] == "RESOLVE_EVIDENCE_PLAN"
    assert route(task, verify_source=lambda _: False)["action"] == "RESOLVE_EVIDENCE_PLAN"
    # An unverified or user-claimed DB state must not silently become a diagnosis.
    task["facts"][1]["evidence_status"] = "UNVERIFIED"
    checked(task, "RESOLVE_EVIDENCE_PLAN")
    task["facts"][1]["evidence_status"] = "VERIFIED"
    task["facts"][1].pop("independent_readback_ref")
    checked(task, "RESOLVE_EVIDENCE_PLAN")
    # No source => one specific clarifying question, not a generic handoff.
    task = copy.deepcopy(BASE)
    task["acquisitions"] = []
    result = checked(task, "ASK_USER")
    assert "hora" in result["question"]["text"]
    task["asked_question_ids"] = ["which_load"]
    checked(task, "LIMITED_RESPONSE")
    task["facts"] = [{"reason": "load_identity", "value": "10:00",
                      "source_type": "USER_CONTEXT",
                      "source_ref": "conversation://turn-2", "evidence_status": "DECLARED"}]
    checked(task, "LIMITED_RESPONSE")  # still lacks trusted DB readback
    # User clarification must be consumed to avoid repeating the same question.
    task["requirements"] = [{"reason": "load_identity", "min_source_level": "USER_CONTEXT"}]
    checked(task, "PROCEED")
    # User may provide a log or file when no system tool can read it.
    # The submitted log is NOT automatically trusted until independently verified.
    task=copy.deepcopy(BASE)
    task["acquisitions"]=[]
    task["questions"].append({
        "question_id":"upload_source",
        "question":"¿Puedes facilitar el recibo de ejecución o el registro de la carga?",
        "question_type":"PROVIDE_SOURCE_FOR_VERIFICATION",
        "covers_reasons":["load_state"],"cost_rank":0})
    out=checked(task,"ASK_USER")
    assert out["question"]["id"]=="upload_source"
    # Stop from existing acquisition provider falls back to user ONLY if answerable.
    task = copy.deepcopy(BASE)
    checked(task, "ASK_USER", STOP)
    task["questions"] = []
    checked(task, "LIMITED_RESPONSE", STOP)
    # Provider error is NOT a reason to ask or blindly continue.
    bad = dict(STOP, code="DEPENDENCY_CURRENTNESS_DRIFT")
    checked(task, "BLOCKED", bad)
    bad = dict(ACQ, consumer_ref="PE-OTHER")
    checked(task, "BLOCKED", bad)
    bad = dict(ACQ, next_evidence={"candidate_ref": "fabricated"})
    checked(task, "BLOCKED", bad)
    # Disagreement between trusted sources reopens investigation.
    task = copy.deepcopy(BASE)
    task["facts"] = [{"reason": "load_identity", "value": "LOAD-1",
                      "source_type": "USER_CONTEXT", "evidence_status": "DECLARED",
                      "source_ref": "conversation://t1"},
                     {"reason": "load_identity", "value": "LOAD-2",
                      "source_type": "USER_CONTEXT", "evidence_status": "DECLARED",
                      "source_ref": "conversation://t2"}]
    r = checked(task, "RESOLVE_EVIDENCE_PLAN")
    assert "load_identity" in r["conflicting_reasons"]
    # Source unavailable, no question: honest limitation rather than root-cause claim.
    task["acquisitions"] = []
    task["questions"] = []
    checked(task, "LIMITED_RESPONSE")
    # Empty requirement list enables helpful direct responses without interrogation.
    task = copy.deepcopy(BASE)
    task["requirements"] = []
    task["acquisitions"] = []
    checked(task, "PROCEED")
    # Rejected malformed requests and duplicated identifiers.
    task = copy.deepcopy(BASE)
    task["requirements"].append(dict(task["requirements"][0]))
    checked(task, "BLOCKED")
    task = copy.deepcopy(BASE)
    task["facts"] = [{"reason": "load_state", "value": "DONE",
                      "source_type": "TRUSTED_READBACK", "evidence_status": "VERIFIED",
                      "source_ref": "db://claimed"}]
    checked(task, "RESOLVE_EVIDENCE_PLAN")
    print("PASS_PROFILE_CONVERSATIONAL_CONTEXT_V1 retrieve_first=1 readback_required=1 targeted_question=1 no_repeated_question=1 contradiction_reopens=1 provider_error_blocks=1 direct_answer=1 authority_writes=0")

if __name__ == "__main__":
    run()
