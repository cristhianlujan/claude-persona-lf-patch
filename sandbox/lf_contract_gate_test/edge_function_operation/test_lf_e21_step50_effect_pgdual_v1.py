"""E21 Step50 real DB effect guard. Docker PG17.6/PG18.7; all business writes BEGIN/ROLLBACK.

The fixture Train and rule changes are explicitly synthetic and rollback-only;
they are NOT evidence of a user RUN, PR promotion or real implementation.
"""
import shutil
import subprocess
import time
import unittest
import uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MIGS=list((ROOT/"supabase/migrations").glob("*_lf_e21_step50_verified_real_effect_v1.sql"))
assert len(MIGS)==1,"E21_STEP50_MIGRATION_MISSING_OR_AMBIGUOUS"
MIG=MIGS[0].read_text(encoding="utf-8")
DDL=MIG.split("-- Bind the authoritative guard inside the EXISTING Step50 writer",1)[0]+"\nCOMMIT;\n"
TEST_SETUP=r"""
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA extensions;
CREATE SCHEMA lf_ops;
CREATE SCHEMA supabase_migrations;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE TABLE lf_ops.reglas (
 id int PRIMARY KEY,
 codigo text UNIQUE NOT NULL,
 titulo text NOT NULL,
 categoria text NOT NULL DEFAULT 'SECURITY',
 valor_config jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz DEFAULT now(),
 updated_at timestamptz DEFAULT now()
);
CREATE TABLE lf_ops.pantallas(id int PRIMARY KEY,codigo text UNIQUE NOT NULL);
CREATE TABLE lf_ops.reglas_pantallas(regla_id int NOT NULL,pantalla_id int NOT NULL);
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,
 target_code text,
 status text NOT NULL,
 manifest jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text NOT NULL,
 step_order int NOT NULL,
 step_id text NOT NULL,
 status text NOT NULL,
 evidence_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 PRIMARY KEY(execution_id,step_order)
);
CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text NOT NULL);
"""
TXN=r"""
BEGIN;
INSERT INTO lf_ops.pantallas VALUES (51,'B2B-AUTH-001');
INSERT INTO lf_ops.reglas(id,codigo,titulo) VALUES
 (111,'B2B-RULE-AUTH-004','Original login policy'),
 (112,'B2B-RULE-AUTH-049','Existing other rule');
INSERT INTO lf_ops.reglas_pantallas VALUES (111,51),(112,51);
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_code,status,manifest)
VALUES
 ('E21-TEST-GOV','EJECUCION_PERFIL_LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS',
 jsonb_build_object('governed_repair_write',true,'promotion_allowed',true,
 'repair_execution_authority',jsonb_build_object('promotion_allowed',true),
 'screen_selection_result',jsonb_build_object('selected_screen_code','B2B-AUTH-001'))),
 ('E21-TEST-READ-ONLY','EJECUCION_PERFIL_LF','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','IN_PROGRESS',
 jsonb_build_object('governed_repair_write',false,'promotion_allowed',false)),
 ('EXEC-DB-TRAIN-PR4100-20261116102000-R44444444','ACTUALIZACION_DB_LF',
 '20261116102000_lf_e21_fixture_test_only_v1','IN_PROGRESS',
 jsonb_build_object('pr',4100,'producer','lf-migration-merge-train',
 'train_run_id','44444444','operation_closed',false));
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload)
 VALUES ('E21-TEST-GOV',40,'input_validate','STEP_PASS_WITH_EVIDENCE',
  jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('a',64)));
DO $e21$
DECLARE g jsonb;
BEGIN
 g:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-READ-ONLY',
 '{"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}}'::jsonb);
 IF g->>'status'<>'ALLOW_NO_PROMOTION' THEN
 RAISE EXCEPTION 'E21_READ_ONLY_MUST_ALLOW_UNEXECUTED:%',g; END IF;
 g:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-GOV',
 '{"repair_execution":{"mode":"AUTHORIZED_NOT_EXECUTED"}}'::jsonb);
 IF g->>'code'<>'STEP50_AUTHORIZED_NOT_EXECUTED_FORBIDDEN' THEN
 RAISE EXCEPTION 'E21_GOV_UNEXECUTED_MUST_BLOCK:%',g; END IF;
 g:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-GOV',
 '{"repair_execution":{"mode":"EXECUTED_WITH_READBACK"}}'::jsonb);
 IF g->>'code'<>'STEP50_RULE_RECEIPTS_REQUIRED' THEN
 RAISE EXCEPTION 'E21_MISSING_RECEIPT_MUST_BLOCK:%',g; END IF;
END $e21$;
SELECT 'E21_MODE_NEGATIVES=PASS';

-- The source DB computes BEFORE. A text-only model output cannot create it.
DO $e21$
DECLARE x jsonb;
BEGIN
 x:=public.lf_profile_step50_rule_effect_before_v1('E21-TEST-GOV',
  'EXEC-DB-TRAIN-PR4100-20261116102000-R44444444','B2B-RULE-AUTH-004');
 IF x->>'status'<>'BEFORE_CAPTURED' THEN RAISE EXCEPTION 'E21_BEFORE_NOT_CAPTURED:%',x; END IF;
END $e21$;
-- An unchanged rule must not have an after-effect receipt.
DO $e21$
DECLARE x jsonb;
BEGIN
 x:=public.lf_profile_step50_rule_effect_after_v1('E21-TEST-GOV',
  'EXEC-DB-TRAIN-PR4100-20261116102000-R44444444','B2B-RULE-AUTH-004');
 IF x->>'code'<>'STEP50_EFFECT_NO_CHANGE' THEN RAISE EXCEPTION 'E21_FAKE_EFFECT_ACCEPTED:%',x; END IF;
END $e21$;
UPDATE lf_ops.reglas SET titulo='Updated login policy' WHERE codigo='B2B-RULE-AUTH-004';
DO $e21$
DECLARE x jsonb;
BEGIN
 x:=public.lf_profile_step50_rule_effect_after_v1('E21-TEST-GOV',
  'EXEC-DB-TRAIN-PR4100-20261116102000-R44444444','B2B-RULE-AUTH-004');
 IF x->>'status'<>'EFFECT_CAPTURED'
 OR x->>'before_sha256'=x->>'after_sha256' THEN
 RAISE EXCEPTION 'E21_GENUINE_EFFECT_NOT_CAPTURED:%',x; END IF;
END $e21$;
CREATE TEMP TABLE e21_output AS
SELECT jsonb_build_object(
 'repair_execution',jsonb_build_object(
  'mode','EXECUTED_WITH_READBACK',
  'changes',jsonb_build_array(jsonb_build_object('target_ref',
     'supabase://lf_ops.reglas/B2B-RULE-AUTH-004',
     'before_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-004/before',
     'after_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-004/after')),
  'rule_receipts',jsonb_build_array(jsonb_build_object(
    'rule_code','B2B-RULE-AUTH-004',
    'source_ref','supabase://lf_ops.reglas/B2B-RULE-AUTH-004',
    'before_sha256',r.before_sha256,'after_sha256',r.after_sha256,
    'train_execution_id','EXEC-DB-TRAIN-PR4100-20261116102000-R44444444',
    'train_pr',4100,'train_run_id','44444444',
    'migration_version','20261116102000',
    'migration_name','lf_e21_fixture_test_only_v1',
    'merge_sha',repeat('f',40)
  ))
)) AS raw FROM public.lf_profile_step50_rule_effect_receipts_v1 r;

DO $e21$
DECLARE v_raw jsonb; x jsonb;
BEGIN
 SELECT o.raw INTO v_raw FROM e21_output o;
 x:=public.lf_profile_step50_rule_effect_guard_v1(
 'E21-TEST-GOV',jsonb_set(v_raw,'{repair_execution,rule_receipts,0,before_sha256}','null'::jsonb));
 IF x->>'code'<>'STEP50_EFFECT_HASH_PAIR_REQUIRED' THEN
 RAISE EXCEPTION 'E21_MISSING_BEFORE_HASH_NOT_BLOCKED:%',x; END IF;
 x:=public.lf_profile_step50_rule_effect_guard_v1(
 'E21-TEST-GOV',jsonb_set(v_raw,'{repair_execution,rule_receipts,0,after_sha256}','null'::jsonb));
 IF x->>'code'<>'STEP50_EFFECT_HASH_PAIR_REQUIRED' THEN
 RAISE EXCEPTION 'E21_MISSING_AFTER_HASH_NOT_BLOCKED:%',x; END IF;
 x:=public.lf_profile_step50_rule_effect_guard_v1(
 'E21-TEST-GOV',jsonb_set(v_raw,'{repair_execution,rule_receipts,0,source_ref}',
  to_jsonb('supabase://lf_ops.reglas/B2B-RULE-AUTH-049'::text)));
 IF x->>'code'<>'STEP50_RULE_RECEIPT_SOURCE_REF_MISMATCH' THEN
 RAISE EXCEPTION 'E21_OTHER_RULE_RECEIPT_ACCEPTED:%',x; END IF;
 x:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-GOV',v_raw);
 IF x->>'code'<>'STEP50_TRAIN_RECEIPT_NOT_VERIFIED' THEN
 RAISE EXCEPTION 'E21_INCOMPLETE_TRAIN_ACCEPTED:%',x; END IF;
END $e21$;
SELECT 'E21_MISSING_HASH_WRONG_RULE_AND_UNFINISHED_TRAIN=PASS';

UPDATE public.lf_operation_execution
SET status='COMPLETED',
 manifest=manifest||jsonb_build_object('operation_closed',true,
  'closure_evidence',jsonb_build_object('parity','PASS',
   'ledger',jsonb_build_object('version','20261116102000','name','lf_e21_fixture_test_only_v1'),
   'merge_sha',repeat('f',40)))
WHERE execution_id='EXEC-DB-TRAIN-PR4100-20261116102000-R44444444';
INSERT INTO supabase_migrations.schema_migrations VALUES ('20261116102000','lf_e21_fixture_test_only_v1');
INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload)
VALUES
 ('EXEC-DB-TRAIN-PR4100-20261116102000-R44444444',20,'patch','PASS_CLEAN',
  '{"train_run_id":"44444444"}'::jsonb),
 ('EXEC-DB-TRAIN-PR4100-20261116102000-R44444444',30,'verify','PASS_CLEAN',
  '{"train_run_id":"44444444","readback":{"in_main":true}}'::jsonb);
DO $e21$
DECLARE v_raw jsonb; x jsonb;
BEGIN
 SELECT o.raw INTO v_raw FROM e21_output o;
 x:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-GOV',v_raw);
 IF x->>'status'<>'VERIFIED' OR x->>'verified_rule_count'<>'1'
 OR x#>>'{rule_receipts,0,source_ref}'<>'supabase://lf_ops.reglas/B2B-RULE-AUTH-004' THEN
 RAISE EXCEPTION 'E21_VERIFIED_EFFECT_NOT_ACCEPTED:%',x; END IF;
 x:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-GOV',
 jsonb_set(v_raw,'{repair_execution,rule_receipts,0,train_pr}','4101'::jsonb));
 IF x->>'code'<>'STEP50_TRAIN_RECEIPT_NOT_VERIFIED' THEN
 RAISE EXCEPTION 'E21_FOREIGN_TRAIN_PR_ACCEPTED:%',x; END IF;
END $e21$;
SELECT 'E21_SOURCE_BOUND_REAL_DB_EFFECT_POSITIVE=PASS';
-- An out-of-band later update invalidates the previous AFTER snapshot.
UPDATE lf_ops.reglas SET titulo='Unrelated latest change' WHERE codigo='B2B-RULE-AUTH-004';
DO $e21$
DECLARE v_raw jsonb;x jsonb;
BEGIN
 SELECT o.raw INTO v_raw FROM e21_output o;
 x:=public.lf_profile_step50_rule_effect_guard_v1('E21-TEST-GOV',v_raw);
 IF x->>'code'<>'STEP50_EFFECT_AFTER_NOT_CURRENT' THEN
 RAISE EXCEPTION 'E21_STALE_AFTER_RECEIPT_ACCEPTED:%',x; END IF;
END $e21$;
SELECT 'E21_STALE_AFTER_FAIL_CLOSED=PASS';
ROLLBACK;
SELECT 'E21_ROLLBACK_NO_RULE_ROWS='||count(*) FROM lf_ops.reglas;
SELECT 'E21_ROLLBACK_NO_EFFECT_ROWS='||count(*) FROM public.lf_profile_step50_rule_effect_receipts_v1;
"""
class Step50RealEffectPgDual(unittest.TestCase):
 def test_step50_real_snapshots_train_and_negative_pg17_pg18_rollback(self):
  self.assertIsNotNone(shutil.which("docker"),"DOCKER_REQUIRED")
  self.assertIn("STEP50_AUTHORIZED_NOT_EXECUTED_FORBIDDEN",MIG)
  self.assertIn("lf_profile_step50_rule_effect_guard_v1(p_execution_id,p_profile_output)",MIG)
  for pg in ("17.6","18.7"):
   with self.subTest(pg=pg):
    name="lf-e21-step50-"+uuid.uuid4().hex[:8]
    process=subprocess.run(["docker","run","-d","--rm","--name",name,
      "-e","POSTGRES_PASSWORD=fixture-only","postgres:"+pg],
      text=True,capture_output=True,timeout=180)
    self.assertEqual(process.returncode,0,process.stderr)
    try:
     for _ in range(90):
      ready=subprocess.run(["docker","exec",name,"pg_isready","-U","postgres"],
        text=True,capture_output=True,timeout=10)
      if ready.returncode==0:
       logs=subprocess.run(["docker","logs",name],text=True,capture_output=True,timeout=10)
       if "PostgreSQL init process complete; ready for start up." in logs.stdout+logs.stderr:break
      time.sleep(.5)
     self.assertEqual(ready.returncode,0,"PG_NOT_READY")
     def sql(s):
      p=subprocess.run(["docker","exec","-i",name,"psql","-X","-A","-t",
       "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"],
       input=s,text=True,capture_output=True,timeout=180)
      self.assertEqual(p.returncode,0,p.stderr[-5200:]+"\n"+p.stdout[-2500:])
      return p.stdout
     sql(TEST_SETUP+"\n"+DDL)
     out=sql(TXN)
     for marker in (
       "E21_MODE_NEGATIVES=PASS",
       "E21_MISSING_HASH_WRONG_RULE_AND_UNFINISHED_TRAIN=PASS",
       "E21_SOURCE_BOUND_REAL_DB_EFFECT_POSITIVE=PASS",
       "E21_STALE_AFTER_FAIL_CLOSED=PASS",
       "E21_ROLLBACK_NO_RULE_ROWS=0",
       "E21_ROLLBACK_NO_EFFECT_ROWS=0"):
      self.assertIn(marker,out,marker+"\n"+out[-2400:])
     print("PASS_E21_STEP50_SOURCE_BOUND_REAL_EFFECT_PG"+pg+"_ROLLBACK",flush=True)
    finally:
     subprocess.run(["docker","rm","-f",name],capture_output=True,timeout=30)
if __name__=="__main__":unittest.main()
