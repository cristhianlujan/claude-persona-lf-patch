"""LF-PIGP-01/02: exact live preimages, PG17+PG18 BEGIN/ROLLBACK.

Test the real migration, verified semantic screen -> pre-Step40 skill eligibility,
and selector-only finding -> no IG claim in Step40/Step80. No live RUN writes.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
FIXTURE=(Path(__file__).parent/"fixtures/lf_pigp_live_preimage_20261116.sql").read_text()
MIG_PATHS=list((ROOT/"supabase/migrations").glob("*_lf_pigp_step70_ig_findings_and_pre40_screen_v1.sql"))
assert len(MIG_PATHS)==1,"PIGP_MIGRATION_MISSING_OR_DUPLICATED"
MIG=MIG_PATHS[0].read_text()
MIG_BODY=MIG.split("BEGIN;",1)[1].rsplit("COMMIT;",1)[0]

SETUP=r"""
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,
 status text,manifest jsonb,target_repo text,target_path text
);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,evidence_payload jsonb,
 step_order int,PRIMARY KEY(execution_id,step_id)
);
CREATE TABLE public.lf_activos(
 codigo_activo text PRIMARY KEY,tipo_activo text,metadata jsonb,archived_at timestamptz
);
CREATE FUNCTION public.lf_profile_execution_plan_v1(text,text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('operation_code','EJECUCION_PERFIL_LF',
    'steps',(SELECT jsonb_agg(x) FROM generate_series(1,11) x)) $$;
CREATE FUNCTION public.lf_skill_selection_legacy_running_compat_v1(text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT $2 $$;
CREATE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
   'status','READY','selection_status','SKILL_SELECTION_PENDING_FINDING',
   'skills','[]'::jsonb,
   'skill_candidates',CASE WHEN $4#>>'{input,pantalla_codigo}'='B2B-CARGA-002'
     THEN jsonb_build_array(jsonb_build_object('skill_code','INPUT_GOVERNANCE_CONTEXT_PACK'))
     ELSE '[]'::jsonb END,
   'content_findings',jsonb_build_array(
       jsonb_build_object('finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED')),
   'continuation_allowed',true,
   'next_action','SUBMIT_SKILL_SELECTION') $$;
CREATE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"READY","resolved_scope":{"resolved_screen_code":"B2B-CARGA-002"}}'::jsonb $$;
CREATE FUNCTION public.lf_profile_skill_reconcile_late_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"BLOCKED","blocking_code":"TEST_STOP_AFTER_STEP40"}'::jsonb $$;
CREATE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 RETURNS jsonb LANGUAGE plpgsql AS $rec$
 BEGIN
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
 VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$4);
 RETURN '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb;
 END $rec$;
CREATE FUNCTION public.lf_input_family_catalog_receipts_for_run_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
INSERT INTO public.lf_activos(codigo_activo,tipo_activo,metadata)
VALUES ('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL','{"profile_slug":"product_director_lf"}');
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,target_type,target_code,status,manifest,target_repo,target_path)
VALUES
 ('IG-CASE','EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
  'IN_PROGRESS',jsonb_build_object(
    'executor_mode','GPT_NATIVE','executor_provider','OPENAI_CHATGPT_NATIVE',
    'read_only',true,'no_write',true,'automatic_impact',false,
    'governed_repair_write',false,
    'router_profile_handoff',jsonb_build_object(
       'literal_request','repara carga masiva B2B','channel','PRODUCTO',
       'scope',jsonb_build_object('target_hint','carga masiva','target_type','PANTALLA')),
    'screen_selection_result',jsonb_build_object(
       'decision','SELECTED','selected_screen_code','B2B-CARGA-002'),
    'screen_selection_validation',jsonb_build_object(
       'status','VALID','decision','SELECTED',
       'selected_screen_code','B2B-CARGA-002')
   ),'repo/test','profiles/product_director_lf/PROFILE.md'),
 ('NEG-CASE','EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
  'IN_PROGRESS',jsonb_build_object(
    'router_profile_handoff',jsonb_build_object(
       'literal_request','repara carga masiva B2B','channel','PRODUCTO'),
    'screen_selection_result',jsonb_build_object(
       'decision','SELECTED','selected_screen_code','B2B-CARGA-002'),
    'screen_selection_validation',jsonb_build_object(
       'status','INVALID','decision','SELECTED',
       'selected_screen_code','B2B-CARGA-002')
   ),'repo/test','profiles/product_director_lf/PROFILE.md');
"""
ASSERTIONS=r"""
SELECT 'PRE40_IG_CANDIDATES='||
 jsonb_array_length(public.lf_profile_execution_plan_for_run_v1('IG-CASE',NULL)->'skill_candidates');
SELECT 'INVALID_SCREEN_CANDIDATES='||
 jsonb_array_length(public.lf_profile_execution_plan_for_run_v1('NEG-CASE',NULL)->'skill_candidates');
SELECT 'STEP40_GATE='||(public.lf_profile_native_bridge_prepare_v1(
  'IG-CASE',repeat('a',40),'sha256:'||repeat('b',64),'IG-CASE')->>'blocking_code');
SELECT 'STEP40_SCOPES='||(evidence_payload->>'analysis_scope')||':'||
 jsonb_array_length(evidence_payload->'skill_selection_findings')||':'||
 jsonb_array_length(evidence_payload->'input_governance_findings')||':'||
 jsonb_array_length(evidence_payload->'skill_execution_receipts')
FROM public.lf_operation_execution_steps
WHERE execution_id='IG-CASE' AND step_id='input_validate';
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
VALUES ('IG-CASE','semantic_judge','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('semantic_judge_result',
   jsonb_build_object('candidate_sha256',repeat('a',64),
                      'scope_packet_sha256',repeat('b',64))));
SELECT 'STEP80_GATE='||(public.lf_profile_native_bridge_record_report_v1(
  'IG-CASE','supabase://fixture/step80','IG-CASE')->>'blocking_code');
SELECT 'STEP80_IG_REPORTED='||
 coalesce((evidence_payload->>'ig_findings_reported')::boolean,false)
FROM public.lf_operation_execution_steps
WHERE execution_id='IG-CASE' AND step_id='report_output';
DO $checks$
DECLARE r jsonb;
BEGIN
 r:=public.lf_profile_execution_plan_for_run_v1('IG-CASE',NULL);
 IF jsonb_array_length(r->'skill_candidates')<1 THEN
  RAISE EXCEPTION 'LF_PIGP_01_PRE40_IG_NOT_ELIGIBLE'; END IF;
 r:=public.lf_profile_execution_plan_for_run_v1('NEG-CASE',NULL);
 IF jsonb_array_length(r->'skill_candidates')<>0 THEN
  RAISE EXCEPTION 'LF_PIGP_01_ACCEPTED_UNVERIFIED_SCREEN'; END IF;
 SELECT evidence_payload INTO r FROM public.lf_operation_execution_steps
 WHERE execution_id='IG-CASE' AND step_id='input_validate';
 IF r->>'analysis_scope'<>'READ_ONLY_PROFILE_VALIDATION'
  OR jsonb_array_length(r->'skill_selection_findings')<>1
  OR jsonb_array_length(r->'input_governance_findings')<>0
  OR jsonb_array_length(r->'skill_execution_receipts')<>0 THEN
  RAISE EXCEPTION 'LF_PIGP_02_SELECTION_WRONGLY_COUNTED_AS_IG'; END IF;
 SELECT evidence_payload INTO r FROM public.lf_operation_execution_steps
 WHERE execution_id='IG-CASE' AND step_id='report_output';
 IF coalesce((r->>'ig_findings_reported')::boolean,false) THEN
  RAISE EXCEPTION 'LF_PIGP_02_STEP80_IG_REPORT_WITHOUT_RECEIPT'; END IF;
END $checks$;
"""

class PIGPPGDual(unittest.TestCase):
    def test_pg17_pg18_begin_rollback(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-pigp-"+uuid.uuid4().hex[:10]
                r=subprocess.run(["docker","run","-d","--rm","--name",name,
                  "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                  text=True,capture_output=True,timeout=180)
                self.assertEqual(r.returncode,0,r.stderr)
                try:
                    for _ in range(90):
                        p=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                          text=True,capture_output=True,timeout=12)
                        if p.returncode==0:
                            logs=subprocess.run(["docker","logs",name],
                              text=True,capture_output=True,timeout=12)
                            if "PostgreSQL init process complete; ready for start up." in (
                                logs.stdout+logs.stderr): break
                        time.sleep(.5)
                    self.assertEqual(p.returncode,0,"PG_NOT_READY")
                    def sql(q,fail=False):
                        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
                           "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                          input=q,text=True,capture_output=True,timeout=200)
                        if fail:self.assertNotEqual(p.returncode,0,p.stdout)
                        else:self.assertEqual(p.returncode,0,p.stderr[-4500:]+p.stdout[-3000:])
                        return p.stdout,p.stderr
                    # Negative: exact source state guard rejects a changed preimage.
                    neg="""CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(
                        p_execution_id text,p_decision jsonb DEFAULT NULL::jsonb)
                        RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;"""
                    out,err=sql("BEGIN;\n"+SETUP+FIXTURE+"\n"+neg+"\n"+
                        MIG_BODY+"\nROLLBACK;",fail=True)
                    self.assertIn("SOURCE_STATE_DRIFT:lf_profile_execution_plan_for_run_v1",err)
                    # Positive: all writes are fixture-only and rolled back.
                    out,err=sql("BEGIN;\n"+SETUP+FIXTURE+"\n"+MIG_BODY+
                        "\n"+ASSERTIONS+"\nROLLBACK;\n"+
                        "SELECT 'RESIDUE='||(to_regclass('public.lf_operation_execution') IS NOT NULL);\n")
                    for marker in (
                      "PRE40_IG_CANDIDATES=1",
                      "INVALID_SCREEN_CANDIDATES=0",
                      "STEP40_GATE=TEST_STOP_AFTER_STEP40",
                      "STEP40_SCOPES=READ_ONLY_PROFILE_VALIDATION:1:0:0",
                      "STEP80_GATE=BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN",
                      "STEP80_IG_REPORTED=false","RESIDUE=false"):
                        self.assertIn(marker,out,marker+"\n"+out[-4500:])
                    print("PASS_PIGP_PG"+pg+"_PRE40_IG_STEP80_NEGATIVE_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)

if __name__=="__main__":
    unittest.main()
