"""PG17/18 synthetic checks of bounded same-conversation SRCR scope, all ROLLBACK.

No real model judgment or source mutation is claimed by these fixtures.
"""
import json
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261115074500_lf_srcr_step70_same_native_conversation_candidate_v1.sql"
RUN = "EXEC-PROFILE-GATE2-TESTSRCRSAMECHAT0001"
SRC = "github://cristhianlujan/claude-persona-lf-patch@" + "a" * 40 + "/sandbox/lf_contract_gate_test/fixture.json"

def q(value):
    return "'" + value.replace("'", "''") + "'"

def payload(value):
    return q(json.dumps(value, sort_keys=True, separators=(",", ":"))) + "::jsonb"

def sql(docker, script, expected_success=True):
    p = subprocess.run(["docker", "exec", "-i", docker, "psql", "-X", "-A", "-t",
                        "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"],
                       input=script, capture_output=True, text=True, timeout=90)
    if expected_success and p.returncode:
        raise AssertionError(p.stderr[-2400:])
    if not expected_success and not p.returncode:
        raise AssertionError("NEGATIVE_SQL_SHOULD_FAIL")
    return p.stdout

def helper_ddl():
    s = MIG.read_text(encoding="utf-8")
    a = s.index("CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(")
    b = s.index("CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1", a)
    return s[a:b]

class ScopePgDual(unittest.TestCase):
    def test_pg17(self):
        self.exercise("postgres:17.6")

    def test_pg18(self):
        self.exercise("postgres:18.7")

    def exercise(self, image):
        if not shutil.which("docker"):
            self.fail("DOCKER_REQUIRED_FOR_PG17_PG18_ROLLBACK_TEST")
        name = "lf-samechat-" + uuid.uuid4().hex[:12]
        p = subprocess.run(["docker", "run", "-d", "--rm", "--name", name,
                            "-e", "POSTGRES_PASSWORD=postgres", image],
                           capture_output=True, text=True, timeout=150)
        self.assertEqual(p.returncode, 0, p.stderr[-1800:])
        try:
            for _ in range(75):
                x = subprocess.run(["docker", "exec", name, "pg_isready",
                                    "-U", "postgres"], capture_output=True,
                                   text=True, timeout=10)
                if x.returncode == 0:
                    break
                time.sleep(1)
            else:
                self.fail("PG_NOT_READY")
            self.check(name)
        finally:
            subprocess.run(["docker", "rm", "-f", name],
                           capture_output=True, text=True, timeout=30)

    def check(self, name):
        manifest = {
            "executor_mode": "GPT_NATIVE", "read_only": False,
            "no_write": False, "no_promotion": True,
            "governed_repair_write": True, "automatic_impact": False,
            "router_profile_handoff": {
                "router_authorization_receipt": {"effect_authority": False}
            },
        }
        input_step = {
            "analysis_scope": "READ_ONLY_WITH_IG_FINDINGS",
            "mutation_authorized": False, "promotion_authorized": False,
            "input_governance": {"analysis_scope": "READ_ONLY_WITH_IG_FINDINGS"},
            "allowed_actions": ["ANALYZE", "PROPOSE", "VALIDATE", "REPORT"],
        }
        producer = {"profile_output": {"repair_execution": {"changes": [
            {"target_ref": SRC, "after_ref": SRC,
             "before_ref": None, "change_type": "CREATE"}
        ]}}}
        script = """CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY, status text, operation_code text,
 target_code text, manifest jsonb);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text, step_id text, status text, evidence_payload jsonb);
"""
        script += (f"INSERT INTO public.lf_operation_execution VALUES("
                   f"{q(RUN)},'IN_PROGRESS','EJECUCION_PERFIL_LF',"
                   f"'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',{payload(manifest)});\n")
        for step, value in [
            ("input_validate", input_step), ("execute_profile", producer),
            ("output_validate", {"deterministic_validation": {"status": "PASS"}}),
        ]:
            script += (f"INSERT INTO public.lf_operation_execution_steps VALUES("
                       f"{q(RUN)},{q(step)},'STEP_PASS_WITH_EVIDENCE',{payload(value)});\n")
        sql(name, script)
        fn = f"public.lf_profile_srcr_same_context_candidate_scope_v1({q(RUN)})"
        statement = f"""BEGIN;
{helper_ddl()}
SELECT 'VALID|'||({fn})::text;
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,'{{no_promotion}}','false'::jsonb);
SELECT 'PROMOTION|'||({fn})::text;
UPDATE public.lf_operation_execution
 SET manifest=jsonb_set(manifest,'{{no_promotion}}','true'::jsonb);
UPDATE public.lf_operation_execution_steps
 SET evidence_payload=jsonb_set(evidence_payload,'{{mutation_authorized}}','true'::jsonb)
 WHERE step_id='input_validate';
SELECT 'MUTATION|'||({fn})::text;
UPDATE public.lf_operation_execution_steps
 SET evidence_payload=jsonb_set(evidence_payload,'{{mutation_authorized}}','false'::jsonb)
 WHERE step_id='input_validate';
UPDATE public.lf_operation_execution_steps
 SET evidence_payload=jsonb_set(evidence_payload,'{{allowed_actions}}','["ANALYZE","APPLY"]'::jsonb)
 WHERE step_id='input_validate';
SELECT 'ACTION|'||({fn})::text;
ROLLBACK;
"""
        out = sql(name, statement)
        for expected in ("VALID|true", "PROMOTION|false",
                         "MUTATION|false", "ACTION|false"):
            self.assertIn(expected, out)
        check = sql(name, "SELECT to_regprocedure("
                          "'public.lf_profile_srcr_same_context_candidate_scope_v1(text)') IS NULL;")
        self.assertEqual(check.strip(), "t", "ROLLBACK_LEAK")

if __name__ == "__main__":
    unittest.main()
