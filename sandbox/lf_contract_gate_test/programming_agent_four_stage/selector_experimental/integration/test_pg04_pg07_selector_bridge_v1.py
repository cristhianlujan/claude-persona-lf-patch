#!/usr/bin/env python3
"""Independent local-only PG04-PG07 selector bridge tests (PostgreSQL disposable).
Leaves original/ and tests/test_parity.py untouched. The runner uses original SQL.
"""
import copy
import json
import os
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tests"))
sys.path.insert(0,str(Path(__file__).resolve().parent))
from test_experimental import guard, call, run_psql, sql_json, lit, reference
from test_parity import TABLES,FUNCTIONS
from pg05_profile_assignment_bridge_v1 import (
  BridgeBlocked,digest,declare_pg04_areas,pg04_area_lot,assign_pg05,pg06_currentness,pg07_worker_projection)

def check(x,label):
    if not x:raise AssertionError(label)

def failcode(fn,code):
    try: fn()
    except BridgeBlocked as e:
        check(str(e)==code,f"Expected {code}, got {e}")
        print("PASS blocked",code)
        return
    raise AssertionError("Expected rejection: "+code)

def frozen(record):
    o=copy.deepcopy(record)
    o["candidate_sha256"]=digest(o)
    return o

def sql_bridge(dsn):
    def prepare(request,project,area,paths):
        return call(dsn,"public.lf_profile_selector_semantic_prepare_v3_exp("+
                    ",".join([lit(request),lit(project),lit(area),sql_json(paths)])+")")
    def finalize(request,draft):
        return call(dsn,"public.lf_profile_selector_semantic_finalize_v2_exp("+
                    sql_json(request)+","+sql_json(draft)+")")
    return prepare,finalize

def fixture(path="src/main/java/com/lf/Loan.java",solution="SOL-001"):
    exit=frozen({"schema_version":"PG04_TO_PG05_EXIT_CANDIDATE_V1",
                 "status":"CANDIDATE_NOT_ADMITTED","production_authority":False,
                 "handoff_allowed":False,"solutions":[{"solution_id":solution,
                 "write_scope_candidates":["write-token-backend"]}]})
    c2=frozen({"schema_version":"PG05_C2_WRITE_SCOPE_RESOLUTION_CANDIDATE_V1",
              "status":"CANDIDATE_NOT_ADMITTED","production_authority":False,
              "write_scope_authorized":False,"source_pg04_exit_sha256":exit["candidate_sha256"],
              "solution_scopes":[{"solution_id":solution,"write_authorized":False,
                                 "write_resource_keys":[{"kind":"REPO_PATH","identity":path}]}]})
    return exit,c2

def draft_for_code(request,code):
    p=next(p for p in request["candidate_profiles"] if p["profile_code"]==code)
    evidence=p["descriptor"]["selection_evidence"][0]
    return {"decision":"SELECTED","selected_profile_code":code,
            "ambiguous_profile_codes":[],"material_ambiguities":[],
            "reason":"Elección semántica de ensayo",
            "evidence_refs":[{"profile_code":code,"kind":evidence["kind"],
                              "source_section":evidence["source_section"]}]}

def test_chain(dsn):
    prepare,finalize=sql_bridge(dsn)
    exit,c2=fixture()
    path="src/main/java/com/lf/Loan.java"
    project_rules=call(dsn,"coalesce((SELECT jsonb_agg(jsonb_build_object('area',area,'path_prefix',path_prefix) ORDER BY area,path_prefix) FROM public.lf_project_area_pattern_exp WHERE project_ref='lf_java'),'[]'::jsonb)")
    pg04_areas=declare_pg04_areas(pg04_exit=exit,project_ref="lf_java",project_rules=project_rules,
                    lot_declarations=[{"solution_id":"SOL-001","area":"BACKEND","paths":[path]}])
    failcode(lambda:declare_pg04_areas(pg04_exit=exit,project_ref="lf_java",project_rules=project_rules,
                    lot_declarations=[{"solution_id":"SOL-001","area":"BACKEND",
                                       "paths":[path,"web/src/app/loan.ts"]}]),"LOTE_MULTI_AREA")
    failcode(lambda:declare_pg04_areas(pg04_exit=exit,project_ref="lf_java",project_rules=project_rules,
                    lot_declarations=[{"solution_id":"SOL-001","area":"FRONTEND","paths":[path]}]),
             "LOTE_AREA_MISMATCH")
    conflicted=project_rules+[{"area":"FRONTEND","path_prefix":"src/main/java/"}]
    failcode(lambda:declare_pg04_areas(pg04_exit=exit,project_ref="lf_java",project_rules=conflicted,
                    lot_declarations=[{"solution_id":"SOL-001","area":"BACKEND","paths":[path]}]),
             "LOTE_ROUTE_CONFLICT")
    print("PASS PG04 declared areas, mixed lot and route conflict controls")
    lot=pg04_area_lot(pg04_exit=exit,pg05_c2=c2,pg04_areas=pg04_areas,solution_id="SOL-001",area="BACKEND",paths=[path])
    print("PASS PG04 explicit area, exact PG05 C2 scope binding")
    failcode(lambda:pg04_area_lot(pg04_exit=exit,pg05_c2=c2,pg04_areas=pg04_areas,solution_id="SOL-001",
                                 area="BACKEND",paths=["web/src/app/x.ts"]),
             "PG04_AREA_LOT_DRIFT")
    failcode(lambda:pg04_area_lot(pg04_exit=exit,pg05_c2=c2,pg04_areas=pg04_areas,solution_id="SOL-001",
                                 area="BACKEND",paths=[path,"web/src/app/x.ts"]),
             "PG04_AREA_LOT_DRIFT")
    out_scope="src/main/java/com/lf/Outside.java"
    scope_overlay=declare_pg04_areas(pg04_exit=exit,project_ref="lf_java",project_rules=project_rules,
                    lot_declarations=[{"solution_id":"SOL-001","area":"BACKEND","paths":[out_scope]}])
    failcode(lambda:pg04_area_lot(pg04_exit=exit,pg05_c2=c2,pg04_areas=scope_overlay,
                                  solution_id="SOL-001",area="BACKEND",paths=[out_scope]),
             "LOT_OUTSIDE_PG05_RESOLVED_SCOPE")
    req=prepare("Corregir servicio Spring","lf_java","BACKEND",[path])["request"]
    general="PERFIL-PROG-BACKEND-EXP"
    spring="PERFIL-PROG-BACKEND-SPRING-EXP"
    args={"lot":lot,"project_ref":"lf_java","literal_request":"Corregir servicio Spring",
          "prepare":prepare,"finalize":finalize}
    assignment=assign_pg05(**args,model_draft=draft_for_code(req,spring))
    check(assignment["status"]=="SELECTED" and assignment["profile_code"]==spring
          and assignment["production_authority"] is False,"Assignment not selected")
    check(assignment["catalog_sha256"]==req["catalog_sha256"],"Catalog digest drift")
    check(assignment["request_sha256"]==digest(req) and
          assignment["result_sha256"]==digest(assignment["result"]),"Unbound hashes")
    print("PASS PG05 SELECTED, three bound digests, no production authority")
    alternative=assign_pg05(**args,model_draft=draft_for_code(req,general))
    check(alternative["status"]=="SELECTED" and alternative["profile_code"]==general,
          "Alternative valid BACKEND must remain selectable")
    print("PASS PG05 second valid backend selected by fixed AI draft")
    amb={"decision":"AMBIGUOUS","selected_profile_code":None,
         "ambiguous_profile_codes":[general,spring],"reason":"Two candidates",
         "material_ambiguities":[{"reason":"Both backend"}],
         "evidence_refs":[v for c in (general,spring)
                          for v in draft_for_code(req,c)["evidence_refs"]]}
    check(assign_pg05(**args,model_draft=amb)["status"]=="REQUIRES_HUMAN_DECISION",
          "Ambiguous must stop")
    no={"decision":"NO_MATCH","selected_profile_code":None,"ambiguous_profile_codes":[],
        "reason":"No suitable profile","material_ambiguities":[],"evidence_refs":[]}
    check(assign_pg05(**args,model_draft=no)["status"]=="REQUIRES_HUMAN_DECISION",
          "No match must stop")
    print("PASS PG05 AMBIGUOUS and NO_MATCH human stop")
    wrong=assign_pg05(**args,model_draft=draft_for_code(
       prepare("Frontend","lf_java","FRONTEND",["web/src/app/x.ts"])["request"],
       "PERFIL-PROG-FRONTEND-EXP"))
    check(wrong["status"]=="BLOCKED","Wrong area selected")
    print("PASS wrong-area selected BLOCKED")
    elevated=draft_for_code(req,spring)
    elevated["production_authority"]=True
    check(assign_pg05(**args,model_draft=elevated)["status"]=="BLOCKED",
          "Rehashed authority injection accepted")
    print("PASS authority injection BLOCKED despite regenerated receipt hash")
    current=pg06_currentness(assignment=assignment,lot=lot,prepare=prepare,finalize=finalize)
    check(current["status"]=="CURRENT","PG06 currentness failed")
    print("PASS PG06 reprepare and sealed result revalidation")
    tampered=copy.deepcopy(assignment);tampered["profile_code"]=general
    failcode(lambda:pg06_currentness(assignment=tampered,lot=lot,prepare=prepare,finalize=finalize),
             "SOURCE_DIGEST_INVALID")
    tampered=copy.deepcopy(assignment);tampered["production_authority"]=True
    tampered["assignment_sha256"]=digest({k:v for k,v in tampered.items() if k!="assignment_sha256"})
    failcode(lambda:pg06_currentness(assignment=tampered,lot=lot,prepare=prepare,finalize=finalize),
             "ASSIGNMENT_SCOPE_OR_AUTHORITY_INVALID")
    # Simulate stale areas/route/descriptor, restore in the disposable DB.
    for sql,undo,reason in [
       ("UPDATE public.lf_profile_area_policy_exp SET areas='[\"FRONTEND\"]'::jsonb WHERE profile_code="+lit(spring),
        "UPDATE public.lf_profile_area_policy_exp SET areas='[\"BACKEND\"]'::jsonb WHERE profile_code="+lit(spring),"area"),
       ("INSERT INTO public.lf_project_area_pattern_exp(project_ref,area,path_prefix) VALUES ('lf_java','BACKEND','server/src/')",
        "DELETE FROM public.lf_project_area_pattern_exp WHERE project_ref='lf_java' AND path_prefix='server/src/'","routes"),
       ("UPDATE public.lf_profile_selection_registry_v1 SET descriptor_status='STALE_SOURCE_CHANGED' WHERE profile_code="+lit(spring),
        "UPDATE public.lf_profile_selection_registry_v1 SET descriptor_status='CURRENT' WHERE profile_code="+lit(spring),"descriptor")]:
        run_psql(dsn,sql=sql)
        try:
            failcode(lambda:pg06_currentness(assignment=assignment,lot=lot,prepare=prepare,finalize=finalize),
                     "PG06_SELECTOR_POLICY_OR_CATALOG_STALE")
        finally:run_psql(dsn,sql=undo)
        print("PASS PG06 changed",reason,"blocked")
    spec={"schema_version":2,"task_id":"trial-only","objective":"Modify Loan.java",
          "write_path_patterns":[path],"protected_path_patterns":[]}
    out=pg07_worker_projection(assignment=assignment,lot=lot,
                               currentness=current,worker_spec=spec)
    task=out["worker_task_overlay"];receipt=out["receipt_link_candidate"]
    check(task["profile_code"]==spring and task["write_scope"]==[path] and
          task["profile_assignment_sha256"]==assignment["assignment_sha256"] and
          receipt["profile_assignment_sha256"]==assignment["assignment_sha256"] and
          receipt["worker_receipt_verified"] is False and
          out["worker_invoked"] is False and out["production_authority"] is False,
          "PG07 chain not intact")
    print("PASS PG07 scoped worker task and candidate receipt digest chain")
    failcode(lambda:pg07_worker_projection(assignment=assignment,lot=lot,
               currentness=current,worker_spec={"schema_version":2,"oracle_envelope":{}}),
             "PG07_ORACLE_EXPOSURE")
    failcode(lambda:pg07_worker_projection(assignment=assignment,lot=lot,
               currentness=current,worker_spec={"schema_version":2,
               "write_path_patterns":[path,"src/main/java/com/lf/Unexpected.java"]}),
             "PG07_WORKER_SPEC_SCOPE_EXCEEDS_ASSIGNMENT")
    print("PASS PG07 Worker-visible write scope cannot expand outside PG05 C2")

    # PG04-mixed projects are also blocked by the actual SQL classifier.
    mixed=prepare("Split or block","lf_java","BACKEND",
                  [path,"web/src/app/loan.ts"])
    check(mixed.get("blocking_code")=="LOTE_MULTI_AREA_BLOCKED","Mixed-area PG04 lot accepted")
    print("PASS PG04 mixed area LOTE_MULTI_AREA_BLOCKED")

def main():
    dsn=os.environ.get("SELECTOR_EXP_TEST_DSN","")
    guard(dsn)
    try:
        run_psql(dsn,file=ROOT/"original/schema/bootstrap.sql")
        run_psql(dsn,file=ROOT/"original/schema/tables.sql")
        run_psql(dsn,file=ROOT/"original/schema/constraints.sql")
        for t in TABLES:run_psql(dsn,file=ROOT/"original/data"/(t+".sql"))
        for f in FUNCTIONS:run_psql(dsn,file=ROOT/"original/functions"/f)
        reference(dsn)
        for f in ("seed_profiles_exp.sql","area_policy_exp.sql","functions_exp.sql"):
            run_psql(dsn,file=ROOT/"experimental"/f)
        test_chain(dsn)
    finally:
        run_psql(dsn,sql="DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public; DROP SCHEMA IF EXISTS extensions CASCADE")
        left=run_psql(dsn,sql="SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','extensions') AND c.relkind IN ('r','p','v','m')")
        check(left=="0","Residual tables/views: "+left)
        check(run_psql(dsn,sql="SELECT count(*) FROM pg_namespace WHERE nspname='extensions'")=="0",
              "Residual extensions schema")
        print("PASS cleanup 0 residual schemas/objects")
    print("PASS PG04_TO_PG07_BRIDGE_CANDIDATE_V1")

if __name__=="__main__":
    try:main()
    except Exception as exc:
        print("FAIL",repr(exc),file=sys.stderr)
        raise SystemExit(1)
