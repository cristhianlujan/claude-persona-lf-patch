#!/usr/bin/env python3
import re
HEX64=re.compile(r"^[a-f0-9]{64}$");STATES={"BOUND","BOUND_CANDIDATE_ONLY","RETURN_TO_ORCHESTRATOR_MISSING_BRAND_AUTHORITY","BLOCKED_VISUAL_SOURCE_CONFLICT","BLOCKED_TARGET_UNRESOLVED"}
def fail(m):raise ValueError(m)
def validate_result(d):
 if set(d)!={"state","render_binding","lf_adapter_invocations"}:fail("root keys")
 if d["state"] not in STATES:fail("state")
 invs=d["lf_adapter_invocations"]
 if not isinstance(invs,list) or len(invs)!=1:fail("exactly one invocation")
 i=invs[0];req={"adapter_code","adapter_version","invocation_id","activation_reason","source_sha256","capsule_sha256","verdict"}
 if set(i)!=req or i["adapter_code"]!="ADAPTER_PROJECT_BRAND_MOCKUP_RENDER_LF":fail("invocation identity")
 if len(str(i["invocation_id"]))<8 or not HEX64.fullmatch(str(i["source_sha256"])) or not HEX64.fullmatch(str(i["capsule_sha256"])):fail("invocation evidence")
 b=d["render_binding"];keys={"project_code","output_target","canonical_refs","resolved_tokens","screen_frame_policy","mockup_template","qa_checks","blockers"}
 if set(b)!=keys or b["output_target"] not in {"PDF","PPTX","HTML","BRANDBOOK"} or not b["canonical_refs"] or not b["qa_checks"]:fail("binding")
 blocked=d["state"].startswith("BLOCKED") or d["state"].startswith("RETURN_TO_ORCHESTRATOR")
 if blocked!=bool(b["blockers"]):fail("blocker consistency")
 if not blocked and (not b["resolved_tokens"] or not b["screen_frame_policy"]):fail("governed visual binding required")
