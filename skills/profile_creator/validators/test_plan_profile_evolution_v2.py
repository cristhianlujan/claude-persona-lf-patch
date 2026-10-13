import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
for p in [ROOT/"sandbox/lf_contract_gate_test/transversal_assets/profile_assessment",ROOT/"sandbox/lf_contract_gate_test/transversal_assets/capability_selector"]:
    if str(p) not in sys.path: sys.path.insert(0,str(p))
from plan_profile_evolution_v2 import build_from_resolved

def v(value):
    return {"value":value,"verification_state":"VERIFIED","evidence_refs":["e://1"]}
def obs(i,score=.99):
    return {"task_ref":f"task://{i}","task_family":"D","difficulty":4,"score":score,"verification_state":"VERIFIED",
            "output_receipt_ref":f"out://{i}","evaluator_receipt_ref":f"judge://{i}","evidence_refs":[f"e://{i}"],
            "repeat_group":f"g{i//2}","adaptation_case":True,"transfer_case":True,"preservation_case":True,"generation":1}

def run():
    structural={"decision":"NO_UPDATE_REQUIRED"}
    learning={"status":"PASS"}
    assessment={"architecture_status":"PASS","competency_observations":[obs(i,.65) for i in range(8)],
                "signals":{"complexity":"HIGH","optimization_need":"REQUIRED"},"budget":{"max_method_cost_points":10}}
    catalog=[{"capability_code":"PACK_VALIDATION_HARNESS","signal_type":"complexity","accepted_values":["HIGH"],"rank":10,"state":"AVAILABLE"}]
    policy={"fallback_capabilities":["PACK_VALIDATION_HARNESS"]}
    import json
    reg=json.loads((ROOT/"sandbox/lf_contract_gate_test/transversal_assets/method_pack_registry/method_pack_registry_v2.json").read_text())
    pre={"candidate_exists":v(True),"grader_available":v(True),"benchmark_exists":v(True),"uplift_target_defined":v(True),"holdout_exists":v(True),"search_budget_approved":v(True),
         "deterministic_verifier_exists":v(True),"workflow_search_budget_approved":v(True),"evaluator_feedback_available":v(True)}
    r=build_from_resolved("x",structural,learning,assessment,catalog,policy,reg,pre)
    assert r["schema"]=="PROFILE_EVOLUTION_PLAN_V2"
    assert r["architecture_control_benchmark_is_cutover_evidence"] is False
    assert r["candidate_execution_required_before_expertise_claim"] is True
    assert r["profile_source_write_allowed"] is False
    assert r["adaptive_loop"]["replan_allowed"] is True

    # No task evidence -> no candidate, even if structurally compatible.
    assessment2={"architecture_status":"PASS","competency_observations":[],"signals":{"complexity":"HIGH"},"budget":{"max_method_cost_points":10}}
    r2=build_from_resolved("x",structural,learning,assessment2,catalog,policy,reg,pre)
    assert r2["candidate_materialization_allowed"] is False
    assert "PROFILE_ASSESSMENT_NEEDS_MORE_EVIDENCE" in r2["blocking_codes"]
    print("PASS_PROFILE_EVOLUTION_PLAN_V2 competency_grounded=1 adaptive_loop=1 expert_benchmark_required=1 authority=0")

if __name__=="__main__": run()
