"""Actual live SRCR Step70 scope guard, strict no-effect CURRENT_CONTEXT_REVIEW; PG17/18."""
import shutil,subprocess,time,unittest,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
MIG_MATCHES=list((ROOT/"supabase/migrations").glob("*_lf_srcr_step70_governed_no_effect_context_v1.sql"))
assert len(MIG_MATCHES)==1,"SRCR_STEP70_MIGRATION_NOT_UNIQUE"
MIG=MIG_MATCHES[0]
SOURCE=Path(__file__).resolve().parent/"fixtures/lf_srcr_step70_scope_prepatch_live_v1.sql"
SCHEMA=r'''CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text,target_code text,status text,manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text,step_id text,status text,evidence_payload jsonb);
'''
TEST=r'''BEGIN;
INSERT INTO public.lf_operation_execution VALUES(
 'E12-VALID','EJECUCION_PERFIL_LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS',
 '{"executor_mode":"GPT_NATIVE","governed_repair_write":true,"read_only":false,"no_write":false,"automatic_impact":false,"router_profile_handoff":{"router_authorization_receipt":{"effect_authority":false}},"repair_execution_authority":{"mode":"GOVERNED_REPAIR_WRITE","promotion_allowed":false}}');
INSERT INTO public.lf_operation_execution_steps VALUES
 ('E12-VALID','input_validate','STEP_PASS_WITH_EVIDENCE',
 '{"analysis_scope":"GOVERNED_REPAIR","mutation_authorized":true,"promotion_authorized":false,"input_governance":{"analysis_scope":"GOVERNED_REPAIR"},"allowed_actions":["ANALYZE","PROPOSE","VALIDATE","REPORT"]}'),
 ('E12-VALID','execute_profile','STEP_PASS_WITH_EVIDENCE',
 '{"raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","profile_output":{"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED","changes":[],"promotion_performed":false}}}'),
 ('E12-VALID','output_validate','STEP_PASS_WITH_EVIDENCE',
 '{"raw_output_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","deterministic_validation":{"status":"PASS"}}');
SELECT 'POSITIVE='||public.lf_profile_srcr_same_context_candidate_scope_v1('E12-VALID');
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{profile_output,repair_execution,promotion_performed}','true'::jsonb) WHERE step_id='execute_profile';
SELECT 'NEG_PROMOTION='||public.lf_profile_srcr_same_context_candidate_scope_v1('E12-VALID');
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{profile_output,repair_execution,promotion_performed}','false'::jsonb) WHERE step_id='execute_profile';
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{profile_output,repair_execution,changes}','[{"target":"out-of-scope"}]'::jsonb) WHERE step_id='execute_profile';
SELECT 'NEG_CHANGES='||public.lf_profile_srcr_same_context_candidate_scope_v1('E12-VALID');
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{profile_output,repair_execution,changes}','[]'::jsonb) WHERE step_id='execute_profile';
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{analysis_scope}','"READ_ONLY_WITH_IG_FINDINGS"'::jsonb) WHERE step_id='input_validate';
SELECT 'NEG_SCOPE='||public.lf_profile_srcr_same_context_candidate_scope_v1('E12-VALID');
ROLLBACK;
SELECT 'NO_RESIDUE='||count(*) FROM public.lf_operation_execution;
'''
class SrcrGovernedStep70PGDual(unittest.TestCase):
 def test_no_effect_guard_real_source_pg17_pg18(self):
  self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertTrue(MIG.is_file())
  src=SOURCE.read_text(encoding="utf8")
  mig=MIG.read_text(encoding="utf8")
  for version in ("17.6","18.7"):
   with self.subTest(version=version):
    name="lf-e12-"+uuid.uuid4().hex[:10]
    p=subprocess.run(["docker","run","-d","--rm","--name",name,"-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],capture_output=True,text=True,timeout=180)
    self.assertEqual(p.returncode,0,p.stderr)
    try:
     for _ in range(90):
      ok=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,text=True,timeout=10)
      if ok.returncode==0:
       logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in logs.stdout+logs.stderr:break
      time.sleep(.5)
     self.assertEqual(ok.returncode,0,"PG_NOT_READY")
     def sql(s,fail=False):
      proc=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],input=s,capture_output=True,text=True,timeout=180)
      if fail:self.assertNotEqual(proc.returncode,0,"EXPECTED_NEGATIVE")
      else:self.assertEqual(proc.returncode,0,proc.stderr[-2500:]+"\n"+proc.stdout[-1000:])
      return proc.stdout,proc.stderr
     sql(SCHEMA+src)
     sql("CREATE OR REPLACE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id text) RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;")
     _,err=sql(mig,fail=True)
     self.assertIn("LF_SRCR_STEP70_GOVERNED_SOURCE_DRIFT",err)
     sql(src)
     sql(mig)
     output,_=sql(TEST)
     for marker in ("POSITIVE=true","NEG_PROMOTION=false","NEG_CHANGES=false","NEG_SCOPE=false","NO_RESIDUE=0"):
      self.assertIn(marker,output,marker+"\n"+output[-2500:])
     print("PASS_E12_SRCR_GOVERNED_NO_EFFECT_PG"+version+"_REAL_GUARD_NEGATIVE_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
