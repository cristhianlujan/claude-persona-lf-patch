#!/usr/bin/env python3
from copy import deepcopy
from waiver_authority_v1 import evaluate_waiver_authority, receipt_digest

PLAN="a"*64; REQ="b"*64; MERGE="c"*40; SOURCE="d"*40

def signed(obj, field):
    obj[field]=receipt_digest(obj,field); return obj

request={
 "schema_version":"LF_WAIVER_AUTHORITY_REQUEST_V1","capability_code":"WAIVER_AUTHORITY",
 "entry_guard_readback":{"decision":"ORCHESTRATOR_ENTRY_ACCEPTED"},
 "orchestrator_execution_id":"ORCH-1","consumer_execution_id":"CLOSURE-1","dispatch_receipt_id":"D-1",
 "post_pase_execution_id":"PP-1","control_id":"CONTROL-A","subject_ref":"subject://A",
 "plan_digest":PLAN,"merge_sha":MERGE,"source_revision":SOURCE,"request_digest":REQ,"authority_refs":{}
}
plan=signed({"schema_version":"LF_PLAN_AUTHORITY_DRIFT_RECEIPT_V1","decision":"MATCH","ready":True,"resolved_plan_digest":PLAN,"plan_id":"P1","anchor_event_id":1},"receipt_digest")
current=signed({"schema_version":"LF_CURRENTNESS_AUTHORITY_RECEIPT_V1","authority_layer":"CURRENTNESS_AUTHORITY","decision":"CURRENT","ready":True,"current_revision":SOURCE,"bound_revision":SOURCE},"receipt_sha256")
scope={k:request[k] for k in ("post_pase_execution_id","control_id","plan_digest","merge_sha","source_revision","subject_ref")}
grant=signed({
 "schema_version":"LF_POST_PASE_WAIVER_GRANT_READBACK_V1","authority_layer":"WAIVER_AUTHORITY_STORE",
 "decision":"WAIVER_GRANT_CURRENT","ready":True,"waiver_id":7,"scope":scope,
 "approval_authority":"LF_GOVERNANCE","approval_decision":"APPROVED","approval_event_id":19699,
 "max_uses":1,"uses_count":0,"active":True,"consumed_at":None,
 "rationale":"Emergency bounded waiver for exact control only.","grant_sha256":"e"*64
},"readback_digest")
consume=signed({
 "schema_version":"LF_POST_PASE_WAIVER_CONSUMPTION_READBACK_V1","authority_layer":"WAIVER_AUTHORITY_STORE",
 "decision":"WAIVER_CONSUMED","ready":True,"waiver_id":7,"scope":scope,
 "max_uses":1,"uses_count":1,"active":False,"consumed_at":"2026-10-01T02:30:00Z",
 "consumed_by_execution_id":"CLOSURE-1","consumed_by_request_digest":REQ,"grant_sha256":"e"*64
},"readback_digest")
request["authority_refs"]={
 "plan_authority_receipt_digest":plan["receipt_digest"],"currentness_receipt_sha256":current["receipt_sha256"],
 "grant_readback_digest":grant["readback_digest"],"consumption_readback_digest":consume["readback_digest"]
}

def verdict(req=request,p=plan,c=current,g=grant,co=consume):
    r=evaluate_waiver_authority(request=req,plan_authority_receipt=p,currentness_receipt=c,grant_readback=g,consumption_readback=co)
    return r,(r["decision"],r["ready"])

checks=0
r,v=verdict(); assert v==("WAIVER_AUTHORIZED",True) and r["closure_status"] is None and "WAIVED" not in r.values(); checks+=1
x=deepcopy(request); x["entry_guard_readback"]={"decision":"BLOCK"}; assert verdict(req=x)[1]==("WAIVER_BLOCKED",False); checks+=1
p=deepcopy(plan); p["resolved_plan_digest"]="f"*64; p=signed({k:v for k,v in p.items() if k!="receipt_digest"},"receipt_digest"); x=deepcopy(request); x["authority_refs"]["plan_authority_receipt_digest"]=p["receipt_digest"]; assert verdict(req=x,p=p)[1]==("WAIVER_BLOCKED",False); checks+=1
c=deepcopy(current); c["decision"]="STALE_AFFECTED"; c["ready"]=False; c=signed({k:v for k,v in c.items() if k!="receipt_sha256"},"receipt_sha256"); x=deepcopy(request); x["authority_refs"]["currentness_receipt_sha256"]=c["receipt_sha256"]; assert verdict(req=x,c=c)[1]==("WAIVER_BLOCKED",False); checks+=1
g=deepcopy(grant); g["scope"]["control_id"]="OTHER"; g=signed({k:v for k,v in g.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["grant_readback_digest"]=g["readback_digest"]; assert verdict(req=x,g=g)[1]==("WAIVER_BLOCKED",False); checks+=1
g=deepcopy(grant); g["approval_authority"]="VALIDATION_EXEMPTION_ONE_USE"; g=signed({k:v for k,v in g.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["grant_readback_digest"]=g["readback_digest"]; assert verdict(req=x,g=g)[1]==("WAIVER_BLOCKED",False); checks+=1
g=deepcopy(grant); g.update(uses_count=1,active=False,consumed_at="2026-10-01T02:29:00Z"); g=signed({k:v for k,v in g.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["grant_readback_digest"]=g["readback_digest"]; assert verdict(req=x,g=g)[1]==("WAIVER_BLOCKED",False); checks+=1
co=deepcopy(consume); co["uses_count"]=2; co=signed({k:v for k,v in co.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["consumption_readback_digest"]=co["readback_digest"]; assert verdict(req=x,co=co)[1]==("WAIVER_BLOCKED",False); checks+=1
co=deepcopy(consume); co["consumed_by_request_digest"]="f"*64; co=signed({k:v for k,v in co.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["consumption_readback_digest"]=co["readback_digest"]; assert verdict(req=x,co=co)[1]==("WAIVER_BLOCKED",False); checks+=1
co=deepcopy(consume); co.update(decision="WAIVER_NOT_CONSUMED",ready=False); co=signed({k:v for k,v in co.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["consumption_readback_digest"]=co["readback_digest"]; assert verdict(req=x,co=co)[1]==("WAIVER_BLOCKED",False); checks+=1
g=deepcopy(grant); g["schema_version"]="validation-exemption/v2"; g=signed({k:v for k,v in g.items() if k!="readback_digest"},"readback_digest"); x=deepcopy(request); x["authority_refs"]["grant_readback_digest"]=g["readback_digest"]; assert verdict(req=x,g=g)[1]==("WAIVER_BLOCKED",False); checks+=1
x=deepcopy(request); x["authority_refs"]["grant_readback_digest"]="0"*64; assert verdict(req=x)[1]==("WAIVER_BLOCKED",False); checks+=1
print(f"PASS_WAIVER_AUTHORITY_V1 checks={checks}")
