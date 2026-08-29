#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"validators"/"validate_adapter_package.py";s=importlib.util.spec_from_file_location("v",p);v=importlib.util.module_from_spec(s);s.loader.exec_module(v)
V={"state":"BOUND","marketplace_ux_binding":{"source_refs":["asset"],"marketplace_context":{"objective":"clarity"},"prioritized_frictions":["selection"],"improvements":[{"status":"PROPOSED_NOT_CANONICAL"}],"protected_constraints":["no unsupported claims"],"downstream_dependencies":[],"blockers":[]},"lf_adapter_invocations":[{"adapter_code":"ADAPTER_MARKETPLACE_LF_UX","adapter_version":"v0.2-candidate","invocation_id":"inv-ux-0001","activation_reason":"marketplace UX","source_sha256":"a"*64,"capsule_sha256":"b"*64,"verdict":"APPLIED"}]}
def bad(n,x):
 try:v.validate_result(x)
 except ValueError:print("PASS expected-fail",n);return
 raise AssertionError(n)
def main():
 v.validate_result(V);print("PASS bound")
 x=deepcopy(V);x["lf_adapter_invocations"]=[];bad("missing invocation",x)
 x=deepcopy(V);x["marketplace_ux_binding"]["source_refs"]=[];bad("missing sources",x)
 x=deepcopy(V);x["state"]="RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY";x["marketplace_ux_binding"]["blockers"]=["missing authority"];x["lf_adapter_invocations"][0]["verdict"]="BLOCKED";v.validate_result(x);print("PASS authority return")
 print("QUALITY_V2_PASS")
if __name__=="__main__":main()
