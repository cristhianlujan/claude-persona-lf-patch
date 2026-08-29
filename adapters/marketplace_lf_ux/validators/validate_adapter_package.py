#!/usr/bin/env python3
import re
H=re.compile(r"^[a-f0-9]{64}$");S={"BOUND","BOUND_CANDIDATE_ONLY","RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY","BLOCKED_SOURCE_CONFLICT","BLOCKED_TARGET_UNRESOLVED"}
def f(m):raise ValueError(m)
def validate_result(d):
 if set(d)!={"state","marketplace_ux_binding","lf_adapter_invocations"} or d["state"] not in S:f("root/state")
 a=d["lf_adapter_invocations"]
 if not isinstance(a,list) or len(a)!=1:f("exactly one invocation")
 i=a[0];r={"adapter_code","adapter_version","invocation_id","activation_reason","source_sha256","capsule_sha256","verdict"}
 if set(i)!=r or i["adapter_code"]!="ADAPTER_MARKETPLACE_LF_UX" or len(str(i["invocation_id"]))<8 or not H.fullmatch(str(i["source_sha256"])) or not H.fullmatch(str(i["capsule_sha256"])):f("invocation evidence")
 b=d["marketplace_ux_binding"];k={"source_refs","marketplace_context","prioritized_frictions","improvements","protected_constraints","downstream_dependencies","blockers"}
 if set(b)!=k or not b["source_refs"] or not b["protected_constraints"] :f("binding")
 blocked=d["state"].startswith("BLOCKED") or d["state"].startswith("RETURN_TO_ORCHESTRATOR")
 if blocked!=bool(b["blockers"]):f("blocker consistency")
