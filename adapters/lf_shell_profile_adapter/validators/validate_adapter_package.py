#!/usr/bin/env python3
import re
HEX64=re.compile(r"^[a-f0-9]{64}$")
STATES={"BOUND","BOUND_CANDIDATE_ONLY","RETURN_TO_ORCHESTRATOR_MISSING_AUTHORITY","RETURN_TO_ORCHESTRATOR_SHELL_CHANGE_REQUIRED","BLOCKED_SOURCE_CONFLICT","BLOCKED_SCREEN_UNRESOLVED"}
def fail(m): raise ValueError(m)
def validate_result(d):
 if set(d)!={"state","shell_binding","lf_adapter_invocations"}: fail("root keys")
 if d["state"] not in STATES: fail("state")
 invs=d["lf_adapter_invocations"]
 if not isinstance(invs,list) or len(invs)!=1: fail("exactly one invocation")
 i=invs[0]; req={"adapter_code","adapter_version","invocation_id","activation_reason","source_sha256","capsule_sha256","verdict"}
 if set(i)!=req or i["adapter_code"]!="ADAPTER_LF_SHELL_PROFILE": fail("invocation identity")
 if len(str(i["invocation_id"]))<8 or not HEX64.fullmatch(str(i["source_sha256"])) or not HEX64.fullmatch(str(i["capsule_sha256"])): fail("invocation evidence")
 if i["verdict"] not in {"APPLIED","BLOCKED"}: fail("verdict")
 b=d["shell_binding"]; keys={"profile_id","screen_code","canonical_refs","protected_targets","writable_targets","normalized_delta","precision_basis","blockers","handoff"}
 if set(b)!=keys or not b["canonical_refs"]: fail("binding")
 if set(b["protected_targets"]) & set(b["writable_targets"]): fail("target overlap")
 blocked=d["state"].startswith("BLOCKED") or d["state"].startswith("RETURN_TO_ORCHESTRATOR")
 if blocked != bool(b["blockers"]): fail("blocker consistency")
