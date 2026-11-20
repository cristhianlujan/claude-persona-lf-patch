"""IG Curator auto-bind: exact source preimages, governed candidate migration,
PG17.6/18.7 disposable fixture, positive/negative, idempotency and ROLLBACK.

The real Curator and family-complete function bodies are captured from Supabase RO
with pinned source MD5. Downstream strategy/writer and graph are stubs to isolate
this particular policy bind behavior, not a production E2E or a real validator.
"""
import pathlib
import re
import shutil
import subprocess
import time
import unittest
import uuid

ROOT=pathlib.Path(__file__).resolve().parents[3]
MIGRATION_CANDIDATES=list((ROOT/"supabase/migrations").glob("*_lf_ig_curator_policy_autobind_channel_v1.sql"))
FIXTURES=ROOT/"sandbox/lf_contract_gate_test/edge_function_operation/fixtures"
CURATOR=FIXTURES/"ig_policy_autobind_curator_preimage_20261114.sql"
COMPLETE=FIXTURES/"ig_policy_autobind_family_complete_preimage_20261114.sql"
FIXTURE=r"""
CREATE ROLE service_role;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA programacion;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.pantallas(
 id integer PRIMARY KEY,codigo text,module_code text,activa boolean);
CREATE TABLE lf_ops.pantalla_elementos(element_id bigint PRIMARY KEY,
 pantalla_id integer,element_role text,required_for_implementation boolean,status text);
CREATE TABLE lf_ops.reglas(id integer PRIMARY KEY,estado text);
CREATE TABLE lf_ops.reglas_pantallas(id integer PRIMARY KEY,
 pantalla_id integer,regla_id integer,UNIQUE(pantalla_id,regla_id));
CREATE TABLE lf_ops.politicas_sesion(session_policy_id bigint PRIMARY KEY,
 policy_code text,scope_code text,status text);
CREATE TABLE lf_ops.politicas_rate_limit(rate_limit_policy_id bigint PRIMARY KEY,
 policy_code text,resource_code text,scope_key text,window_seconds int,max_requests int,status text);
CREATE TABLE lf_ops.politicas_timeout(timeout_policy_id bigint PRIMARY KEY,
 policy_code text,operation_code text,timeout_seconds int,retry_limit int,status text);
CREATE TABLE lf_ops.politicas_seguridad(security_policy_id bigint PRIMARY KEY,
 policy_code text,category text,policy_config jsonb,status text);
CREATE TABLE lf_ops.pantallas_politicas(
 pantalla_politica_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pantalla_id int,policy_kind text,reference_role text,
 rate_limit_policy_id bigint REFERENCES lf_ops.politicas_rate_limit(rate_limit_policy_id),
 timeout_policy_id bigint REFERENCES lf_ops.politicas_timeout(timeout_policy_id),
 session_policy_id bigint REFERENCES lf_ops.politicas_sesion(session_policy_id),
 security_policy_id bigint REFERENCES lf_ops.politicas_seguridad(security_policy_id),
 status text,UNIQUE(pantalla_id,reference_role));
CREATE TABLE lf_ops.pantallas_politicas_reglas(
 pantalla_politica_id bigint REFERENCES lf_ops.pantallas_politicas(pantalla_politica_id),
 regla_id int REFERENCES lf_ops.reglas(id),PRIMARY KEY(pantalla_politica_id,regla_id));

CREATE TABLE programacion.agentes(id bigint PRIMARY KEY,agente_codigo text);
CREATE TABLE programacion.versiones_agente(id bigint PRIMARY KEY,agente_id bigint);
CREATE TABLE programacion.contratos(id bigint PRIMARY KEY,version_id bigint,
 contrato_codigo text,estado text,fail_closed boolean,especificacion jsonb);
CREATE TABLE programacion.input_readiness_runs(
 id bigint PRIMARY KEY,pantalla_id int,version_id bigint,status text,
 curator_identity text,source_snapshot_sha256 text,source_manifest jsonb);
CREATE TABLE programacion.input_family_assessments(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 run_id bigint,family_code text,coverage_status text,curator_evidence jsonb);
CREATE TABLE programacion.input_gap_proposals(id bigint,run_id bigint);

INSERT INTO lf_ops.pantallas VALUES
 (44,'B2B-CARGA-002','B2B_CARGAS',true),
 (51,'B2B-AUTH-001','B2B_AUTENTICACION',true),
 (43,'B2B-CARGA-001','B2B_CARGAS',true);
INSERT INTO lf_ops.pantalla_elementos VALUES(131,44,'UPLOAD_DROPZONE',true,'CANDIDATO');
INSERT INTO lf_ops.reglas VALUES
 (399,'VIGENTE'),(400,'VIGENTE'),(403,'CANDIDATO'),
 (417,'VIGENTE'),(418,'VIGENTE');
INSERT INTO lf_ops.reglas_pantallas VALUES
 (1,44,399),(2,44,400),(3,44,403),(4,44,417),(5,44,418);
INSERT INTO lf_ops.politicas_sesion VALUES
 (1,'SESSION-B2B-DEFAULT','B2B_APP_SHELL','VIGENTE'),
 (2,'SESSION-CLIENT-DEFAULT','CLIENT_APP_SHELL','VIGENTE');
INSERT INTO lf_ops.politicas_rate_limit VALUES
 (2,'RATE-B2B-UPLOAD','FILE_UPLOAD','TENANT_USER',3600,20,'CANDIDATO');
INSERT INTO lf_ops.politicas_timeout VALUES
 (2,'TIMEOUT-B2B-UPLOAD','FILE_UPLOAD',300,2,'CANDIDATO'),
 (4,'TIMEOUT-B2B-VALIDATION','FILE_VALIDATION',600,1,'CANDIDATO'),
 (5,'TIMEOUT-B2B-PROCESSING','LOAD_PROCESSING',1800,0,'CANDIDATO');
INSERT INTO lf_ops.politicas_seguridad VALUES
 (9,'SEC-B2B-IDEMPOTENCY','INTEGRITY','{"actions":["upload","approve"]}'::jsonb,'CANDIDATO');

-- Simulate the 13 already-linked screen51 policies; binder must never modify them.
INSERT INTO lf_ops.pantallas_politicas(pantalla_id,policy_kind,reference_role,security_policy_id,status)
 SELECT 51,'SECURITY','fixture_existing_'||s,9,'CANDIDATO'
 FROM generate_series(1,13) s;

INSERT INTO programacion.agentes VALUES(1,'INPUT_GOVERNANCE_AGENT');
INSERT INTO programacion.versiones_agente VALUES(19,1);
INSERT INTO programacion.contratos VALUES
 (1,19,'INPUT_READINESS_CONTRACT','defined',true,'{}'),
 (2,19,'INPUT_GOVERNANCE_EXECUTION_CONTRACT','defined',true,'{}'),
 (3,19,'INPUT_CONTEXT_MANIFEST_CONTRACT','defined',true,'{}'),
 (4,19,'INPUT_FRESHNESS_DELTA_CONTRACT','defined',true,'{}'),
 (5,19,'INPUT_RETRIEVAL_HANDLE_CONTRACT','defined',true,'{}'),
 (6,19,'INPUT_FAMILY_POLICY_REGISTRY','defined',true,
  '{"families":{
   "SESSION":{},
   "RATE_LIMIT":{},
   "TIMEOUT_RETRY":{},
   "IDEMPOTENCY_CONCURRENCY":{"complete_criteria_v1":{"schema_version":"input-family-complete-criteria/v1","fail_closed":true,"probe_kind":"EXISTING_RESOLVER"}}}}'::jsonb);
INSERT INTO programacion.input_readiness_runs
 VALUES(952,51,19,'COMPLETED','FIXTURE',repeat('a',64),'[]'::jsonb);
INSERT INTO programacion.input_family_assessments(run_id,family_code,coverage_status,curator_evidence)
 SELECT 952,'CURRENT_'||s,'COMPLETE','{}'::jsonb FROM generate_series(1,12) s;

CREATE OR REPLACE FUNCTION programacion.fn_v09_sha256_jsonb(p_payload jsonb)
 RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
 SELECT md5(p_payload::text)||md5(p_payload::text)
$fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_screen_canonical_graph(
 p_pantalla_id integer,p_version_id bigint) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE x int;
BEGIN
 x:=coalesce(nullif(current_setting('lf.input_request_graph_build_count_v1',true),'')::int,0);
 PERFORM set_config('lf.input_request_graph_build_count_v1',(x+1)::text,true);
 RETURN jsonb_build_object('screen_code',(SELECT codigo FROM lf_ops.pantallas WHERE id=p_pantalla_id),
   'graph_contract','IG_SCREEN_GRAPH_FIXTURE','agent_contract_version_id',p_version_id);
END $fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_plan_v1(
 p_pantalla_id integer,p_force_selftest boolean,p_completed_run_id bigint)
 RETURNS jsonb LANGUAGE sql STABLE AS $fn$
 SELECT CASE WHEN p_pantalla_id=51 THEN
   jsonb_build_object('strategy','NOOP','completed_run_id',952)
 ELSE jsonb_build_object('strategy','BOOTSTRAP','completed_run_id',null) END
$fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_bootstrap_materialize_v2(
 p_pantalla_id integer,p_consumer text,p_curator_identity text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE f text; result jsonb;
BEGIN
 INSERT INTO programacion.input_readiness_runs
 VALUES(957,p_pantalla_id,19,'CURATING',p_curator_identity,null,'[]'::jsonb);
 FOREACH f IN ARRAY ARRAY['SESSION','RATE_LIMIT','TIMEOUT_RETRY','IDEMPOTENCY_CONCURRENCY'] LOOP
   result:=programacion.fn_input_governance_family_complete_probe_v1(p_pantalla_id,f,19,null);
   INSERT INTO programacion.input_family_assessments(
     run_id,family_code,coverage_status,curator_evidence)
   VALUES(957,f,
     CASE WHEN coalesce((result->>'handled')::boolean,false)
       AND result->>'level'='COMPLETE' THEN 'COMPLETE' ELSE 'PARTIAL' END,
     jsonb_build_object(
       'core_invocation',jsonb_build_object('contract','M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'),
       'semantic_plan',jsonb_build_object('contract','M5_4_SEMANTIC_PLAN_V1','resolver_result',result)));
 END LOOP;
 PERFORM set_config('lf.input_curator_family_timings_v1',
   '[{},{},{},{}]',true);
 RETURN jsonb_build_object('run_id',957,'status','CURATING','strategy','BOOTSTRAP');
END $fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_curator_handoff_receipt_v1(
 p_run_id bigint,p_curator_identity text) RETURNS jsonb
 LANGUAGE sql STABLE AS $fn$
 SELECT jsonb_build_object('receipt_id',1,'status','PERSISTED',
   'graph_sha256',programacion.fn_v09_sha256_jsonb(
     jsonb_build_object('screen_code','B2B-CARGA-002',
       'graph_contract','IG_SCREEN_GRAPH_FIXTURE','agent_contract_version_id',19)))
$fn$;

CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_handoff_assert_v1(
 p_run_id bigint,p_receipt_id bigint) RETURNS jsonb LANGUAGE sql STABLE AS $fn$
 SELECT jsonb_build_object('status','VERIFIED')
$fn$;
"""
CHECK=r"""
SELECT 'FOUR_COMPLETE='||count(*) FROM programacion.input_family_assessments
 WHERE run_id=957 AND coverage_status='COMPLETE';
SELECT 'RATE_BIND='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND rate_limit_policy_id=2 AND status='CANDIDATO';
SELECT 'SESSION_BIND='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND session_policy_id=1 AND status='CANDIDATO';
SELECT 'SESSION_CLIENT_MISBIND='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND session_policy_id=2;
SELECT 'TIMEOUT_BIND='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND timeout_policy_id IN (2,4,5) AND status='CANDIDATO';
SELECT 'IDEMPOT_BIND='||count(*) FROM lf_ops.pantallas_politicas
 WHERE pantalla_id=44 AND security_policy_id=9 AND status='CANDIDATO';
SELECT 'RECEIPTS='||count(*) FROM programacion.input_policy_autobind_receipts_v1 WHERE pantalla_id=44;
SELECT 'RULE_ASSOCIATIONS='||count(*) FROM lf_ops.pantallas_politicas_reglas pr
 JOIN lf_ops.pantallas_politicas pp USING(pantalla_politica_id)
 WHERE pp.pantalla_id=44;
SELECT 'ALL_POLICY_CANDIDATES='||count(*) FROM lf_ops.politicas_timeout
 WHERE timeout_policy_id IN(2,4,5) AND status='CANDIDATO';
SELECT 'IDEMPOT_RULE_CANDIDATE='||(SELECT estado FROM lf_ops.reglas WHERE id=403);
SELECT 'SCREEN51_13_UNCHANGED='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=51;
SELECT 'SCREEN51_12_CURRENT='||count(*) FROM programacion.input_family_assessments
 WHERE run_id=952 AND coverage_status='COMPLETE';
SELECT 'SCREEN51_NEW_RECEIPTS='||count(*) FROM programacion.input_policy_autobind_receipts_v1
 WHERE pantalla_id=51;
"""

class IGCuratorPolicyAutobindPGDual(unittest.TestCase):
 def test_exact_curator_pg17_pg18_rollback(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertEqual(len(MIGRATION_CANDIDATES),1,"ONE_TRAIN_RETSTAMPED_MIGRATION_REQUIRED")
  original=MIGRATION_CANDIDATES[0].read_text(encoding="utf-8")
  self.assertIn("IG_POLICY_AUTOBIND_CURATOR_SOURCE_DRIFT",original)
  self.assertIn("IG_POLICY_AUTOBIND_COMPLETENESS_SOURCE_DRIFT",original)
  self.assertIn("ON CONFLICT (pantalla_id,reference_role) DO NOTHING",original)
  self.assertIn("production_authorized',false",original)
  self.assertIn("session_context_contract_still_required",original)
  curator=CURATOR.read_text(encoding="utf-8")
  complete=COMPLETE.read_text(encoding="utf-8")
  self.assertIn("v_graph:=programacion.fn_input_screen_canonical_graph",curator)
  self.assertIn("v_kind:=v_criteria->>'probe_kind';",complete)
  for version in ("17.6","18.7"):
   with self.subTest(postgres=version):
    name="lf-ig-pol-"+uuid.uuid4().hex[:9]
    start=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+version],
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
     def psql(sql):
      return subprocess.run(["docker","exec","-i",name,"psql","-X","-Atq",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=sql,text=True,capture_output=True,timeout=120)
     base=psql(FIXTURE+"\n"+complete+";\n"+curator+";\n")
     self.assertEqual(base.returncode,0,base.stderr[-3600:])
     md5cmd="""SELECT md5(pg_get_functiondef('programacion.fn_input_governance_curator_materialize_v1(integer,text,text,boolean)'::regprocedure));
SELECT md5(pg_get_functiondef('programacion.fn_input_governance_family_complete_probe_v1(integer,text,bigint,jsonb)'::regprocedure));
"""
     dig=psql(md5cmd)
     self.assertEqual(dig.returncode,0,dig.stderr)
     hashes=[s for s in dig.stdout.splitlines() if re.fullmatch(r"[0-9a-f]{32}",s)]
     self.assertEqual(len(hashes),2,dig.stdout)
     # Local PG pg_get_functiondef formatting may differ; change only the pin
     # literals in the transaction-local copy. The committed SQL pins live RO MD5.
     mig=original.replace("071fdce8c6ac9851e8106afd511fd3fb",hashes[0]).replace(
       "8b811c9cf20ff4903ced50b7b4b70ba3",hashes[1])
     self.assertTrue(mig.rstrip().endswith("COMMIT;"))
     inner=mig.split("\nBEGIN;\n",1)[1].rsplit("\nCOMMIT;",1)[0]
     tests=r"""
SELECT 'CURATOR44='||(programacion.fn_input_governance_curator_materialize_v1(
 44,'STORY_CREATOR','FIXTURE_CURATOR',false)->>'status');
SELECT 'CURATOR51='||(programacion.fn_input_governance_curator_materialize_v1(
 51,'STORY_CREATOR','FIXTURE_CURATOR',false)->>'status');
SELECT 'REPLAY_WRITE_ZERO='||(programacion.fn_input_governance_policy_autobind_v1(
 44,'STORY_CREATOR','FIXTURE_CURATOR')->>'write_count');
"""
     txn=psql("BEGIN;\n"+inner+"\n"+tests+CHECK+"\nROLLBACK;\n"
       "SELECT 'ROLLED_BACK_LINKS='||count(*) FROM lf_ops.pantallas_politicas WHERE pantalla_id=44;\n"
       "SELECT 'ROLLED_BACK_ASSESSMENTS='||count(*) FROM programacion.input_family_assessments WHERE run_id=957;\n"
       "SELECT 'SCREEN51_STILL_12='||count(*) FROM programacion.input_family_assessments WHERE run_id=952 AND coverage_status='COMPLETE';\n")
     self.assertEqual(txn.returncode,0,txn.stderr[-4300:])
     for required in ("CURATOR44=CURATING","CURATOR51=NOOP_CURRENT_RUN","REPLAY_WRITE_ZERO=0",
       "FOUR_COMPLETE=4","RATE_BIND=1","SESSION_BIND=1",
       "SESSION_CLIENT_MISBIND=0","TIMEOUT_BIND=3","IDEMPOT_BIND=1",
       "RECEIPTS=6","RULE_ASSOCIATIONS=7",
       "ALL_POLICY_CANDIDATES=3","IDEMPOT_RULE_CANDIDATE=CANDIDATO",
       "SCREEN51_13_UNCHANGED=13","SCREEN51_12_CURRENT=12",
       "SCREEN51_NEW_RECEIPTS=0","ROLLED_BACK_LINKS=0",
       "ROLLED_BACK_ASSESSMENTS=0","SCREEN51_STILL_12=12"):
      self.assertIn(required,txn.stdout,required+"\n"+txn.stdout[-3000:])
     # Missing source is a content finding, not an abort or invented coverage.
     negative=psql("BEGIN;\n"+inner+"\n"
       "UPDATE lf_ops.politicas_rate_limit SET policy_code='MISSING_TEST_SOURCE' WHERE rate_limit_policy_id=2;\n"
       "SELECT 'NEGATIVE_CURATOR='||(programacion.fn_input_governance_curator_materialize_v1("
         "44,'STORY_CREATOR','FIXTURE_CURATOR',false)->>'status');\n"
       "SELECT 'NEGATIVE_RATE_PARTIAL='||count(*) FROM programacion.input_family_assessments"
         " WHERE run_id=957 AND family_code='RATE_LIMIT' AND coverage_status='PARTIAL';\n"
       "SELECT 'NEGATIVE_RATE_BIND='||count(*) FROM lf_ops.pantallas_politicas"
         " WHERE pantalla_id=44 AND rate_limit_policy_id=2;\nROLLBACK;\n")
     self.assertEqual(negative.returncode,0,negative.stderr[-4500:])
     for required in ("NEGATIVE_CURATOR=CURATING",
       "NEGATIVE_RATE_PARTIAL=1","NEGATIVE_RATE_BIND=0"):
      self.assertIn(required,negative.stdout,negative.stdout[-3000:])
     print("PASS_IG_POLICY_AUTOBIND_PG"+version+"_CURATOR_4_4_SCREEN51_12_UNCHANGED_ROLLBACK")
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
