"""LF-PIGP-01/02 PG17/18: exact live source functions and E12 owner prerequisite,
validated screen before Step40, separate selection-vs-IG findings, and Step80
IG receipt-only reporting. BEGIN/ROLLBACK; negative tamper must fail-closed.
Mock only unrelated external catalog/recorder/IG transport, not target functions.
"""
import shutil,subprocess,time,unittest,uuid,re
from pathlib import Path

BASE=Path(__file__).resolve().parent
ROOT=BASE.parents[2]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_pigp_profile_ig_profile_fixes_v1.sql"))
assert len(MIGS)==1,"PIGP_SQL_AMBIGUOUS"
PLAN=(BASE/"fixtures/lf_pigp_plan_live_prepatch_v1.sql").read_text(encoding="utf8")
BRIDGE=(BASE/"fixtures/lf_pigp_e12_bridge_live_prepatch_v1.sql").read_text(encoding="utf8")
E12=(BASE/"fixtures/lf_pigp_e12_scope_patch_v1.sql").read_text(encoding="utf8")
PIGP=MIGS[0].read_text(encoding="utf8")
BRIDGE=re.sub(r"(\$function\$)(\s+)(?=CREATE OR REPLACE FUNCTION)",r"\1;\2",BRIDGE).rstrip()+";\n"
SCHEMA=r"""
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,target_type text NOT NULL,target_code text NOT NULL,
 status text NOT NULL,manifest jsonb NOT NULL,target_repo text,target_path text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 evidence_ref text,observed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(execution_id,step_id));
CREATE TABLE public.lf_activos(
 codigo_activo text PRIMARY KEY,tipo_activo text,archived_at timestamptz,
 metadata jsonb DEFAULT '{}'::jsonb);
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"valid":true}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY","resolved_scope":{}}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
RETURNS jsonb LANGUAGE plpgsql AS $record$
BEGIN
 INSERT INTO public.lf_operation_execution_steps(
   execution_id,step_id,status,evidence_payload,evidence_ref)
 VALUES($1,$2,'STEP_PASS_WITH_EVIDENCE',$4,$3);
 RETURN '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb;
END $record$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_v1(text,text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('operation_code','EJECUCION_PERFIL_LF',
  'steps',(SELECT jsonb_agg(i) FROM generate_series(1,11) i))
$$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(text,text,jsonb,jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $select$
DECLARE candidate jsonb:='[]'::jsonb; skills jsonb:='[]'::jsonb;
  findings jsonb:='[]'::jsonb;
BEGIN
 IF $4#>>'{input,pantalla_codigo}'='B2B-CARGA-002' THEN
   candidate:=jsonb_build_array(jsonb_build_object(
     'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK'));
 ELSE
   findings:=jsonb_build_array(jsonb_build_object(
     'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
     'skill_code','SKILL_SELECTION','status','SKILL_CONTENT_FINDING'));
 END IF;
 IF $4->>'intent'='IG_FAIL' THEN
  skills:=jsonb_build_array(jsonb_build_object(
    'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK','effect','READ_ONLY'));
 END IF;
 RETURN jsonb_build_object('status','READY','skills',skills,
  'skill_candidates',candidate,'content_findings',findings,
  'selection_status','SKILL_SELECTION_PENDING_FINDING',
  'continuation_allowed',true,'required_skills','[]'::jsonb);
END $select$;
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_prepare_v1(text,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"READY"}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_screen_selector_semantic_validate_v1(jsonb,jsonb)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('status',
  CASE WHEN $2->>'selected_screen_code'='B2B-CARGA-002' THEN 'VALID' ELSE 'INVALID' END)
$$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"BLOCKED","blocking_code":"IG_STUB_BLOCKED","input_governance":{"status":"BLOCKED"}}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_skill_reconcile_late_v1(text)
RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"status":"BLOCKED","blocking_code":"TEST_STOP_AFTER_STEP40"}'::jsonb
$$;
CREATE OR REPLACE FUNCTION public.lf_input_family_catalog_receipts_for_run_v1(text)
RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
INSERT INTO public.lf_activos(codigo_activo,tipo_activo,metadata)
 VALUES('PERFIL-PRODUCT-DIRECTOR-LF','PERFIL','{"profile_slug":"product_director_lf"}');
"""
BEHAVIOR=r"""
INSERT INTO public.lf_operation_execution(
 execution_id,operation_code,target_type,target_code,status,manifest,
 target_repo,target_path)
SELECT x.id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
 'IN_PROGRESS',
 jsonb_build_object('executor_mode','GPT_NATIVE',
  'executor_provider','OPENAI_CHATGPT_NATIVE',
  'governed_repair_write',x.gov,
  'router_profile_handoff',jsonb_build_object(
   'literal_request','Revisar pantalla B2B-CARGA-002',
   'channel','PRODUCTO','intent',x.intent,'scope','{}'::jsonb))
  ||coalesce(x.selection,'{}'::jsonb),
 'cristhianlujan/claude-persona-lf-patch','profiles/product_director_lf/SKILL.md'
FROM (VALUES
 ('SELECTED',false,'NORMAL','{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"B2B-CARGA-002"}}'::jsonb),
 ('BADSCREEN',false,'NORMAL','{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"BAD-SCREEN"}}'::jsonb),
 ('UNSELECTED',false,'NORMAL','{}'::jsonb),
 ('IGFAIL',false,'IG_FAIL','{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"B2B-CARGA-002"}}'::jsonb),
 ('GOVFAIL',true,'IG_FAIL','{"screen_selection_result":{"decision":"SELECTED","selected_screen_code":"B2B-CARGA-002"}}'::jsonb)
) x(id,gov,intent,selection);
SELECT 'PRESTEP40_ELIGIBLE='||
 jsonb_array_length(public.lf_profile_execution_plan_for_run_v1('SELECTED',NULL)->'skill_candidates');
SELECT 'NEGATIVE_INVALID_SCREEN_CANDIDATES='||
 jsonb_array_length(public.lf_profile_execution_plan_for_run_v1('BADSCREEN',NULL)->'skill_candidates');
SELECT 'NEGATIVE_NO_SCREEN_CANDIDATES='||
 jsonb_array_length(public.lf_profile_execution_plan_for_run_v1('UNSELECTED',NULL)->'skill_candidates');
SELECT 'CALL='||execution_id||':'||
 (public.lf_profile_native_bridge_prepare_v1(execution_id,repeat('a',40),
 'sha256:'||repeat('b',64),execution_id)->>'blocking_code')
 FROM public.lf_operation_execution ORDER BY execution_id;
SELECT 'STEP40='||execution_id||':'||
 (evidence_payload->>'analysis_scope')||':'||
 (evidence_payload->>'mutation_authorized')||':'||
 jsonb_array_length(evidence_payload->'skill_selection_findings')||':'||
 jsonb_array_length(evidence_payload->'input_governance_findings')||':'||
 jsonb_array_length(evidence_payload->'skill_execution_receipts')
 FROM public.lf_operation_execution_steps
 WHERE step_id='input_validate' ORDER BY execution_id;
-- Prepare must preserve Step40 findings separate from real IG execution receipts.
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
 SELECT id,'semantic_judge','STEP_PASS_WITH_EVIDENCE',jsonb_build_object(
  'semantic_judge_result',jsonb_build_object(
   'candidate_sha256',repeat('c',64),
   'scope_packet_sha256',repeat('d',64)))
 FROM (VALUES ('GOVFAIL'),('UNSELECTED')) x(id);
SELECT 'REPORT='||execution_id||':'||
 (public.lf_profile_native_bridge_record_report_v1(
  execution_id,'supabase://test/terminal',execution_id)->>'blocking_code')
 FROM public.lf_operation_execution
 WHERE execution_id IN ('GOVFAIL','UNSELECTED')
 ORDER BY execution_id;
SELECT 'REPORT_IG='||execution_id||':'||
 coalesce(evidence_payload->>'ig_findings_reported','false')
 FROM public.lf_operation_execution_steps
 WHERE step_id='report_output' ORDER BY execution_id;
"""
class PigpProfileIGProfilePGDual(unittest.TestCase):
 def test_real_functions_screen_source_and_receipts(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertIn("LF_PIGP_E12_GOVERNED_REPAIR_BASE_NOT_INSTALLED",PIGP)
  self.assertIn("input_governance_findings",PIGP)
  self.assertIn("LF_PIGP_01_SOURCE_OR_SCREEN_PATCH_NOT_APPLIED",PIGP)
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-pigp-"+uuid.uuid4().hex[:9]
    started=subprocess.run(["docker","run","-d","--rm","--name",name,
     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
     capture_output=True,text=True,timeout=180)
    self.assertEqual(started.returncode,0,started.stderr[-1000:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        capture_output=True,text=True,timeout=10)
      if ready.returncode==0:break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(st,fail=False):
      r=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
        "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
        input=st,capture_output=True,text=True,timeout=180)
      if fail:self.assertNotEqual(r.returncode,0,r.stdout[-800:])
      else:self.assertEqual(r.returncode,0,r.stderr[-4500:]+"\n"+r.stdout[-2700:])
      return r.stdout,r.stderr
     e12=E12.split("BEGIN;",1)[1].rsplit("COMMIT;",1)[0]
     pigp=PIGP.split("BEGIN;",1)[1].rsplit("COMMIT;",1)[0]
     st="BEGIN;\n"+SCHEMA+BRIDGE+"\n"+PLAN+"\n"+e12+"\n"+pigp+"\n"+BEHAVIOR+\
         "\nROLLBACK;\nSELECT 'RESIDUE='||count(*) FROM public.lf_operation_execution;\n"
     out,err=sql(st)
     for marker in (
      "PRESTEP40_ELIGIBLE=1",
      "NEGATIVE_INVALID_SCREEN_CANDIDATES=0",
      "NEGATIVE_NO_SCREEN_CANDIDATES=0",
      "STEP40=UNSELECTED:READ_ONLY_PROFILE_VALIDATION:false:1:0:0",
      "STEP40=SELECTED:READ_ONLY_PROFILE_VALIDATION:false:0:0:0",
      "STEP40=IGFAIL:READ_ONLY_WITH_IG_FINDINGS:false:0:1:1",
      "STEP40=GOVFAIL:GOVERNED_REPAIR:true:0:1:1",
      "REPORT_IG=GOVFAIL:true","REPORT_IG=UNSELECTED:false",
      "RESIDUE=0"
     ):
      self.assertIn(marker,out,marker+"\n"+out[-3700:])
     self.assertNotIn("BLOCK_REPORT_IG_FINDINGS_WRITE_SCOPE",out)
     print("PASS_LF_PIGP_PG"+pg+"_PRESTEP40_SCREEN_IG_RECEIPT_REPORT_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
