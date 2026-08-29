#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path
p=Path(__file__).resolve().parents[2]/"validators"/"validate_adapter_package.py";s=importlib.util.spec_from_file_location("v",p);v=importlib.util.module_from_spec(s);s.loader.exec_module(v)
V={"state":"BOUND","render_binding":{"project_code":"LF","output_target":"PPTX","canonical_refs":["design","screen"],"resolved_tokens":{"primary":"token"},"screen_frame_policy":{"frame":"app"},"mockup_template":"mobile","qa_checks":["provenance"],"blockers":[]},"lf_adapter_invocations":[{"adapter_code":"ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF","adapter_version":"v0.2-candidate","invocation_id":"inv-brand-01","activation_reason":"governed visual artifact","source_sha256":"a"*64,"capsule_sha256":"b"*64,"verdict":"APPLIED"}]}
def bad(n,x):
 try:v.validate_result(x)
 except ValueError:print("PASS expected-fail",n);return
 raise AssertionError(n)
def main():
 v.validate_result(V);print("PASS bound")
 x=deepcopy(V);x["lf_adapter_invocations"]=[];bad("missing invocation",x)
 x=deepcopy(V);x["render_binding"]["resolved_tokens"]={};bad("missing governed tokens",x)
 x=deepcopy(V);x["state"]="RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY";x["render_binding"]["resolved_tokens"]={};x["render_binding"]["screen_frame_policy"]={};x["render_binding"]["blockers"]=["missing authority"];x["lf_adapter_invocations"][0]["verdict"]="BLOCKED";v.validate_result(x);print("PASS authority return")
 x=deepcopy(V);x["state"]="BLOCKED_VISUAL_SOURCE_CONFLICT";bad("conflict without evidence",x)
 print("QUALITY_V2_PASS")
if __name__=="__main__":main()
