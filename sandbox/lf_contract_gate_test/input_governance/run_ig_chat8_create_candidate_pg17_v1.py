#!/usr/bin/env python3
"""IG Chat8: exact new CREATE function source, real PG17 with synthetic fixtures only."""
from pathlib import Path
import hashlib, json, os, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[3]
MIG = ROOT / "supabase/migrations/20261118214500_lf_ig_create_candidate_auth_window_v1.sql"
OUT = ROOT / ".lf_ci/ig_chat8_create_candidate"
DB = "ig_chat8_create_pg17"

def guard(x, name):
    if not x:
        raise AssertionError(name)

def pg(sql, database="postgres"):
    return subprocess.run(
        ["psql","-X","-v","ON_ERROR_STOP=1","-A","-t",
         "-h","127.0.0.1","-p","5432","-U","postgres","-d",database,"-f","-"],
        input=sql,text=True,capture_output=True,env=os.environ.copy(),
        timeout=120,check=False)

def good(sql,label,database=DB):
    r=pg(sql,database)
    guard(r.returncode == 0,label+": "+r.stderr[-1200:])
    return r

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sql=MIG.read_text()
    start=sql.index("CREATE OR REPLACE FUNCTION public.lf_ig_step70_functional_train_auto_v1")
    end=sql.index("\nDO $ig_create_post$",start)
    funs=sql[start:end]
    guard(funs.count("CREATE OR REPLACE FUNCTION")==2,"TWO_FUNCTIONS_REQUIRED")
    guard("APPROVED_AND_CANDIDATO_VERIFIED" in funs,"CANDIDATO_STATUS_REQUIRED")
    guard("RULE_CONTRACT_LEVEL" in funs,"CREATE_TRAIN_SCOPE_REQUIRED")
    guard(funs.index(" IF v_kind='CREATE' THEN") <
          funs.index(" v_final:=public.lf_ig_rule_finalize_v2("),
          "CREATE_MUST_RETURN_BEFORE_PROMOTION")
    guard("AUTO_TRAIN_VIGENTE_SCOPE_INVALID" in funs,"FUNCTIONAL_GUARD_PRESERVED")
    guard(not re.search(r"\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+lf_ops\.reglas\b",sql,re.I),
          "DIRECT_RULE_DML_FORBIDDEN")

    good("CREATE DATABASE "+DB+";","CREATE_EPHEMERAL_DB_FAILED","postgres")
    setup=r"""
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA lf_ops;
CREATE TABLE lf_ops.reglas(
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 codigo text UNIQUE NOT NULL, estado text NOT NULL,
 pendiente_decision boolean DEFAULT TRUE, created_by text);
CREATE TABLE lf_ops.pantallas(
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY, codigo text NOT NULL UNIQUE);
CREATE TABLE lf_ops.reglas_pantallas(regla_id integer,pantalla_id integer);
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY, operation_code text, target_type text,
 target_code text, status text, manifest jsonb, started_at timestamptz DEFAULT now(),
 updated_by_execution_id text, created_by_execution_id text);
CREATE TABLE public.lf_operation_execution_steps(
 execution_id text, step_id text, status text, evidence_payload jsonb);
CREATE TABLE public.lf_ig_functional_train_evidence_v1(
 rule_code text,source_snapshot_sha256 text,proposal_sha256 text,
 candidate_snapshot_sha256 text,train_execution_id text,train_run_id text,
 train_event_id bigint,train_head_sha text,
 pg_rollback_status text,independent_readback_status text,
 functional_checks_status text,negative_checks_status text,
 pg_report_sha256 text,readback_sha256 text,check_manifest_sha256 text,
 report_ref text);
CREATE TABLE public.lf_eventos(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 entidad_codigo text, evento_tipo text,origen text,payload jsonb);
"""
    good(setup,"SYNTHETIC_BASE_SETUP_FAILED")
    data=r"""
INSERT INTO lf_ops.pantallas(codigo) VALUES('TEST-SCREEN');
INSERT INTO public.lf_operation_execution
(execution_id,operation_code,target_type,target_code,status,manifest,updated_by_execution_id)
VALUES
('P-CREATE','EJECUCION_PERFIL_LF','PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
 'IN_PROGRESS',
 '{"read_only":true,"no_write":true,"router_profile_handoff":{"router_authorization_receipt":{"profile_execution_allowed":true}},"screen_selection_result":{"selected_screen_code":"TEST-SCREEN"}}',
 NULL),
('T-CREATE','ACTUALIZACION_DB_LF','DB','TEST-TRAIN','COMPLETED',
 '{"train_run_id":"TEST-RUN","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}',
 'LF-MIGRATION-TRAIN-RUN-TEST-RUN');
INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
VALUES
('P-CREATE','input_validate','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object('scope_authority_packet_sha256','sha256:'||repeat('b',64))),
('P-CREATE','execute_profile','STEP_PASS_WITH_EVIDENCE',
 jsonb_build_object(
  'candidate_digest','sha256:'||repeat('c',64),
  'profile_output',jsonb_build_object(
   'worker','product_director_lf','output_type','PRODUCT_DIRECTION_SPEC',
   'self_verdict','PASS',
   'deliverable_created',jsonb_build_object(
    'governed_rule_patch',jsonb_build_object(
      'rule_code','TEST-CREATE','change_kind','CREATE',
      'changes',jsonb_build_object(
       'categoria','AUTENTICACION','titulo','Regla de prueba CREATE',
       'descripcion','Detalle con parametros server-side para test solamente',
       'es_transversal',false)))))),
('P-CREATE','output_validate','STEP_PASS_WITH_EVIDENCE',
 '{"output_contract_result":"PASS"}');
WITH receipt AS (
 SELECT jsonb_build_object(
   'train_run_id','TEST-RUN',
   'heads',jsonb_build_object(
     'final_head',repeat('a',40),'final_head_is_execution_head',true),
   'terminal_status','COMPLETED',
   'parity',jsonb_build_object('migration_source_parity','PASS'),
   'ledger_readback',jsonb_build_object('matches_target',true)) AS value
)
INSERT INTO public.lf_eventos(entidad_codigo,evento_tipo,origen,payload)
SELECT 'T-CREATE','MIGRATION_TRAIN_RECEIPT_RECORDED','lf-migration-merge-train',
 jsonb_build_object('receipt',value,'receipt_sha256',
   encode(extensions.digest(convert_to(value::text,'UTF8'),'sha256'),'hex'))
FROM receipt;
INSERT INTO public.lf_ig_functional_train_evidence_v1
(rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
 train_execution_id,train_run_id,train_event_id,train_head_sha,
 pg_rollback_status,independent_readback_status,functional_checks_status,
 negative_checks_status,pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
SELECT 'TEST-CREATE',
 encode(extensions.digest(convert_to('LF_RULE_ABSENT:TEST-CREATE','UTF8'),'sha256'),'hex'),
 encode(extensions.digest(convert_to(
  (s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}')::text,
  'UTF8'),'sha256'),'hex'),
 repeat('d',64),
 'T-CREATE','TEST-RUN',(SELECT id FROM public.lf_eventos LIMIT 1),repeat('a',40),
 'PASS','PASS','PASS','PASS',repeat('e',64),repeat('f',64),repeat('b',64),
 'synthetic://ephemeral-postgres/#RULE_CONTRACT_LEVEL'
FROM public.lf_operation_execution_steps s
WHERE s.execution_id='P-CREATE' AND s.step_id='execute_profile';
"""
    checks=r"""
DO $assert$
DECLARE result jsonb;
BEGIN
 result:=public.lf_ig_step70_functional_train_auto_v1('P-CREATE');
 IF result->>'status'<>'PASS' OR result->>'verdict'<>'PASS_TRAIN_EVIDENCE_AUTOMATICO'
 OR result#>>'{train_evidence,evidence_scope}'<>'RULE_CONTRACT_LEVEL'
 THEN RAISE EXCEPTION 'CREATE_TEST_POSITIVE_FAILED: %',result; END IF;
 RAISE NOTICE 'IG_CHAT8_CREATE_TRAIN_SCOPE_POSITIVE_PASS';
END $assert$;
UPDATE public.lf_ig_functional_train_evidence_v1
 SET report_ref='synthetic://ephemeral-postgres/#WRONG_SCOPE';
DO $assert$
DECLARE result jsonb;
BEGIN
 result:=public.lf_ig_step70_functional_train_auto_v1('P-CREATE');
 IF result->>'blocking_code'<>'AUTO_TRAIN_EXACT_SHA_OR_PASS_MISSING'
 THEN RAISE EXCEPTION 'CREATE_TEST_WRONG_SCOPE_NOT_BLOCKED: %',result; END IF;
 RAISE NOTICE 'IG_CHAT8_CREATE_WRONG_SCOPE_BLOCK_PASS';
END $assert$;
UPDATE public.lf_ig_functional_train_evidence_v1
 SET report_ref='synthetic://ephemeral-postgres/#RULE_CONTRACT_LEVEL';
INSERT INTO lf_ops.reglas(codigo,estado) VALUES('TEST-CREATE','CANDIDATO');
DO $assert$
DECLARE result jsonb;
BEGIN
 result:=public.lf_ig_step70_functional_train_auto_v1('P-CREATE');
 IF result->>'blocking_code'<>'AUTO_TRAIN_CREATE_ABSENCE_OR_SCREEN_INVALID'
 THEN RAISE EXCEPTION 'CREATE_TEST_DUPLICATE_NOT_BLOCKED: %',result; END IF;
 RAISE NOTICE 'IG_CHAT8_CREATE_DUPLICATE_RULE_BLOCK_PASS';
END $assert$;
DELETE FROM lf_ops.reglas WHERE codigo='TEST-CREATE';
UPDATE public.lf_eventos SET
 payload=jsonb_set(payload,'{receipt_sha256}',to_jsonb(repeat('0',64)));
DO $assert$
DECLARE result jsonb;
BEGIN
 result:=public.lf_ig_step70_functional_train_auto_v1('P-CREATE');
 IF result->>'blocking_code'<>'AUTO_TRAIN_SIGNED_RECEIPT_INVALID'
 THEN RAISE EXCEPTION 'CREATE_TEST_UNVERIFIED_TRAIN_NOT_BLOCKED: %',result; END IF;
 RAISE NOTICE 'IG_CHAT8_CREATE_BAD_TRAIN_RECEIPT_BLOCK_PASS';
END $assert$;
UPDATE public.lf_eventos SET payload=jsonb_set(payload,'{receipt_sha256}',
 to_jsonb(encode(extensions.digest(convert_to((payload->'receipt')::text,'UTF8'),'sha256'),'hex')));
UPDATE public.lf_operation_execution_steps SET status='BLOCKED'
 WHERE execution_id='P-CREATE' AND step_id='output_validate';
DO $assert$
DECLARE result jsonb;
BEGIN
 result:=public.lf_ig_step70_functional_train_auto_v1('P-CREATE');
 IF result->>'blocking_code'<>'AUTO_TRAIN_PROFILE_OR_STEP_INVALID'
 THEN RAISE EXCEPTION 'CREATE_TEST_STEP60_NOT_BLOCKED: %',result; END IF;
 RAISE NOTICE 'IG_CHAT8_CREATE_STEP60_MISSING_BLOCK_PASS';
END $assert$;
DO $assert$
BEGIN
 BEGIN
   PERFORM public.lf_ig_rule_owner_decide_v2(
    'P-CREATE','TEST-CREATE',repeat('a',64),
    '{"usuario":"NO_DUENO","veredicto":"APROBAR"}'::jsonb);
   RAISE EXCEPTION 'WRONG_OWNER_NOT_BLOCKED';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM='WRONG_OWNER_NOT_BLOCKED'
      OR SQLERRM NOT LIKE 'LF_IG_OWNER_DECISION_INPUT_INVALID%'
   THEN RAISE; END IF;
 END;
 RAISE NOTICE 'IG_CHAT8_WRONG_OWNER_BLOCK_PASS';
END $assert$;
"""
    report={"status":"FAIL","type":"SYNTHETIC_PG17_ONLY","remote_supabase_tested":False}
    tx="BEGIN;\n"+funs+"\n"+data+"\n"+checks+"\nROLLBACK;\n"
    trial=pg(tx,DB)
    log=trial.stdout+"\n"+trial.stderr
    (OUT/"postgresql.log").write_text(log)
    tags=[
      "IG_CHAT8_CREATE_TRAIN_SCOPE_POSITIVE_PASS",
      "IG_CHAT8_CREATE_WRONG_SCOPE_BLOCK_PASS",
      "IG_CHAT8_CREATE_DUPLICATE_RULE_BLOCK_PASS",
      "IG_CHAT8_CREATE_BAD_TRAIN_RECEIPT_BLOCK_PASS",
      "IG_CHAT8_CREATE_STEP60_MISSING_BLOCK_PASS",
      "IG_CHAT8_WRONG_OWNER_BLOCK_PASS",
    ]
    report["checks"]={tag:(tag in log) for tag in tags}
    report["transaction_exit"]=trial.returncode
    report["log_sha256"]=hashlib.sha256(log.encode()).hexdigest()
    r=pg("""SELECT CASE WHEN
     to_regprocedure('public.lf_ig_step70_functional_train_auto_v1(text)') IS NULL
     AND to_regprocedure('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)') IS NULL
     AND (SELECT count(*) FROM lf_ops.reglas)=0
     AND (SELECT count(*) FROM public.lf_operation_execution)=0
     AND (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1)=0
    THEN 'ROLLBACK_RESTORED' ELSE 'ROLLBACK_DIRTY' END;""",DB)
    report["independent_readback"]=r.stdout.strip()
    report["source_sha256"]=hashlib.sha256(sql.encode()).hexdigest()
    guard(trial.returncode == 0 and all(report["checks"].values()),
          "PG17_TRANSACTION_CHECKS_NOT_ALL_PASS "+trial.stderr[-1200:])
    guard(r.returncode == 0 and report["independent_readback"]=="ROLLBACK_RESTORED",
          "PG17_INDEPENDENT_READBACK_FAILED "+r.stderr[-300:])
    report["status"]="PASS"
    (OUT/"report.json").write_text(json.dumps(report,sort_keys=True,indent=2)+"\n")
    print("IG_CHAT8_CREATE_PG17_ALL_6_CHECKS_PASS")
    return 0

if __name__=="__main__":
    try:
      sys.exit(main())
    except Exception as e:
      print("IG_CHAT8_CREATE_PG17_BLOCKED",str(e)[:1500],file=sys.stderr)
      sys.exit(1)
