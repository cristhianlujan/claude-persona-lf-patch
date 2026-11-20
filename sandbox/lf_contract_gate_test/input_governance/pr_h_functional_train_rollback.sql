-- PR-H isolated PostgreSQL 17 (fixtures ARE NOT production RUNs or real Train receipts).
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA lf_ops;
@@PROJECT_OWNER_TABLE_DDL@@
@@OWNER_DECISION_TABLE_DDL@@
ALTER TABLE public.lf_ig_owner_decision_v2
 DROP CONSTRAINT lf_ig_owner_decision_v2_identity_mode_check;
ALTER TABLE public.lf_ig_owner_decision_v2
 ADD CONSTRAINT lf_ig_owner_decision_v2_identity_mode_check
 CHECK (identity_mode='USERNAME_ONLY_UNVERIFIED');
ALTER TABLE public.lf_ig_owner_decision_v2
 ALTER COLUMN identity_mode SET DEFAULT 'USERNAME_ONLY_UNVERIFIED';
@@RULE_CHANGE_TABLE_DDL@@
CREATE TABLE lf_ops.reglas (
 id bigint PRIMARY KEY,
 codigo text NOT NULL UNIQUE,
 categoria text NOT NULL DEFAULT 'SEGURIDAD',
 titulo text NOT NULL DEFAULT 'Fixture',
 descripcion text NOT NULL DEFAULT 'ORIGINAL DESCRIPTION',
 razon text NOT NULL DEFAULT 'FIXTURE',
 valor_config jsonb NOT NULL DEFAULT '{}'::jsonb,
 es_transversal boolean NOT NULL DEFAULT false,
 estado text NOT NULL,
 origen text NOT NULL DEFAULT 'FIXTURE',
 pendiente_decision boolean NOT NULL DEFAULT false,
 pendiente_detalle text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,
 status text NOT NULL,
 target_code text,
 created_by_execution_id text,
 updated_by_execution_id text,
 manifest jsonb DEFAULT '{}'::jsonb
);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text NOT NULL, step_id text NOT NULL,
 status text NOT NULL, PRIMARY KEY (execution_id,step_id)
);
CREATE TABLE public.lf_eventos (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 evento_tipo text NOT NULL,
 entidad_codigo text,
 origen text NOT NULL,
 payload jsonb NOT NULL
);
CREATE FUNCTION public.lf_asset_snapshot_sha_v1(p_asset_type text,p_code text)
RETURNS text LANGUAGE plpgsql STABLE
SECURITY DEFINER SET search_path='pg_catalog','public','extensions'
AS $snapshot$
DECLARE v jsonb;
BEGIN
 IF p_asset_type='REGLA' THEN
  SELECT to_jsonb(r)-'created_at'-'updated_at' INTO v
  FROM lf_ops.reglas r WHERE r.codigo=p_code;
 ELSE RETURN NULL; END IF;
 IF v IS NULL THEN RETURN NULL; END IF;
 RETURN encode(extensions.digest(convert_to(v::text,'UTF8'),'sha256'),'hex');
END
$snapshot$;
@@SOURCE_FINALIZER_DDL@@
REVOKE ALL ON FUNCTION public.lf_ig_rule_finalize_v2(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ig_rule_finalize_v2(text) TO service_role;

INSERT INTO public.lf_ig_project_owner_v2
 (project_code,owner_sub,owner_name,owner_profile_code,
  authority_receipt_sha256,status,source_execution_id)
VALUES ('LF','00000000-0000-4000-8000-000000000001',
 'Cristhian Luján','PERFIL-PRODUCT-DIRECTOR-LF',repeat('a',64),
 'TEMP_DOCUMENTARY_ACTIVE','PRH_TEST_ONLY');

INSERT INTO lf_ops.reglas(id,codigo,estado,valor_config) VALUES
 (437,'B2B-RULE-AUTH-018','VIGENTE','{"fixture":"AUTH-018"}'),
 (438,'B2B-RULE-AUTH-019','VIGENTE','{"fixture":"AUTH-019"}'),
 (439,'B2B-RULE-AUTH-020','VIGENTE',
  '{"hold_hours":48,"human_approval_count_required":2}');

DO $pre$
BEGIN
 IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0 OR
    (SELECT count(*) FROM public.lf_ig_rule_change_v2)<>0 OR
    (SELECT count(*) FROM lf_ops.reglas)<>3
 THEN RAISE EXCEPTION 'PR_H_PREIMAGE_ROWS_DRIFT'; END IF;
 IF md5(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure))
 <> '9d1a771fe5dd8b466b76071b582f19fa'
 THEN RAISE EXCEPTION 'PR_H_PREIMAGE_FUNCTION_DRIFT'; END IF;
 RAISE NOTICE 'PR_H_PREIMAGE_PASS original_md5=9d1a771fe5dd8b466b76071b582f19fa owner_rows=0 change_rows=0 auth_rules=3';
END
$pre$;

BEGIN;
@@PR_H_MIGRATION_SQL@@

DO $test$
DECLARE
 v_source text; v_candidate text; v_proposal text;
 v_patch jsonb; v_record jsonb; v_receipt jsonb; v_event bigint;
 v_decision uuid; v_result jsonb;
 v_train text:='EXEC-DB-TRAIN-PR99999-20261118090000-R123456789';
 v_head text:=repeat('a',40);
 v_rule text:='PRH-TEST-FUNCTIONAL-001';
 v_count int;
BEGIN
 IF md5(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure))
 <> 'df1acd69a46b8bc4a6c257d95cc9a47a'
 THEN RAISE EXCEPTION 'PR_H_TEST_POSTMIGRATION_MD5_FAILED'; END IF;
 INSERT INTO lf_ops.reglas(id,codigo,estado,descripcion,valor_config)
 VALUES (999,v_rule,'VIGENTE','BEFORE','{"test":"original"}');
 v_source:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 v_patch:=jsonb_build_object(
   'rule_code',v_rule,'change_kind','FUNCTIONAL',
   'changes',jsonb_build_object(
     'descripcion','AFTER FUNCTIONAL APPROVED ONLY IN TEST',
     'valor_config','{"test":"after"}'::jsonb));
 v_proposal:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
 -- Projected snapshot is calculated with the exact finalizer update semantics,
 -- in its own automatically rolled-back PL/pgSQL subtransaction.
 BEGIN
   UPDATE lf_ops.reglas SET descripcion='AFTER FUNCTIONAL APPROVED ONLY IN TEST',
     valor_config='{"test":"after"}',pendiente_decision=false,pendiente_detalle=NULL,
     updated_at=now() WHERE codigo=v_rule;
   v_candidate:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
   RAISE EXCEPTION 'PR_H_LOCAL_PROJECTION_ROLLBACK';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM <> 'PR_H_LOCAL_PROJECTION_ROLLBACK' THEN RAISE; END IF;
 END;
 IF public.lf_asset_snapshot_sha_v1('REGLA',v_rule) IS DISTINCT FROM v_source
 OR v_source IS NULL OR v_candidate IS NULL OR v_candidate=v_source
 THEN RAISE EXCEPTION 'PR_H_PROJECTION_NOT_ISOLATED'; END IF;
 INSERT INTO public.lf_operation_execution(
   execution_id,operation_code,status,target_code,manifest,updated_by_execution_id)
 VALUES
 ('PRH-PARENT-FIXTURE','EJECUCION_PERFIL_LF','IN_PROGRESS','PERFIL-PRODUCT-DIRECTOR-LF','{}',NULL),
 ('PRH-CHILD-FIXTURE','ACTUALIZACION_REGLA_LF','COMPLETED',v_rule,'{}',NULL),
 (v_train,'ACTUALIZACION_DB_LF','COMPLETED','TEST_MIGRATION',
 jsonb_build_object('train_run_id','123456789','head_sha',v_head),
 'LF-MIGRATION-TRAIN-RUN-123456789');
 UPDATE public.lf_operation_execution SET created_by_execution_id='PRH-PARENT-FIXTURE'
 WHERE execution_id='PRH-CHILD-FIXTURE';
 FOR v_count IN 1..7 LOOP
   INSERT INTO public.lf_operation_execution_steps VALUES
    ('PRH-CHILD-FIXTURE','STEP'||v_count,'PASS_CLEAN');
 END LOOP;
 v_record:=jsonb_build_object(
   'codigo_regla',v_rule,'propuesta_sha256',v_proposal,
   'veredicto','APROBAR','decisor','Cristhian Luján',
   'fecha','2026-11-18T09:00:00Z','frase_literal','OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE');
 INSERT INTO public.lf_ig_owner_decision_v2
  (project_code,owner_sub,decisor,proponente,decision_date,
   literal_phrase,decision_record,decision_record_sha256,
   parent_execution_id,rule_code,kind,source_sha256,proposal_sha256,verdict,approved_patch)
 VALUES
  ('LF','00000000-0000-4000-8000-000000000001',
   'Cristhian Luján','PRH_TEST_PRODUCER',now(),
   'OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE',v_record,
   encode(extensions.digest(convert_to(v_record::text,'UTF8'),'sha256'),'hex'),
   'PRH-PARENT-FIXTURE',v_rule,'CORRECT_VIGENTE',
   v_source,v_proposal,'APROBAR',v_patch)
 RETURNING decision_id INTO v_decision;
 INSERT INTO public.lf_ig_rule_change_v2(
    parent_execution_id,child_execution_id,rule_code,kind,
    owner_decision_id,source_snapshot_sha256,approved_patch,state)
 VALUES('PRH-PARENT-FIXTURE','PRH-CHILD-FIXTURE',v_rule,'CORRECT_VIGENTE',
   v_decision,v_source,v_patch,'STAGED');

 -- A different username MUST fail existing decision-table constraint.
 BEGIN
  INSERT INTO public.lf_ig_owner_decision_v2
   (project_code,owner_sub,decisor,proponente,decision_date,literal_phrase,
    decision_record,decision_record_sha256,parent_execution_id,
    rule_code,kind,source_sha256,proposal_sha256,verdict,approved_patch)
  VALUES('LF','00000000-0000-4000-8000-000000000001',
   'OTRO_USUARIO','PRH_TEST_PRODUCER',now(),
   'OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE',v_record,
   encode(extensions.digest(convert_to(v_record::text,'UTF8'),'sha256'),'hex'),
   'PRH-OTHER-PARENT',v_rule,'CORRECT_VIGENTE',
   v_source,v_proposal,'APROBAR',v_patch);
  RAISE EXCEPTION 'PR_H_FOREIGN_USER_ACCEPTED';
 EXCEPTION WHEN check_violation THEN
  RAISE NOTICE 'PR_H_FOREIGN_USER_REJECTED_PASS';
 END;

 -- No per-rule Train evidence => FUNCTIONAL must remain blocked.
 BEGIN
  PERFORM public.lf_ig_rule_finalize_v2('PRH-CHILD-FIXTURE');
  RAISE EXCEPTION 'PR_H_MISSING_EVIDENCE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LF_IG_VIGENTE_FUNCTIONAL_TRAIN_EVIDENCE_MISSING'
  THEN RAISE EXCEPTION 'PR_H_MISSING_EVIDENCE_WRONG_BLOCK:%',SQLERRM; END IF;
 END;

 -- Fixture Train ledger receipt: entirely synthetic, never a live attestation.
 v_receipt:=jsonb_build_object(
  'train_run_id','123456789',
  'heads',jsonb_build_object(
      'final_head',v_head,'final_head_is_execution_head',true),
  'terminal_status','COMPLETED',
  'parity',jsonb_build_object('migration_source_parity','PASS'),
  'ledger_readback',jsonb_build_object('matches_target',true));
 INSERT INTO public.lf_eventos(evento_tipo,entidad_codigo,origen,payload)
 VALUES('MIGRATION_TRAIN_RECEIPT_RECORDED',v_train,'lf-migration-merge-train',
   jsonb_build_object('receipt',v_receipt,'receipt_sha256',
     encode(extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),'hex')))
 RETURNING id INTO v_event;

 -- Missing candidate SHA is rejected at table schema.
 BEGIN
  INSERT INTO public.lf_ig_functional_train_evidence_v1
   (rule_code,source_snapshot_sha256,proposal_sha256,
    candidate_snapshot_sha256,train_execution_id,train_run_id,train_event_id,
    train_head_sha,pg_rollback_status,independent_readback_status,
    functional_checks_status,negative_checks_status,
    pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
  VALUES(v_rule,v_source,v_proposal,NULL,v_train,'123456789',v_event,
   v_head,'PASS','PASS','PASS','PASS',repeat('a',64),
   repeat('b',64),repeat('c',64),'PRH_LOCAL_TEST_ONLY');
  RAISE EXCEPTION 'PR_H_NULL_CANDIDATE_HASH_ACCEPTED';
 EXCEPTION WHEN not_null_violation THEN
  RAISE NOTICE 'PR_H_MISSING_CANDIDATE_HASH_REJECTED_PASS';
 END;

 INSERT INTO public.lf_ig_functional_train_evidence_v1
   (rule_code,source_snapshot_sha256,proposal_sha256,
    candidate_snapshot_sha256,train_execution_id,train_run_id,train_event_id,
    train_head_sha,pg_rollback_status,independent_readback_status,
    functional_checks_status,negative_checks_status,
    pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref)
 VALUES(v_rule,v_source,v_proposal,repeat('f',64),v_train,
  '123456789',v_event,v_head,'PASS','PASS','PASS','PASS',
  repeat('a',64),repeat('b',64),repeat('c',64),'PRH_LOCAL_TEST_ONLY');

 -- Unmatched Train run ID cannot verify even if an event exists.
 UPDATE public.lf_ig_functional_train_evidence_v1 SET train_run_id='9999'
 WHERE rule_code=v_rule;
 BEGIN
  PERFORM public.lf_ig_rule_finalize_v2('PRH-CHILD-FIXTURE');
  RAISE EXCEPTION 'PR_H_INVALID_TRAIN_RUN_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LF_IG_VIGENTE_FUNCTIONAL_TRAIN_RUN_UNVERIFIED'
  THEN RAISE EXCEPTION 'PR_H_INVALID_RUN_WRONG_BLOCK:%',SQLERRM; END IF;
 END;
 UPDATE public.lf_ig_functional_train_evidence_v1 SET train_run_id='123456789'
 WHERE rule_code=v_rule;

 -- Correct run ID with wrong projected candidate SHA MUST roll back the write.
 BEGIN
  PERFORM public.lf_ig_rule_finalize_v2('PRH-CHILD-FIXTURE');
  RAISE EXCEPTION 'PR_H_WRONG_CANDIDATE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'LF_IG_VIGENTE_FUNCTIONAL_CANDIDATE_HASH_DRIFT'
  THEN RAISE EXCEPTION 'PR_H_WRONG_CANDIDATE_WRONG_BLOCK:%',SQLERRM; END IF;
 END;
 IF public.lf_asset_snapshot_sha_v1('REGLA',v_rule)<>v_source
 THEN RAISE EXCEPTION 'PR_H_NEGATIVE_TEST_MUTATED_RULE'; END IF;
 UPDATE public.lf_ig_functional_train_evidence_v1
 SET candidate_snapshot_sha256=v_candidate WHERE rule_code=v_rule;

 -- Now correct full evidence permits a change FUNCTIONAL, but only in outer BEGIN.
 v_result:=public.lf_ig_rule_finalize_v2('PRH-CHILD-FIXTURE');
 IF v_result->>'status'<>'VIGENTE_VERIFIED'
    OR v_result->>'result_snapshot_sha256' IS DISTINCT FROM v_candidate
    OR v_result->>'production_authorized'<>'false'
 THEN RAISE EXCEPTION 'PR_H_VALID_FUNCTIONAL_NOT_COMPLETED:%',v_result; END IF;
 IF public.lf_asset_snapshot_sha_v1('REGLA',v_rule)<>v_candidate OR
  (SELECT state FROM public.lf_ig_rule_change_v2
   WHERE child_execution_id='PRH-CHILD-FIXTURE')<>'VIGENTE_VERIFIED'
 THEN RAISE EXCEPTION 'PR_H_VALID_FUNCTIONAL_READBACK_MISMATCH'; END IF;

 IF (SELECT count(*) FROM lf_ops.reglas
 WHERE codigo IN('B2B-RULE-AUTH-018','B2B-RULE-AUTH-019','B2B-RULE-AUTH-020')
   AND estado='VIGENTE')<>3
 OR (SELECT valor_config->>'hold_hours' FROM lf_ops.reglas
     WHERE codigo='B2B-RULE-AUTH-020')<>'48'
 OR (SELECT valor_config->>'human_approval_count_required' FROM lf_ops.reglas
     WHERE codigo='B2B-RULE-AUTH-020')<>'2'
 THEN RAISE EXCEPTION 'PR_H_AUTH_SOURCE_DRIFT'; END IF;
 RAISE NOTICE 'PR_H_IN_TRANSACTION_PASS functional_applied=true correct_candidate=true bad_run_denied=true null_hash_denied=true wrong_hash_denied=true foreign_owner_denied=true auth_unchanged=3';
END
$test$;

ROLLBACK;

DO $after$
BEGIN
 IF to_regclass('public.lf_ig_functional_train_evidence_v1') IS NOT NULL
 OR (SELECT count(*) FROM public.lf_ig_rule_change_v2)<>0
 OR (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0
 OR (SELECT count(*) FROM lf_ops.reglas)<>3
 THEN RAISE EXCEPTION 'PR_H_ROLLBACK_PERSISTED_TEST_ARTIFACTS'; END IF;
 IF md5(pg_get_functiondef('public.lf_ig_rule_finalize_v2(text)'::regprocedure))
 <> '9d1a771fe5dd8b466b76071b582f19fa'
 THEN RAISE EXCEPTION 'PR_H_ROLLBACK_FINALIZER_NOT_RESTORED'; END IF;
 RAISE NOTICE 'PR_H_POST_ROLLBACK_PASS decisions=0 changes=0 auth_rules=3 impact_evidence_absent=true finalizer_original=true';
END
$after$;
