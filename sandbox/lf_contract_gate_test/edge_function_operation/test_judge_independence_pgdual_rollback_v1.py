"""LF: Postgres 17.6/18.7 ROLLBACK with three completed original RUNs.

A new finding cannot rewrite canonical Step70/80 or retroactively create
independent review proof. Mode is READ_ONLY_REEVALUATION, not a second model call.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIX = ROOT / "sandbox/lf_contract_gate_test/edge_function_operation/fixture_judge_independence_live_pgdual_v1.sql"
MIG = ROOT / "supabase/migrations/20261114203100_lf_judge_independence_skill_selector_contract_v1.sql"

CHECK = r"""
DO $audit$
DECLARE r record; n integer;
BEGIN
 SELECT count(*) INTO n FROM public.lf_profile_semantic_independence_finding_v1;
 IF n<>3 THEN RAISE EXCEPTION 'JUDGE_IMMUTABLE_FINDINGS_NOT_THREE:%',n; END IF;
 FOR r IN SELECT execution_id FROM public.lf_operation_execution
  WHERE status='COMPLETED' ORDER BY execution_id LOOP
  IF (public.lf_profile_semantic_independence_readback_v1(r.execution_id)->>'status')
       IS DISTINCT FROM 'FINDING_RECORDED'
    OR (public.lf_profile_semantic_terminal_recheck_v1(r.execution_id)->>'canonical_step_reexecution_performed')
       IS DISTINCT FROM 'false'
    OR (public.lf_profile_semantic_terminal_recheck_v1(r.execution_id)->>'finding_code')
       IS DISTINCT FROM 'JUDGE_INDEPENDENCE_NOT_PROVEN'
    OR (public.lf_profile_semantic_terminal_recheck_v1(r.execution_id)->>'same_execution_id')
       IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'JUDGE_FINDING_INVALID_FOR:%',r.execution_id; END IF;
 END LOOP;
 IF (SELECT count(*) FROM public.lf_operation_execution_steps)!=6
   OR (SELECT count(*) FROM public.lf_operation_execution WHERE status='COMPLETED')!=3
 THEN RAISE EXCEPTION 'HISTORICAL_STEPS_CHANGED';END IF;
 IF position('SKILL_SELECTION_REQUESTED' IN pg_get_functiondef(
   'public.lf_profile_skill_selection_prepare_v1(text,text,jsonb)'::regprocedure))=0
  OR position('SKILL_SELECTION_PENDING_FINDING' IN pg_get_functiondef(
   'public.lf_profile_skill_selection_prepare_v1(text,text,jsonb)'::regprocedure))=0
  OR position('SUBMIT_SKILL_SELECTION' IN pg_get_functiondef(
   'public.lf_profile_skill_selection_prepare_v1(text,text,jsonb)'::regprocedure))=0
  OR position('selected_skill_codes' IN pg_get_functiondef(
   'public.lf_profile_skill_selection_prepare_v1(text,text,jsonb)'::regprocedure))=0
  OR position('skill_candidates' IN pg_get_functiondef(
   'public.lf_profile_skill_selection_prepare_v1(text,text,jsonb)'::regprocedure))=0
 THEN RAISE EXCEPTION 'SKILL_V1_VOCABULARY_INCOMPLETE'; END IF;
 IF position('JUDGE_INDEPENDENCE_UNVERIFIED_AUTHORITY_CLAIM' IN pg_get_functiondef(
   'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'INDEPENDENT_CLAIM_FAIL_CLOSED_MISSING'; END IF;
 IF position('JUDGE_INDEPENDENCE_NOT_PROVEN' IN pg_get_functiondef(
   'public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))=0
 OR position('judge_independence_status' IN pg_get_functiondef(
   'public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure))=0
 THEN RAISE EXCEPTION 'JUDGE_FINDING_NOT_PROPAGATED';END IF;
END $audit$;
SELECT public.lf_profile_skill_selection_prepare_v1('PERFIL-PRODUCT-DIRECTOR-LF','PRODUCTO',NULL)->>'finding_status';
SELECT 'PASS_LF_JUDGE_INDEPENDENCE_FINDINGS_AND_V1_NAMES_3RUN_ROLLBACK';
"""

class JudgeIndependencePgDualRollback(unittest.TestCase):
    def test_pg17_6(self):
        self.run_pg("postgres:17.6", "170006")

    def test_pg18_7(self):
        self.run_pg("postgres:18.7", "180007")

    def run_pg(self, image, version):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        name="lf-judge-independ-"+uuid.uuid4().hex[:10]
        started=subprocess.run(["docker","run","--rm","-d","--name",name,
                                "-e","POSTGRES_PASSWORD=postgres",image],
                               capture_output=True,text=True,timeout=120)
        self.assertEqual(started.returncode,0,started.stderr)
        try:
            for _ in range(70):
                h=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                    capture_output=True,text=True,timeout=8)
                if h.returncode==0:
                    logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=8)
                    if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                        break
                time.sleep(1)
            else:self.fail("POSTGRES_NOT_READY")
            def execute(sql, expect_failure=False):
                p=subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
                                  "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                    input=sql,text=True,capture_output=True,timeout=140)
                if expect_failure:
                    self.assertNotEqual(p.returncode,0)
                else:
                    self.assertEqual(p.returncode,0,p.stderr[-7000:])
                return p.stdout
            self.assertTrue(execute("SHOW server_version_num;").strip().startswith(version))
            execute(FIX.read_text(encoding="utf8"))
            pre_hash=execute("SELECT md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));").strip()
            self.assertEqual(len(pre_hash),32)
            mig=MIG.read_text(encoding="utf8")
            self.assertTrue(mig.startswith("-- LF sandbox"))
            self.assertTrue(mig.rstrip().endswith("COMMIT;"))
            body=mig.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
            result=execute("BEGIN;\n"+body+"\n"+CHECK+"\nROLLBACK;\n"
                "SELECT to_regclass('public.lf_profile_semantic_independence_finding_v1') IS NULL;\n"
                "SELECT md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure));")
            self.assertIn("PASS_LF_JUDGE_INDEPENDENCE_FINDINGS_AND_V1_NAMES_3RUN_ROLLBACK",result)
            self.assertIn("SKILL_SELECTION_PENDING_FINDING",result)
            self.assertEqual(result.strip().splitlines()[-2:],[ "t",pre_hash])
            print("PASS_JUDGE_INDEPENDENCE_FUTURE_AND_HISTORICAL_PG"+version,flush=True)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=40)

if __name__=="__main__":
    unittest.main()
