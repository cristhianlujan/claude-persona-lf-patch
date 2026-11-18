-- PR-G: real PostgreSQL17 test fixture, entire migration inside BEGIN/ROLLBACK.
-- No real owner approval, judge, AUTH rule or production RUN is created.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA lf_ops;
@@PROJECT_OWNER_TABLE_DDL@@
@@OWNER_DECISION_TABLE_DDL@@

-- Fixture-only minimal relations read by the EXISTING owner V2 function.
CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL, status text NOT NULL,
 target_type text, target_code text, manifest jsonb,
 started_at timestamptz, request_sha256 text
);
CREATE TABLE public.lf_operation_execution_steps (
 execution_id text, step_id text, status text, evidence_payload jsonb,
 PRIMARY KEY (execution_id,step_id)
);
CREATE TABLE lf_ops.reglas (
 id bigint PRIMARY KEY,
 codigo text UNIQUE NOT NULL,
 estado text NOT NULL,
 valor_config jsonb NOT NULL
);
INSERT INTO lf_ops.reglas VALUES
 (437,'B2B-RULE-AUTH-018','VIGENTE','{"fixture":"PR-G-AUTH-018-UNCHANGED"}'),
 (438,'B2B-RULE-AUTH-019','VIGENTE','{"fixture":"PR-G-AUTH-019-UNCHANGED"}'),
 (439,'B2B-RULE-AUTH-020','VIGENTE','{"hold_hours":48,"human_approval_count_required":2}');

INSERT INTO public.lf_ig_project_owner_v2
 (project_code,owner_sub,owner_name,owner_profile_code,
  authority_receipt_sha256,status,source_execution_id)
VALUES ('LF','00000000-0000-4000-8000-000000000001',
        'Cristhian Luján','PERFIL-PRODUCT-DIRECTOR-LF',
        repeat('a',64),'TEMP_DOCUMENTARY_ACTIVE','LOCAL_TEST_ONLY');

@@SOURCE_OWNER_WRITER_DDL@@
REVOKE ALL ON FUNCTION public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)
 TO service_role;

-- No actual profile/judge execution: these are synthetic in a disposable PG fixture.
INSERT INTO public.lf_operation_execution
 (execution_id,operation_code,status,target_type,target_code,manifest,started_at,request_sha256)
VALUES
 ('PRG-EPHEMERAL-PARENT','EJECUCION_PERFIL_LF','IN_PROGRESS',
 'PERFIL','PERFIL-PRODUCT-DIRECTOR-LF',
 '{
  "read_only":true,"no_write":true,"no_promotion":true,
  "router_profile_handoff":{"router_authorization_receipt":{"profile_execution_allowed":true}},
  "screen_selection_result":{"selected_screen_code":"B2B-AUTH-001"}
 }'::jsonb,
 now(),'fixture_parent_request_not_live');

INSERT INTO public.lf_operation_execution_steps
  (execution_id,step_id,status,evidence_payload)
VALUES
 ('PRG-EPHEMERAL-PARENT','input_validate','STEP_PASS_WITH_EVIDENCE','{}'),
 ('PRG-EPHEMERAL-PARENT','output_validate','STEP_PASS_WITH_EVIDENCE',
  '{"output_contract_result":"PASS"}'),
 ('PRG-EPHEMERAL-PARENT','semantic_judge','STEP_PASS_WITH_EVIDENCE',
  '{"blocking_codes":[],"semantic_judge_result":{"verdict":"PASS_INDEPENDENT_SEMANTIC"}}'),
 ('PRG-EPHEMERAL-PARENT','execute_profile','STEP_PASS_WITH_EVIDENCE',
  '{"profile_output":{"worker":"product_director_lf","output_type":"PRODUCT_DIRECTION_SPEC",
    "self_verdict":"PASS",
    "deliverable_created":{
      "product_decision":{"proposed_by":"PRODUCER_FIXTURE_NOT_OWNER"},
      "governed_rule_patch":{
        "rule_code":"B2B-PRG-TEST-001",
        "change_kind":"CREATE",
        "changes":{"titulo":"Test isolated PG decision","descripcion":"Only test rejection, no production write"}
      }
    }
  }}');

DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
    <> '2d6f2592e8f7e002ab29f212bcca0663'
 THEN RAISE EXCEPTION 'PR_G_FIXTURE_FUNCTION_NOT_EXACT_SOURCE'; END IF;
 IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0
 THEN RAISE EXCEPTION 'PR_G_FIXTURE_OWNER_TABLE_DIRTY'; END IF;
 RAISE NOTICE 'PR_G_PREIMAGE_PASS source_function_md5=2d6f2592e8f7e002ab29f212bcca0663 decisions=0';
END
$pre$;

BEGIN;
@@PR_G_MIGRATION_SQL@@

DO $trial$
DECLARE
 v_source text;
 v_out jsonb;
 v_dec public.lf_ig_owner_decision_v2%ROWTYPE;
 v_expected text;
BEGIN
 IF md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
    <> 'e9bd839b8978a3f7872dd82a104ce99c'
 THEN RAISE EXCEPTION 'PR_G_POST_MIGRATION_FUNCTION_MD5_FAILED'; END IF;
 IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0
 THEN RAISE EXCEPTION 'PR_G_PRETRIAL_DECISION_COUNT_NOT_ZERO'; END IF;
 v_source:=encode(extensions.digest(convert_to(
  'LF_RULE_ABSENT:B2B-PRG-TEST-001','UTF8'),'sha256'),'hex');
 BEGIN
   PERFORM public.lf_ig_rule_owner_decide_v2(
     'PRG-EPHEMERAL-PARENT','B2B-PRG-TEST-001',v_source,
     '{"usuario":"OTRO_USUARIO","veredicto":"RECHAZAR"}'::jsonb);
   RAISE EXCEPTION 'PR_G_FOREIGN_USER_UNEXPECTEDLY_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'LF_IG_OWNER_DECISION_INPUT_INVALID%'
   THEN RAISE EXCEPTION 'PR_G_FOREIGN_USER_REJECTION_WRONG:%',SQLERRM; END IF;
 END;
 IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0
 THEN RAISE EXCEPTION 'PR_G_REJECTED_USER_WROTE_A_DECISION'; END IF;
 v_out:=public.lf_ig_rule_owner_decide_v2(
     'PRG-EPHEMERAL-PARENT','B2B-PRG-TEST-001',v_source,
     '{"usuario":"Cristhian Lujan","veredicto":"RECHAZAR"}'::jsonb);
 IF v_out->>'status'<>'RECHAZADO' OR v_out->>'write_performed'<>'false'
 THEN RAISE EXCEPTION 'PR_G_OWNER_TEST_RESPONSE_UNEXPECTED:%',v_out; END IF;
 SELECT * INTO v_dec FROM public.lf_ig_owner_decision_v2
 WHERE parent_execution_id='PRG-EPHEMERAL-PARENT';
 IF NOT FOUND OR v_dec.decisor<>'Cristhian Luján'
  OR v_dec.identity_mode<>'USERNAME_ONLY_UNVERIFIED'
  OR v_dec.verdict<>'RECHAZAR' OR v_dec.owner_sub<>'00000000-0000-4000-8000-000000000001'
  OR v_dec.proponente='Cristhian Luján'
 THEN RAISE EXCEPTION 'PR_G_OWNER_USERNAME_RECORD_INVALID'; END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(v_dec.decision_record))<>6
 OR v_dec.decision_record->>'decisor'<>'Cristhian Luján'
 OR v_dec.decision_record->>'codigo_regla'<>'B2B-PRG-TEST-001'
 OR v_dec.decision_record->>'veredicto'<>'RECHAZAR'
 OR v_dec.decision_record->>'frase_literal'<>'OWNER_USERNAME_ONLY_NO_SIGNED_PHRASE'
 THEN RAISE EXCEPTION 'PR_G_ARCHIVE_DOWNSTREAM_CONTRACT_DRIFT'; END IF;
 v_expected:=encode(extensions.digest(convert_to(v_dec.decision_record::text,'UTF8'),'sha256'),'hex');
 IF v_dec.decision_record_sha256 IS DISTINCT FROM v_expected
  OR v_dec.source_sha256 IS DISTINCT FROM v_source
  OR v_dec.proposal_sha256 IS NULL
 THEN RAISE EXCEPTION 'PR_G_SNAPSHOT_HASH_MISMATCH'; END IF;
 IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>1
 OR (SELECT count(*) FROM lf_ops.reglas)<>3
 THEN RAISE EXCEPTION 'PR_G_TEST_UNEXPECTED_INSERTS'; END IF;
 IF has_function_privilege('anon','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'PR_G_FUNCTION_PRIVILEGE_EXPOSED'; END IF;
 RAISE NOTICE 'PR_G_IN_TRANSACTION_PASS username_only=1 generated_sha=true real_postgresql=true foreign_user_denied=true rules_unchanged=3';
END
$trial$;

ROLLBACK;

DO $post$
DECLARE v_identity text;
BEGIN
 IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2)<>0 THEN
  RAISE EXCEPTION 'PR_G_ROLLBACK_DID_NOT_REMOVE_TEST_DECISION'; END IF;
 IF md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
 <> '2d6f2592e8f7e002ab29f212bcca0663'
 THEN RAISE EXCEPTION 'PR_G_ROLLBACK_FUNCTION_NOT_RESTORED'; END IF;
 SELECT pg_get_constraintdef(oid) INTO v_identity FROM pg_constraint
 WHERE conrelid='public.lf_ig_owner_decision_v2'::regclass
 AND conname='lf_ig_owner_decision_v2_identity_mode_check';
 IF md5(v_identity)<>'f2e2c80a1d8e7d85ac15b7238df02a2b'
 THEN RAISE EXCEPTION 'PR_G_ROLLBACK_CONSTRAINT_NOT_RESTORED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>3 OR
 (SELECT count(*) FROM lf_ops.reglas WHERE codigo='B2B-RULE-AUTH-020'
 AND valor_config->>'hold_hours'='48' AND valor_config->>'human_approval_count_required'='2')<>1
 THEN RAISE EXCEPTION 'PR_G_ROLLBACK_AUTH_SOURCE_CHANGED'; END IF;
 RAISE NOTICE 'PR_G_REAL_POST_ROLLBACK_PASS decisions=0 legacy_function_restored=true auth_rules=3';
END
$post$;
