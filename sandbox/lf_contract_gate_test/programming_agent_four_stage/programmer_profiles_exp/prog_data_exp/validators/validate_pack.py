#!/usr/bin/env python3
"""Structural subset of exact WorkerTaskSpecV2; sandbox-only and fail-closed.

Source: programming-agent/src/programming_agent_runner/worker_task_spec.py.
The real PG07 C2 producer is also exercised by the selector integration test.
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
TASK_ID=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,119}\.v[1-9][0-9]*$")

def allowed_path(value):
    return (isinstance(value,str) and bool(value) and len(value)<=400
            and not value.startswith("/") and "\\" not in value
            and not any(x in value for x in "*?[]{}\x00:")
            and all(x not in ("",".","..") for x in value.split("/")))

def scan_forbidden(obj):
    if isinstance(obj,dict):
        return any(k in FORBIDDEN or scan_forbidden(v) for k,v in obj.items())
    if isinstance(obj,list):
        return any(scan_forbidden(v) for v in obj)
    return False

def validate(output,binding,input_packet,schema):
    problems=[]
    if not isinstance(output,dict):return ["OUTPUT_NOT_OBJECT"]
    if scan_forbidden(output):problems.append("HIDDEN_ORACLE_OR_AUTHORITY_EXPOSED")
    if set(output)!=set(schema["properties"]):problems.append("WORKER_V2_EXACT_FIELDS_INVALID")
    if output.get("schema_version")!=2:problems.append("WORKER_SCHEMA_INVALID")
    if not TASK_ID.fullmatch(str(output.get("task_id",""))):
        problems.append("WORKER_VERSIONED_TASK_ID_INVALID")
    if binding.get("runtime_enabled") is not False or binding.get("promotion_allowed") is not False:
        problems.append("BINDING_AUTHORITY_INVALID")
    if input_packet.get("area")!=binding.get("area"):
        problems.append("PROFILE_AREA_MISMATCH")
    if input_packet.get("profile_code")!=binding.get("profile_code"):
        problems.append("PROFILE_ID_MISMATCH")
    if not HEX64.fullmatch(str(input_packet.get("profile_assignment_sha256",""))):
        problems.append("ASSIGNMENT_DIGEST_MISSING")
    if not HEX40.fullmatch(str(output.get("base_head_sha",""))) or output.get("base_head_sha")!=input_packet.get("base_head_sha"):
        problems.append("BASE_SHA_INVALID")
    if not HEX64.fullmatch(str(output.get("source_snapshot_sha256",""))) or output.get("source_snapshot_sha256")!=input_packet.get("source_snapshot_sha256"):
        problems.append("SNAPSHOT_SHA_INVALID")
    for field in ("objective","expected_change"):
        if not isinstance(output.get(field),str) or not output[field].strip():
            problems.append("MISSING_"+field.upper())
    story=output.get("human_story")
    story_fields={"story_code","title","persona","need","benefit","dependencies","technical_notes"}
    if not isinstance(story,dict) or set(story)!=story_fields or any(not isinstance(story.get(k),str) or not story[k].strip() for k in ("story_code","title","persona","need","benefit")) or not isinstance(story.get("dependencies"),list) or not isinstance(story.get("technical_notes"),dict):
        problems.append("HUMAN_STORY_SHAPE_INVALID")
    contract=output.get("functional_contract")
    valid_refs=set()
    semantics=set()
    if not isinstance(contract,dict) or set(contract)!={"acceptance_criteria","invariants","negative_controls","source_rule_codes"}:
        problems.append("FUNCTIONAL_CONTRACT_INVALID")
    else:
        for key in ("acceptance_criteria","invariants","negative_controls"):
            rows=contract[key]
            if not isinstance(rows,list) or not rows or any(not isinstance(row,dict) or not isinstance(row.get("code"),str) or not row["code"] for row in rows):
                problems.append("FUNCTIONAL_"+key.upper()+"_INVALID")
            else:
                refs=[row["code"] for row in rows]
                if len(refs)!=len(set(refs)):problems.append("DUPLICATE_"+key.upper())
                semantics.update(refs);valid_refs.update(refs)
        rule_codes=contract["source_rule_codes"]
        if not isinstance(rule_codes,list) or not rule_codes or any(not isinstance(x,str) or not x for x in rule_codes):
            problems.append("SOURCE_RULE_CODES_MISSING")
        else:valid_refs.update(rule_codes)
    scope=output.get("scope")
    if not isinstance(scope,dict) or set(scope)!={"in_scope","out_of_scope","must_not_change"} or any(not isinstance(scope.get(k),list) or not scope[k] for k in ("in_scope","out_of_scope","must_not_change")):
        problems.append("WORKER_SCOPE_SHAPE_INVALID")
    cases=output.get("cases")
    if not isinstance(cases,dict) or set(cases)!={"positive","edge","regression"}:
        problems.append("WORKER_CASES_SHAPE_INVALID")
    else:
        for family in ("positive","edge","regression"):
            rows=cases[family]
            if not isinstance(rows,list) or not rows or any(not isinstance(r,dict) or not r.get("code") or not isinstance(r.get("statement"),str) or len(r["statement"].strip())<10 or not isinstance(r.get("source_refs"),list) or not r["source_refs"] or not set(r["source_refs"]).issubset(valid_refs) for r in rows):
                problems.append("CASES_"+family.upper()+"_INVALID")
    if output.get("dependency_resolution")!=[] or output.get("dependency_task_ids")!=[]:
        problems.append("UNRESOLVED_DEPENDENCY_IN_SANDBOX")
    covered=set()
    tests=output.get("required_tests")
    if not isinstance(tests,list) or not tests:
        problems.append("EMPTY_REQUIRED_TESTS")
    else:
        for row in tests:
            if not isinstance(row,dict) or not isinstance(row.get("test_ref"),str) or not row["test_ref"] or not isinstance(row.get("purpose"),str) or len(row["purpose"].strip())<10 or not isinstance(row.get("covers_refs"),list):
                problems.append("TEST_SHAPE_INVALID")
            else:
                refs=set(row["covers_refs"])
                if not refs.issubset(valid_refs):problems.append("TEST_UNKNOWN_SOURCE_REF")
                covered.update(refs)
        if not semantics.issubset(covered):problems.append("TEST_COVERAGE_MISSING")
    evidence=output.get("required_evidence")
    if not isinstance(evidence,list) or not evidence or any(not isinstance(x,dict) or not x.get("evidence_type") or not x.get("source_ref") or not isinstance(x.get("covers_refs"),list) for x in evidence):
        problems.append("REQUIRED_EVIDENCE_INVALID")
    blocks=output.get("blocked_if")
    if not isinstance(blocks,list) or not blocks or any(not isinstance(x,dict) or not x.get("code") or not isinstance(x.get("condition"),str) or len(x["condition"].strip())<10 for x in blocks):
        problems.append("BLOCKED_IF_INVALID")
    for field in ("write_path_patterns","context_path_patterns","protected_path_patterns","files_expected"):
        paths=output.get(field)
        if not isinstance(paths,list) or not paths or any(not allowed_path(x) for x in paths) or len(paths)!=len(set(paths)):
            problems.append("PATHS_"+field.upper()+"_INVALID")
    if output.get("write_path_patterns")!=sorted(input_packet.get("write_scope",[])):
        problems.append("WRITE_SCOPE_OUTSIDE_LOT")
    if output.get("protected_path_patterns")!=input_packet.get("protected_path_patterns"):
        problems.append("PROTECTED_PATHS_DRIFT")
    cmds=output.get("acceptance_commands")
    if not isinstance(cmds,list) or not cmds or any(not isinstance(x,dict) or set(x)!={"name","argv"} or not x["name"] or not isinstance(x["argv"],list) or not x["argv"] or any(not isinstance(y,str) or not y for y in x["argv"]) for x in cmds):
        problems.append("EMPTY_ACCEPTANCE_COMMANDS")
    if cmds!=input_packet.get("visible_acceptance_commands"):
        problems.append("ACCEPTANCE_COMMANDS_DRIFT")
    for field in ("platform_refs","interface_refs"):
        if not isinstance(output.get(field),list):problems.append("INVALID_"+field.upper())
    for field in ("max_attempts","max_patch_bytes","max_changed_files","max_context_bytes"):
        v=output.get(field)
        if type(v) is not int or v<1:problems.append("INVALID_"+field.upper())
    if output.get("allow_deletions") is not False:problems.append("DELETIONS_FORBIDDEN")
    return sorted(set(problems))

def main(argv=None):
    args=argv if argv is not None else sys.argv[1:]
    root=Path(__file__).resolve().parents[1]
    if len(args)==1 and args[0] in (".",str(root)):args=[]
    binding=json.loads((root/"runtime_binding.json").read_text())
    schema=json.loads((root/"schemas/output.schema.json").read_text())
    packet=json.loads((root/"fixtures/happy_path/input.json").read_text())
    source=root/"examples/good_output.json" if not args else Path(args[0])
    output=json.loads(source.read_text())
    problems=validate(output,binding,packet,schema)
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
        problems.extend("MISSING_FILE:"+x for x in required if not (root/x).is_file())
        manifest=json.loads((root/"manifest.json").read_text())
        if manifest.get("document_status")!="CANDIDATE_SANDBOX_ONLY" or manifest.get("runtime")!="NO_HABILITADO":
            problems.append("MANIFEST_STATUS_INVALID")
    result={"status":"PASS" if not problems else "BLOCKED","blocking_codes":sorted(set(problems)),
            "profile_code":binding.get("profile_code"),"runtime_enabled":False}
    print(json.dumps(result,ensure_ascii=False))
    return 0 if not problems else 1

if __name__=="__main__":
    raise SystemExit(main())
