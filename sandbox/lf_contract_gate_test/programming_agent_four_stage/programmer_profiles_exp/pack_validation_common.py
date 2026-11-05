"""Shared, sandbox-only structural and adversarial validation for three LF programmer profile candidates.
The profile creates a Worker TASK SPEC, never code. No network, git writes or runtime activation.
"""
import json,re,sys,copy
from pathlib import Path
STANDARD_SOURCE="supabase/migrations/20261028160000_lf_programming_pg00_standards_checkpoints_decisions_v2.sql"
FILES=["SKILL.md","README.md","adapters/document_patch_adapter.md","adapters/github_pack_adapter.md","checklists/preflight_checklist.md","checklists/priority_checklist.md","contracts/main_contract.md","contracts/missing_input_policy.md","evals/eval_matrix.json","examples/bad_output.json","examples/good_output.json","examples/self_repair_output.json","fixtures/happy_path/input.json","fixtures/missing_inputs/input.json","fixtures/self_repair/bad_output.json","fixtures/unsafe_or_blocked/input.json","handoffs/to_quality_pack.handoff.json","judges/mini_judge.md","judges/score_rubric.md","manifest.json","schemas/missing_input.schema.json","schemas/output.schema.json","validators/validate_pack.py","contracts/runtime_binding.json"]
REQUIRED=["schema_version","task_id","objective","expected_change","human_story","functional_contract","scope","cases","dependency_resolution","dependency_task_ids","required_tests","required_evidence","blocked_if","base_head_sha","source_snapshot_sha256","context_path_patterns","write_path_patterns","protected_path_patterns","files_expected","platform_refs","interface_refs","acceptance_commands","max_attempts","max_patch_bytes","max_changed_files","max_context_bytes","allow_deletions"]
FORBIDDEN={"hidden_oracle_ref","hidden_oracle_sha256","oracle_envelope","hidden_oracle","oracle_payload","readiness","production_authority","dispatch_allowed","write_allowed","route_authority","effect_authority"}
PATH=re.compile(r"^[a-zA-Z0-9_./-]+$")
def walk_forbidden(obj):
    if isinstance(obj,dict):return bool(FORBIDDEN.intersection(obj)) or any(walk_forbidden(x) for x in obj.values())
    if isinstance(obj,list):return any(walk_forbidden(x) for x in obj)
    return False
def valid_path(p):
    return isinstance(p,str) and bool(PATH.fullmatch(p)) and len(p)<=400 and not p.startswith("/") and not p.endswith("/") and all(x not in ("",".","..") for x in p.split("/"))
def check_output(spec,task,binding):
    errors=[]
    if not isinstance(spec,dict) or set(spec)!=set(REQUIRED):return ["WORKER_SPEC_FIELDS_INVALID"]
    if walk_forbidden(spec):errors.append("ORACLE_OR_AUTHORITY_EXPOSURE")
    if not isinstance(task,dict):return errors+["LOT_INPUT_INVALID"]
    if task.get("area")!=binding["area"]:errors.append("AREA_MISMATCH")
    if task.get("profile_code")!=binding["profile_code"]:errors.append("PROFILE_CODE_MISMATCH")
    if task.get("production_authority") is not False:errors.append("LOT_AUTHORITY_INVALID")
    paths=task.get("write_scope")
    if not isinstance(paths,list) or not paths or not all(valid_path(p) for p in paths) or len(paths)!=len(set(paths)):
        errors.append("LOT_PATHS_INVALID");paths=[]
    allowed=sorted(paths)
    for k in ("write_path_patterns","context_path_patterns","files_expected"):
        if spec.get(k)!=allowed:errors.append("OUTSIDE_LOT:"+k)
    if spec.get("protected_path_patterns")!=task.get("protected_paths") or not spec.get("protected_path_patterns"):
        errors.append("PROTECTED_TEST_PATHS_INVALID")
    if any(not isinstance(p,str) or not p.strip() for p in spec.get("protected_path_patterns",[])):
        errors.append("PROTECTED_TEST_PATHS_INVALID")
    for protected in spec.get("protected_path_patterns",[]):
        if isinstance(protected,str) and any(w==protected or w.startswith(protected) or protected.startswith(w+"/") for w in allowed):
            errors.append("PROTECTED_TEST_WRITE_OVERLAP")
    if spec.get("required_tests")==[] or not isinstance(spec.get("required_tests"),list):
        errors.append("REQUIRED_TESTS_EMPTY")
    if not isinstance(spec.get("acceptance_commands"),list) or not spec["acceptance_commands"] or not all(isinstance(x,str) and x.strip() for x in spec["acceptance_commands"]):
        errors.append("ACCEPTANCE_COMMANDS_EMPTY")
    if spec.get("scope",{}).get("in_scope")!=allowed:errors.append("SCOPE_INVALID")
    if spec.get("schema_version")!=2:errors.append("SCHEMA_VERSION_INVALID")
    if spec.get("task_id")!=task.get("task_id"):errors.append("TASK_ID_INVALID")
    if not isinstance(spec.get("base_head_sha"),str) or not re.fullmatch(r"[0-9a-f]{40}",spec["base_head_sha"]):errors.append("BASE_HEAD_INVALID")
    if not isinstance(spec.get("source_snapshot_sha256"),str) or not re.fullmatch(r"[0-9a-f]{64}",spec["source_snapshot_sha256"]):errors.append("SNAPSHOT_INVALID")
    if spec.get("allow_deletions") is not False:errors.append("DELETION_AUTHORITY_FORBIDDEN")
    for k in ("max_attempts","max_patch_bytes","max_changed_files","max_context_bytes"):
        if not isinstance(spec.get(k),int) or isinstance(spec[k],bool) or spec[k]<=0:errors.append("LIMIT_INVALID:"+k)
    return errors
def check_pack(root):
    errors=["PACK_FILE_MISSING:"+f for f in FILES if not (root/f).is_file()]
    if errors:return errors
    try:
        manifest=json.loads((root/"manifest.json").read_text())
        binding=json.loads((root/"contracts/runtime_binding.json").read_text())
        skill=(root/"SKILL.md").read_text()
        task=json.loads((root/"fixtures/happy_path/input.json").read_text())
        output=json.loads((root/"examples/good_output.json").read_text())
        if manifest.get("schema_version")!="lf-profile-pack-manifest/v1" or manifest.get("document_status")!="CANDIDATE_SANDBOX_ONLY" or manifest.get("operational_status")!="READ_ONLY" or manifest.get("runtime")!="NO_HABILITADO" or manifest.get("automatic_impact")!="BLOQUEADO":errors.append("MANIFEST_GOVERNANCE_INVALID")
        if binding.get("runtime_enabled") is not False or binding.get("promotion_allowed") is not False or binding.get("production_authority") is not False:errors.append("RUNTIME_ENABLED")
        if "RUNTIME CRITICAL GATE" not in skill or "PROFILE_SELECTION_DESCRIPTION:" not in skill or STANDARD_SOURCE not in skill:errors.append("SKILL_SOURCE_OR_GATE_MISSING")
        errors+=check_output(output,task,binding)
        if json.loads((root/"schemas/output.schema.json").read_text()).get("required")!=REQUIRED:errors.append("SCHEMA_WORKER_FIELDS_DRIFT")
        if manifest.get("required_files")!=FILES:errors.append("MANIFEST_FILE_SET_DRIFT")
    except (ValueError,KeyError,TypeError,OSError) as exc:errors.append("PACK_PARSE_ERROR:"+str(exc))
    return errors
def evaluate(root):
    binding=json.loads((root/"contracts/runtime_binding.json").read_text())
    task=json.loads((root/"fixtures/happy_path/input.json").read_text())
    spec=json.loads((root/"examples/good_output.json").read_text())
    cases=[]
    cases.append(("HAPPY_PATH",not check_output(spec,task,binding)))
    altered=copy.deepcopy(spec);altered["write_path_patterns"]=["outside/escape.java"]
    cases.append(("OUTSIDE_LOT",bool(check_output(altered,task,binding))))
    altered=copy.deepcopy(spec);altered["acceptance_commands"]=[];altered["required_tests"]=[]
    cases.append(("EMPTY_TESTS",bool(check_output(altered,task,binding))))
    altered=copy.deepcopy(spec);altered["oracle_envelope"]={"secret":"never in builder"}
    cases.append(("HIDDEN_ORACLE",bool(check_output(altered,task,binding))))
    altered=copy.deepcopy(task);altered["area"]="FRONTEND" if binding["area"]=="BACKEND" else "BACKEND"
    cases.append(("WRONG_AREA",bool(check_output(spec,altered,binding))))
    altered=copy.deepcopy(spec);altered["production_authority"]=True
    cases.append(("AUTHORITY_INJECTED",bool(check_output(altered,task,binding))))
    return cases
def main(root,evals=False):
    problems=check_pack(root)
    if evals:
        results=evaluate(root) if not problems else []
        problems+=["EVAL_FAILED:"+name for name,passed in results if not passed]
    else:results=[]
    print(json.dumps({"status":"PASS" if not problems else "FAIL","pack":root.name,"blocking_codes":problems,"evals":[{"case":name,"pass":ok} for name,ok in results]},ensure_ascii=False))
    return int(bool(problems))
