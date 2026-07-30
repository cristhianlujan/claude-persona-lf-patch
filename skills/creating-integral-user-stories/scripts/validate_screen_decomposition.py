"""Deterministic semantic validator for J02_SCREEN_DECOMPOSITION."""
from __future__ import annotations
import argparse, json, os, tempfile
from pathlib import Path
from typing import Any
from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object
JUDGE="J02_SCREEN_DECOMPOSITION"; VERSION="v0.5"
def obj(v,n):
    if not isinstance(v,dict): raise ValidationInputError(f"{n}_must_be_object")
    return v
def arr(v,n):
    if not isinstance(v,list): raise ValidationInputError(f"{n}_must_be_array")
    return v
def validate_payload(payload:dict[str,Any]):
    dec=obj(payload.get("screen_decomposition",payload),"screen_decomposition")
    target=payload.get("target_screen_code",dec.get("screen_code"))
    contexts=arr(dec.get("context_inventory"),"context_inventory")
    permissions=arr(dec.get("permission_inventory"),"permission_inventory")
    transitions=arr(dec.get("transition_inventory"),"transition_inventory")
    units=arr(dec.get("functional_units"),"functional_units")
    coverage=arr(dec.get("coverage_items"),"coverage_items")
    summary=obj(dec.get("coverage_summary"),"coverage_summary")
    statuses=[str(x.get("mapping_status")) for x in coverage if isinstance(x,dict)]
    codes=[str(x.get("functional_unit_code","")) for x in units if isinstance(x,dict)]
    source_types=[str(x.get("source_type","")) for x in coverage if isinstance(x,dict)]
    checks={
      "source_snapshot_sha_present":0 if isinstance(dec.get("source_snapshot_sha"),str) and len(dec["source_snapshot_sha"])==64 else 1,
      "source_screen_code_matches_target":0 if dec.get("screen_code")==target else 1,
      "context_coverage":max(len(contexts)-source_types.count("CONTEXT"),0),
      "permission_coverage":max(len(permissions)-source_types.count("PERMISSION"),0),
      "transition_coverage":max(len(transitions)-source_types.count("TRANSITION"),0),
      "unmapped_count":sum(1 for s in statuses if s not in {"MAPPED","JUSTIFIED_OUT"}),
      "unjustified_count":sum(1 for x in coverage if isinstance(x,dict) and x.get("mapping_status")=="JUSTIFIED_OUT" and not str(x.get("justification","")).strip()),
      "conflicting_count":statuses.count("CONFLICT"),
      "duplicate_functional_units":len(codes)-len(set(codes)),
      "functional_units_complete":sum(1 for x in units if not isinstance(x,dict) or not all(str(x.get(k,"")).strip() for k in ("actor","goal","observable_output"))),
      "confirmed_rules_have_source":sum(1 for x in units if isinstance(x,dict) and x.get("classification")=="CONFIRMED" and not str(x.get("source_ref","")).strip()),
      "coverage_summary_mismatch":0 if summary.get("source_items_count")==len(coverage) and summary.get("unmapped_count")==0 and summary.get("unjustified_count")==0 and summary.get("conflicting_count")==0 else 1,
    }
    evidence={"checks":checks,"context_count":len(contexts),"permission_count":len(permissions),"transition_count":len(transitions),"functional_units_count":len(units),"coverage_items_count":len(coverage)}
    return checks,evidence
def run(path,refs,retry):
    payload=obj(load_json(path),"input"); checks,evidence=validate_payload(payload); evidence["input_path"]=str(path)
    failed=[k for k,v in checks.items() if v]
    repairs=[failure(k,f"$.evidence.checks.{k}",f"Repair decomposition until {k}=0") for k in failed]
    return emit(result_object(JUDGE,failed,evidence,refs or [f"file:{path}"],repairs,retry_count=retry,judge_version=VERSION,executor_identity=os.getenv("LF_EXECUTOR_IDENTITY") or "R8_SCREEN_VALIDATOR"))
def positive():
    return {"target_screen_code":"SCR-X","screen_decomposition":{"screen_code":"SCR-X","source_version":"v1","source_snapshot_sha":"a"*64,"main_responsibility":"Manage customer search","context_inventory":[{"code":"C1","description":"search","source_ref":"S1"}],"field_inventory":[],"permission_inventory":[{"permission_code":"P1","actor_profile":"A","action_code":"SEARCH","source_ref":"S2"}],"transition_inventory":[{"from":"I","action":"SEARCH","to":"R","allowed":True,"source_ref":"S3"}],"functional_units":[{"functional_unit_code":"FU-X","actor":"Operator","goal":"search customer","trigger":"submit","observable_output":"customer result","risk_level":"LOW","decision":"CREATE_STORY","justification":"independent result","source_ref":"S4","classification":"CONFIRMED"}],"coverage_items":[{"source_item_code":"I1","source_type":"CONTEXT","source_ref":"S1","mapping_status":"MAPPED","mapped_to":["FU-X"],"justification":"mapped"},{"source_item_code":"I2","source_type":"PERMISSION","source_ref":"S2","mapping_status":"MAPPED","mapped_to":["FU-X"],"justification":"mapped"},{"source_item_code":"I3","source_type":"TRANSITION","source_ref":"S3","mapping_status":"MAPPED","mapped_to":["FU-X"],"justification":"mapped"}],"coverage_summary":{"source_items_count":3,"mapped_count":3,"justified_count":0,"unmapped_count":0,"unjustified_count":0,"conflicting_count":0,"duplicate_functional_units_count":0},"pending_decisions":[]}}
def self_test():
    good=positive(); bad=positive(); bad["screen_decomposition"]["coverage_items"][0]["mapping_status"]="PENDING"; bad["screen_decomposition"]["functional_units"].append(dict(bad["screen_decomposition"]["functional_units"][0]))
    pc,_=validate_payload(good); nc,_=validate_payload(bad)
    out={"positive_pass":all(v==0 for v in pc.values()),"negative_rejected":nc["unmapped_count"]>0 and nc["duplicate_functional_units"]>0,"positive_checks":pc,"negative_checks":nc}; print(json.dumps(out,sort_keys=True)); return 0 if out["positive_pass"] and out["negative_rejected"] else 1
def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("input",nargs="?",type=Path); p.add_argument("--evidence-ref",action="append",default=[]); p.add_argument("--retry-count",type=int,default=0); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
    if a.self_test:return self_test()
    if a.input is None:raise ValidationInputError("input_required")
    return run(a.input,a.evidence_ref,a.retry_count)
if __name__=="__main__": raise SystemExit(main_guard(JUDGE,main))
