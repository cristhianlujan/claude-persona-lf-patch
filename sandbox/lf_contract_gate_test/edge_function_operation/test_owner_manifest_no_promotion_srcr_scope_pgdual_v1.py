"""PG17/PG18: manifest.no_promotion true/false cannot deny existing SRCR scoped closure.
Only source helper redefinition is exercised in disposable PG; all effects ROLLBACK.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

from test_srcr_same_chat_candidate_scope_pgdual_v1 import (
    RUN, SRC, q, payload, helper_ddl, sql,
)

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT/"supabase/migrations/20261116001500_lf_owner_rule_promotion_score_and_manifest_neutral_v1.sql"

def revised_helper():
    source=MIG.read_text(encoding="utf-8")
    start="-- Owner neutralization: lf_profile_srcr_same_context_candidate_scope_v1"
    end="-- Owner neutralization: lf_profile_step70_clean_eval_context_verify_v1"
    a=source.index(start)
    b=source.index(end,a)
    sql_fragment=source[a:b]
    assert "CREATE OR REPLACE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1" in sql_fragment
    assert "no_promotion'<>'true'" not in sql_fragment
    return sql_fragment

class ManifestNeutralSRCRPGDual(unittest.TestCase):
    def test_manifest_true_false_missing_and_mutation_guard_pgdual(self):
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
        for pg in ("17.6","18.7"):
            with self.subTest(pg=pg):
                name="lf-nopromotion-neutral-"+uuid.uuid4().hex[:8]
                start=subprocess.run(["docker","run","-d","--rm","--name",name,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
                    capture_output=True,text=True,timeout=180)
                self.assertEqual(start.returncode,0,start.stderr[-2500:])
                try:
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                            capture_output=True,text=True,timeout=10)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=10)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr): break
                        time.sleep(.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")
                    manifest={
                        "executor_mode":"GPT_NATIVE","read_only":False,
                        "no_write":False,"no_promotion":True,
                        "governed_repair_write":True,"automatic_impact":False,
                        "router_profile_handoff":{"router_authorization_receipt":{"effect_authority":False}},
                    }
                    input_step={
                        "analysis_scope":"READ_ONLY_WITH_IG_FINDINGS",
                        "mutation_authorized":False,"promotion_authorized":False,
                        "input_governance":{"analysis_scope":"READ_ONLY_WITH_IG_FINDINGS"},
                        "allowed_actions":["ANALYZE","PROPOSE","VALIDATE","REPORT"],
                    }
                    producer={"profile_output":{"repair_execution":{"changes":[{
                        "target_ref":SRC,"after_ref":SRC,"before_ref":None,"change_type":"CREATE"
                    }]}}}
                    init="""CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE TABLE public.lf_operation_execution(
execution_id text PRIMARY KEY,status text,operation_code text,target_code text,manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps(
execution_id text,step_id text,status text,evidence_payload jsonb);
"""
                    init+=f"INSERT INTO public.lf_operation_execution VALUES ({q(RUN)},'IN_PROGRESS','EJECUCION_PERFIL_LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',{payload(manifest)});\n"
                    for step,ev in [
                        ("input_validate",input_step),
                        ("execute_profile",producer),
                        ("output_validate",{"deterministic_validation":{"status":"PASS"}}),
                    ]:
                        init+=f"INSERT INTO public.lf_operation_execution_steps VALUES ({q(RUN)},{q(step)},'STEP_PASS_WITH_EVIDENCE',{payload(ev)});\n"
                    sql(name,init+helper_ddl())
                    fn=f"public.lf_profile_srcr_same_context_candidate_scope_v1({q(RUN)})"
                    script=f"""BEGIN;
{revised_helper()}
SELECT 'TRUE_FLAG='||({fn})::text;
UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,'{{no_promotion}}','false'::jsonb);
SELECT 'FALSE_FLAG='||({fn})::text;
UPDATE public.lf_operation_execution SET manifest=manifest-'no_promotion';
SELECT 'MISSING_FLAG='||({fn})::text;
UPDATE public.lf_operation_execution_steps
 SET evidence_payload=jsonb_set(evidence_payload,'{{mutation_authorized}}','true'::jsonb)
 WHERE step_id='input_validate';
SELECT 'MUTATION_STILL_DENIED='||({fn})::text;
ROLLBACK;
"""
                    out=sql(name,script)
                    for marker in ("TRUE_FLAG=true","FALSE_FLAG=true","MISSING_FLAG=true",
                                   "MUTATION_STILL_DENIED=false"):
                        self.assertIn(marker,out,marker+"\n"+out)
                    self.assertEqual(sql(name,
                      "SELECT to_regprocedure('public.lf_profile_srcr_same_context_candidate_scope_v1(text)') IS NOT NULL;").strip(),"t")
                    print(f"PASS_MANIFEST_NO_PROMOTION_NEUTRAL_PG{pg}_SCOPE_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",name],
                        capture_output=True,text=True,timeout=30)

if __name__=="__main__":
    unittest.main()
