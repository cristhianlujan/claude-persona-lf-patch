"""Deterministic source-integrity validator for J01_SOURCE_INTEGRITY."""
from __future__ import annotations
import argparse, hashlib, json, os
from pathlib import Path
from typing import Any
from lf_common import ValidationInputError, emit, failure, load_json, main_guard, result_object
JUDGE="J01_SOURCE_INTEGRITY"
def obj(v,n):
    if not isinstance(v,dict): raise ValidationInputError(f"{n}_must_be_object")
    return v
def arr(v,n):
    if not isinstance(v,list): raise ValidationInputError(f"{n}_must_be_array")
    return v
def validate_payload(payload:dict[str,Any]):
    snap=obj(payload.get("source_snapshot"),"source_snapshot"); refs=arr(payload.get("source_references"),"source_references"); ledger=arr(payload.get("classification_ledger"),"classification_ledger")
    content=snap.get("content"); declared=snap.get("sha256"); actual=hashlib.sha256(content.encode()).hexdigest() if isinstance(content,str) else None
    target_version=payload.get("target_source_version",snap.get("source_version"))
    checks={
      "source_snapshot_sha_present":0 if isinstance(declared,str) and len(declared)==64 else 1,
      "source_version_matches_target":0 if snap.get("source_version")==target_version else 1,
      "source_references_resolvable":sum(1 for r in refs if not isinstance(r,dict) or r.get("resolved") is not True),
      "source_hash_mismatches":0 if actual and declared==actual else 1,
      "confirmed_rules_without_literal_source":sum(1 for x in ledger if isinstance(x,dict) and x.get("classification")=="CONFIRMED" and not str(x.get("source_ref","")).strip()),
      "inferred_rules_without_label":sum(1 for x in ledger if isinstance(x,dict) and x.get("inferred") is True and x.get("classification")!="INFERRED"),
      "blocked_items_without_reason":sum(1 for x in ledger if isinstance(x,dict) and x.get("classification")=="BLOCKED" and not str(x.get("blocked_reason","")).strip()),
    }
    return checks,{"checks":checks,"source_snapshot_sha":declared,"computed_sha":actual,"source_version":snap.get("source_version"),"source_reference_resolution_count":len(refs)-checks["source_references_resolvable"],"classification_counts":{c:sum(1 for x in ledger if isinstance(x,dict) and x.get("classification")==c) for c in ("CONFIRMED","INFERRED","PROPOSED","BLOCKED")}}
def run(path,refs,retry):
    payload=obj(load_json(path),"input"); checks,evidence=validate_payload(payload); evidence["input_path"]=str(path); failed=[k for k,v in checks.items() if v]; repairs=[failure(k,f"$.evidence.checks.{k}",f"Repair source integrity until {k}=0") for k in failed]
    return emit(result_object(JUDGE,failed,evidence,refs or [f"file:{path}"],repairs,retry_count=retry,judge_version=os.getenv("LF_JUDGE_VERSION"),executor_identity=os.getenv("LF_EXECUTOR_IDENTITY")))
def self_test():
    content="canonical source"; sha=hashlib.sha256(content.encode()).hexdigest(); good={"source_snapshot":{"content":content,"sha256":sha,"source_version":"v1"},"target_source_version":"v1","source_references":[{"ref":"S1","resolved":True}],"classification_ledger":[{"classification":"CONFIRMED","source_ref":"S1"}]}; bad=json.loads(json.dumps(good)); bad["source_snapshot"]["sha256"]="0"*64; bad["source_references"][0]["resolved"]=False
    pc,_=validate_payload(good); nc,_=validate_payload(bad); out={"positive_pass":all(v==0 for v in pc.values()),"negative_rejected":nc["source_hash_mismatches"]>0 and nc["source_references_resolvable"]>0,"positive_checks":pc,"negative_checks":nc}; print(json.dumps(out,sort_keys=True)); return 0 if out["positive_pass"] and out["negative_rejected"] else 1
def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument("input",nargs="?",type=Path); p.add_argument("--evidence-ref",action="append",default=[]); p.add_argument("--retry-count",type=int,default=0); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
    if a.self_test:return self_test()
    if a.input is None:raise ValidationInputError("input_required")
    return run(a.input,a.evidence_ref,a.retry_count)
if __name__=="__main__": raise SystemExit(main_guard(JUDGE,main))
