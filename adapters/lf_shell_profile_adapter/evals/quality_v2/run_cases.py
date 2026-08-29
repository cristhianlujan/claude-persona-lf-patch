#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"validators"/"validate_adapter_package.py";s=importlib.util.spec_from_file_location("v",p);v=importlib.util.module_from_spec(s);s.loader.exec_module(v)
V={"state":"BOUND","shell_binding":{"profile_id":"PERFIL-UI-ARCHITECT","screen_code":"CHECKOUT","canonical_refs":["screen","shell"],"protected_targets":["header"],"writable_targets":["payment_summary"],"normalized_delta":{},"precision_basis":"UPSTREAM_VALUE","blockers":[],"handoff":"UI"},"lf_adapter_invocations":[{"adapter_code":"ADAPTER_LF_SHELL_PROFILE","adapter_version":"v0.2-candidate","invocation_id":"inv-shell-01","activation_reason":"bound LF screen","source_sha256":"a"*64,"capsule_sha256":"b"*64,"verdict":"APPLIED"}]}
def bad(n,x):
 try:v.validate_result(x)
 except ValueError: print("PASS expected-fail",n);return
 raise AssertionError(n)
def main():
 v.validate_result(V);print("PASS bound")
 x=deepcopy(V);x["lf_adapter_invocations"]=[];bad("missing invocation",x)
 x=deepcopy(V);x["shell_binding"]["protected_targets"].append("payment_summary");bad("protected overlap",x)
 x=deepcopy(V);x["state"]="RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED";x["shell_binding"]["blockers"]=["locked"];x["lf_adapter_invocations"][0]["verdict"]="BLOCKED";v.validate_result(x);print("PASS locked return")
 x=deepcopy(V);x["state"]="BLOCKED_SOURCE_CONFLICT";bad("block without evidence",x)
 print("QUALITY_V2_PASS")
if __name__=="__main__":main()
