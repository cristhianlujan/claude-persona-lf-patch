from validate_profile_learning_admission_v2 import evaluate

def valid():
    return {
      "observations":[
        {"run":"1","evidence_refs":["e://1"]},{"run":"2","evidence_refs":["e://2"]},{"run":"3","evidence_refs":["e://3"]}
      ],
      "hypothesis":"Method M improves task family X when signal Y is present.",
      "method_ids":["M"],
      "causal_attribution":{"design":"ABLATION","control_ref":"control://1","evidence_refs":["causal://1"],"confidence":.82,"effect_size":.18},
      "replication":{"repeat_count":3,"cross_case_refs":["case://1","case://2","case://3"]},
      "transfer_validation":{"verification_state":"VERIFIED","source_classes":["X"],"successful_target_classes":["Y","Z"],"failed_target_classes":["W"]},
      "holdout":{"ref":"holdout://1","direction":"UP","contaminated":False},
      "cost_effectiveness":{"observed":True,"within_budget":True,"benefit_cost_positive":True},
      "negative_outcomes":[{"class":"W","severity":"NON_CRITICAL","unresolved":False}],
      "admission":{"ref":"assurance://1","verdict":"PASS","independent":True},
      "lifecycle":{"review_after":"2027-01-01","retirement_conditions":["REPEATED_NO_UPLIFT","CRITICAL_REGRESSION"]}
    }

def run():
    r=evaluate(valid())
    assert r["status"]=="ADMIT_SCOPED_REUSABLE_PATTERN" and r["auto_promoted"] is False
    assert r["failed_transfers_retained"]==["W"]

    p=valid(); p["causal_attribution"].pop("control_ref")
    assert evaluate(p)["status"]=="NEEDS_MORE_EVIDENCE"

    p=valid(); p["causal_attribution"]["effect_size"]=-.01
    assert evaluate(p)["status"]=="REJECT"

    p=valid(); p["transfer_validation"]["successful_target_classes"]=["Y"]
    assert evaluate(p)["status"]=="NEEDS_MORE_EVIDENCE"

    p=valid(); p["holdout"]["contaminated"]=True
    assert evaluate(p)["status"]=="NEEDS_MORE_EVIDENCE"

    p=valid(); p["admission"]["independent"]=False
    assert evaluate(p)["status"]=="REJECT"

    p=valid(); p["negative_outcomes"]=[{"severity":"CRITICAL","unresolved":True}]
    assert evaluate(p)["status"]=="REJECT"
    print("PASS_PROFILE_LEARNING_ADMISSION_V2 causal=1 transfer=1 negative_results=1 lifecycle=1 auto_promote=0")

if __name__=="__main__": run()
