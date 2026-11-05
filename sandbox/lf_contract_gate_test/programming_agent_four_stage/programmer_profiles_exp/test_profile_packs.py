#!/usr/bin/env python3
"""Sandbox pack gates, four project stack skills, and actual PG07-C2 worker spec acceptance.
No Supabase, no DB writes, no model invocation or Worker execution.
"""
import copy,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
STAGES=ROOT.parent
sys.path.insert(0,str(ROOT))
sys.path.insert(0,str(STAGES/"selector_experimental"/"integration"))
sys.path.insert(0,str(STAGES/"pg07_worker_candidate"/"tools"))
from pack_validation_common import check_pack,evaluate
from selector_descriptor_from_skill import SLUGS,descriptor
from stack_skills_exp.project_stack_resolver_exp import (
    load_json,skill_material,role_material,select_binding,compose_visible_worker_spec,validate_visible_skill_rules,StackBlocked)
from test_pg04_pg07_selector_bridge_v1 import real_producers,real_pg07_validation

def check(v,reason):
    if not v:raise AssertionError(reason)
def fixture_binding(project,area):
    rows=[]
    for r in load_json("project_stack_binding_fixtures.json")["rows"]:
        if r["project_ref"]==project and r["area"]==area:
            rows.append({**r,"skill_sha256":skill_material(r["skill_code"],r["skill_version"])["skill_sha256"]})
    return select_binding(project,area,lambda _p,_a:rows)
def expect_error(fn,code):
    try:fn()
    except StackBlocked as exc:
        check(str(exc)==code,repr((str(exc),code)))
        print("PASS BLOCK",code)
        return
    raise AssertionError("Expected "+code)
def run():
    chain=real_producers()
    c2=chain["c2"]
    sid=sorted(x["solution_id"] for x in c2["solution_scopes"])[-1]
    for slug in SLUGS:
        pack=ROOT/slug
        errors=check_pack(pack)
        check(not errors,slug+" "+repr(errors))
        print("PASS PROFILE_PACK",slug)
        ev=evaluate(pack)
        check(len(ev)==7 and all(v for _,v in ev),slug+" "+repr(ev))
        for k,v in ev:print("PASS ROLE_EVAL",slug,k)
        d=descriptor(slug)
        check(d["schema_version"]=="LF_PROFILE_SELECTION_DESCRIPTOR_V1","Descriptor schema")
        print("PASS SKILL_SOURCE_DESCRIPTOR",slug)
        sample=json.loads((pack/"examples/good_output.json").read_text())
        task=json.loads((pack/"fixtures/happy_path/input.json").read_text())
        profile=task["profile_code"]
        role=role_material(profile)
        projects=["lf_java","lf_python"] if role["area"]=="BACKEND" else ["lf_java"]
        for project in projects:
            skill=fixture_binding(project,role["area"])
            assignment={"profile_code":profile,"area":role["area"],"project_ref":project}
            def transform(raw):
                spec=copy.deepcopy(sample)
                for k in ("task_id","base_head_sha","source_snapshot_sha256","context_path_patterns","write_path_patterns","files_expected"):
                    spec[k]=copy.deepcopy(raw[k])
                spec["scope"]["in_scope"]=copy.deepcopy(raw["write_path_patterns"])
                return compose_visible_worker_spec(spec,assignment,role,skill)
            visible,real_c2,c1=real_pg07_validation(chain,c2,sid,return_c1=True,spec_transform=transform)
            rules=visible["functional_contract"]["role_and_stack"]
            check(rules["profile_sha256"]==role["profile_sha256"] and
                  rules["skill_sha256"]==skill["skill_sha256"] and
                  rules["skill_code"]==skill["skill_code"] and
                  rules["project_ref"]==project and
                  rules["skill_set_sha256"]==skill["skill_set_sha256"] and
                  len(rules["skills"])==len(skill["skills"]) and
                  all(len(x["expert_rules"])>=3 for x in rules["skills"]),"C2 missing source identity/rules")
            check(validate_visible_skill_rules(visible,skill),"Worker expert rule gate failed")
            tampered_two=copy.deepcopy(visible)
            tampered_two["functional_contract"]["role_and_stack"]["skills"][0]["expert_rules"] = (
                tampered_two["functional_contract"]["role_and_stack"]["skills"][0]["expert_rules"][:2])
            expect_error(lambda:validate_visible_skill_rules(tampered_two,skill),"WORKER_SKILL_RULES_TOO_FEW")
            tampered_rule=copy.deepcopy(visible)
            tampered_rule["functional_contract"]["role_and_stack"]["skills"][0]["expert_rules"][0]["source_url"]="https://example.invalid/fake"
            expect_error(lambda:validate_visible_skill_rules(tampered_rule,skill),"WORKER_SKILL_RULE_SOURCE_MISMATCH")
            print("PASS Worker >=3 official sourced rules for every priority-bound skill",project)
            check(real_c2["dispatch_allowed"] is False and
                  real_c2["production_authority"] is False,"C2 premature authority")
            print("PASS REAL_PG07_C2_ROLE_STACK",slug,project,skill["skill_code"])
    backend=role_material("PERFIL-PROG-BACKEND-EXP")
    java=fixture_binding("lf_java","BACKEND")
    py=fixture_binding("lf_python","BACKEND")
    check(java["skill_code"]=="SPRINGBOOT_EXP" and py["skill_code"]=="FASTAPI_EXP","Project-bound backend skill drift")
    check(backend["profile_code"]=="PERFIL-PROG-BACKEND-EXP","Same role not reused")
    check([x["skill_code"]+"@"+x["skill_version"] for x in java["skills"]]==["SPRINGBOOT_EXP@3","KAFKA_EXP@3"],"Priority did not order Spring/Kafka")
    print("PASS MULTI_STACK_PRIORITY SpringBoot@3 > Kafka@3")
    print("PASS SAME_BACKEND_ROLE_TWO_PROJECT_STACKS")
    expect_error(lambda:fixture_binding("lf_python","FRONTEND"),"SKILL_NOT_BOUND")
    badrow={**java["binding_row"],"skill_sha256":"0"*64}
    expect_error(lambda:select_binding("lf_java","BACKEND",lambda p,a:[badrow]),"SKILL_SHA256_MISMATCH")
    no_priority=[{**x["binding_row"]} for x in java["skills"]]
    no_priority[1]["priority"]=None
    expect_error(lambda:select_binding("lf_java","BACKEND",lambda p,a:no_priority),"SKILL_PRIORITY_REQUIRED")
    duplicate_priority=[{**x["binding_row"]} for x in java["skills"]]
    duplicate_priority[1]["priority"]=duplicate_priority[0]["priority"]
    expect_error(lambda:select_binding("lf_java","BACKEND",lambda p,a:duplicate_priority),"SKILL_PRIORITY_CONFLICT")
    wrong_version={**java["binding_row"],"skill_version":"2"}
    expect_error(lambda:select_binding("lf_java","BACKEND",lambda p,a:[wrong_version]),"SKILL_VERSION_MISMATCH")
    print("PASS VERSIONED MULTI-SKILL PRIORITY NEGATIVES")
    fe=fixture_binding("lf_java","FRONTEND")
    badarea={**java["binding_row"],"skill_code":fe["skill_code"],"skill_version":fe["skill_version"],"skill_sha256":fe["skill_sha256"]}
    expect_error(lambda:select_binding("lf_java","BACKEND",lambda p,a:[badarea]),"SKILL_AREA_MISMATCH")
    for entry in load_json("skill_catalog_exp.json")["skills"]:
        m=skill_material(entry["skill_code"],entry["version"])
        check(len(m["skill_sha256"])==64,"Missing stack SHA")
        check(m["area"]==entry["area"],"Stack area drift")
        check(m["skill_text"].count("https://")>=3,"Stack source missing")
        check(len(m["expert_rules"])>=3,"Less than three expert rules")
        check(m["pg00_standard_family"] if "pg00_standard_family" in m else m["standard_family"]==entry["standard_family"],"Standard reference missing")
        print("PASS STACK_SKILL_SOURCE",entry["skill_code"])
    print("PASS ROLE_STACK_SANDBOX_CANDIDATES; PG00 normative text unresolved -> NO PRODUCTION")
if __name__=="__main__":
    try:run()
    except Exception as exc:
        print("FAIL",type(exc).__name__,str(exc),file=sys.stderr)
        raise SystemExit(1)
