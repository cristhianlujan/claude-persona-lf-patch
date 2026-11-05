#!/usr/bin/env python3
"""Adapter contract tests against EXACT original Worker parse_worker_task() @298307e.
Requires a local checkout, no provider key, model, network or workflow.
"""
import copy,json,os,sys,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
STAGES=HERE.parent
sys.path.insert(0,str(STAGES/"programmer_profiles_exp"))
sys.path.insert(0,str(HERE))
from stack_skills_exp.project_stack_resolver_exp import (
 role_material,skill_material,select_binding,compose_visible_worker_spec,load_json)
from pg07_to_worker_v1_adapter import (
 adapt,AdapterBlocked,sha,TASK_FIELDS,load_real_worker_contract,
 build_worker_command,materialize_external)
from worker_cost_report_v1 import price_receipt
def check(condition,message):
    if not condition:raise AssertionError(message)
def blocked(fn,code):
    try:fn()
    except AdapterBlocked as exc:
        check(str(exc)==code,(code,str(exc)))
        print("PASS BLOCK",code)
        return
    raise AssertionError("No block: "+code)
def build():
    p=STAGES/"programmer_profiles_exp/prog_backend_exp/examples/good_output.json"
    pg07=json.loads(p.read_text(encoding="utf-8"))
    pg07["max_attempts"]=1
    role=role_material("PERFIL-PROG-BACKEND-EXP")
    rows=[]
    for b in load_json("project_stack_binding_fixtures.json")["rows"]:
        if b["project_ref"]=="lf_java" and b["area"]=="BACKEND":
            x=skill_material(b["skill_code"],b["skill_version"])
            rows.append({**b,"skill_sha256":x["skill_sha256"]})
    stack=select_binding("lf_java","BACKEND",lambda p,a:rows)
    pg07=compose_visible_worker_spec(pg07,{"profile_code":role["profile_code"],
                  "area":"BACKEND","project_ref":"lf_java"},role,stack)
    pg07["task_id"]="PILOT-001"
    source=pg07["acceptance_commands"][0]
    metadata=[{"source_command":source,"name":"visible-check",
               "argv":["project-visible-check","--fixture-only"],
               "timeout_seconds":60,"max_output_bytes":4096}]
    overlay={"production_authority":False,"dispatch_allowed":False,"worker_invoked":False,
             "worker_task_overlay":{"worker_spec_sha256":sha(pg07),
                                    "write_scope":pg07["write_path_patterns"]}}
    return pg07,overlay,metadata
def run():
    checkout=os.environ.get("WORKER_298307E_CHECKOUT","")
    if not checkout:raise SystemExit("WORKER_298307E_CHECKOUT_REQUIRED")
    parse_task,load_quality,load_readback,load_oracle,readback_source_paths=load_real_worker_contract(Path(checkout))
    def checked_adapt(*args,**kwargs):
        return adapt(*args,worker_checkout=Path(checkout),**kwargs)
    pg07,overlay,commands=build()
    task,envelope=checked_adapt(pg07,owner_commands=commands,pg07_overlay=overlay)
    check(set(task)==TASK_FIELDS and len(task)==14 and task["schema_version"]==1,
          "Worker V1 exact 14-field mapping")
    parsed=parse_task(task)
    check(parsed.max_attempts==1 and parsed.max_context_bytes<=60000 and
          parsed.max_patch_bytes<=20000 and parsed.max_changed_files<=3,
          "Pilot limits not enforced")
    check("SB3-01" in task["objective"] and "KF3-01" in task["objective"] and
          "profile_sha256=" in task["objective"] and "skill_sha256=" in task["objective"] and
          "SOURCE https://" in task["objective"],"Missing rules/sha/source in objective")
    check("oracle_envelope" not in task["objective"] and
          "hidden_oracle" not in task["objective"] and
          "holdout.oracle" not in task["objective"] and
          all("oracle" not in p.lower() and "holdout" not in p.lower()
              for p in task["context_path_patterns"]),"Hidden oracle reached objective/context")
    check(envelope["task_id"]==task["task_id"] and envelope["task_sha256"]==sha(task)
          and envelope["pg07_extra"]["functional_contract"]["role_and_stack"]["skill_set_sha256"],
          "External envelope unbound")
    print("PASS Worker original parse_worker_task() accepts exact V1 task + rule provenance")
    injected=copy.deepcopy(pg07)
    injected["functional_contract"]["oracle_envelope"]={"secret":"NO"}
    bad_overlay=copy.deepcopy(overlay)
    bad_overlay["worker_task_overlay"]["worker_spec_sha256"]=sha(injected)
    blocked(lambda:checked_adapt(injected,owner_commands=commands,pg07_overlay=bad_overlay),
            "ORACLE_FIELD_IN_PG07_TASK")
    context_leak=copy.deepcopy(pg07)
    context_leak["context_path_patterns"]=["tests/holdout.oracle.json"]
    leaked_overlay=copy.deepcopy(overlay)
    leaked_overlay["worker_task_overlay"]["worker_spec_sha256"]=sha(context_leak)
    blocked(lambda:checked_adapt(context_leak,owner_commands=commands,pg07_overlay=leaked_overlay),
            "ORACLE_OR_SECRET_IN_CONTEXT")
    for field in ("context_path_patterns","write_path_patterns","protected_path_patterns"):
        bad=copy.deepcopy(pg07)
        bad[field]=["tests/protected/"]
        mapped=copy.deepcopy(overlay)
        mapped["worker_task_overlay"]["worker_spec_sha256"]=sha(bad)
        blocked(lambda b=bad,m=mapped:checked_adapt(b,owner_commands=commands,pg07_overlay=m),
                "ADAPTER_PATH_NOT_CANONICAL")
    bad_wildcard=copy.deepcopy(pg07)
    bad_wildcard["context_path_patterns"]=["src/**foo/bar.py"]
    mapped=copy.deepcopy(overlay)
    mapped["worker_task_overlay"]["worker_spec_sha256"]=sha(bad_wildcard)
    blocked(lambda:checked_adapt(bad_wildcard,owner_commands=commands,pg07_overlay=mapped),
            "ADAPTER_PATH_NOT_CANONICAL")
    print("PASS Worker original canonical path functions reject trailing slash and malformed **")
    modified={**task,"extra_elevated_authority":True}
    try:parse_task(modified)
    except ValueError:print("PASS Worker original rejects additional field")
    else:raise AssertionError("Original Worker accepted extra")
    changed=copy.deepcopy(pg07)
    changed["acceptance_commands"][0]="python -m pytest | tee /tmp/x"
    blocked(lambda:checked_adapt(changed,owner_commands=commands,
                          pg07_overlay={**overlay,"worker_task_overlay":{"worker_spec_sha256":sha(changed),
                          "write_scope":changed["write_path_patterns"]}}),"ACCEPTANCE_SHELL_OR_AMBIGUOUS")
    bad=copy.deepcopy(pg07);del bad["max_attempts"]
    blocked(lambda:checked_adapt(bad,owner_commands=commands,pg07_overlay=overlay),"PG07_TASK_INCOMPLETE")
    for k in ("max_attempts","max_context_bytes","max_patch_bytes","max_changed_files"):
        incomplete=copy.deepcopy(pg07);del incomplete[k]
        blocked(lambda b=incomplete:checked_adapt(b,owner_commands=commands,pg07_overlay=overlay),
                "PG07_TASK_INCOMPLETE")
        bad=copy.deepcopy(pg07);bad[k]={"max_attempts":2,"max_context_bytes":60001,
                           "max_patch_bytes":20001,"max_changed_files":4}[k]
        bad_overlay=copy.deepcopy(overlay)
        bad_overlay["worker_task_overlay"]["worker_spec_sha256"]=sha(bad)
        blocked(lambda b=bad,o=bad_overlay:checked_adapt(b,owner_commands=commands,pg07_overlay=o),
                "PILOT_LIMIT_MISSING_OR_EXCEEDED:"+k)
    no_metadata=copy.deepcopy(pg07)
    blocked(lambda:checked_adapt(no_metadata,pg07_overlay=overlay),"ACCEPTANCE_COMMAND_METADATA_MISSING")
    oversized=copy.deepcopy(pg07)
    oversized["objective"]="X"*20000
    over=copy.deepcopy(overlay);over["worker_task_overlay"]["worker_spec_sha256"]=sha(oversized)
    blocked(lambda:checked_adapt(oversized,owner_commands=commands,pg07_overlay=over),"OBJECTIVE_RULES_TOO_LARGE")
    receipt={"schema_version":1,"receipt_sha256":"a"*64,"model_provider":"anthropic",
             "requested_model":"claude-haiku-5-5","resolved_model":"claude-haiku-5-5",
             "attempts":[{"attempt":1,"usage":{"input_tokens":1000,"output_tokens":2000}}]}
    priced=price_receipt(receipt)
    check(priced["total_input_tokens"]==1000 and priced["total_output_tokens"]==2000
          and priced["total_estimated_usd"]=="0.0011",
          "Cost: external USD estimate inaccurate")
    check("total_estimated_usd" not in receipt and "total_input_tokens" not in receipt,
          "Sealed receipt modified by cost")
    no_usage=copy.deepcopy(receipt)
    no_usage["attempts"][0]["usage"]={}
    blocked(lambda:price_receipt(no_usage),"USAGE_INPUT_OUTPUT_TOKENS_MISSING")
    print("PASS cost separately computed from actual-shaped usage for assumed prices")
    with tempfile.TemporaryDirectory() as d:
        outside=Path(d)/"outside"
        blocked(lambda:materialize_external(repo_root=STAGES,outside_dir=outside,
               worker_checkout=Path(checkout),task=task,envelope=envelope,
               owner_quality_plan=None,owner_readback_manifest=None,
               owner_hidden_oracle=None),"OWNER_MANIFEST_MISSING")
        check(not outside.exists(),"Created manifest despite missing owner provenance")
    with tempfile.TemporaryDirectory() as d:
        # Dummy content ONLY checks CLI argv construction; no false manifest
        # acceptance claim, and absolutely no invocation of that argv.
        q=Path(d)
        (q/"task.v1.json").write_text(json.dumps(task),encoding="utf-8")
        (q/"extra.envelope.json").write_text(json.dumps(envelope),encoding="utf-8")
        for name in ("quality-plan.json","readback-manifest.json","holdout.oracle.json"):
            (q/name).write_text("{}",encoding="utf-8")
        argv=build_worker_command(repo_path=STAGES,output_dir=q,worker_checkout=Path(checkout))
        check(argv[argv.index("--max-output-tokens")+1]=="8000" and
              argv[argv.index("--provider")+1]=="anthropic" and
              argv[argv.index("--model")+1]=="claude-haiku-5-5" and
              all("API_KEY" not in a and "secret" not in a.lower() for a in argv),
              "Unsafe or unbounded CLI arguments")
        print("PASS generated CLI args bound to Haiku and 8000 output tokens (NOT RUN)")
    print("PASS no fabricated quality/oracle/readback manifest")
    print("PASS PG07_TO_WORKER_V1_ADAPTER_NO_MODEL_NO_SECRET")
if __name__=="__main__":
    try:run()
    except Exception as exc:
        print("FAIL",type(exc).__name__,str(exc),file=sys.stderr)
        raise SystemExit(1)
