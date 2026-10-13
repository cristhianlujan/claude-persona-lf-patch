#!/usr/bin/env python3
from __future__ import annotations
from typing import Any

ALLOWED_DESIGNS={"ABLATION","PAIRED_CONTROL","COUNTERFACTUAL","FACTORIAL"}

def _nonempty(v: Any) -> bool:
    return v not in (None,"",[],{})

def evaluate(payload: dict[str,Any]) -> dict[str,Any]:
    if not isinstance(payload,dict):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["LEARNING_PAYLOAD_INVALID"]}

    required=("observations","hypothesis","method_ids","causal_attribution","replication","transfer_validation","holdout","cost_effectiveness","negative_outcomes","admission","lifecycle")
    missing=[k for k in required if not _nonempty(payload.get(k)) and k!="negative_outcomes"]
    if missing:
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["LEARNING_EVIDENCE_INCOMPLETE"],"missing":missing}

    obs=payload.get("observations")
    if not isinstance(obs,list) or len(obs)<3 or any(not isinstance(x,dict) or not x.get("evidence_refs") for x in obs):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["REPLICATED_OBSERVATIONS_NOT_DEMONSTRATED"]}

    attr=payload.get("causal_attribution")
    if not isinstance(attr,dict) or attr.get("design") not in ALLOWED_DESIGNS:
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["CAUSAL_DESIGN_MISSING"]}
    if not attr.get("control_ref") or not attr.get("evidence_refs"):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["CAUSAL_CONTROL_OR_EVIDENCE_MISSING"]}
    conf=attr.get("confidence"); effect=attr.get("effect_size")
    if not isinstance(conf,(int,float)) or isinstance(conf,bool) or conf<0.7:
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["CAUSAL_CONFIDENCE_INSUFFICIENT"]}
    if not isinstance(effect,(int,float)) or isinstance(effect,bool):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["CAUSAL_EFFECT_UNMEASURED"]}
    if effect<=0:
        return {"status":"REJECT","blocking_codes":["CAUSAL_EFFECT_NOT_POSITIVE"]}

    rep=payload.get("replication")
    if not isinstance(rep,dict) or not isinstance(rep.get("repeat_count"),int) or rep["repeat_count"]<3 or not rep.get("cross_case_refs"):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["REPLICATION_INSUFFICIENT"]}

    transfer=payload.get("transfer_validation")
    if not isinstance(transfer,dict) or transfer.get("verification_state")!="VERIFIED":
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["TRANSFER_NOT_VERIFIED"]}
    success=transfer.get("successful_target_classes")
    failed=transfer.get("failed_target_classes")
    if not isinstance(success,list) or len(set(success))<2:
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["TRANSFER_SCOPE_TOO_NARROW"]}
    if not isinstance(failed,list):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["FAILED_TRANSFERS_NOT_RETAINED"]}

    holdout=payload.get("holdout")
    if not isinstance(holdout,dict) or not holdout.get("ref") or holdout.get("contaminated") is not False:
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["HOLDOUT_INVALID_OR_CONTAMINATED"]}
    if holdout.get("direction")!="UP":
        return {"status":"REJECT","blocking_codes":["HOLDOUT_NOT_UP"]}

    cost=payload.get("cost_effectiveness")
    if not isinstance(cost,dict) or cost.get("observed") is not True:
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["COST_NOT_OBSERVED"]}
    if cost.get("within_budget") is not True or cost.get("benefit_cost_positive") is not True:
        return {"status":"REJECT","blocking_codes":["COST_NOT_EFFECTIVE"]}

    negative=payload.get("negative_outcomes")
    if not isinstance(negative,list):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["NEGATIVE_OUTCOMES_NOT_RETAINED"]}
    if any(isinstance(x,dict) and x.get("severity")=="CRITICAL" and x.get("unresolved") is True for x in negative):
        return {"status":"REJECT","blocking_codes":["UNRESOLVED_CRITICAL_NEGATIVE_OUTCOME"]}

    lifecycle=payload.get("lifecycle")
    if not isinstance(lifecycle,dict) or not lifecycle.get("review_after") or not lifecycle.get("retirement_conditions"):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["LEARNING_LIFECYCLE_UNBOUNDED"]}

    admission=payload.get("admission")
    if not isinstance(admission,dict) or not admission.get("ref"):
        return {"status":"NEEDS_MORE_EVIDENCE","blocking_codes":["LEARNING_ADMISSION_MISSING"]}
    if admission.get("verdict")!="PASS" or admission.get("independent") is not True:
        return {"status":"REJECT","blocking_codes":["LEARNING_ADMISSION_NOT_INDEPENDENT_PASS"]}

    return {
      "status":"ADMIT_SCOPED_REUSABLE_PATTERN",
      "blocking_codes":[],
      "auto_promoted":False,
      "scope":{"source_classes":transfer.get("source_classes",[]),"validated_target_classes":sorted(set(success))},
      "causal_confidence":float(conf),
      "effect_size":float(effect),
      "review_after":lifecycle["review_after"],
      "retirement_conditions":lifecycle["retirement_conditions"],
      "failed_transfers_retained":failed,
    }

if __name__=="__main__":
    import json,sys
    data=json.load(open(sys.argv[1],encoding="utf-8"))
    print(json.dumps(evaluate(data),sort_keys=True))
