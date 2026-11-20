"""P51 manual owner-approved 22-definition promotion: PG17.6/PG18.7 fixtures ONLY.

Every migration test substitutes the final COMMIT with ROLLBACK. No connected
Supabase project, production data, human assertion, role grant, or real approval.
Existing source functions are reconstructed from the same PG17/18 fixture used
by test_lf_ig0815_auto_score_promotion_pgdual_v1.py.
"""
import re
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

from test_lf_ig0815_auto_score_promotion_pgdual_v1 import (
    SCHEMA,
    SOURCE,
    MIGRATION as IG0815_MIGRATION,
)

BASE = Path(__file__).resolve().parents[3]
MIGRATION = BASE / "supabase/migrations/20261116201600_lf_p51_manual_promotion_22_v1.sql"
RUN = "EXEC-PROFILE-GATE2-F9D127E87575564A021B3F10"
RULES = [
    "B2B-RULE-AUTH-004", "B2B-RULE-AUTH-005", "B2B-RULE-AUTH-006",
    "B2B-RULE-AUTH-007", "B2B-RULE-AUTH-011", "B2B-RULE-AUTH-012",
    "B2B-RULE-AUTH-013", "B2B-RULE-AUTH-014", "B2B-RULE-AUTH-017",
    "B2B-RULE-AUTH-018", "B2B-RULE-AUTH-019", "B2B-RULE-AUTH-020",
    "B2B-RULE-AUTH-021", "B2B-RULE-AUTH-023", "B2B-RULE-AUTH-024",
    "B2B-RULE-AUTH-025", "B2B-RULE-AUTH-026", "B2B-RULE-AUTH-036",
    "B2B-RULE-AUTH-040", "B2B-RULE-AUTH-048",
    "B2B-RULE-AUTH-STATE-001", "B2B-RULE-SECURITY-BASELINE-001",
]
EXCLUDED = [
    "B2B-RULE-AUTH-047", "B2B-RULE-AUTH-049",
    "B2B-RULE-RATE-001", "B2B-RULE-TIMEOUT-001",
    "B2B-RULE-AUTH-035",
]
ORDER = [0, 10, 20, 30, 40, 45, 47, 50, 60, 70, 80]
def sql_arr(items):
    return "ARRAY[" + ",".join("'" + x + "'" for x in items) + "]::text[]"

SETUP = """
-- Fixture only: a 64-character structural snapshot, not real production SHA.
ALTER TABLE lf_ops.reglas ADD COLUMN id integer GENERATED ALWAYS AS IDENTITY;
CREATE TABLE lf_ops.reglas_pantallas(
  id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  regla_id integer NOT NULL,
  pantalla_id integer NOT NULL,
  nota text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION public.lf_asset_snapshot_sha_v1(p_type text,p_rule_code text)
 RETURNS text LANGUAGE sql STABLE AS $snapshot$
 SELECT repeat(md5(r.codigo||'|'||r.estado||'|'||r.categoria||'|'||
                  r.pendiente_decision::text||'|'||r.updated_at::text),2)
 FROM lf_ops.reglas r WHERE p_type='REGLA' AND r.codigo=p_rule_code
 $snapshot$;
INSERT INTO public.lf_profile_write_authority_v1
 VALUES ('PERFIL-PRODUCT-DIRECTOR-LF','PROMOCION_REGLA_LF','ACTIVE');
INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision,updated_at)
 SELECT code,'CANDIDATO','UX',false,now()-interval '2 hours'
 FROM unnest(%(rules)s || %(excluded)s) AS code;
INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id)
 SELECT id, CASE WHEN codigo='B2B-RULE-AUTH-035' THEN 55 ELSE 51 END
 FROM lf_ops.reglas;
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,target_code,status)
 VALUES ('%(run)s','EJECUCION_PERFIL_LF','PERFIL-PRODUCT-DIRECTOR-LF','COMPLETED');
INSERT INTO public.lf_operation_execution_steps
 (execution_id,step_order,step_id,status,evidence_payload,observed_at)
SELECT '%(run)s',n,
 CASE n WHEN 0 THEN 'init_execution' WHEN 10 THEN 'router'
 WHEN 20 THEN 'profile_resolve' WHEN 30 THEN 'profile_source_read'
 WHEN 40 THEN 'input_validate' WHEN 45 THEN 'context_admission'
 WHEN 47 THEN 'research_baseline_freeze' WHEN 50 THEN 'execute_profile'
 WHEN 60 THEN 'output_validate' WHEN 70 THEN 'semantic_judge'
 ELSE 'report_output' END,
 'STEP_PASS_WITH_EVIDENCE',
 CASE n WHEN 40 THEN
   jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('b',64))
 WHEN 50 THEN jsonb_build_object('raw_output_sha256',repeat('a',64),
   'profile_output',jsonb_build_object('deliverable_created',
     jsonb_build_object('product_decision',
       jsonb_build_object('source_refs',
         (SELECT jsonb_agg(jsonb_build_object(
          'source_ref','supabase://lf_ops.reglas/'||r)) FROM unnest(%(rules)s) r)))))
 WHEN 60 THEN jsonb_build_object('raw_output_sha256',repeat('a',64))
 WHEN 70 THEN jsonb_build_object('semantic_judge_result',
   jsonb_build_object('verdict','PASS_REVIEWED_CURRENT_CONTEXT',
     'candidate_sha256',repeat('a',64),'scope_packet_sha256',repeat('b',64),
     'judge_v3_evidence',jsonb_build_object('unsupported_claims','[]'::jsonb)))
 ELSE '{}'::jsonb END,
 now()
FROM unnest(ARRAY[0,10,20,30,40,45,47,50,60,70,80]) AS n;
""" % {"rules": sql_arr(RULES), "excluded": sql_arr(EXCLUDED), "run": RUN}

# Synthetic mutations happen inside the same transaction as the attempted
# migration. Expected exceptions cannot commit partially applied earlier rules.
NEGATIVES = {
    "score_insufficient": (
        "UPDATE lf_ops.reglas SET updated_at=now() "
        "WHERE codigo='B2B-RULE-AUTH-004';",
        "LF_P51_MANUAL_SCORE_DRIFT:B2B-RULE-AUTH-004",
    ),
    "hard_block": (
        "UPDATE lf_ops.reglas SET categoria='LEGAL' "
        "WHERE codigo='B2B-RULE-AUTH-004';",
        "LF_P51_MANUAL_SCORE_DRIFT:B2B-RULE-AUTH-004",
    ),
    "pending_decision": (
        "UPDATE lf_ops.reglas SET pendiente_decision=true "
        "WHERE codigo='B2B-RULE-AUTH-004';",
        "LF_P51_COHORT_CHANGED_FROM_OWNER_22",
    ),
    "run_incomplete": (
        "DELETE FROM public.lf_operation_execution_steps "
        "WHERE execution_id='" + RUN + "' AND step_order=47;",
        "LF_P51_PARENT_NOT_CLEAN_11_OF_11",
    ),
    "duplicate_request": (
        "INSERT INTO public.lf_rule_promotion_v1 "
        "(rule_code,request_execution_id,requested_by_profile,status)"
        " VALUES ('B2B-RULE-AUTH-004','" + RUN + "',"
        "'PERFIL-PRODUCT-DIRECTOR-LF','PENDING');",
        "LF_P51_PROMOTION_ALREADY_EXISTS:B2B-RULE-AUTH-004",
    ),
    "cohort_expansion": (
        "INSERT INTO lf_ops.reglas(codigo,estado,categoria,pendiente_decision,"
        "updated_at) VALUES ('B2B-RULE-AUTH-099','CANDIDATO','UX',false,"
        "now()-interval '2 hours'); "
        "INSERT INTO lf_ops.reglas_pantallas(regla_id,pantalla_id) "
        "SELECT id,51 FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-099';",
        "LF_P51_COHORT_CHANGED_FROM_OWNER_22",
    ),
    "stale_snapshot": (
        """CREATE FUNCTION public.lf_p51_fixture_stale() RETURNS trigger
          LANGUAGE plpgsql AS $f$
          BEGIN UPDATE lf_ops.reglas SET updated_at=now()
            WHERE codigo=NEW.rule_code; RETURN NEW; END $f$;
          CREATE TRIGGER lf_p51_fixture_after_request
          AFTER INSERT ON public.lf_rule_promotion_v1
          FOR EACH ROW EXECUTE FUNCTION public.lf_p51_fixture_stale();""",
        "LF_P51_PROMOTION_STALE_BEFORE_DECISION:B2B-RULE-AUTH-004",
    ),
}
class P51ManualPromotion22PGDual(unittest.TestCase):
    def test_closed_22_atomic_success_and_fail_closed(self):
        self.assertEqual(len(RULES),22)
        self.assertEqual(len(set(RULES)),22)
        self.assertTrue(shutil.which("docker"),"DOCKER_REQUIRED")
        migration=MIGRATION.read_text(encoding="utf-8")
        self.assertTrue(migration.endswith("COMMIT;\n"),"EXPECTED_SINGLE_LAST_COMMIT")
        self.assertEqual(migration.count("public.lf_rule_promotion_request_v1("),1)
        self.assertEqual(migration.count("public.lf_rule_promotion_decide_v1("),1)
        self.assertEqual(migration.count("public.lf_rule_promotion_apply_v1("),1)
        self.assertNotIn("GRANT EXECUTE",migration)
        self.assertNotIn("CREATE ROLE",migration)
        self.assertNotIn("EXEC-PROFILE-GATE2-95968F50D6214EADB117E45E",migration)
        self.assertNotIn("B2B-RULE-AUTH-047',\n    'B2B-RULE-AUTH-049',",migration)
        self.assertIn("VIGENTE como definicion; NO-GO de produccion",migration)
        migration_test=migration[:-len("COMMIT;\n")]
        self.assertTrue(migration_test.endswith("END $lf_p51_manual_22$;\n"))
        for version in ("17.6","18.7"):
            with self.subTest(postgres=version):
                container="lf-p51-22-"+uuid.uuid4().hex[:10]
                started=subprocess.run(["docker","run","-d","--rm","--name",container,
                   "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
                   capture_output=True,text=True,timeout=180)
                self.assertEqual(started.returncode,0,started.stderr)
                try:
                    ready=None
                    for _ in range(90):
                        ready=subprocess.run(["docker","exec",container,"pg_isready",
                          "-U","postgres"],capture_output=True,text=True,timeout=15)
                        if ready.returncode==0:
                            logs=subprocess.run(["docker","logs",container],
                               capture_output=True,text=True,timeout=15)
                            if "PostgreSQL init process complete; ready for start up." in (logs.stdout+logs.stderr):
                                break
                        time.sleep(.5)
                    self.assertEqual(ready.returncode,0,"PG_NOT_READY")
                    def sql(txt, expect=True):
                        proc=subprocess.run(["docker","exec","-i",container,"psql","-X",
                            "-A","-t","-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
                            input=txt,capture_output=True,text=True,timeout=240)
                        if expect:
                            self.assertEqual(proc.returncode,0,
                                proc.stderr[-5000:]+"\n"+proc.stdout[-2200:])
                        else:
                            self.assertNotEqual(proc.returncode,0,
                                "EXPECTED_DB_EXCEPTION_NOT_RAISED")
                        return proc.stdout+"\n"+proc.stderr
                    sql(SCHEMA+"\n"+SOURCE.read_text(encoding="utf-8"))
                    sql(IG0815_MIGRATION.read_text(encoding="utf-8"))
                    sql(SETUP)
                    # The migration's DO block runs in a transaction; no real COMMIT.
                    test_script=migration_test + """
SELECT 'P51_APPLIED_INSIDE_TX='||count(*)
 FROM public.lf_rule_promotion_v1 WHERE status='APPLIED';
SELECT 'P51_VIGENTE_INSIDE_TX='||count(*)
 FROM lf_ops.reglas WHERE codigo=ANY(%s) AND estado='VIGENTE';
SELECT 'P51_EXCLUDED_UNTOUCHED='||count(*)
 FROM lf_ops.reglas WHERE codigo=ANY(%s) AND estado='CANDIDATO';
SELECT 'P51_DEPENDENCIES_NOTED='||count(*)
 FROM public.lf_rule_promotion_v1 WHERE rule_code=ANY(%s)
  AND reason LIKE '%%VIGENTE como definicion; NO-GO de produccion%%';
ROLLBACK;
""" % (
                        sql_arr(RULES),sql_arr(EXCLUDED),
                        sql_arr(["B2B-RULE-AUTH-013","B2B-RULE-AUTH-019",
                                 "B2B-RULE-AUTH-020","B2B-RULE-AUTH-021",
                                 "B2B-RULE-AUTH-026",
                                 "B2B-RULE-SECURITY-BASELINE-001"])
                    )
                    result=sql(test_script)
                    for expected in ["P51_APPLIED_INSIDE_TX=22",
                                     "P51_VIGENTE_INSIDE_TX=22",
                                     "P51_EXCLUDED_UNTOUCHED=5",
                                     "P51_DEPENDENCIES_NOTED=6",
                                     "LF_P51_MANUAL_22_APPLIED_WITH_READBACK"]:
                        self.assertIn(expected,result,result[-2800:])
                    for label,(mutation,code) in NEGATIVES.items():
                        with self.subTest(version=version,negative=label):
                            script="BEGIN;\n"+mutation+"\n"+migration_test+"ROLLBACK;\n"
                            out=sql(script,expect=False)
                            self.assertIn(code,out,out[-2300:])
                            verify=sql("""
SELECT 'P51_ROLLBACK_RULES='||count(*) FROM lf_ops.reglas
 WHERE codigo=ANY(%s) AND estado='CANDIDATO';
SELECT 'P51_ROLLBACK_PROMOTIONS='||count(*) FROM public.lf_rule_promotion_v1;
SELECT 'P51_ROLLBACK_STEP_COUNT='||count(*) FROM public.lf_operation_execution_steps
 WHERE execution_id='%s';
"""%(sql_arr(RULES),RUN))
                            for mark in ("P51_ROLLBACK_RULES=22",
                                         "P51_ROLLBACK_PROMOTIONS=0",
                                         "P51_ROLLBACK_STEP_COUNT=11"):
                                self.assertIn(mark,verify,verify)
                    final=sql("""
SELECT 'P51_FINAL_CANDIDATES='||count(*) FROM lf_ops.reglas
 WHERE codigo=ANY(%s) AND estado='CANDIDATO';
SELECT 'P51_FINAL_REQUESTS='||count(*) FROM public.lf_rule_promotion_v1;
"""%(sql_arr(RULES)))
                    self.assertIn("P51_FINAL_CANDIDATES=22",final)
                    self.assertIn("P51_FINAL_REQUESTS=0",final)
                    print("P51_MANUAL_22_PG"+version+"_BEGIN_ROLLBACK_8_CASES_PASS",flush=True)
                finally:
                    subprocess.run(["docker","rm","-f",container],
                        capture_output=True,timeout=30)

if __name__=="__main__":
    unittest.main()
