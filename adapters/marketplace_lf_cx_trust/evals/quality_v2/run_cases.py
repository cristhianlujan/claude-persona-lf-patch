#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"validators"/"validate_adapter_package.py";s=importlib.util.spec_from_file_location("v",p);v=importlib.util.module_from_spec(s);s.loader.exec_module(v)
V={"state":"BOUND","marketplace_cx_trust_binding":{"source_refs":["promise"],"promise_boundary":"current supported promise","prioritized_trust_risks":["ambiguity"],"transparency_improvements":[{"status":"PROPOSED_NOT_CANONICAL"}],"protected_claims_guardrails":["preserve qualifiers"],"downstream_dependencies":[],"blockers":[]},"lf_adapter_invocations":[{"adapter_code":"ADAPTER_MARKETPLACE_LF_CX_TRUST","adapter_version":"v0.2-candidate","invocation_id":"inv-cx-0001","activation_reason":"marketplace trust","source_sha256":"a"*64,"capsule_sha256":"b"*64,"verdict":"APPLIED"}]}
def bad(n,x):
 try:v.validate_result(x)
 except ValueError:print("PASS expected-fail",n);return
 raise AssertionError(n)
def main():
 v.validate_result(V);print("PASS bound")
 x=deepcopy(V);x["lf_adapter_invocations"]=[];bad("missing invocation",x)
 x=deepcopy(V);x["marketplace_cx_trust_binding"]["protected_claims_guardrails"]=[];bad("missing guardrails",x)
 x=deepcopy(V);x["state"]="BLOCKED_UNSUPPORTED_TRUST_CLAIM";x["marketplace_cx_trust_binding"]["blockers"]=["claim outside current authority"];x["lf_adapter_invocations"][0]["verdict"]="BLOCKED";v.validate_result(x);print("PASS protected claim block")
 print("QUALITY_V2_PASS")
if __name__=="__main__":main()
