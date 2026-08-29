#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path

p=Path(__file__).resolve().parents[2]/"validators"/"validate_adapter_package.py"
s=importlib.util.spec_from_file_location("v",p); v=importlib.util.module_from_spec(s); s.loader.exec_module(v)
VALID={
 "state":"BOUND",
 "marketplace_cx_trust_binding":{"source_refs":["marketplace:promise"],"promise_boundary":"clarity without guarantee","prioritized_trust_risks":["ambiguous outcome"],"transparency_improvements":[{"proposal":"clarify status","status":"PROPOSED_NOT_CANONICAL"}],"protected_claims_guardrails":["no guaranteed debt closure"],"downstream_dependencies":[],"blockers":[]},
 "lf_adapter_invocations":[{"adapter_code":"ADAPTER_MARKETPLACE_LF_CX_TRUST","adapter_version":"v0.2-candidate","invocation_id":"inv-cx-0001","activation_reason":"marketplace trust task","source_sha256":"a"*64,"capsule_sha256":"b"*64,"verdict":"APPLIED"}]
}

def bad(name,x):
 try:v.validate_result(x)
 except ValueError:print("PASS expected-fail",name);return
 raise AssertionError(name)

def main():
 v.validate_result(VALID);print("PASS bound_valid")
 x=deepcopy(VALID);x["lf_adapter_invocations"]=[];bad("missing_invocation",x)
 x=deepcopy(VALID);x["marketplace_cx_trust_binding"]["protected_claims_guardrails"]=[];bad("missing_claim_guardrails",x)
 x=deepcopy(VALID);x["state"]="BLOCKED_UNSUPPORTED_TRUST_CLAIM";x["marketplace_cx_trust_binding"]["blockers"]=["unsupported guarantee"];x["lf_adapter_invocations"][0]["verdict"]="BLOCKED";v.validate_result(x);print("PASS unsupported_claim_block")
 x=deepcopy(VALID);x["state"]="BLOCKED_SOURCE_CONFLICT";bad("conflict_without_evidence",x)
 print("QUALITY_V2_PASS")
if __name__=="__main__":main()
