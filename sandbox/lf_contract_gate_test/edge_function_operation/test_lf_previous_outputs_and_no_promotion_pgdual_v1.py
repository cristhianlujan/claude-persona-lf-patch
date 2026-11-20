"""Live begin-from-handoff target source; PG17/18 BEGIN/ROLLBACK, missing source blocks."""
import shutil, subprocess, time, unittest, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_previous_outputs_and_no_promotion_off_v1.sql"))
SOURCE=Path(__file__).resolve().parent/"fixtures/lf_previous_outputs_begin_prepatch_live_v1.sql"
SCHEMA=r"""
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,manifest jsonb NOT NULL DEFAULT '{}'::jsonb);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,step_id text NOT NULL,status text NOT NULL,
 evidence_ref text, evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 observed_at timestamptz NOT NULL DEFAULT now());
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_validate_v1(jsonb,text,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"valid":true,"governed_repair_write_allowed":false}'::jsonb$$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_executor_admission_v1(text,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"admitted":true}'::jsonb$$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_begin_v1(
 text,text,text,text,text,text,text,jsonb)
 RETURNS jsonb LANGUAGE plpgsql AS $f$
 BEGIN
  INSERT INTO public.lf_operation_execution(execution_id,manifest)
    VALUES($1,$8);
  RETURN '{"status":"READY"}'::jsonb;
 END $f$;
CREATE OR REPLACE FUNCTION public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)
 RETURNS jsonb LANGUAGE sql AS $$SELECT '{"status":"STEP_PASS_WITH_EVIDENCE"}'::jsonb$$;
"""
TEST=r"""
BEGIN;
INSERT INTO public.lf_operation_execution_steps(
 execution_id,step_id,status,evidence_ref,evidence_payload)
VALUES('SRC-OK','execute_profile','STEP_PASS_WITH_EVIDENCE',
 'actions://actual/source/step50','{"raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","profile_output":{"summary":"verified canonical Step50"}}');
SELECT 'WITH_SOURCE='||(public.lf_profile_execution_begin_from_handoff_v1(
 jsonb_build_object('profile_code','PERFIL-TEST','literal_request','test',
 'scope',jsonb_build_object('source_execution_id','SRC-OK'),
 'request_sha256',repeat('b',64)),
 'GPT_NATIVE','E10-WITH','idem-1','actor-1','repo','profile-path','{}'::jsonb)->>'status');
SELECT 'PREV_COUNT='||jsonb_array_length(manifest->'previous_outputs')
 FROM public.lf_operation_execution WHERE execution_id='E10-WITH';
SELECT 'PREV_REF='||(manifest#>>'{previous_outputs,0,output_ref}')
 FROM public.lf_operation_execution WHERE execution_id='E10-WITH';
SELECT 'PREV_SUMMARY='||(manifest#>>'{previous_outputs,0,summary}')
 FROM public.lf_operation_execution WHERE execution_id='E10-WITH';
SELECT 'PROMOTION_FLAG_WITH='||(manifest->>'no_promotion')
 FROM public.lf_operation_execution WHERE execution_id='E10-WITH';
SELECT 'NO_SOURCE='||(public.lf_profile_execution_begin_from_handoff_v1(
 jsonb_build_object('profile_code','PERFIL-TEST','literal_request','test','request_sha256',repeat('b',64)),
 'GPT_NATIVE','E10-WITHOUT','idem-2','actor-1','repo','profile-path','{}'::jsonb)->>'status');
SELECT 'PREV_EMPTY='||jsonb_array_length(manifest->'previous_outputs')
 FROM public.lf_operation_execution WHERE execution_id='E10-WITHOUT';
SELECT 'PROMOTION_FLAG_NO_SOURCE='||(manifest->>'no_promotion')
 FROM public.lf_operation_execution WHERE execution_id='E10-WITHOUT';
SELECT 'MISSING_SOURCE='||(
 public.lf_profile_execution_begin_from_handoff_v1(
 jsonb_build_object('profile_code','PERFIL-TEST','literal_request','test',
 'scope',jsonb_build_object('source_execution_id','SRC-NO50'),
 'request_sha256',repeat('b',64)),
 'GPT_NATIVE','E10-MISSING','idem-3','actor-1','repo','profile-path','{}'::jsonb)
 ->>'blocking_code');
SELECT 'NO_FORGED_RUN='||count(*) FROM public.lf_operation_execution WHERE execution_id='E10-MISSING';
ROLLBACK;
SELECT 'NO_RESIDUE='||count(*) FROM public.lf_operation_execution;
"""
class PreviousOutputsPGDual(unittest.TestCase):
 def test_real_begin_source_and_migration_pgdual(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertEqual(len(MIGS),1)
  src=SOURCE.read_text(encoding="utf-8")
  migration=MIGS[0].read_text(encoding="utf-8")
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-e10-"+uuid.uuid4().hex[:10]
    r=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],capture_output=True,text=True,timeout=180)
    self.assertEqual(r.returncode,0,r.stderr[-1500:])
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
         capture_output=True,text=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(q,fail=False):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t","-v","ON_ERROR_STOP=1",
      "-U","postgres","-d","postgres"],input=q,capture_output=True,text=True,timeout=180)
      if fail:self.assertNotEqual(p.returncode,0,"EXPECTED NEGATIVE FAIL")
      else:self.assertEqual(p.returncode,0,p.stderr[-5000:]+"\n"+p.stdout[-2500:])
      return p.stdout,p.stderr
     sql(SCHEMA+"\n"+src)
     sql("CREATE OR REPLACE FUNCTION public.lf_profile_execution_begin_from_handoff_v1("
        "p_handoff jsonb,p_executor_mode text,p_execution_id text,p_idempotency_key text,"
        "p_actor_execution_id text,p_target_repo text,p_target_path text,"
        "p_manifest jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql "
        "AS $$ SELECT '{}'::jsonb $$;")
     out,err=sql(migration,fail=True)
     self.assertIn("LF_PREVIOUS_OUTPUTS_PATCH_NOT_APPLIED",err)
     sql(src)
     sql(migration)
     out,err=sql(TEST)
     for marker in (
       "WITH_SOURCE=READY","PREV_COUNT=1",
       "PREV_REF=actions://actual/source/step50",
       "PREV_SUMMARY=verified canonical Step50",
       "PROMOTION_FLAG_WITH=false","NO_SOURCE=READY",
       "PREV_EMPTY=0","PROMOTION_FLAG_NO_SOURCE=false",
       "MISSING_SOURCE=BLOCK_PREVIOUS_OUTPUTS_MISSING","NO_FORGED_RUN=0",
       "NO_RESIDUE=0"):
      self.assertIn(marker,out,marker+"\n"+out[-2800:])
     print("PASS_E10_E3_PREVIOUS_OUTPUTS_PG"+pg+"_REAL_FUNCTION_NEGATIVE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
