"""PG17/18 screen44 idempotency policy/rule link: real candidate migration,
idempotency, negative source drift, positive readback, ROLLBACK.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261115003003_lf_screen44_idempotency_concurrency_v1.sql"
FIXTURE=r"""
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.pantallas(id integer PRIMARY KEY,codigo text);
CREATE TABLE lf_ops.politicas_seguridad(security_policy_id bigint PRIMARY KEY,
 policy_code text,status text,category text);
CREATE TABLE lf_ops.reglas(id integer PRIMARY KEY,codigo text,estado text,pendiente_decision boolean);
CREATE TABLE lf_ops.reglas_pantallas(id integer PRIMARY KEY,regla_id integer,pantalla_id integer);
CREATE TABLE lf_ops.estados_transiciones(entity_type text,transition_code text,
 requires_idempotency_key boolean);
CREATE TABLE lf_ops.pantallas_politicas(
 pantalla_politica_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pantalla_id integer,policy_kind text,reference_role text,
 security_policy_id bigint REFERENCES lf_ops.politicas_seguridad(security_policy_id),
 status text,UNIQUE(pantalla_id,reference_role));
CREATE TABLE lf_ops.pantallas_politicas_reglas(
 pantalla_politica_id bigint REFERENCES lf_ops.pantallas_politicas(pantalla_politica_id),
 regla_id integer REFERENCES lf_ops.reglas(id),PRIMARY KEY(pantalla_politica_id,regla_id));
INSERT INTO lf_ops.pantallas VALUES(44,'B2B-CARGA-002');
INSERT INTO lf_ops.politicas_seguridad VALUES(9,'SEC-B2B-IDEMPOTENCY','CANDIDATO','INTEGRITY');
INSERT INTO lf_ops.reglas VALUES(403,'B2B-RULE-IDEMP-001','CANDIDATO',false);
INSERT INTO lf_ops.reglas_pantallas VALUES(9080,403,44);
INSERT INTO lf_ops.estados_transiciones VALUES
 ('UPLOAD_BATCH','TR_LOAD_CREATE',true),
 ('UPLOAD_BATCH','TR_LOAD_VALIDATE_START',true),
 ('UPLOAD_BATCH','TR_LOAD_VALIDATE_OK',true);
"""
class Screen44IdempotencyPGDual(unittest.TestCase):
 def test_pg17_pg18_rollback_and_negative(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  sql=MIGRATION.read_text("utf-8")
  self.assertTrue(sql.rstrip().endswith("COMMIT;"))
  inner=sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
  for ver in ("17.6","18.7"):
   with self.subTest(postgres=ver):
    name="lf44-ic-"+uuid.uuid4().hex[:10]
    start=subprocess.run(["docker","run","-d","--rm","--name",name,
     "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+ver],
     capture_output=True,text=True,timeout=120)
    self.assertEqual(start.returncode,0,start.stderr)
    try:
     for _ in range(120):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
       capture_output=True,timeout=8)
      log=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=8)
      if ready.returncode==0 and "PostgreSQL init process complete; ready for start up." in log.stdout+log.stderr: break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0)
     def psql(script):
      return subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=script,text=True,capture_output=True,timeout=120)
     setup=psql(FIXTURE)
     self.assertEqual(setup.returncode,0,setup.stderr)
     checks=r"""
SELECT 'POLICY_LINKS='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=44;
SELECT 'RULE_LINKS='||count(*) FROM lf_ops.pantallas_politicas_reglas WHERE regla_id=403;
SELECT 'POLICY_CANDIDATE='||(SELECT status FROM lf_ops.politicas_seguridad WHERE security_policy_id=9);
SELECT 'RULE_CANDIDATE='||(SELECT estado FROM lf_ops.reglas WHERE id=403);
"""
     result=psql("BEGIN;\n"+inner+"\n"+inner+"\n"+checks+"ROLLBACK;\n"
       "SELECT 'ROLLBACK_POLICY_LINKS='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=44;\n"
       "SELECT 'ROLLBACK_RULE_LINKS='||count(*) FROM lf_ops.pantallas_politicas_reglas;\n")
     self.assertEqual(result.returncode,0,result.stderr[-3000:])
     for s in ("POLICY_LINKS=1","RULE_LINKS=1","POLICY_CANDIDATE=CANDIDATO",
       "RULE_CANDIDATE=CANDIDATO","ROLLBACK_POLICY_LINKS=0","ROLLBACK_RULE_LINKS=0"):
      self.assertIn(s,result.stdout,s+"\n"+result.stdout)
     bad=psql("BEGIN;\nDELETE FROM lf_ops.reglas_pantallas WHERE id=9080;\n"+inner)
     self.assertNotEqual(bad.returncode,0)
     self.assertIn("SCREEN44_IDEMPOTENCY_RULE_SOURCE_DRIFT",bad.stderr)
     print("PASS_SCREEN44_IDEMPOTENCY_PG"+ver+"_CANDIDATE_LINK_ROLLBACK")
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
