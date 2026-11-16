"""PIGP01/02 real live PostgreSQL function text; PG17/18 with verified run/step fixtures."""
import shutil,subprocess,time,unittest,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_pigp_step40_ig_findings_screen_selection_v1.sql"))
SOURCE=Path(__file__).resolve().parent/"fixtures/lf_pigp_prepatch_live_bridge_plan_report_v1.sql"
SCHEMA=r"""
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY, operation_code text NOT NULL,target_type text NOT NULL,
 target_code text NOT NULL,status text NOT NULL,manifest jsonb NOT NULL DEFAULT '{}'::jsonb,
 target_repo text,target_path text,started_at timestamptz DEFAULT now());
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_ref text,evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 observed_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_activos(
 codigo_activo text PRIMARY KEY,tipo_activo text,archived_at timestamptz,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb);
INSERT INTO public.lf_activos VALUES
 ('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL',NULL,'{"profile_slug":"product_director_lf"}');
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(jsonb,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"VALID"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"READY","resolved_scope":{"resolved_screen_code":"B2B-CARGA-002","resolution_status":"RESOLVED"}}'::jsonb
$$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
  'status','READY',
  'selection_status','READY',
  'continuation_allowed',true,
  'candidate_count',CASE WHEN $4#>>'{input,pantalla_codigo}'='B2B-CARGA-002' THEN 1 ELSE 0 END,
  'skill_candidates',jsonb_build_array(jsonb_build_object('skill_code','INPUT_GOVERNANCE_CONTEXT_PACK')),
  'skills',CASE WHEN $4#>>'{input,execution_id}' IN ('IG','GOV')
    THEN jsonb_build_array(jsonb_build_object('skill_code','INPUT_GOVERNANCE_CONTEXT_PACK','effect','READ_ONLY'))
    ELSE '[]'::jsonb END,
  'content_findings', CASE WHEN $4#>>'{input,execution_id}'='SEL'
    THEN jsonb_build_array(jsonb_build_object('code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED'))
    ELSE '[]'::jsonb END
 )
$$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_v1(text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('operation_code','EJECUCION_PERFIL_LF',
   'steps',(SELECT jsonb_agg(jsonb_build_object('step',g)) FROM generate_series(1,11) g))
$$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"FAILED","blocking_code":"IG_TEST_FAILURE"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_reconcile_late_v1(text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"BLOCKED","blocking_code":"STOP_AFTER_STEP40"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
RETURNS jsonb LANGUAGE plpgsql AS $rec$
BEGIN
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_ref,evidence_payload)
 VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$3,$4);
 RETURN '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb;
END $rec$;
CREATE OR REPLACE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(text)
RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE OR REPLACE FUNCTION public.lf_input_family_catalog_receipts_for_run_v1(text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
"""
FIXTURE=r"""
BEGIN;
INSERT INTO public.lf_operation_execution(execution_id,operation_code,
 target_type,target_code,status,manifest,target_repo,target_path)
SELECT t.id,'EJECUCION_PERFIL_LF','PERFIL',
 'PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',
 jsonb_build_object('executor_mode','GPT_NATIVE',
  'executor_provider','OPENAI_CHATGPT_NATIVE',
  'screen_selection_result',jsonb_build_object('decision','SELECTED',
   'selected_screen_code','B2B-CARGA-002'),
  'router_profile_handoff',jsonb_build_object(
   'literal_request','Reparar B2B-CARGA-002','channel','PRODUCTO',
   'scope',jsonb_build_object('target_type','PANTALLA','target_hint','B2B-CARGA-002')))
  || t.extra,
 'cristhianlujan/claude-persona-lf-patch','profiles/product_director_lf/SKILL.md'
FROM (VALUES ('SEL','{}'::jsonb),('IG','{}'::jsonb),
 ('GOV','{"governed_repair_write":true}'::jsonb)) t(id,extra);
-- PIGP-01: actual plan is executed before input_validate Step40 exists.
SELECT 'BEFORE_STEP40='||count(*) FROM public.lf_operation_execution_steps;
SELECT 'PRE_STEP40_CANDIDATES='||
 (public.lf_profile_execution_plan_for_run_v1('SEL',NULL::jsonb)#>>
 '{selection_receipt,candidate_count}');
SELECT 'PRE_STEP40_SKILL='||
 (public.lf_profile_execution_plan_for_run_v1('SEL',NULL::jsonb)#>>
 '{skill_candidates,0,skill_code}');
SELECT 'PREP_SEL='||
 (public.lf_profile_native_bridge_prepare_v1('SEL',repeat('a',40),'sha256:'||repeat('b',64),'SEL')
 ->>'blocking_code');
SELECT 'PREP_IG='||
 (public.lf_profile_native_bridge_prepare_v1('IG',repeat('a',40),'sha256:'||repeat('b',64),'IG')
 ->>'blocking_code');
SELECT 'PREP_GOV='||
 (public.lf_profile_native_bridge_prepare_v1('GOV',repeat('a',40),'sha256:'||repeat('b',64),'GOV')
 ->>'blocking_code');
SELECT 'STEP40='||execution_id||':'||(evidence_payload->>'analysis_scope')||':'||
 (evidence_payload->>'mutation_authorized')||':'||
 jsonb_array_length(evidence_payload->'skill_selection_findings')||':'||
 jsonb_array_length(evidence_payload->'input_governance_findings')||':'||
 jsonb_array_length(evidence_payload->'skill_execution_receipts')
 FROM public.lf_operation_execution_steps
 WHERE step_id='input_validate' ORDER BY execution_id;
-- Advance only two fixtures to report preconditions. No changes are committed.
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_id,status,evidence_ref,evidence_payload)
SELECT id,'semantic_judge','STEP_PASS_WITH_EVIDENCE',
 'supabase://test/step70',
 jsonb_build_object('semantic_judge_result',jsonb_build_object(
 'candidate_sha256',repeat('c',64),'scope_packet_sha256',repeat('d',64)))
 FROM (VALUES('SEL'),('IG')) x(id);
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_id,status,evidence_ref,evidence_payload)
SELECT id,'execute_profile','STEP_PASS_WITH_EVIDENCE',
 'supabase://test/step50','{"profile_output":{"summary":"tested"}}'::jsonb
 FROM (VALUES('SEL'),('IG')) x(id);
SELECT 'REPORT='||id||':'||
 coalesce(public.lf_profile_native_bridge_record_report_v1(
 id,'supabase://test/report','TEST')->>'blocking_code','OK')
FROM (VALUES('SEL'),('IG')) x(id);
SELECT 'REPORT_IG_CLAIM='||execution_id||':'||
 coalesce(evidence_payload->>'ig_findings_reported','NULL')
 FROM public.lf_operation_execution_steps
 WHERE step_id='report_output' ORDER BY execution_id;
ROLLBACK;
SELECT 'ROLLBACK_ROW_COUNT='||count(*) FROM public.lf_operation_execution;
"""
class PIGPPGDual(unittest.TestCase):
 def test_pre_step40_screen_ig_provenance_report_and_rollback(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertEqual(len(MIGS),1)
  migration=MIGS[0].read_text(encoding="utf-8")
  source=SOURCE.read_text(encoding="utf-8")
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-pigp-"+uuid.uuid4().hex[:10]
    run=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
       capture_output=True,text=True,timeout=180)
    self.assertEqual(run.returncode,0,run.stderr[-1500:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(s,fail=False):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=s,capture_output=True,text=True,timeout=160)
      if fail:self.assertNotEqual(p.returncode,0,"EXPECTED SQL FAILURE")
      else:self.assertEqual(p.returncode,0,p.stderr[-6000:]+"\n"+p.stdout[-3500:])
      return p.stdout,p.stderr
     sql(SCHEMA+"\n"+source)
     # Deliberate negative preimage drift: installed function cannot be patched.
     sql("""CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(
       text,jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;""")
     _,err=sql(migration,fail=True)
     self.assertIn("LF_PIGP_01_PLAN_DECLARATION_DRIFT",err)
     sql(source)
     sql(migration)
     out,err=sql(FIXTURE)
     for marker in (
      "BEFORE_STEP40=0","PRE_STEP40_CANDIDATES=1",
      "PRE_STEP40_SKILL=INPUT_GOVERNANCE_CONTEXT_PACK",
      "PREP_SEL=STOP_AFTER_STEP40","PREP_IG=STOP_AFTER_STEP40",
      "PREP_GOV=STOP_AFTER_STEP40",
      "STEP40=SEL:READ_ONLY_PROFILE_VALIDATION:false:1:0:0",
      "STEP40=IG:READ_ONLY_WITH_IG_FINDINGS:false:0:1:1",
      "STEP40=GOV:GOVERNED_REPAIR:true:0:1:1",
      "REPORT_IG_CLAIM=SEL:NULL","REPORT_IG_CLAIM=IG:true",
      "ROLLBACK_ROW_COUNT=0"):
      self.assertIn(marker,out,marker+"\n"+out[-3200:])
     print("PASS_PIGP_STEP40_IG_SCREEN_REPORT_PG"+pg+"_NEGATIVE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
