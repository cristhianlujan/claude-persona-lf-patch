"""PG17/18 source-real begin handoff patch: source PASS -> previous outputs,
source absent -> [] and no_promotion false, source without Step50 -> BLOCKED.
All data inside BEGIN/ROLLBACK; invalid patch source must abort.
"""
import shutil, subprocess, time, unittest, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_previous_outputs_and_no_promotion_off_v1.sql"))
SRC=Path(__file__).resolve().parent/"fixtures/lf_previous_outputs_begin_live_prepatch_v1.sql"
assert len(MIGS)==1
SCHEMA=r"""
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_ref text,evidence_payload jsonb DEFAULT '{}'::jsonb,
 observed_at timestamptz DEFAULT now());
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,manifest jsonb NOT NULL DEFAULT '{}'::jsonb);
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"valid":true,"governed_repair_write_allowed":false}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_executor_admission_v1(text,text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"admitted":true}'::jsonb $$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)
 RETURNS jsonb LANGUAGE plpgsql AS $$
 BEGIN
  INSERT INTO public.lf_operation_execution(execution_id,manifest)
  VALUES($1,$8);
  RETURN '{"outcome":"EXECUTION_OPENED"}'::jsonb;
 END $$;
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb $$;
"""
BEHAVIOR=r"""
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_id,status,evidence_ref,evidence_payload)
 VALUES('PARENT','execute_profile','STEP_PASS_WITH_EVIDENCE',
 'actions://real/parent/artifact',jsonb_build_object(
  'raw_output_sha256',repeat('f',64),
  'profile_output',jsonb_build_object('summary',repeat('s',600)),
  'step_result','STEP_PASS_WITH_EVIDENCE'));
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status)
 VALUES ('MISSING','input_validate','STEP_PASS_WITH_EVIDENCE');
SELECT 'PARENT_RESULT='||(public.lf_profile_execution_begin_from_handoff_v1(
 '{"profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","literal_request":"test","request_sha256":"source","scope":{"source_execution_id":"PARENT"}}',
 'GPT_NATIVE','RUN-A','idempotent-a','actor',
 'repo','path','{}'::jsonb)->>'status');
SELECT 'PARENT_OUTPUT_LENGTH='||jsonb_array_length(manifest->'previous_outputs'),
 'PARENT_OUTPUT_REF='||(manifest#>>'{previous_outputs,0,output_ref}'),
 'PARENT_OUTPUT_SHA='||(manifest#>>'{previous_outputs,0,deliverable_sha256}'),
 'PARENT_OUTPUT_SUMMARY_CHARS='||length(manifest#>>'{previous_outputs,0,summary}'),
 'PARENT_NO_PROMOTION='||(manifest->>'no_promotion')
 FROM public.lf_operation_execution WHERE execution_id='RUN-A';
SELECT 'NO_SOURCE_RESULT='||(public.lf_profile_execution_begin_from_handoff_v1(
 '{"profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","literal_request":"test","request_sha256":"source","scope":{}}',
 'GPT_NATIVE','RUN-B','idempotent-b','actor','repo','path','{}'::jsonb)->>'status');
SELECT 'NO_SOURCE_OUTPUT_LENGTH='||jsonb_array_length(manifest->'previous_outputs'),
 'NO_SOURCE_NO_PROMOTION='||(manifest->>'no_promotion')
 FROM public.lf_operation_execution WHERE execution_id='RUN-B';
SELECT 'MISSING_RESULT='||(public.lf_profile_execution_begin_from_handoff_v1(
 '{"profile_code":"PERFIL-PRODUCT-DIRECTOR-LF","literal_request":"test","request_sha256":"source","scope":{"source_execution_id":"MISSING"}}',
 'GPT_NATIVE','RUN-C','idempotent-c','actor','repo','path','{}'::jsonb)->>'blocking_code');
SELECT 'NO_GHOST='||count(*) FROM public.lf_operation_execution WHERE execution_id='RUN-C';
"""
class PreviousOutputsPGDual(unittest.TestCase):
 def test_patch_source_bound_behavior_and_fail_closed(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  migration=MIGS[0].read_text(encoding="utf-8")
  src=SRC.read_text(encoding="utf-8")
  self.assertIn("LF_PREVIOUS_OUTPUTS_PATCH_NOT_APPLIED",migration)
  self.assertIn("v_repair_write boolean:=false;",src)
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-prev-"+uuid.uuid4().hex[:10]
    start=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
      capture_output=True,text=True,timeout=180)
    self.assertEqual(start.returncode,0,start.stderr[-2000:])
    try:
     for _ in range(90):
      p=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        capture_output=True,text=True,timeout=10)
      if p.returncode==0: break
      time.sleep(.5)
     self.assertEqual(p.returncode,0,"PG_NOT_READY")
     def sql(code,fail=False):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
         "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
         input=code,capture_output=True,text=True,timeout=120)
      if fail:self.assertNotEqual(p.returncode,0,p.stdout[-1300:])
      else:self.assertEqual(p.returncode,0,p.stderr[-4300:]+"\n"+p.stdout[-2000:])
      return p.stdout,p.stderr
     sql(SCHEMA+src)
     # Intentional drift invalidates required exact textual match.
     tamper="CREATE OR REPLACE FUNCTION public.lf_profile_execution_begin_from_handoff_v1("+\
       "p_handoff jsonb,p_executor_mode text,p_execution_id text,p_idempotency_key text,"+\
       "p_actor_execution_id text,p_target_repo text,p_target_path text,p_manifest jsonb DEFAULT '{}'::jsonb)"+\
       " RETURNS jsonb LANGUAGE plpgsql AS $tam$ BEGIN RETURN '{}'::jsonb; END $tam$;"
     sql(tamper)
     _,err=sql(migration,fail=True)
     self.assertIn("LF_PREVIOUS_OUTPUTS_PATCH_NOT_APPLIED",err)
     sql(src)
     code="BEGIN;\n"+migration.split("BEGIN;",1)[1].rsplit("COMMIT;",1)[0]+"\n"+BEHAVIOR+\
       "\nROLLBACK;\nSELECT 'POST_ROLLBACK_RUN_COUNT='||count(*) FROM public.lf_operation_execution;\n"
     out,_=sql(code)
     for marker in (
      "PARENT_RESULT=READY","PARENT_OUTPUT_LENGTH=1",
      "PARENT_OUTPUT_REF=actions://real/parent/artifact",
      "PARENT_OUTPUT_SHA="+("f"*64),"PARENT_OUTPUT_SUMMARY_CHARS=500",
      "PARENT_NO_PROMOTION=false","NO_SOURCE_RESULT=READY",
      "NO_SOURCE_OUTPUT_LENGTH=0","NO_SOURCE_NO_PROMOTION=false",
      "MISSING_RESULT=BLOCK_PREVIOUS_OUTPUTS_MISSING","NO_GHOST=0",
      "POST_ROLLBACK_RUN_COUNT=0"
     ):
      self.assertIn(marker,out,marker+"\n"+out[-2600:])
     print("PASS_E10_E3_PG"+pg+"_PREVIOUS_OUTPUTS_FAIL_CLOSED_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__": unittest.main()
