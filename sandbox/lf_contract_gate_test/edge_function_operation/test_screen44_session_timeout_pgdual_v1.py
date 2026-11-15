"""PG17/18: screen44 B2B session + upload/validation/processing timing.
Transactional positive/negative, idempotency, rollback; disposable DB only.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[3]
MIGRATION=ROOT/"supabase/migrations/20261115003002_lf_screen44_session_timeout_retry_v1.sql"
FIXTURE=r"""
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.pantallas(id integer PRIMARY KEY,codigo text);
CREATE TABLE lf_ops.politicas_sesion(session_policy_id bigint PRIMARY KEY,
 policy_code text,status text,scope_code text);
CREATE TABLE lf_ops.politicas_timeout(timeout_policy_id bigint PRIMARY KEY,
 policy_code text,status text,operation_code text,timeout_seconds integer,
 retry_limit integer,backoff_strategy text);
CREATE TABLE lf_ops.reglas(id integer PRIMARY KEY,estado text);
CREATE TABLE lf_ops.pantallas_politicas(
 pantalla_politica_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pantalla_id integer,policy_kind text,reference_role text,
 session_policy_id bigint REFERENCES lf_ops.politicas_sesion(session_policy_id),
 timeout_policy_id bigint REFERENCES lf_ops.politicas_timeout(timeout_policy_id),
 status text,UNIQUE(pantalla_id,reference_role));
CREATE TABLE lf_ops.pantallas_politicas_reglas(
 pantalla_politica_id bigint REFERENCES lf_ops.pantallas_politicas(pantalla_politica_id),
 regla_id integer REFERENCES lf_ops.reglas(id),
 PRIMARY KEY(pantalla_politica_id,regla_id));
INSERT INTO lf_ops.pantallas VALUES(44,'B2B-CARGA-002');
INSERT INTO lf_ops.politicas_sesion VALUES(1,'SESSION-B2B-DEFAULT','VIGENTE','B2B_APP_SHELL');
INSERT INTO lf_ops.politicas_timeout VALUES
 (2,'TIMEOUT-B2B-UPLOAD','CANDIDATO','FILE_UPLOAD',300,2,'EXPONENTIAL'),
 (4,'TIMEOUT-B2B-VALIDATION','CANDIDATO','FILE_VALIDATION',600,1,'FIXED'),
 (5,'TIMEOUT-B2B-PROCESSING','CANDIDATO','LOAD_PROCESSING',1800,0,'NONE');
INSERT INTO lf_ops.reglas VALUES(399,'VIGENTE'),(400,'VIGENTE'),(417,'VIGENTE');
"""
class Screen44SessionTimeoutPGDual(unittest.TestCase):
 def test_pg17_pg18_rollback_and_negative(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  sql=MIGRATION.read_text("utf-8")
  self.assertTrue(sql.startswith("-- Screen") and sql.rstrip().endswith("COMMIT;"))
  inner=sql.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
  for ver in ("17.6","18.7"):
   with self.subTest(postgres=ver):
    name="lf44-st-"+uuid.uuid4().hex[:10]
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
     check=r"""
SELECT 'LINKS='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=44;
SELECT 'SESSION='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND policy_kind='SESSION' AND session_policy_id=1
 AND status='CANDIDATO';
SELECT 'TIMEOUTS='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND policy_kind='TIMEOUT' AND timeout_policy_id IN(2,4,5)
 AND status='CANDIDATO';
SELECT 'RULE_LINKS='||count(*) FROM lf_ops.pantallas_politicas_reglas;
SELECT 'SESSION_SOURCE='||(SELECT status FROM lf_ops.politicas_sesion WHERE session_policy_id=1);
SELECT 'TIMEOUT_CANDIDATES='||count(*) FROM lf_ops.politicas_timeout WHERE status='CANDIDATO';
"""
     result=psql("BEGIN;\n"+inner+"\n"+inner+"\n"+check+"ROLLBACK;\n"
       "SELECT 'ROLLBACK_LINKS='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=44;\n"
       "SELECT 'ROLLBACK_RULE_LINKS='||count(*) FROM lf_ops.pantallas_politicas_reglas;\n")
     self.assertEqual(result.returncode,0,result.stderr[-3000:])
     for s in ("LINKS=4","SESSION=1","TIMEOUTS=3","RULE_LINKS=5",
       "SESSION_SOURCE=VIGENTE","TIMEOUT_CANDIDATES=3",
       "ROLLBACK_LINKS=0","ROLLBACK_RULE_LINKS=0"):
      self.assertIn(s,result.stdout,s+"\n"+result.stdout)
     bad=psql("BEGIN;\nUPDATE lf_ops.politicas_sesion SET status='CANDIDATO' WHERE session_policy_id=1;\n"+inner)
     self.assertNotEqual(bad.returncode,0)
     self.assertIn("SCREEN44_SESSION_TIMEOUT_SESSION_SOURCE_DRIFT",bad.stderr)
     print("PASS_SCREEN44_SESSION_TIMEOUT_PG"+ver+"_4LINKS_5RULES_ROLLBACK")
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
