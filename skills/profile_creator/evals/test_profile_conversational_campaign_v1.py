"""Required conversational benchmark must pass AND fail with real validations."""
import copy
from score_profile_expert_behavior_v1 import evaluate
from test_score_profile_expert_behavior_v1 import good,PROTOCOL

CONFIG={
 "mandatory_for_expertise_admission":True,
 "minimum_scenarios":40,
 "minimum_blind_holdout_scenarios":20
}
def campaign():
    raw=good()
    # Extend the ordinary matched positive scorer fixture to 40 cases.
    for i in range(20,40):
        row=copy.deepcopy(raw["cases"][i-20])
        row["case_id"]=f"C{i:02d}"
        raw["cases"].append(row)
    raw["sample_size_plan"]["planned_case_count"]=40
    raw["resource_metrics"]["cost_budget_pass"]=True
    for case in raw["cases"]:
        case["interaction_mode"]="STAGED_NATURAL_CONVERSATION"
        case["initial_user_request"]="La carga aparece terminada pero el usuario no recibió confirmación."
        case["complete_handoff_preloaded"]=False
        for arm,a in case["arms"].items():
            ref=case["case_id"]+":"+arm
            a["dialogue_trace"]={
                "initial_user_request":case["initial_user_request"],
                "producer_execution_id":a["producer_execution_id"],
                "independent_evaluator_receipt_ref":a["evaluator_receipt_ref"],
                "evaluation_status":"VERIFIED",
                "premature_unsupported_conclusion":False,
                "events":[
                    {"kind":"USER_INITIAL","event_ref":"conversation://"+ref+"/1"},
                    {"kind":"TOOL_READBACK","event_ref":"runtime://"+ref+"/read",
                     "source_ref":"supabase://case/"+case["case_id"],
                     "verification_receipt_ref":"verifier://"+ref},
                    {"kind":"REASSESSMENT","event_ref":"reasoning://"+ref},
                    {"kind":"FINAL_RESPONSE","event_ref":"answer://"+ref}
                ]}
    return raw,{"holdout_case_ids":[f"C{i:02d}" for i in range(20,40)]}

def run():
    policy=copy.deepcopy(PROTOCOL)
    policy["conversational_subcampaign"]=CONFIG
    raw,hold=campaign()
    passed=evaluate(raw,hold,policy)
    assert passed["status"]=="BENCHMARK_PASS",passed
    # A high static score is insufficient without actual conversational trace.
    bad=copy.deepcopy(raw); bad["cases"][0]["arms"]["D_EVOLUTION_TARGET"].pop("dialogue_trace")
    out=evaluate(bad,hold,policy)
    assert out["status"]=="BLOCK"
    assert any("DIALOGUE_TRACE_MISSING" in s for s in out["blocking_codes"])
    bad=copy.deepcopy(raw);bad["cases"][0]["complete_handoff_preloaded"]=True
    out=evaluate(bad,hold,policy)
    assert out["status"]=="BLOCK" and any("COMPLETE_HANDOFF_FORBIDDEN" in s for s in out["blocking_codes"])
    bad=copy.deepcopy(raw)
    events=bad["cases"][0]["arms"]["D_EVOLUTION_TARGET"]["dialogue_trace"]["events"]
    events.insert(1,{"kind":"QUESTION","event_ref":"chat://q","question_id":"q1",
                     "decision_changing":False,"recoverable_from_authorized_source":True})
    events.insert(2,{"kind":"USER_REPLY","event_ref":"chat://r","question_id":"q1"})
    out=evaluate(bad,hold,policy)
    assert out["status"]=="BLOCK" and any("UNNECESSARY_OR_DUPLICATE_QUESTION" in s for s in out["blocking_codes"])
    bad=copy.deepcopy(raw)
    bad["cases"][0]["arms"]["D_EVOLUTION_TARGET"]["dialogue_trace"]["events"][1].pop("verification_receipt_ref")
    out=evaluate(bad,hold,policy)
    assert out["status"]=="BLOCK" and any("TOOL_READBACK_UNVERIFIED" in s for s in out["blocking_codes"])
    bad=copy.deepcopy(raw)
    bad["cases"][0]["arms"]["D_EVOLUTION_TARGET"]["dialogue_trace"]["events"].append("malformed")
    out=evaluate(bad,hold,policy)
    assert out["status"]=="BLOCK" and any("EVENT_INVALID" in s for s in out["blocking_codes"])
    bad=copy.deepcopy(raw)
    for case in bad["cases"][39:]:
        case["interaction_mode"]="STATIC"
    out=evaluate(bad,hold,policy)
    assert out["status"]=="BLOCK"
    assert "CONVERSATION_MINIMUM_SCENARIOS_NOT_MET" in out["blocking_codes"]
    print("PASS_PROFILE_INTERACTIVE_BENCHMARK_V1 positive=1 negatives=6 matched_arms=4 preloaded_handoff_blocked=1 unnecessary_question_blocked=1 source_receipt_required=1")

if __name__=="__main__":
    run()
