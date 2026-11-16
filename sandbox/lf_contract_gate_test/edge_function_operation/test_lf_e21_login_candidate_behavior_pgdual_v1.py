"""E21 Login candidates: PG17/18 parameterized source/runtime-readiness negative gate.

IMPORTANT: A registry check, a synthetic auth algorithm, a SQL fixture, and
a green CI run are NOT behavioral tests of LF_AUTH_BOUNDARY. This suite marks
each missing live target NOT_TESTABLE, never PG17/18 PASS for a rule, and NEVER
writes lf_ops.regla_behavior_tests in the actual Supabase project.

The two PG versions run a real PostgreSQL rollback test of admission
preconditions. Until a runnable Login/OTP/UI implementation with per-rule
positive and negative probes exists, its business behavior is NOT certified.
"""
import json
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
FIXTURE=HERE/"fixtures/lf_e21_login_candidate_behavior_scope_v1.json"
SCOPE=json.loads(FIXTURE.read_text(encoding="utf-8"))
RULES=SCOPE["scenarios"]
CODES=[x["rule_code"] for x in RULES]
TRANSVERSALS={
 "B2B-RULE-AUTH-001","B2B-RULE-PRIVACY-001","B2B-RULE-RATE-001",
 "B2B-RULE-SESSION-002","B2B-RULE-TIMEOUT-001",
}

def escaped(s):
    return "'" + str(s).replace("'","''") + "'"

def pg_sql():
    rows=",\n".join("(" + ",".join([
        escaped(r["rule_code"]),escaped(r["estado"]),
        "true" if r["es_transversal"] else "false",
        "true" if r["pendiente_decision"] else "false",
        escaped(r["transversal_vigente_ref"]),
        escaped(r["blocking_code"]),
    ]) + ")" for r in RULES)
    references=",\n".join(f"({escaped(x)},'VIGENTE')" for x in sorted(TRANSVERSALS))
    return f"""
BEGIN;
CREATE SCHEMA lf_ops;
CREATE SCHEMA programacion;
CREATE TABLE lf_ops.reglas(
 codigo text PRIMARY KEY,estado text NOT NULL,es_transversal boolean NOT NULL,
 pendiente_decision boolean NOT NULL,transversal_ref text NOT NULL,
 blocking_code text NOT NULL
);
CREATE TABLE lf_ops.transversal_reference(
 codigo text PRIMARY KEY, estado text NOT NULL
);
CREATE TABLE lf_ops.regla_behavior_tests(
 regla_codigo text NOT NULL,test_ref text NOT NULL,ci_run text NOT NULL,
 pg17 text NOT NULL,pg18 text NOT NULL,source_sha text
);
CREATE TABLE programacion.contratos(
 contrato_codigo text PRIMARY KEY, especificacion jsonb NOT NULL
);
INSERT INTO lf_ops.transversal_reference VALUES {references};
INSERT INTO lf_ops.reglas VALUES {rows};
INSERT INTO programacion.contratos(contrato_codigo,especificacion)
VALUES('B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT',
 '{{"logical_contract_only":true,"runtime_activation":false,
    "physical_binding":{{"endpoint":"UNBOUND"}},
    "implementation_status":"PENDING_IDENTITY_BINDING_QA"}}'::jsonb);
DO $verify$
DECLARE r record; n int:=0; ready boolean; missing text:='';
BEGIN
 SELECT (
    c.especificacion->>'logical_contract_only'='false'
    AND c.especificacion->>'runtime_activation'='true'
    AND c.especificacion#>>'{{physical_binding,endpoint}}' NOT IN ('UNBOUND','UNDEFINED','')
 ) INTO ready FROM programacion.contratos c
 WHERE c.contrato_codigo='B2B_AUTH_LOGIN_LOGICAL_BOUNDARY_CONTRACT';
 IF coalesce(ready,true) THEN
    RAISE EXCEPTION 'E21_UNBOUND_RUNTIME_WAS_ACCEPTED';
 END IF;
 FOR r IN SELECT * FROM lf_ops.reglas ORDER BY codigo LOOP
    n:=n+1;
    IF r.estado<>'CANDIDATO' OR
       NOT EXISTS (SELECT 1 FROM lf_ops.transversal_reference t
                   WHERE t.codigo=r.transversal_ref AND t.estado='VIGENTE') THEN
      RAISE EXCEPTION 'E21_CANDIDATE_OR_TRANSVERSAL_DRIFT:%',r.codigo;
    END IF;
    -- A rule's business behavior is NOT run here. Every candidate lacks
    -- a verified runnable provider/controller, so no PASS may be registered.
    IF nullif(r.blocking_code,'') IS NULL THEN
       RAISE EXCEPTION 'E21_UNEXPLAINED_UNTESTABLE_RULE:%',r.codigo;
    END IF;
 END LOOP;
 IF n<>40 OR (SELECT count(*) FROM lf_ops.reglas WHERE NOT pendiente_decision)<>38
    OR (SELECT count(*) FROM lf_ops.reglas WHERE es_transversal)<>1 THEN
      RAISE EXCEPTION 'E21_LIVE_CANDIDATE_SCOPE_DRIFT:%',n;
 END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.regla_behavior_tests) THEN
      RAISE EXCEPTION 'E21_SYNTHETIC_A_PASS_WOULD_BE_FORBIDDEN';
 END IF;
END $verify$;
SELECT 'E21_READINESS_NOT_BEHAVIOR_PASS=PASS' AS proof;
ROLLBACK;
SELECT 'E21_ROLLBACK_CLEAN='||
  (to_regclass('lf_ops.regla_behavior_tests') IS NULL) AS rollback_proof;
"""

class LoginCandidateBehaviorPreconditions(unittest.TestCase):
    def test_source_inventory_38_unblocked_plus_2_pending_without_fabricated_ci(self):
        self.assertEqual(len(CODES),40)
        self.assertEqual(len(set(CODES)),40)
        self.assertEqual(sum(not r["pendiente_decision"] for r in RULES),38)
        self.assertEqual(sum(r["es_transversal"] for r in RULES),1)
        self.assertEqual(SCOPE["source_summary"]["specific"],39)
        self.assertEqual(SCOPE["source_summary"]["specific_without_owner_pending"],37)
        self.assertEqual(SCOPE["contract"]["runtime_activation"],False)
        self.assertEqual(SCOPE["contract"]["physical_endpoint"],"UNBOUND")
        for r in RULES:
            with self.subTest(rule=r["rule_code"]):
                self.assertEqual(r["estado"],"CANDIDATO")
                self.assertIn(r["transversal_vigente_ref"],TRANSVERSALS)
                self.assertEqual(r["eligibility"],"NOT_TESTABLE")
                self.assertIsNone(r["behavior_ci_run"])
                self.assertIsNone(r["pg17_behavior"])
                self.assertIsNone(r["pg18_behavior"])
                self.assertTrue(r["blocking_code"])
        self.assertEqual(
          {r["rule_code"] for r in RULES if r["pendiente_decision"]},
          {"B2B-RULE-AUTH-047","B2B-RULE-AUTH-049"})

    def test_pg17_pg18_begin_rollback_no_false_behavior_receipt(self):
        self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
        for version in ("17.6","18.7"):
            with self.subTest(pg=version):
                container="lf-e21-notestable-"+uuid.uuid4().hex[:10]
                cmd=["docker","run","-d","--rm","--name",container,
                    "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version]
                run=subprocess.run(cmd,text=True,capture_output=True,timeout=180)
                self.assertEqual(run.returncode,0,run.stderr)
                try:
                    for _ in range(100):
                        status=subprocess.run(["docker","exec",container,"pg_isready",
                            "-U","postgres"],text=True,capture_output=True,timeout=12)
                        if status.returncode==0:
                            logs=subprocess.run(["docker","logs",container],
                                text=True,capture_output=True,timeout=12)
                            if "PostgreSQL init process complete; ready for start up." in (
                                    logs.stdout+logs.stderr):
                                break
                        time.sleep(.5)
                    self.assertEqual(status.returncode,0,"PG_STARTUP_UNAVAILABLE")
                    p=subprocess.run(["docker","exec","-i",container,"psql",
                        "-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres",
                        "-d","postgres"],input=pg_sql(),text=True,capture_output=True,timeout=180)
                    self.assertEqual(p.returncode,0,p.stderr[-5000:]+"\n"+p.stdout[-2500:])
                    self.assertIn("E21_READINESS_NOT_BEHAVIOR_PASS=PASS",p.stdout)
                    self.assertIn("E21_ROLLBACK_CLEAN=true",p.stdout)
                    print("PASS_E21_LOGIN_READINESS_NO_FALSE_A_PG"+
                          version+"_ROLLBACK",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",container],
                        capture_output=True,timeout=30)

# DYNAMIC, PER-RULE PARAMETRIZATION. These are explicit SKIPS, NOT a claim
# to have tested the real Login, MFA, Brevo, browser, WAF, or OIDC behavior.
# When a runnable implementation appears, replace each skip with a genuinely
# executable positive+negative test and register CI only after both PG passes.
class LoginCandidateRuntimeBehaviors(unittest.TestCase):
    pass

for _candidate in RULES:
    def _case(self, spec=_candidate):
        self.skipTest("NO_REAL_BEHAVIOR_IMPLEMENTATION:"+spec["rule_code"]+
                      ":"+spec["blocking_code"]+
                      ":reference="+spec["transversal_vigente_ref"])
    setattr(LoginCandidateRuntimeBehaviors,
        "test_actual_behavior_"+re.sub(r"[^A-Za-z0-9]","_",_candidate["rule_code"]),
        _case)

if __name__=="__main__":
    unittest.main()
