from profile_assessment_v2 import assess_profile_v2

def obs(i, score=.9, difficulty=4, **kw):
    x={
      "task_ref":f"task://{i}","task_family":"DOMAIN","difficulty":difficulty,"score":score,
      "verification_state":"VERIFIED","output_receipt_ref":f"output://{i}",
      "evaluator_receipt_ref":f"judge://{i}","evidence_refs":[f"evidence://{i}"],
      "preservation_case":False,"cost_budget_ratio":.25
    }
    x.update(kw); return x

def run():
    # Structural compatibility alone cannot claim maturity.
    p={"structural_status":"PASS","architecture_status":"PASS","competency_observations":[]}
    r=assess_profile_v2(p)
    assert r["maturity"]=="UNDETERMINED" and r["evolution_mode"] is None

    # References without verified execution/evaluator receipts do not score.
    bad=[{"task_ref":"t","task_family":"D","difficulty":5,"score":1.0,"verification_state":"UNKNOWN",
          "output_receipt_ref":"o","evaluator_receipt_ref":"j","evidence_refs":["e"]} for _ in range(8)]
    r=assess_profile_v2({"structural_status":"PASS","architecture_status":"PASS","competency_observations":bad})
    assert r["maturity"]=="UNDETERMINED"
    assert r["competency_vector"]["verified_observation_count"]==0

    # Specialized: effective domain work but no adaptation/transfer evidence.
    xs=[obs(i,score=.82,difficulty=2) for i in range(4)]
    xs += [obs(100+i,score=.99,difficulty=2,preservation_case=True) for i in range(2)]
    r=assess_profile_v2({"structural_status":"PASS","architecture_status":"PASS","competency_observations":xs})
    assert r["maturity"]=="SPECIALIZED" and r["evolution_mode"]=="ADAPT"

    # Expert requires quality+difficulty+robustness+adaptation+transfer+preservation.
    xs=[]
    for i in range(8):
        xs.append(obs(i,score=.99,difficulty=4,repeat_group=f"g{i//2}",
                      adaptation_case=True,transfer_case=True,preservation_case=True,critical=(i<2),generation=1))
    r=assess_profile_v2({"structural_status":"PASS","architecture_status":"PASS","competency_observations":xs})
    assert r["maturity"]=="EXPERT" and r["competency_vector"]["critical_failures"]==0

    # Evidence optimized needs longitudinal + verified causal attribution.
    xs=[]
    for i in range(12):
        xs.append(obs(i,score=.99,difficulty=4,repeat_group=f"g{i//2}",
                      adaptation_case=True,transfer_case=True,preservation_case=True,generation=(i%3)+1))
    r=assess_profile_v2({
      "structural_status":"PASS","architecture_status":"PASS","competency_observations":xs,
      "causal_attribution":{"verification_state":"VERIFIED","confidence":.82,"evidence_refs":["causal://1"]}
    })
    assert r["maturity"]=="EVIDENCE_OPTIMIZED" and r["evolution_mode"]=="NO_CHANGE"

    # Critical regression prevents expert.
    xs[0]["score"]=.2; xs[0]["critical"]=True
    r=assess_profile_v2({
      "structural_status":"PASS","architecture_status":"PASS","competency_observations":xs,
      "causal_attribution":{"verification_state":"VERIFIED","confidence":.9,"evidence_refs":["causal://1"]}
    })
    assert r["maturity"]!="EXPERT" and r["maturity"]!="EVIDENCE_OPTIMIZED"

    # Assessment is never write authority.
    assert r["write_authorized"] is False and r["admission_required"] is True
    print("PASS_PROFILE_ASSESSMENT_V2 structural_only_blocked=1 verified_tasks_required=1 expert_vector=1 longitudinal_causal=1 authority=0")

if __name__=="__main__":
    run()
