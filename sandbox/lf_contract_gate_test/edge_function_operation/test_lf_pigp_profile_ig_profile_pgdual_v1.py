"""PG17/18 PIGP-01/02, actual prepatch live Plan40/Bridge40/Report80 functions.

The suite runs the governed migration on source-exact functions under
BEGIN/ROLLBACK. External schema/screen selector/skill adapter dependencies are
minimal behavioral test doubles; no production model, remote IG or provider
attestation is claimed.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_pigp_profile_ig_profile_repairs_v1.sql"))
SOURCE=Path(__file__).resolve().parent/"fixtures/lf_pigp_prepatch_live_functions_v1.sql"

SCHEMA=r"""
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,operation_code text,target_type text,target_code text,
 status text,manifest jsonb NOT NULL DEFAULT '{}'::jsonb,target_repo text,
 target_path text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_ref text,evidence_payload jsonb DEFAULT '{}'::jsonb,
 step_order integer,observed_at timestamptz DEFAULT now(),
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_activos(
 codigo_activo text PRIMARY KEY,tipo_activo text,archived_at timestamptz,metadata jsonb);
INSERT INTO public.lf_activos(codigo_activo,tipo_activo,metadata)
 VALUES('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL','{"profile_slug":"product_director_lf"}');

CREATE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('status','READY','target_hint',$2->>'target_hint') $$;
CREATE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(jsonb,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
  'status',CASE WHEN $2->>'decision'='SELECTED'
    AND $2->>'selected_screen_code'=$1->>'target_hint'
    THEN 'VALID' ELSE 'BLOCKED' END,
  'decision',$2->>'decision','selected_screen_code',$2->>'selected_screen_code') $$;
CREATE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object(
 'status','READY',
 'skills',CASE WHEN $4->>'request_text'='ig_failure'
   THEN jsonb_build_array(jsonb_build_object(
       'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK','effect','READ_ONLY'))
   ELSE '[]'::jsonb END,
 'content_findings',jsonb_build_array(jsonb_build_object(
   'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
   'finding_alias','SKILL_SELECTION_PENDING_FINDING')),
 'skill_candidates',CASE WHEN $4#>>'{input,pantalla_codigo}'='B2B-CARGA-002'
   THEN jsonb_build_array(jsonb_build_object('skill_code','INPUT_GOVERNANCE_CONTEXT_PACK'))
   ELSE '[]'::jsonb END,
 'selected_skill_codes','[]'::jsonb,
 'selection_status','SKILL_SELECTION_REQUESTED') $$;
CREATE FUNCTION public.lf_profile_execution_plan_v1(text,text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('operation_code','EJECUCION_PERFIL_LF',
   'steps',(SELECT jsonb_agg(n) FROM generate_series(1,11) n)) $$;
CREATE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('status','READY','resolved_scope',
   jsonb_build_object('resolved_screen_code','B2B-CARGA-002')) $$;
CREATE FUNCTION public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('status','FAILED',
  'blocking_code','TEST_IG_FAILED','remediation_action','RETRY_IG') $$;
CREATE FUNCTION public.lf_profile_skill_reconcile_late_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"BLOCKED","blocking_code":"TEST_STOP_AFTER_STEP40"}'::jsonb $$;
CREATE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 RETURNS jsonb LANGUAGE plpgsql AS $rec$
BEGIN
 INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_ref,evidence_payload)
 VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$3,$4);
 IF $2='report_output' THEN
   UPDATE public.lf_operation_execution SET status='COMPLETED'
    WHERE execution_id=$1;
 END IF;
 RETURN '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb;
END $rec$;
CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(text)
 RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION public.lf_input_family_catalog_receipts_for_run_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
CREATE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object(
 'status','READY','terminal_authority_receipt_sha256',repeat('a',64)) $$;
CREATE FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object(
 'result','TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
 'terminal_authority_receipt_sha256',repeat('a',64),
 'post_profile_route','{}'::jsonb,'next_action','REENTER_ROUTER_STAGE1') $$;
"""
RUNS=r"""
INSERT INTO public.lf_operation_execution
(execution_id,operation_code,target_type,target_code,status,manifest,target_repo,target_path)
SELECT x.id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF','IN_PROGRESS',
 jsonb_build_object('executor_mode','GPT_NATIVE',
   'executor_provider','OPENAI_CHATGPT_NATIVE',
   'router_profile_handoff',jsonb_build_object(
      'literal_request',x.request,'channel','PRODUCTO','scope',
      jsonb_build_object('target_type','PANTALLA','target_hint','B2B-CARGA-002')),
   'screen_selection_result',jsonb_build_object(
     'decision','SELECTED','selected_screen_code',x.screen),
   'governed_repair_write',x.governed),
 'cristhianlujan/claude-persona-lf-patch','profiles/product_director_lf/SKILL.md'
FROM (VALUES ('PIGP-SEL','selector_only','B2B-CARGA-002',false),
 ('PIGP-IG','ig_failure','B2B-CARGA-002',false),
 ('PIGP-GOV','governed','B2B-CARGA-002',true),
 ('PIGP-STALE','bad_source','B2B-CARGA-WRONG',false))
 AS x(id,request,screen,governed);

SELECT 'PLAN='||execution_id||':'||
 coalesce((public.lf_profile_execution_plan_for_run_v1(execution_id,NULL::jsonb)
 #>>'{selection_receipt,skill_candidates,0,skill_code}'),'NONE')
FROM public.lf_operation_execution ORDER BY execution_id;

SELECT 'BRIDGE='||execution_id||':'||
 (public.lf_profile_native_bridge_prepare_v1(
 execution_id,repeat('b',40),'sha256:'||repeat('c',64),execution_id)->>'blocking_code')
FROM public.lf_operation_execution WHERE execution_id<>'PIGP-STALE'
ORDER BY execution_id;

SELECT 'SCOPE='||execution_id||':'||
 (evidence_payload->>'analysis_scope')||':'||
 (evidence_payload#>>'{input_governance,analysis_scope}')||':'||
 (evidence_payload->>'mutation_authorized')||':'||
 jsonb_array_length(evidence_payload->'skill_selection_findings')::text||':'||
 jsonb_array_length(evidence_payload->'input_governance_findings')::text
FROM public.lf_operation_execution_steps
WHERE step_id='input_validate' ORDER BY execution_id;

-- Step80: genuine IG receipt is required before ig_findings_reported=true.
-- Populate the remaining 10 canonical step IDs for the two output paths.
INSERT INTO public.lf_operation_execution_steps
 (execution_id,step_id,status,evidence_ref,evidence_payload)
SELECT x.id, stepid,'STEP_PASS_WITH_EVIDENCE','test://receipt/'||stepid,
 CASE WHEN stepid='semantic_judge'
 THEN jsonb_build_object('semantic_judge_result',jsonb_build_object(
   'candidate_sha256',repeat('e',64),'scope_packet_sha256',repeat('f',64),
   'verdict','PASS_REVIEWED_CURRENT_CONTEXT'))
 WHEN stepid='execute_profile'
 THEN '{"profile_output":{"summary":"fixture material output"}}'::jsonb
 ELSE '{}'::jsonb END
FROM (VALUES('PIGP-SEL'),('PIGP-IG')) AS x(id)
CROSS JOIN (VALUES('router'),('context_admission'),('research_baseline_freeze'),
 ('execute_profile'),('output_validate'),('semantic_judge'),('policy_selection')) s(stepid)
ON CONFLICT(execution_id,step_id) DO NOTHING;

SELECT 'REPORT='||execution_id||':'||
 (public.lf_profile_native_bridge_record_report_v1(
 execution_id,'test://report/'||execution_id,execution_id)->>'status')
FROM public.lf_operation_execution
WHERE execution_id IN ('PIGP-SEL','PIGP-IG') ORDER BY execution_id;
SELECT 'IG_REPORTED='||execution_id||':'||
 coalesce(evidence_payload->>'ig_findings_reported','ABSENT')
FROM public.lf_operation_execution_steps
WHERE step_id='report_output' ORDER BY execution_id;
"""
class TestPIGPPG17PG18(unittest.TestCase):
 def test_live_sql_negative_and_rollback(self):
  self.assertIsNotNone(shutil.which('docker'),'DOCKER_REQUIRED')
  assert len(MIGS)==1
  source=SOURCE.read_text(encoding='utf-8')
  migration=MIGS[0].read_text(encoding='utf-8')
  body=migration.split('BEGIN;',1)[1].rsplit('COMMIT;',1)[0]
  for pg in ('17.6','18.7'):
   with self.subTest(engine=pg):
    name='lf-pigp-'+uuid.uuid4().hex[:9]
    result=subprocess.run(['docker','run','-d','--rm','--name',name,
      '-e','POSTGRES_PASSWORD=fixture-only','postgres:'+pg],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(result.returncode,0,result.stderr[-1500:])
    try:
     for _ in range(90):
      ready=subprocess.run(['docker','exec',name,'pg_isready','-U','postgres'],
        capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(['docker','logs',name],capture_output=True,text=True,timeout=10)
       if 'PostgreSQL init process complete; ready for start up.' in (logs.stdout+logs.stderr):
        break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,'PG_NOT_READY')
     def sql(stmt,expect_error=False):
      p=subprocess.run(['docker','exec','-i',name,'psql','-X','-A','-t',
         '-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],
         input=stmt,capture_output=True,text=True,timeout=150)
      if expect_error:self.assertNotEqual(p.returncode,0,'NEGATIVE_UNEXPECTED_SUCCESS')
      else:self.assertEqual(p.returncode,0,p.stderr[-4500:]+'\n'+p.stdout[-3500:])
      return p.stdout,p.stderr
     sql('BEGIN;\n'+SCHEMA+'\n'+source+'\nCOMMIT;')
     negative="""BEGIN;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(p_execution_id text,p_decision jsonb DEFAULT NULL::jsonb)
RETURNS jsonb LANGUAGE sql AS $stub$ SELECT '{}'::jsonb $stub$;
"""
     out,err=sql(negative+body+'\nCOMMIT;',expect_error=True)
     self.assertIn('LF_PIGP01_SOURCE_PATCH_NOT_APPLIED',err)
     out,err=sql('BEGIN;\n'+body+'\n'+RUNS+
       '\nROLLBACK;\nSELECT \'POST_ROLLBACK=\'||count(*) FROM public.lf_operation_execution;\n')
     for marker in (
      'PLAN=PIGP-SEL:INPUT_GOVERNANCE_CONTEXT_PACK',
      'PLAN=PIGP-IG:INPUT_GOVERNANCE_CONTEXT_PACK',
      'PLAN=PIGP-STALE:NONE',
      'SCOPE=PIGP-SEL:READ_ONLY_PROFILE_VALIDATION:READ_ONLY_PROFILE_VALIDATION:false:1:0',
      'SCOPE=PIGP-IG:READ_ONLY_WITH_IG_FINDINGS:READ_ONLY_WITH_IG_FINDINGS:false:1:1',
      'SCOPE=PIGP-GOV:GOVERNED_REPAIR:GOVERNED_REPAIR:true:1:0',
      'IG_REPORTED=PIGP-SEL:ABSENT',
      'IG_REPORTED=PIGP-IG:true',
      'POST_ROLLBACK=0'):
      self.assertIn(marker,out,marker+'\n'+out[-3500:])
     print('PASS_PIGP_01_02_PG'+pg+'_SCREEN_PRE40_SELECTOR_NOT_IG_STEP80_GUARD_ROLLBACK',flush=True)
    finally:
     subprocess.run(['docker','rm','-f',name],capture_output=True,timeout=30)

if __name__=='__main__':
 unittest.main()
