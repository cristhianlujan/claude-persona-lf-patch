#!/usr/bin/env python3
"""Candidate-only validation of a bounded Worker-visible v2 spec.
No hidden oracle, model call, executable patch or promotion.
"""
import json
import re
import sys
from pathlib import Path

FORBIDDEN={"oracle_envelope","hidden_oracle_ref","hidden_oracle_sha256","hidden_oracle",
           "oracle_payload","readiness","route_authority","effect_authority",
           "production_authority","dispatch_allowed","write_allowed","worker_invoked"}
HEX40=re.compile(r"^[a-f0-9]{40}$")
HEX64=re.compile(r"^[a-f0-9]{64}$")

def allowed_path(value):
    return isinstance(value,str) and bool(value) and not value.startswith("/") and "\\" not in value and not any(x in value for x in "*?[]{}\x00:") and all(x not in ("",".","..") for x in value.split("/"))

def scan_forbidden(obj):
    if isinstance(obj,dict):
        return any(k in FORBIDDEN or scan_forbidden(v) for k,v in obj.items())
    if isinstance(obj,list):
        return any(scan_forbidden(v) for v in obj)
    return False

def validate(output, binding, input_packet, schema):
    issues=[]
    if not isinstance(output,dict):return ["OUTPUT_NOT_OBJECT"]
    if scan_forbidden(output):issues.append("HIDDEN_ORACLE_OR_AUTHORITY_EXPOSED")
    if set(output)!=set(schema["properties"]):issues.append("OUTPUT_FIELDS_INVALID")
    if output.get("schema_version")!=2:issues.append("WORKER_SCHEMA_INVALID")
    if output.get("profile_code")!=binding.get("profile_code"):issues.append("PROFILE_ID_MISMATCH")
    if binding.get("runtime_enabled") is not False or binding.get("promotion_allowed") is not False:
        issues.append("BINDING_AUTHORITY_INVALID")
    if input_packet.get("area")!=binding.get("area"):
        issues.append("PROFILE_AREA_MISMATCH")
    if input_packet.get("profile_code")!=binding.get("profile_code"):
        issues.append("INPUT_PROFILE_MISMATCH")
    if not HEX64.fullmatch(str(output.get("profile_assignment_sha256",""))) or output.get("profile_assignment_sha256")!=input_packet.get("profile_assignment_sha256"):
        issues.append("ASSIGNMENT_BINDING_INVALID")
    if not HEX40.fullmatch(str(output.get("base_head_sha",""))):issues.append("BASE_SHA_INVALID")
    if not HEX64.fullmatch(str(output.get("source_snapshot_sha256",""))):issues.append("SNAPSHOT_SHA_INVALID")
    for field in ("task_id","objective","expected_change","human_story"):
        if not isinstance(output.get(field),str) or not output[field].strip():
            issues.append("MISSING_"+field.upper())
    for field in ("write_path_patterns","context_path_patterns","protected_path_patterns","files_expected"):
        val=output.get(field)
        if not isinstance(val,list) or not val or any(not allowed_path(v) for v in val) or len(val)!=len(set(val)):
            issues.append("INVALID_"+field.upper())
    scoped=input_packet.get("write_scope")
    if not isinstance(scoped,list) or not scoped or output.get("write_path_patterns")!=sorted(scoped):
        issues.append("WRITE_SCOPE_OUTSIDE_LOT")
    for field in ("required_tests","acceptance_commands"):
        val=output.get(field)
        if not isinstance(val,list) or not val or any(not isinstance(v,str) or not v.strip() for v in val):
            issues.append("EMPTY_"+field.upper())
    if output.get("acceptance_commands")!=input_packet.get("visible_acceptance_commands"):
        issues.append("ACCEPTANCE_COMMANDS_DRIFT")
    if output.get("protected_path_patterns")!=input_packet.get("protected_path_patterns"):
        issues.append("PROTECTED_PATHS_DRIFT")
    if not isinstance(output.get("scope"),dict) or not {"in_scope","out_of_scope","must_not_change"}<=set(output["scope"]):
        issues.append("WORKER_SCOPE_SHAPE_INVALID")
    for field in ("max_attempts","max_patch_bytes","max_changed_files","max_context_bytes"):
        v=output.get(field)
        if type(v) is not int or v<1:issues.append("INVALID_"+field.upper())
    if output.get("allow_deletions") is not False:issues.append("DELETIONS_FORBIDDEN")
    for field in ("functional_contract","dependency_resolution"):
        if not isinstance(output.get(field),dict):issues.append("INVALID_"+field.upper())
    for field in ("cases","dependency_task_ids","required_evidence","blocked_if","platform_refs","interface_refs"):
        if not isinstance(output.get(field),list):issues.append("INVALID_"+field.upper())
    if output.get("scope",{}).get("in_scope")!=input_packet.get("write_scope"):
        issues.append("SCOPE_DECLARATION_DRIFT")
    return sorted(set(issues))

def main(argv=None):
    args=argv if argv is not None else sys.argv[1:]
    root=Path(__file__).resolve().parents[1]
    if len(args)==1 and args[0] in (".",str(root)):args=[]
    binding=json.loads((root/"runtime_binding.json").read_text())
    schema=json.loads((root/"schemas/output.schema.json").read_text())
    packet=json.loads((root/"fixtures/happy_path/input.json").read_text())
    source=root/"examples/good_output.json" if not args else Path(args[0])
    output=json.loads(source.read_text())
    issues=validate(output,binding,packet,schema)
    if not args:
        required=["SKILL.md","README.md","contracts/main_contract.md","contracts/missing_input_policy.md",
                  "schemas/output.schema.json","schemas/missing_input.schema.json","judges/score_rubric.md",
                  "judges/mini_judge.md","checklists/preflight_checklist.md","checklists/priority_checklist.md",
                  "examples/good_output.json","examples/bad_output.json","examples/self_repair_output.json",
                  "fixtures/happy_path/input.json","fixtures/missing_inputs/input.json",
                  "fixtures/unsafe_or_blocked/input.json","fixtures/self_repair/bad_output.json",
                  "validators/validate_pack.py","evals/eval_matrix.json",
                  "handoffs/to_quality_pack.handoff.json","adapters/github_pack_adapter.md",
                  "adapters/document_patch_adapter.md","manifest.json","runtime_binding.json"]
        issues.extend("MISSING_FILE:"+x for x in required if not (root/x).is_file())
        manifest=json.loads((root/"manifest.json").read_text())
        if manifest.get("document_status")!="CANDIDATE_SANDBOX_ONLY" or manifest.get("runtime")!="NO_HABILITADO":
            issues.append("MANIFEST_STATUS_INVALID")
    result={"status":"PASS" if not issues else "BLOCKED","blocking_codes":sorted(set(issues)),
            "profile_code":binding.get("profile_code"),"runtime_enabled":False}
    print(json.dumps(result,ensure_ascii=False))
    return 0 if not issues else 1

if __name__=="__main__":
    raise SystemExit(main())
