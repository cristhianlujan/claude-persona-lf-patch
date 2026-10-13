#!/usr/bin/env python3
from __future__ import annotations
import json,re,sys
from pathlib import Path

HEX64=re.compile(r"^[0-9a-f]{64}$")
HEX40=re.compile(r"^[0-9a-f]{40}$")

def validate(envelope: dict, receipt: dict, capability_current: bool=True) -> dict:
    st=str(envelope.get("subject_type") or "").strip()
    sr=str(envelope.get("subject_ref") or "").strip()
    ss=str(envelope.get("subject_sha256") or "")
    sh=str(envelope.get("source_head_sha") or "")
    producer=str(envelope.get("producer_execution_id") or "").strip()
    reviewer=str(envelope.get("reviewer_execution_id") or "").strip()
    dims=envelope.get("required_dimensions")
    if not st:
        return {"result":"BLOCK","code":"SUBJECT_TYPE_MISSING"}
    if not sr or not HEX64.fullmatch(ss) or not HEX40.fullmatch(sh):
        return {"result":"BLOCK","code":"SUBJECT_IDENTITY_INVALID"}
    if not producer or not reviewer:
        return {"result":"BLOCK","code":"EXECUTION_IDENTITY_MISSING"}
    if producer==reviewer:
        return {"result":"BLOCK","code":"BUILDER_REVIEWER_NOT_INDEPENDENT"}
    if envelope.get("review_required") is not True:
        return {"result":"BLOCK","code":"REVIEW_NOT_REQUIRED"}
    if not isinstance(dims,list) or not dims or any(not isinstance(x,str) or not x.strip() for x in dims):
        return {"result":"BLOCK","code":"REQUIRED_DIMENSIONS_MISSING"}
    if not isinstance(receipt,dict) or receipt.get("verification_state")!="VERIFIED":
        return {"result":"BLOCK","code":"SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID"}
    for key in ("subject_type","subject_ref","subject_sha256","source_head_sha"):
        if receipt.get(key)!=envelope.get(key):
            return {"result":"BLOCK","code":"SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID"}
    if not str(receipt.get("authority_ref") or "").strip():
        return {"result":"BLOCK","code":"SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID"}
    if not capability_current:
        return {"result":"BLOCK","code":"INDEPENDENT_ASSURANCE_NOT_CURRENT"}
    return {"result":"PASS","subject_type":st,"contract_mode":"CONTRACT_DRIVEN_ANY_SUBJECT","required_dimensions":dims}

def self_test() -> None:
    def env(t="PROFILE_CANDIDATE"):
        return {
          "subject_type":t,"subject_ref":"subject://1","subject_sha256":"a"*64,
          "source_head_sha":"1"*40,"subject_receipt_id":"receipt-1",
          "producer_execution_id":"producer","reviewer_execution_id":"reviewer",
          "review_required":True,"required_dimensions":["quality"]
        }
    def rec(t="PROFILE_CANDIDATE"):
        return {
          "verification_state":"VERIFIED","subject_type":t,"subject_ref":"subject://1",
          "subject_sha256":"a"*64,"source_head_sha":"1"*40,"authority_ref":"authority://1"
        }
    assert validate(env("PROFILE_CANDIDATE"),rec("PROFILE_CANDIDATE"))["result"]=="PASS"
    assert validate(env("FUTURE_ARBITRARY_SUBJECT"),rec("FUTURE_ARBITRARY_SUBJECT"))["result"]=="PASS"
    e=env(); e["reviewer_execution_id"]="producer"
    assert validate(e,rec())["code"]=="BUILDER_REVIEWER_NOT_INDEPENDENT"
    e=env(); e["required_dimensions"]=[]
    assert validate(e,rec())["code"]=="REQUIRED_DIMENSIONS_MISSING"
    assert validate(env("OTHER"),rec("PROFILE_CANDIDATE"))["code"]=="SUBJECT_PROVIDER_BOUND_RECEIPT_INVALID"
    print("INDEPENDENT_REVIEW_SUBJECT_ENVELOPE_V3=PASS")

if __name__=="__main__":
    if len(sys.argv)==1:
        self_test()
    else:
        payload=json.loads(Path(sys.argv[1]).read_text())
        print(json.dumps(validate(payload["envelope"],payload["receipt"],payload.get("capability_current",True)),sort_keys=True))
