"""PG17.6/PG18.7 BEGIN/ROLLBACK against actual SRCR scope function source.

Positive only for honest governed NO-EFFECT repair. Wrong profile, mutations,
unsafe promotions, missing evidence, source drift and updated rules fail closed.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261116070001_lf_srcr_e12_step70_no_effect_context_v1.sql"
ORIG = ROOT / "supabase/migrations/20261115074500_lf_srcr_step70_same_native_conversation_candidate_v1.sql"
RUN = "EXEC-PROFILE-GATE2-TESTE12NOEFFECT000001"

def q(x):
    return "'" + x.replace("'", "''") + "'"

def j(x):
    return q(json.dumps(x, separators=(",", ":"), sort_keys=True)) + "::jsonb"

def psql(name, stmt, ok=True):
    proc = subprocess.run(["docker", "exec", "-i", name, "psql", "-X", "-A", "-t",
        "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
        input=stmt, text=True, capture_output=True, timeout=120)
    if ok and proc.returncode:
        raise AssertionError(proc.stderr[-3500:])
    if not ok and not proc.returncode:
        raise AssertionError("NEGATIVE_SHOULD_FAIL")
    return proc.stdout + proc.stderr

def original():
    src = ORIG.read_text(encoding="utf8")
    pos = src.index("CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(")
    end = src.index("CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1", pos)
    return src[pos:end]

class E12NoEffect(unittest.TestCase):
    def test_pg17(self): self.exercise("postgres:17.6")
    def test_pg18(self): self.exercise("postgres:18.7")

    def exercise(self, image):
        if not shutil.which("docker"):
            self.fail("DOCKER_REQUIRED_FOR_DUAL_PG_TEST")
        name = "lf-e12-review-" + uuid.uuid4().hex[:10]
        proc = subprocess.run(["docker","run","-d","--rm","--name",name,
           "-e","POSTGRES_PASSWORD=postgres",image],capture_output=True,text=True,timeout=150)
        self.assertEqual(proc.returncode,0,proc.stderr[-1600:])
        try:
            for _ in range(80):
                if subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
                      capture_output=True,text=True,timeout=10).returncode==0: break
                time.sleep(1)
            else: self.fail("PG_NOT_READY")
            self.verify(name)
        finally:
            subprocess.run(["docker","rm","-f",name],capture_output=True,text=True,timeout=30)

    def verify(self, name):
        mig = MIG.read_text(encoding="utf8")
        self.assertIn("LF_SRCR_E12_STEP70_NO_EFFECT_PATCH_NOT_APPLIED",mig)
        manifest = {"executor_mode":"GPT_NATIVE","governed_repair_write":True,
          "read_only":False,"no_write":False,"automatic_impact":False,
          "no_promotion":False,"repair_execution_authority":{"mode":"GOVERNED_REPAIR_WRITE","promotion_allowed":False},
          "router_profile_handoff":{"router_authorization_receipt":{"effect_authority":False},
            "scope":{"target_type":"PANTALLA","target_hint":"login B2B"}}}
        step40 = {"analysis_scope":"GOVERNED_REPAIR","mutation_authorized":True,
          "promotion_authorized":False,"input_governance":{"analysis_scope":"GOVERNED_REPAIR"},
          "resolved_scope":{"resolved_screen_code":"B2B-AUTH-001"},
          "allowed_actions":["ANALYZE","PROPOSE","VALIDATE","REPORT"]}
        raw = "2"*64
        step50 = {"raw_output_sha256":raw,"profile_output":{"status":"SYSTEMIC_REPAIR_SPEC",
          "repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED","changes":[],
             "promotion_performed":False}}}
        step60 = {"raw_output_sha256":raw,"deterministic_validation":{"status":"PASS"}}
        boot = """CREATE SCHEMA lf_ops;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE TABLE public.lf_operation_execution(
  execution_id text PRIMARY KEY,status text,operation_code text,target_code text,
  manifest jsonb,created_at timestamptz);
CREATE TABLE public.lf_operation_execution_steps(
  execution_id text,step_id text,status text,evidence_payload jsonb);
CREATE TABLE lf_ops.pantallas(id int PRIMARY KEY,codigo text);
CREATE TABLE lf_ops.reglas(id int PRIMARY KEY,updated_at timestamptz);
CREATE TABLE lf_ops.reglas_pantallas(pantalla_id int,regla_id int);
INSERT INTO lf_ops.pantallas VALUES (51,'B2B-AUTH-001');
INSERT INTO lf_ops.reglas VALUES (1,'2026-11-15T05:00:00Z');
INSERT INTO lf_ops.reglas_pantallas VALUES (51,1);
"""
        boot += (f"INSERT INTO public.lf_operation_execution VALUES("
             f"{q(RUN)},'IN_PROGRESS','EJECUCION_PERFIL_LF',"
             f"'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',{j(manifest)},'2026-11-16T06:10:10Z');\n")
        for step,body in [("input_validate",step40),("execute_profile",step50),("output_validate",step60)]:
            boot += (f"INSERT INTO public.lf_operation_execution_steps VALUES ("
                 f"{q(RUN)},{q(step)},'STEP_PASS_WITH_EVIDENCE',{j(body)});\n")
        psql(name,boot+original())
        fn="public.lf_profile_srcr_same_context_candidate_scope_v1("+q(RUN)+")"
        self.assertIn("f",psql(name,"SELECT ("+fn+")::text;"))
        invalid=original().replace(
           " IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL",
           " IF (v40 IS NULL) OR v50 IS NULL OR v60 IS NULL")
        self.assertNotEqual(invalid,original())
        psql(name,invalid)
        err=psql(name,mig,ok=False)
        self.assertIn("LF_SRCR_E12_STEP70_NO_EFFECT_PATCH_NOT_APPLIED",err)
        psql(name,original().replace("CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(", "CREATE OR REPLACE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1("))
        out=psql(name,"BEGIN;\n"+mig.strip().removeprefix("BEGIN;").strip().removesuffix("COMMIT;").strip()+f"""
SELECT 'GOOD|'||({fn})::text;
UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,'{{repair_execution_authority,promotion_allowed}}','true'::jsonb);
SELECT 'PROMOTION|'||({fn})::text;
UPDATE public.lf_operation_execution SET manifest=jsonb_set(manifest,'{{repair_execution_authority,promotion_allowed}}','false'::jsonb);
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{{profile_output,repair_execution,mode}}','"EXECUTED_WITH_READBACK"'::jsonb) WHERE step_id='execute_profile';
SELECT 'EFFECTS|'||({fn})::text;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{{profile_output,repair_execution,mode}}','"AUTHORIZED_NOT_EXECUTED"'::jsonb) WHERE step_id='execute_profile';
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{{input_governance,analysis_scope}}','"READ_ONLY_WITH_IG_FINDINGS"'::jsonb) WHERE step_id='input_validate';
SELECT 'STEP40_SCOPE|'||({fn})::text;
UPDATE public.lf_operation_execution_steps SET evidence_payload=jsonb_set(evidence_payload,'{{input_governance,analysis_scope}}','"GOVERNED_REPAIR"'::jsonb) WHERE step_id='input_validate';
UPDATE lf_ops.reglas SET updated_at='2026-11-16T06:20:10Z';
SELECT 'LINKED_RULE_MODIFIED|'||({fn})::text;
UPDATE lf_ops.reglas SET updated_at='2026-11-15T05:00:00Z';
UPDATE public.lf_operation_execution SET target_code='PERFIL-PRODUCT-DIRECTOR-LF';
SELECT 'WRONG_PROFILE|'||({fn})::text;
ROLLBACK;""")
        for expected in ["GOOD|true","PROMOTION|false","EFFECTS|false",
                         "STEP40_SCOPE|false","LINKED_RULE_MODIFIED|false","WRONG_PROFILE|false"]:
            self.assertIn(expected,out,(image,expected,out[-3000:]))
        rolled=psql(name,"SELECT ("+fn+")::text;")
        self.assertIn("false",rolled,"ROLLBACK_NOT_RESTORED")
        print("PASS_E12_NO_EFFECT_STEP70_"+image.replace(":","_")+"_ROLLBACK")

if __name__=="__main__":
    unittest.main()
