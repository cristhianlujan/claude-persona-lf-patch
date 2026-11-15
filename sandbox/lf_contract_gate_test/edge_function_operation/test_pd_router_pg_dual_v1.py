"""PG17/PG18 isolated, rollback-only PD -> ACT-0001 -> Reparador -> Quality gates.

Uses SQL preimages read from sandbox, synthetic source runs and real PostgreSQL
function execution. It never calls Supabase or invokes an external model.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIG=ROOT/"supabase/migrations/20261115010000_lf_pd_solution_executor_before_quality_v1.sql"
FIX=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures/lf_pd_router_contract_preimage_20261114.sql"
REQUEST="Entra por el router y revisa las reglas de carga masiva del b2b"

def sql_str(s):
    return "'"+s.replace("'","''")+"'"

def psql(name, sql, good=True):
    r=subprocess.run(
        ["docker","exec","-i",name,"psql","-X","-A","-t",
         "-U","postgres","-d","postgres","-v","ON_ERROR_STOP=1"],
        input=sql,capture_output=True,text=True,timeout=120)
    if good and r.returncode!=0:
        raise AssertionError("POSTGRES_SQL_FAILED: "+r.stderr[-5000:])
    if not good and r.returncode==0:
        raise AssertionError("NEGATIVE_PROBE_UNEXPECTEDLY_SUCCEEDED")
    return r.stdout.strip()

SAMPLE_PD=json.dumps({
    "output_type":"PRODUCT_DIRECTION_SPEC",
    "self_verdict":"PASS",
    "deliverable_created":{"blockers":["missing implementation"],
                           "handoff_to_next":{"target":"PERFIL-QUALITY-PACK"}}
},separators=(",",":"))

SAMPLE_REPAIR=json.dumps({
    "status":"PASS","repair_execution":{
        "mode":"EXECUTED_WITH_READBACK",
        "returned_to_router":True,
        "promotion_performed":False,
        "authority_ref":"router://synthetic-governed-repair",
        "changes":[{"target":"synthetic-asset","status":"APPLIED_VERIFIED"}],
        "preserved_constraints":["no promotion"],
        "readback_refs":["synthetic://after"],
        "rollback_ref":"synthetic://rollback"}
},separators=(",",":"))

def seed_data():
    return f"""
    INSERT INTO public.lf_operation_execution(execution_id,operation_code,status,request_sha256,target_code,manifest)
    SELECT 'RUN-PD','EJECUCION_PERFIL_LF','COMPLETED',
      encode(extensions.digest(convert_to({sql_str(REQUEST)},'UTF8'),'sha256'),'hex'),
      'PERFIL-PRODUCT-DIRECTOR-LF','{{}}'::jsonb;
    INSERT INTO public.lf_operation_execution_steps
    VALUES('RUN-PD','execute_profile','STEP_PASS_WITH_EVIDENCE',
      jsonb_build_object('profile_output',{sql_str(SAMPLE_PD)}::jsonb));

    WITH ctx AS (
      SELECT encode(extensions.digest(convert_to({sql_str(REQUEST)},'UTF8'),'sha256'),'hex') sha
    ), core AS (
      SELECT sha,jsonb_build_object(
       'authority_ref','ROUTER_PROFILE_EXECUTION_AUTHORIZATION',
       'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
       'request_sha256',sha) AS auth FROM ctx
    )
    INSERT INTO public.lf_operation_execution(execution_id,operation_code,status,request_sha256,target_code,manifest)
    SELECT 'RUN-REPAIR','EJECUCION_PERFIL_LF','COMPLETED',sha,
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
      jsonb_build_object('router_profile_handoff',jsonb_build_object(
       'profile_code','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
       'request_sha256',sha,
       'return_to_router_after_profile_result',true,
       'semantic_result',jsonb_build_object('decision','RESOLVED',
          'positive_target_refs',jsonb_build_array('PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF')),
       'router_authorization_receipt',auth||jsonb_build_object(
          'fingerprint_sha256',encode(extensions.digest(convert_to(auth::text,'UTF8'),'sha256'),'hex')
       )))) FROM core;
    INSERT INTO public.lf_operation_execution_steps
    VALUES('RUN-REPAIR','execute_profile','STEP_PASS_WITH_EVIDENCE',
      jsonb_build_object('profile_output',{sql_str(SAMPLE_REPAIR)}::jsonb));
    INSERT INTO public.lf_operation_execution(execution_id,operation_code,status,request_sha256,target_code,manifest)
    SELECT 'RUN-SPOOF','EJECUCION_PERFIL_LF','COMPLETED',
      encode(extensions.digest(convert_to({sql_str(REQUEST)},'UTF8'),'sha256'),'hex'),
      'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','{{}}'::jsonb;
    INSERT INTO public.lf_operation_execution_steps
    VALUES('RUN-SPOOF','execute_profile','STEP_PASS_WITH_EVIDENCE',
      jsonb_build_object('profile_output',{sql_str(SAMPLE_REPAIR)}::jsonb));
    """

def catalogue_select(source):
    derived=(f"jsonb_build_object('source_execution_id',{sql_str(source)})"
             if source is not None else "NULL::jsonb")
    return (
        "SELECT jsonb_build_object("
        "'count',z.x->>'catalog_profile_count',"
        "'candidates',z.x->'candidate_profiles',"
        "'stage',z.x->'derivation_next_stage',"
        "'derivation',z.x->'derivation')"
        "FROM (SELECT public.lf_profile_selector_semantic_prepare_v2("
        f"{sql_str(REQUEST)},'PRODUCTO',{derived},NULL::jsonb) AS x) z"
        
    )

def run_probe(name, source):
    r=psql(name,catalogue_select(source)+";")
    return json.loads(r.splitlines()[-1])

class DualPostgresPDFlow(unittest.TestCase):
    def test_real_pg_functions_under_rollback(self):
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
        src=MIG.read_text(encoding="utf-8")
        self.assertIn("PD_EXECUTOR_SELECTOR_DERIVED_AUTH_DRIFT",src)
        self.assertTrue(src.startswith("-- Candidate ONLY:"))
        self.assertIn("\nBEGIN;\n",src)
        self.assertTrue(src.rstrip().endswith("COMMIT;"))
        body=src.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
        fixture=FIX.read_text(encoding="utf-8")
        for tag in ("17.6","18.7"):
            with self.subTest(postgres=tag):
                name="lf-pd-executor-"+uuid.uuid4().hex[:11]
                launched=subprocess.run([
                    "docker","run","-d","--rm","--name",name,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+tag
                ],capture_output=True,text=True,timeout=180)
                self.assertEqual(launched.returncode,0,launched.stderr[-1000:])
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                              capture_output=True,text=True,timeout=10)
                        if ready.returncode==0:
                            break
                        time.sleep(0.6)
                    self.assertEqual(ready.returncode,0,"POSTGRES_NOT_READY")
                    psql(name,fixture+"\n"+seed_data())
                    old_hash=psql(name,
                       "SELECT md5(pg_get_functiondef("
                       "'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure"
                       "));")
                    self.assertEqual(old_hash,"876a3ce6ffbb2d21a6a2d21372f459c9")
                    old_selector=psql(name,
                       "SELECT md5(pg_get_functiondef("
                       "'public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)'::regprocedure"
                       "));")
                    self.assertEqual(old_selector,"89bd02a1c46e41c156322ab9370b140b")
                    # SQL update and assertions run under transaction, never persist.
                    psql(name,"BEGIN;\n"+body+"\nCOMMIT;")
                    route=psql(name,
                       "SELECT public.lf_profile_result_router_return_classify_v1("
                       f"{sql_str(SAMPLE_PD)}::jsonb,{sql_str(REQUEST)},"
                       "'RUN-PD','PERFIL-PRODUCT-DIRECTOR-LF');")
                    decision=json.loads(route.splitlines()[-1])
                    self.assertEqual(decision["status"],"RETURN_TO_ROUTER")
                    self.assertEqual(decision["redirect_kind"],"PRODUCT_EXECUTOR_HANDOFF")
                    self.assertFalse(decision["router_return_request"]["direct_profile_invocation_allowed"])
                    self.assertEqual(decision["router_return_request"]["stage1_literal"],REQUEST)
                    # No stage1 derivation -> DIRECT product only.
                    direct=run_probe(name,None)
                    self.assertEqual([x["profile_code"] for x in direct["candidates"]],
                                     ["PERFIL-PRODUCT-DIRECTOR-LF"])
                    # Completed PD with no executable package => configured fallback ONLY.
                    repaired=run_probe(name,"RUN-PD")
                    self.assertEqual([x["profile_code"] for x in repaired["candidates"]],
                                     ["PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF"])
                    self.assertEqual(repaired["stage"]["phase"],"EXECUTOR_BEFORE_QUALITY")
                    self.assertFalse(repaired["stage"]["quality_allowed"])
                    # Completed Router-admitted repair with readbacks => Quality ONLY.
                    quality=run_probe(name,"RUN-REPAIR")
                    self.assertEqual([x["profile_code"] for x in quality["candidates"]],
                                     ["PERFIL-QUALITY-PACK"])
                    self.assertEqual(quality["stage"]["phase"],"QUALITY_ON_EXECUTED_ARTIFACT")
                    # Completed but unbound 'repair' cannot unlock derived Quality.
                    spoof=run_probe(name,"RUN-SPOOF")
                    self.assertEqual([x["profile_code"] for x in spoof["candidates"]],
                                     ["PERFIL-PRODUCT-DIRECTOR-LF"])
                    self.assertIsNone(spoof["stage"])
                finally:
                    subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)

if __name__=="__main__":
    unittest.main()
