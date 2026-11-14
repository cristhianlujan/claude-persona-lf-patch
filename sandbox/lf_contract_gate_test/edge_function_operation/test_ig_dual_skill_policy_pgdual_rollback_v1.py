"""PG17.6/18.7: exact migration applied to disposable policy fixture and rolled back.
Confirms IG changes from required to selected-by-task, while SCREEN_RULES remains optional.
"""
import subprocess
import shutil
import time
import uuid
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[3]
SQL=ROOT/"supabase/migrations/20261114173326_lf_profile_ig_semantic_optional_dual_run_v1.sql"
FIXTURE="""
CREATE TABLE public.lf_skill_selector_policy_v1(
 profile_code text,skill_code text,channels text[],required_operation text,
 allowed_effects text[],selection_mode text,enabled boolean,owner_decision_required boolean,
 applicability_contract jsonb,policy_evidence_ref text,updated_at timestamptz);
INSERT INTO public.lf_skill_selector_policy_v1 VALUES
('PERFIL-PRODUCT-DIRECTOR-LF','INPUT_GOVERNANCE_CONTEXT_PACK',ARRAY['PRODUCTO'],
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY'],'DETERMINISTIC_REQUIRED',true,false,
 '{"source":"PROFILE_CURRENT_POLICY","owner_instruction":"2026-11-14","only_if_applicable":false}',
 'owner://lf/2026-11-14/skill-policy-active-by-design',now()),
('PERFIL-PRODUCT-DIRECTOR-LF','SCREEN_RULES_SNAPSHOT',ARRAY['PRODUCTO'],
 'EJECUCION_PERFIL_LF',ARRAY['READ_ONLY'],'SEMANTIC_OPTIONAL',true,false,
 '{"evaluation":"INPUT_REQUIRED_CONTRACT","only_if_applicable":false}',
 'owner://lf/2026-11-14/skill-policy-18-approved',now());
"""
class PgDualSkillPolicy(unittest.TestCase):
  def verify(self,image,version):
    self.assertIsNotNone(shutil.which("docker"))
    name="lf-ig-policy-"+uuid.uuid4().hex[:10]
    p=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=180)
    self.assertEqual(p.returncode,0,p.stderr[-1200:])
    try:
      for _ in range(90):
        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
          capture_output=True,timeout=6)
        if ready.returncode==0:break
        time.sleep(.8)
      else:self.fail("PG_READY_TIMEOUT")
      def run(sql,expect_error=None):
        p=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
          "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
          input=sql,text=True,capture_output=True,timeout=120)
        if expect_error:
          self.assertNotEqual(p.returncode,0)
          self.assertIn(expect_error,p.stderr)
        else:self.assertEqual(p.returncode,0,p.stderr[-3200:])
        return p.stdout.strip()
      self.assertTrue(run("SHOW server_version_num;").startswith(version))
      run(FIXTURE)
      src=SQL.read_text(encoding="utf-8")
      self.assertTrue(src.startswith("-- LF sandbox only."))
      inner=src.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
      old="SELECT selection_mode FROM public.lf_skill_selector_policy_v1 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';"
      self.assertEqual(run(old),"DETERMINISTIC_REQUIRED")
      out=run("BEGIN;\n"+inner+"\n"+old+"\nSELECT applicability_contract->>'only_if_applicable' FROM public.lf_skill_selector_policy_v1 WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';\nROLLBACK;\n"+old)
      self.assertEqual(out.splitlines(),["SEMANTIC_OPTIONAL","true","DETERMINISTIC_REQUIRED"],out)
      run("BEGIN; UPDATE public.lf_skill_selector_policy_v1 SET selection_mode='SEMANTIC_OPTIONAL' WHERE skill_code='INPUT_GOVERNANCE_CONTEXT_PACK';\n"+inner+"\nROLLBACK;",expect_error="LF_IG_DUAL_RUN_POLICY_PREIMAGE_DRIFT")
      self.assertEqual(run(old),"DETERMINISTIC_REQUIRED")
      print("PASS_IG_OPTIONAL_SKILL_POLICY_ROLLBACK_"+image,flush=True)
    finally:
      subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=45)
  def test_pg176(self):self.verify("postgres:17.6","170006")
  def test_pg187(self):self.verify("postgres:18.7","180007")
if __name__=="__main__":unittest.main()
