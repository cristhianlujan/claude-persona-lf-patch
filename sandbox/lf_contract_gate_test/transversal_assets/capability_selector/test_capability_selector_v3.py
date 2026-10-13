import json
from pathlib import Path
from capability_selector_v3 import compose_capabilities_v3,replan_composition

ROOT=Path(__file__).resolve().parent
REG=json.loads((ROOT.parent/"method_pack_registry"/"method_pack_registry_v2.json").read_text())

def verified(value):
    return {"value":value,"verification_state":"VERIFIED","evidence_refs":["evidence://precondition"]}

def catalog():
    return [
      {"capability_code":"PACK_VALIDATION_HARNESS","signal_type":"complexity","accepted_values":["HIGH"],"rank":10,"state":"AVAILABLE"},
      {"capability_code":"PERFORMANCE_EXACT_SOURCE_BENCHMARK","signal_type":"optimization_need","accepted_values":["REQUIRED"],"rank":20,"state":"AVAILABLE"},
      {"capability_code":"INDEPENDENT_ASSURANCE","signal_type":"risk","accepted_values":["HIGH","CRITICAL"],"rank":30,"state":"AVAILABLE"},
    ]

def run():
    ctx={"complexity":"HIGH","optimization_need":"REQUIRED","risk":"MEDIUM","budget":{"max_method_cost_points":10},"selection_cycle":0}
    pre={
      "candidate_exists":verified(True),
      "grader_available":verified(True),
      "benchmark_exists":verified(True),
      "uplift_target_defined":verified(True),
      "holdout_exists":verified(True),
      "search_budget_approved":verified(True),
      "deterministic_verifier_exists":verified(True),
      "workflow_search_budget_approved":verified(True),
      "evaluator_feedback_available":verified(True),
    }
    r=compose_capabilities_v3(ctx,catalog(),{"fallback_capabilities":["PACK_VALIDATION_HARNESS"]},REG,pre)
    assert r["schema"]=="CAPABILITY_SELECTOR_COMPOSITION_V3"
    assert any(m["method_id"]=="SELF_REFINE" for m in r["selected_methods"])
    assert any(m["method_id"]=="EVALUATOR_OPTIMIZER" for m in r["selected_methods"])
    assert all(m["availability_state"]!="EXPERIMENTAL_NOT_ADMITTED" for m in r["selected_methods"])
    assert any(x["reason"]=="EXPERIMENTAL_NOT_ADMITTED" for x in r["rejected_methods"])

    # Missing verified precondition blocks selection even when signal matches.
    pre2=dict(pre); pre2["grader_available"]={"value":True,"verification_state":"UNKNOWN","evidence_refs":[]}
    r2=compose_capabilities_v3(ctx,catalog(),{"fallback_capabilities":["PACK_VALIDATION_HARNESS"]},REG,pre2)
    assert not any(m["method_id"]=="SELF_REFINE" for m in r2["selected_methods"])
    assert any(x["method_id"]=="SELF_REFINE" and x["reason"]=="PRECONDITION_UNKNOWN" for x in r2["rejected_methods"])

    # Dynamic replanning: plateau removes the current method for this run and recomposes.
    rr=replan_composition(ctx,{
      "trigger":"QUALITY_PLATEAU","method_id":"SELF_REFINE","evidence_refs":["judge://plateau"],
      "signal_updates":{"optimization_need":"REQUIRED","risk":"CRITICAL"}
    },catalog(),{"fallback_capabilities":["PACK_VALIDATION_HARNESS"]},REG,pre)
    assert rr["status"]=="REPLANNED" and rr["new_cycle"]==1
    assert "SELF_REFINE" in rr["blocked_methods_for_current_run"]
    assert not any(m["method_id"]=="SELF_REFINE" for m in rr["new_composition"]["selected_methods"])
    assert "INDEPENDENT_ASSURANCE" in rr["new_composition"]["selected_capabilities"]
    assert rr["persistent_learning_authorized"] is False

    # Replanning without evidence is fail-closed.
    bad=replan_composition(ctx,{"trigger":"METHOD_FAILED","method_id":"SELF_REFINE","evidence_refs":[]},catalog(),{},REG,pre)
    assert bad["status"]=="BLOCKED" and "REPLAN_EVIDENCE_REQUIRED" in bad["blocking_codes"]
    print("PASS_CAPABILITY_SELECTOR_V3 preconditions_verified=1 experiments_gated=1 dynamic_replan=1 persistent_learning=0")

if __name__=="__main__": run()
