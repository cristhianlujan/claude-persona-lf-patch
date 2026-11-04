#!/usr/bin/env python3
"""Independent PG stage/checkpoint diagnostic switches. NEVER production admission.

ON=simulate a candidate check; OFF=bypass diagnostics only; FAULT=inject a block.
Existing producer tests may be invoked separately, never as proof of authority.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

SCHEMA="LF_PG_DIAGNOSTIC_SWITCHBOARD_V1"
COUNTS={1:7,2:5,3:10,4:7,5:5,6:5,7:6,8:8,9:5,10:5,11:5,12:4,13:3,14:3}
STAGES=tuple(f"PG-{n:02d}" for n in COUNTS)
CHECKPOINTS=tuple(f"PG-{n:02d}_C{k}" for n,c in COUNTS.items() for k in range(1,c+1))
MODES=("ON","OFF","FAULT")
NAMES=("Admisión y contexto","Clasificación","Estrategia técnica","Lotes",
       "Alcance de escritura","Entorno","Worker","Calidad","Iteraciones",
       "Conflictos","Diff y revisión","Manifiesto","Freeze","Testing local")
SUITES={
 4:("pg04_semantic_partition_candidate","test_pg04_*.py"),
 5:("pg05_target_binding_candidate","test_pg05_chain_c1_c5_v1.py"),
 6:("pg06_preflight_candidate","test_pg06_c1_c5_chain_v1.py"),
 7:("pg07_worker_candidate","test_pg07_c1_c6_chain_v1.py"),
 8:("pg08_build_candidate","test_pg08_full_chain_v1.py"),
 9:("pg09_iteration_candidate","test_pg09_iteration_chain_v1.py"),
 10:("pg10_conflict_candidate","test_pg10_decision_chain_v1.py"),
 11:("pg11_integrity_candidate","test_pg11_integrity_chain_v1.py"),
 12:("pg12_identity_candidate","test_pg12_identity_chain_v1.py"),
 13:("pg13_freeze_candidate","test_pg13_freeze_chain_v1.py"),
 14:("pg14_testing_handoff_candidate","test_pg14_final_chain_v1.py")}
def digest(obj):
    return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(",",":"),
        ensure_ascii=True).encode()).hexdigest()
def default():
    return {"schema_version":SCHEMA,"mode":"SYNTHETIC_TEST","simulation_only":True,
      "case_id":"SOL-TEST-001","defaults":"ON",
      "stage_overrides":{},"checkpoint_overrides":{},
      "fixture":{"objective":"Filtro status para GET /users",
         "target":"fixture://fastapi/users","analysis_ready_authentic":False}}
def validate(c):
    if not isinstance(c,dict) or c.get("schema_version")!=SCHEMA or c.get("mode")!="SYNTHETIC_TEST" or c.get("simulation_only") is not True:
        raise ValueError("SWITCHBOARD_SYNTHETIC_ONLY")
    if c.get("defaults") not in MODES or not isinstance(c.get("case_id"),str) or not c["case_id"].strip():
        raise ValueError("SWITCHBOARD_CONFIG_INVALID")
    if not isinstance(c.get("fixture"),dict) or c["fixture"].get("analysis_ready_authentic") is not False:
        raise ValueError("SWITCHBOARD_AUTHORITY_FORBIDDEN")
    for key,known in (("stage_overrides",set(STAGES)),("checkpoint_overrides",set(CHECKPOINTS))):
        values=c.get(key)
        if not isinstance(values,dict) or not set(values).issubset(known) or any(v not in MODES for v in values.values()):
            raise ValueError("SWITCHBOARD_UNKNOWN_SWITCH")
def mode(c,stage,cp):
    return c["checkpoint_overrides"].get(cp,c["stage_overrides"].get(stage,c["defaults"]))
def run(c):
    validate(c)
    previous=digest({"case_id":c["case_id"],"fixture":c["fixture"],"synthetic":True})
    stages=[];checks=[];blocker=None
    for n,count in COUNTS.items():
        stage=f"PG-{n:02d}";before=len(checks)
        for index in range(1,count+1):
            cp=f"{stage}_C{index}";selected=mode(c,stage,cp)
            if blocker:status,reason="NOT_REACHED","BLOCKED_BY_UPSTREAM:"+blocker
            elif selected=="FAULT":
                status,reason="BLOCKED_SYNTHETIC","INJECTED_FAULT:"+cp
                blocker=cp
            elif selected=="OFF":status,reason="BYPASSED_DIAGNOSTIC","NOT_EXECUTED_NOT_PASSED"
            else:status,reason="SIMULATED_CANDIDATE","FIXTURE_ONLY_NO_AUTHORITY"
            row={"stage":stage,"checkpoint":cp,"switch":selected,"status":status,
                 "reason_code":reason,"input_sha256":previous,"production_authority":False,
                 "handoff_allowed":False,"real_runtime_executed":False,"receipt_verified":False}
            row["trace_sha256"]=digest(row)
            previous=row["trace_sha256"];checks.append(row)
        rows=checks[before:]
        s="BLOCKED_SYNTHETIC" if any(r["status"]=="BLOCKED_SYNTHETIC" for r in rows) else (
            "NOT_REACHED" if all(r["status"]=="NOT_REACHED" for r in rows) else (
            "DIAGNOSTIC_BYPASS_PRESENT" if any(r["status"]=="BYPASSED_DIAGNOSTIC" for r in rows) else "SIMULATED_CANDIDATE"))
        stages.append({"stage":stage,"title":NAMES[n-1],"status":s,
            "output_trace_sha256":previous,"producer_executed":False,"real_authority":False})
    result={"schema_version":"LF_PG_DIAGNOSTIC_TRACE_V1","mode":"SYNTHETIC_TEST",
      "case_id":c["case_id"],"stage_count":len(stages),"checkpoint_count":len(checks),
      "stages":stages,"checkpoints":checks,"first_blocker":blocker,
      "all_stages_reached":blocker is None,
      "any_bypass":any(r["status"]=="BYPASSED_DIAGNOSTIC" for r in checks),
      "source_authenticity":"SYNTHETIC_NOT_ATTESTED",
      "analysis_ready_verified":False,"worker_real_invoked":False,
      "testing_real_invoked":False,"independent_judge_executed":False,
      "admission_allowed":False,"checkpoint_closure_allowed":False,
      "handoff_allowed":False,"production_authority":False}
    result["report_sha256"]=digest(result)
    return result
def run_tests(c,repo_root):
    """Optional existing candidate unittests; NOT independent checkpoint proof."""
    base=Path(repo_root)/"sandbox/lf_contract_gate_test/programming_agent_four_stage"
    answers=[]
    for n,count in COUNTS.items():
        stage=f"PG-{n:02d}";row={"stage":stage,"source_suite_status":"NOT_RUN","production_authority":False}
        if any(mode(c,stage,f"{stage}_C{i}")!="ON" for i in range(1,count+1)):
            row["reason"]="BYPASS_OR_FAULT_CONFIGURED"
        elif n not in SUITES:row["reason"]="NO_STAGE_SUITE_DEFINED"
        else:
            folder,pattern=SUITES[n];path=base/folder
            if not (path/"tests").is_dir():row["reason"]="CHECKOUT_SUITE_NOT_PRESENT"
            else:
                try:
                    proc=subprocess.run([sys.executable,"-m","unittest","discover",
                       "-s","tests","-p",pattern,"-v"],cwd=path,
                       capture_output=True,text=True,timeout=120)
                    row.update(source_suite_status="PASS" if proc.returncode==0 else "FAIL",
                       return_code=proc.returncode,stdout_tail=proc.stdout[-1000:],
                       stderr_tail=proc.stderr[-3000:])
                except subprocess.TimeoutExpired:row["source_suite_status"]="TIMEOUT"
        answers.append(row)
    return answers
def main(argv=None):
    p=argparse.ArgumentParser(description="LF switches PG01-PG14, synthetic-only")
    p.add_argument("--config",type=Path)
    p.add_argument("--stage",action="append",default=[])
    p.add_argument("--checkpoint",action="append",default=[])
    p.add_argument("--all",choices=MODES)
    p.add_argument("--run-tests",action="store_true")
    p.add_argument("--repo-root",type=Path,default=Path.cwd())
    p.add_argument("--output",type=Path)
    a=p.parse_args(argv)
    c=json.loads(a.config.read_text()) if a.config else default()
    if a.all:c["defaults"]=a.all
    for flag,key in (("stage","stage_overrides"),("checkpoint","checkpoint_overrides")):
        for v in getattr(a,flag):
            if v.count("=")!=1:p.error("Expected NAME=ON|OFF|FAULT")
            name,selected=v.split("=",1)
            c[key][name]=selected
    result=run(c)
    if a.run_tests:result["source_candidate_unit_suites"]=run_tests(c,a.repo_root)
    result["report_sha256"]=digest({k:v for k,v in result.items() if k!="report_sha256"})
    data=json.dumps(result,indent=2,ensure_ascii=False)+"\n"
    if a.output:a.output.write_text(data,encoding="utf-8")
    print(data)
if __name__=="__main__":main()
