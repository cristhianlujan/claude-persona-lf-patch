from score_profile_expert_behavior_v1 import evaluate

PROTOCOL={
 "admission_thresholds":{
  "relative_uplift_D_vs_A_min":.15,"paired_ci_lower_D_vs_A_gt":0,"paired_ci_lower_D_vs_C_gt":0,
  "holdout_ci_lower_D_vs_A_gt":0,"holdout_ci_lower_D_vs_C_gt":0,"critical_regressions_max":0,"preservation_ratio_min":.98
 }
}
def arm(score,prefix):
    return {"profile_revision":prefix,"execution_receipt_ref":f"exec://{prefix}","execution_receipt_sha256":"a"*64,
            "producer_execution_id":f"producer-{prefix}","evaluator_receipt_ref":f"judge://{prefix}",
            "evaluator_verification_state":"VERIFIED","evaluator_execution_id":f"judge-{prefix}",
            "blind_arm":True,"score":score}

def good():
    cases=[]
    for i in range(20):
        base=.55 + (i%3)*.02
        cases.append({"case_id":f"C{i:02d}","domain_family":f"D{i%4}","difficulty":(i%5)+1,"critical":i<3,
          "preservation_case":True,"adaptation_case":i%2==0,"transfer_case":i%3==0,
          "arms":{"A_ORIGINAL":arm(base,f"A{i}"),"B_UPDATER_V01":arm(base+.01,f"B{i}"),
                  "C_EVOLUTION_CURRENT":arm(base+.08,f"C{i}"),"D_EVOLUTION_TARGET":arm(min(.99,base+.24),f"D{i}")}})
    return {"benchmark_scope":"EXPERT_TASK_PERFORMANCE_E2E","raw_frozen":True,"thresholds_frozen_before_raw":True,
            "sample_size_plan":{"planned_case_count":20,"power_analysis_ref":"power://frozen"},
            "cases":cases,"resource_metrics":{"cost_budget_pass":True,"latency_observed":True,"token_status":"NOT_OBSERVED","token_estimated":False}}

def run():
    raw=good(); hold={"holdout_case_ids":[f"C{i:02d}" for i in range(10,20)]}
    r=evaluate(raw,hold,PROTOCOL)
    assert r["status"]=="BENCHMARK_PASS"
    assert r["relative_uplift_D_vs_A"]>=.15 and r["critical_regressions"]==0
    assert r["arm_scores"]["D_EVOLUTION_TARGET"]>r["arm_scores"]["C_EVOLUTION_CURRENT"]

    # Contract-only/document-only data cannot pass without actual execution/evaluator receipts.
    bad=good()
    bad["cases"][0]["arms"]["D_EVOLUTION_TARGET"]={"score":1.0,"profile_revision":"doc-only"}
    r=evaluate(bad,hold,PROTOCOL)
    assert r["status"]=="BLOCK"
    assert any("EXECUTION_RECEIPT" in x or "ARM_FIELD_MISSING" in x for x in r["blocking_codes"])

    # Same producer/evaluator cannot certify itself.
    bad=good(); a=bad["cases"][0]["arms"]["D_EVOLUTION_TARGET"]; a["evaluator_execution_id"]=a["producer_execution_id"]
    r=evaluate(bad,hold,PROTOCOL)
    assert r["status"]=="BLOCK" and any("EVALUATOR_NOT_INDEPENDENT" in x for x in r["blocking_codes"])

    # A candidate that is merely equal to current Evolution does not prove the redesign.
    flat=good()
    for c in flat["cases"]:
        c["arms"]["D_EVOLUTION_TARGET"]["score"]=c["arms"]["C_EVOLUTION_CURRENT"]["score"]
    r=evaluate(flat,hold,PROTOCOL)
    assert r["status"]=="BENCHMARK_FAIL" and "paired_ci_D_vs_C" in r["blocking_codes"]
    print("PASS_PROFILE_EXPERT_BEHAVIOR_BENCHMARK_V1 actual_execution_required=1 blind_independent_evaluator=1 four_arms=1 structural_proxy=0")

if __name__=="__main__": run()
