"""LF run956 family -> VIGENTE transversal / existing policy mapping.
Executes the exact PR migration within disposable PostgreSQL 17.6 and 18.7
BEGIN/ROLLBACK. Synthetic fixtures test contractual behavior, not live source truth.
"""
from pathlib import Path
import shutil
import subprocess
import time
import unittest
import uuid

ROOT=Path(__file__).resolve().parents[3]
CANDIDATES=list((ROOT/"supabase/migrations").glob("*_lf_input_family_reuse_map_run956_v1.sql"))
PARTIAL=[
 "API_DATA_CONTRACT","ASSETS_ICONS","AUDIT","BROWSER_PLATFORM","DESIGN_SYSTEM",
 "IDEMPOTENCY_CONCURRENCY","LOADING_EMPTY_ERROR_STATES","OBSERVABILITY",
 "PRIVACY_PII","RATE_LIMIT","SECURITY","SESSION","TESTING_OBLIGATIONS",
 "TIMEOUT_RETRY","TRANSITIONS","VALIDATIONS","VISUAL_EVIDENCE",
]
HERIT_IDS=[179,362,416,387,199,412,411,396,424,25,370]
FIXTURE= r"""
CREATE ROLE service_role;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA programacion;
CREATE SCHEMA lf_ops;
CREATE TABLE programacion.input_readiness_runs(id bigint PRIMARY KEY,
 pantalla_id integer NOT NULL,version_id integer NOT NULL);
CREATE TABLE programacion.input_family_assessments(
 id bigint PRIMARY KEY,run_id bigint,family_code text,
 coverage_status text,source_refs jsonb,curator_sha256 text,blockers jsonb);
CREATE TABLE lf_ops.pantallas(id integer PRIMARY KEY,codigo text);
CREATE TABLE lf_ops.reglas(id integer PRIMARY KEY,estado text,es_transversal boolean,codigo text);
CREATE TABLE lf_ops.pantallas_politicas(pantalla_politica_id bigint PRIMARY KEY,pantalla_id integer);
CREATE TABLE lf_ops.pantallas_politicas_reglas(pantalla_politica_id bigint,regla_id integer);
CREATE TABLE lf_ops.politicas_seguridad(security_policy_id bigint PRIMARY KEY,policy_code text,status text);
CREATE TABLE lf_ops.politicas_rate_limit(rate_limit_policy_id bigint PRIMARY KEY,policy_code text,status text);
CREATE TABLE lf_ops.politicas_sesion(session_policy_id bigint PRIMARY KEY,policy_code text,status text);
CREATE TABLE lf_ops.politicas_timeout(timeout_policy_id bigint PRIMARY KEY,policy_code text,status text);
INSERT INTO programacion.input_readiness_runs VALUES(956,44,19);
INSERT INTO lf_ops.pantallas VALUES(44,'B2B-CARGA-002');
INSERT INTO lf_ops.politicas_seguridad VALUES(9,'SEC-B2B-IDEMPOTENCY','CANDIDATO');
INSERT INTO lf_ops.politicas_rate_limit VALUES(2,'RATE-B2B-UPLOAD','CANDIDATO');
INSERT INTO lf_ops.politicas_sesion VALUES(1,'SESSION-B2B-DEFAULT','VIGENTE');
INSERT INTO lf_ops.politicas_timeout VALUES(2,'TIMEOUT-B2B-UPLOAD','CANDIDATO');
"""
class EvidenceMappingRollback(unittest.TestCase):
 def test_run956_pg176_pg187(self):
  self.assertEqual(len(CANDIDATES),1,"ONE_RETSTAMPED_TRAIN_MIGRATION_REQUIRED")
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  sql=CANDIDATES[0].read_text("utf-8")
  self.assertIn("LF_FAMILY_REUSE_MAP_17_COUNT_MISMATCH",sql)
  for prohibited in (
      "INSERT INTO lf_ops.reglas",
      "UPDATE lf_ops.reglas",
      "INSERT INTO lf_ops.pantallas_politicas",
      "INSERT INTO lf_ops.pantallas_politicas_reglas",
      "UPDATE programacion.input_family_assessments",
      "INSERT INTO public.lf_rule_promotion_v1",
  ):
   self.assertNotIn(prohibited,sql)
  before,after=sql.split("\nBEGIN;\n",1)
  inner=after.rsplit("\nCOMMIT;",1)[0]
  self.assertIn("SOURCE_DRIFT_REVIEW",inner)
  self.assertIn("closure_verified",inner)
  seed=FIXTURE
  for i,k in enumerate(PARTIAL):
   seed+=(f"INSERT INTO programacion.input_family_assessments VALUES"
          f"({500+i},956,'{k}','PARTIAL','[]'::jsonb,repeat('a',64),"
          f"'[{{\"code\":\"FINDING_{i}\"}}]'::jsonb);\n")
  for i in range(30):
   seed+=(f"INSERT INTO programacion.input_family_assessments VALUES "
          f"({800+i},956,'COMPLETE_{i}','COMPLETE','[]'::jsonb,repeat('b',64),'[]'::jsonb);\n")
  for i in HERIT_IDS:
   seed+=f"INSERT INTO lf_ops.reglas VALUES ({i},'VIGENTE',true,'VIG_{i}');\n"
  seed+="INSERT INTO lf_ops.reglas VALUES (403,'CANDIDATO',false,'IDEMP'),(581,'CANDIDATO',false,'WIZARD');\n"
  self.assertEqual(len(HERIT_IDS),11)
  for ver,version in (("17.6","170006"),("18.7","180007")):
   with self.subTest(postgres=ver):
    name="lf-map956-"+uuid.uuid4().hex[:9]
    started=subprocess.run(["docker","run","-d","--rm","--name",name,
       "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+ver],
       capture_output=True,text=True,timeout=120)
    self.assertEqual(started.returncode,0,started.stderr)
    try:
     ready=None
     for _ in range(120):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],capture_output=True,timeout=7)
      log=subprocess.run(["docker","logs",name],capture_output=True,text=True,timeout=7)
      if ready.returncode==0 and "PostgreSQL init process complete; ready for start up." in log.stdout+log.stderr:
       break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0)
     def psql(src):
      return subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=src,text=True,capture_output=True,timeout=120)
     setr=psql(seed)
     self.assertEqual(setr.returncode,0,setr.stderr[-3000:])
     check=r"""
SELECT 'TOTAL='||count(*) FROM programacion.input_family_reuse_map_v1;
SELECT 'HEREDAR='||count(*) FROM programacion.input_family_reuse_map_v1 WHERE resolution_path='HEREDAR';
SELECT 'POLITICA='||count(*) FROM programacion.input_family_reuse_map_v1 WHERE resolution_path='ATAR_POLITICA';
SELECT 'CANDIDATA='||count(*) FROM programacion.input_family_reuse_map_v1 WHERE resolution_path='REGLA_CANDIDATA';
SELECT 'OWNER='||count(*) FROM programacion.input_family_reuse_map_v1 WHERE resolution_path='DECISION_OWNER';
SELECT 'NO_FAKE_CLOSURE='||count(*) FROM programacion.input_family_reuse_map_v1 WHERE closure_verified=false;
SELECT 'POLICY_LINKS='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=44;
SELECT 'RULES='||count(*) FROM lf_ops.reglas;
SELECT 'RUN_PARTIAL='||count(*) FROM programacion.input_family_assessments
 WHERE run_id=956 AND coverage_status='PARTIAL';
SELECT 'REUSE_OK='||(public.lf_input_family_reuse_before_propose_v1(44,'AUDIT',956)->>'status');
SELECT 'POLICY_ROW='||(public.lf_input_family_reuse_before_propose_v1(44,'SESSION',956)
 ->'policy_screen_row_proposal'->>'session_policy_id');
SELECT 'SESSION_IS_VIGENTE='||(public.lf_input_family_reuse_before_propose_v1(44,'SESSION',956)->>'policy_status');
SELECT 'NO_RULE_CREATION='||(public.lf_input_family_reuse_before_propose_v1(44,'RATE_LIMIT',956)->>'automatic_rule_creation');
SELECT 'FLOW_CONTINUES='||(public.lf_input_family_reuse_before_propose_v1(44,'OBSERVABILITY',956)->>'continuation_allowed');
SELECT 'NOT_MAPPED='||(public.lf_input_family_reuse_before_propose_v1(44,'UNKNOWN',956)->>'status');
SELECT 'SERVICE_GRANT='||has_function_privilege('service_role',
 'public.lf_input_family_reuse_before_propose_v1(integer,text,bigint)','EXECUTE')::text;
SELECT 'ANON_DENIED='||(NOT has_function_privilege('anon',
 'public.lf_input_family_reuse_before_propose_v1(integer,text,bigint)','EXECUTE'))::text;
UPDATE lf_ops.politicas_rate_limit SET status='INACTIVO' WHERE policy_code='RATE-B2B-UPLOAD';
SELECT 'DRIFT_DETECTED='||(public.lf_input_family_reuse_before_propose_v1(44,'RATE_LIMIT',956)->>'status');
INSERT INTO programacion.input_readiness_runs VALUES(957,44,19);
SELECT 'STALE_RUN='||(public.lf_input_family_reuse_before_propose_v1(44,'AUDIT',956)->>'status');
"""
     txn="BEGIN;\n"+inner+"\n"+check+"\nROLLBACK;\n"
     txn+="SELECT 'POST_ROLLBACK_MAP='||(to_regclass('programacion.input_family_reuse_map_v1') IS NULL)::text;\n"
     txn+="SELECT 'POST_ROLLBACK_FUNC='||(to_regprocedure('public.lf_input_family_reuse_before_propose_v1(integer,text,bigint)') IS NULL)::text;\n"
     txn+="SELECT 'POLICY_UNCHANGED='||(SELECT status FROM lf_ops.politicas_rate_limit WHERE policy_code='RATE-B2B-UPLOAD');\n"
     rr=psql(txn)
     self.assertEqual(rr.returncode,0,rr.stderr[-4500:])
     for required in ("TOTAL=17","HEREDAR=11","POLITICA=4","CANDIDATA=2","OWNER=0",
       "NO_FAKE_CLOSURE=17","POLICY_LINKS=0","RULES=13","RUN_PARTIAL=17",
       "REUSE_OK=REUSE_PROPOSAL_WITH_FINDINGS","POLICY_ROW=1","SESSION_IS_VIGENTE=VIGENTE",
       "NO_RULE_CREATION=false","FLOW_CONTINUES=true","NOT_MAPPED=NOT_MAPPED_REVIEW_SOURCE",
       "SERVICE_GRANT=true","ANON_DENIED=true","DRIFT_DETECTED=SOURCE_DRIFT_REVIEW","STALE_RUN=STALE_IG_RUN_RECURATE",
       "POST_ROLLBACK_MAP=true","POST_ROLLBACK_FUNC=true","POLICY_UNCHANGED=CANDIDATO"):
      self.assertIn(required,rr.stdout,required+"\n"+rr.stdout[-2800:])
     # A missing referenced policy must abort the exact migration; no fake mapping.
     negative=psql("BEGIN;\nDELETE FROM lf_ops.politicas_rate_limit WHERE policy_code='RATE-B2B-UPLOAD';\n"
       +inner+"\nROLLBACK;\n")
     self.assertNotEqual(negative.returncode,0)
     self.assertIn("LF_FAMILY_REUSE_POLICY_SOURCE_DRIFT:RATE_LIMIT",negative.stderr)
     print("PASS_FAMILY956_REUSE_PG"+ver+"_17_ROUTES_4_POLICY_PROPOSALS_NO_LINKS_ROLLBACK")
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
