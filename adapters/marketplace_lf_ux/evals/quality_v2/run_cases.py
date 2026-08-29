#!/usr/bin/env python3
import importlib.util
from copy import deepcopy
from pathlib import Path

p = Path(__file__).resolve().parents[2] / "validators" / "validate_adapter_package.py"
s = importlib.util.spec_from_file_location("v", p); v = importlib.util.module_from_spec(s); s.loader.exec_module(v)
VALID = {
 "state":"BOUND",
 "marketplace_ux_binding":{"source_refs":["marketplace:asset"],"marketplace_context":{"objective":"clarity"},"prioritized_frictions":["unclear selection"],"improvements":[{"proposal":"clarify comparison","status":"PROPOSED_NOT_CANONICAL"}],"protected_constraints":["no unsupported financial claims"],"downstream_dependencies":[],"blockers":[]},
 "lf_adapter_invocations":[{"adapter_code":"ADAPTER_MARKETPLACE_LF_UX","adapter_version":"v0.2-candidate","invocation_id":"inv-ux-0001","activation_reason":"marketplace UX task","source_sha256":"a"*64,"capsule_sha256":"b"*64,"verdict":"APPLIED"}]
}

def bad(name, x):
 try: v.validate_result(x)
 except ValueError: print("PASS expected-fail", name); return
 raise AssertionError(name)

def main():
 v.validate_result(VALID); print("PASS bound_valid")
 x=deepcopy(VALID); x["lf_adapter_invocations"]=[]; bad("missing_invocation",x)
 x=deepcopy(VALID); x["marketplace_ux_binding"]["source_refs"]=[]; bad("missing_sources",x)
 x=deepcopy(VALID); x["state"]="RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY"; x["marketplace_ux_binding"]["blockers"]=["material authority missing"]; x["lf_adapter_invocations"][0]["verdict"]="BLOCKED"; v.validate_result(x); print("PASS missing_authority_return")
 x=deepcopy(VALID); x["state"]="BLOCKED_SOURCE_CONFLICT"; bad("conflict_without_evidence",x)
 print("QUALITY_V2_PASS")

if __name__=="__main__": main()
