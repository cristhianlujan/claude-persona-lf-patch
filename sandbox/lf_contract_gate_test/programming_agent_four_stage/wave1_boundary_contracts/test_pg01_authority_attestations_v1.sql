\set ON_ERROR_STOP on
-- Disposable PostgreSQL (superuser harness). Run from repository root. Never run on live DB.
-- PG-01 D-A/D-B: authenticated subject verification + reviewer attestation (synthetic logins).
BEGIN;
CREATE SCHEMA private; CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
\i sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/pg01_authority_programacion_fixture.sql
-- Minimal mirrors of the Supabase tables these guards read (column subsets, same names/types).
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY,context_payload jsonb NOT NULL,context_sha256 text NOT NULL,created_by_execution_id text NOT NULL);
CREATE TABLE private.lf_evidence_ledger_v1(receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),execution_id text,capability_code text,gate_code text,receipt_kind text,
 subject_type text,subject_ref text,subject_sha256 text,source_head_sha text,verification_state text,created_by_execution_id text);
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY,operation_code text,status text,manifest jsonb,created_by_execution_id text DEFAULT 'UNKNOWN');
CREATE TABLE public.lf_operation_execution_steps(execution_id text,step_id text,status text,evidence_payload jsonb,created_by_execution_id text DEFAULT 'UNKNOWN');
GRANT USAGE ON SCHEMA private TO service_role;
GRANT SELECT,INSERT,UPDATE ON public.lf_operation_execution, public.lf_operation_execution_steps TO service_role;
-- Load the REAL migration; its BEGIN/COMMIT are removed only for this disposable transaction.
CREATE TEMP TABLE src_lines(n bigint GENERATED ALWAYS AS IDENTITY,line text);
\copy src_lines(line) FROM 'supabase/migrations/20261029160000_lf_pg01_authority_attestations_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'\nBEGIN;\n',E'\n'),E'\nCOMMIT;',E'\n') FROM src_lines
\gexec
CREATE TEMP TABLE res(case_id text PRIMARY KEY, got text, expect text);
CREATE FUNCTION pg_temp.put(p_case text, p_got text, p_expect text) RETURNS void LANGUAGE sql AS $q$ INSERT INTO res VALUES(p_case,p_got,p_expect) $q$;
-- data: producer PROFILE, context C1 and C2, ledger receipts
INSERT INTO private.lf_decision_context_asof_v1 SELECT ('aaaaaaaa-0000-4000-8000-00000000000'||i)::uuid, p, encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex'),'PROFILE'
 FROM (SELECT i, jsonb_build_object('snapshot',i) p FROM generate_series(1,2) i) q;
INSERT INTO private.lf_evidence_ledger_v1(receipt_id,subject_type,subject_ref,subject_sha256,source_head_sha,verification_state,created_by_execution_id)
SELECT r,'PROGRAMMING_ANALYSIS_PACKAGE','PROGRAMMING_ANALYSIS_PACKAGE/'||c.context_id,sha,head,state,anchor FROM (VALUES
 ('11111111-0000-4000-8000-000000000001'::uuid,1,NULL::text,repeat('1',40),'VERIFIED','LEDGER-X'),
 ('11111111-0000-4000-8000-000000000002'::uuid,2,NULL,repeat('1',40),'VERIFIED','LEDGER-X'),
 ('11111111-0000-4000-8000-000000000003'::uuid,1,repeat('f',64),repeat('1',40),'VERIFIED','LEDGER-X'),
 ('11111111-0000-4000-8000-000000000004'::uuid,1,NULL,'not-a-head','VERIFIED','LEDGER-X'),
 ('11111111-0000-4000-8000-000000000005'::uuid,1,NULL,repeat('1',40),'VERIFIED','PROFILE')) v(r,i,sha0,head,state,anchor)
JOIN private.lf_decision_context_asof_v1 c ON c.context_id=('aaaaaaaa-0000-4000-8000-00000000000'||v.i)::uuid
CROSS JOIN LATERAL (SELECT coalesce(v.sha0,c.context_sha256) sha) s;
-- ===== D-B identity boundary =====
SELECT pg_temp.put('B1_service_role_insert_verification',pg_temp.as_service($s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:permission denied%');
SELECT pg_temp.put('B2_service_role_insert_review',pg_temp.as_service($s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J')$s$),'ERROR:permission denied%');
-- B3 (service_role cannot SET SESSION AUTHORIZATION) needs a non-superuser connection: see test_pg01_authority_session_boundary_v1.sql
SELECT pg_temp.put('B4_service_role_set_role_authority',pg_temp.as_service($s$SET ROLE programacion_verifier$s$),'ERROR:permission denied%');
SELECT pg_temp.put('B5_jwt_claims_spoof',pg_temp.as_service($s$SELECT set_config('request.jwt.claims','{"role":"programacion_verifier","sub":"lf_t_verifier_login"}',true); INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:permission denied%');
SELECT pg_temp.put('B6_control_plane_postgres_session',pg_temp.as_authority('postgres','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:shared/control-plane session principal%');
SELECT pg_temp.put('B7_inherit_login',pg_temp.as_authority('lf_t_inherit_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J')$s$),'ERROR:authority login % is not least-privilege%');
SELECT pg_temp.put('B8_dual_authority_login',pg_temp.as_authority('lf_t_dual_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:authority login % has cross-authority membership%');
SELECT pg_temp.put('B9_verifier_cannot_attest_review',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J')$s$),'ERROR:permission denied%');
SELECT pg_temp.put('B10_nologin_principal',pg_temp.as_authority('lf_t_nologin','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J')$s$),'ERROR:authority login % is not least-privilege%');
SELECT pg_temp.put('B11_forged_principal_columns',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id,session_principal) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001','someone_else')$s$),'ERROR:permission denied%');
-- ===== D-A verification (real readback) =====
SELECT pg_temp.put('A1_receipt_missing',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-0000000000ff','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:PG01_SUBJECT_VERIFY_RECEIPT_MISSING');
SELECT pg_temp.put('A2_readback_unavailable',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-0000000000ff')$s$),'ERROR:PG01_SUBJECT_VERIFY_READBACK_UNAVAILABLE');
SELECT pg_temp.put('A3_receipt_of_other_subject',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000002','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH');
SELECT pg_temp.put('A4_self_declared_verified_wrong_hash',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000003','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:PG01_SUBJECT_VERIFY_SUBJECT_MISMATCH');
SELECT pg_temp.put('A5_head_invalid',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000004','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:PG01_SUBJECT_VERIFY_HEAD_INVALID');
SELECT pg_temp.put('A6_anchored_by_producer',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000005','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:PG01_SUBJECT_VERIFY_ANCHORED_BY_PRODUCER');
SELECT pg_temp.put('A7_verify_ok',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001')$s$),'OK');
SELECT pg_temp.put('A8_replay_same_receipt',pg_temp.as_authority('lf_t_verifier2_login','programacion_verifier',$s$INSERT INTO private.lf_pg01_subject_verifications_v1(receipt_id,context_id) VALUES('11111111-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001')$s$),'ERROR:duplicate key%');
SELECT pg_temp.put('A9_stamped_principal',(SELECT session_principal||'/'||authority_role||'/'||resolver_id FROM private.lf_pg01_subject_verifications_v1 WHERE receipt_id='11111111-0000-4000-8000-000000000001'),'lf_t_verifier_login/programacion_verifier/LF_SUPABASE_READBACK_V1');
SELECT pg_temp.put('A10_update_blocked',pg_temp.as_authority('lf_t_verifier_login','programacion_verifier',$s$UPDATE private.lf_pg01_subject_verifications_v1 SET source_head_sha=repeat('2',40)$s$),'ERROR:permission denied%');
SELECT pg_temp.put('A11_owner_update_append_only',(SELECT CASE WHEN true THEN pg_temp.as_role('postgres',$s$UPDATE private.lf_pg01_subject_verifications_v1 SET source_head_sha=repeat('2',40)$s$) END),'ERROR:PG01_ATTESTATION_APPEND_ONLY');
-- ===== D-B review attestation =====
INSERT INTO public.lf_operation_execution VALUES
 ('J1','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','COMPLETED',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','subject_type','PROGRAMMING_ANALYSIS_PACKAGE',
  'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/aaaaaaaa-0000-4000-8000-000000000001','subject_sha256',(SELECT context_sha256 FROM private.lf_decision_context_asof_v1 WHERE context_id='aaaaaaaa-0000-4000-8000-000000000001'),
  'source_head_sha',repeat('1',40),'subject_receipt_id','11111111-0000-4000-8000-000000000001','producer_execution_id','PROFILE'),'ORCH'),
 ('J2','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','IN_PROGRESS','{}','ORCH');
UPDATE public.lf_operation_execution SET manifest=(SELECT manifest FROM public.lf_operation_execution WHERE execution_id='J1') WHERE execution_id='J2';
INSERT INTO public.lf_operation_execution VALUES('J3','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','COMPLETED',
 (SELECT manifest||jsonb_build_object('subject_receipt_id','11111111-0000-4000-8000-000000000002') FROM public.lf_operation_execution WHERE execution_id='J1'),'ORCH');
INSERT INTO public.lf_operation_execution VALUES('J4','REVISION_INDEPENDIENTE_ESTRATEGIA_LF','COMPLETED',
 (SELECT manifest||jsonb_build_object('source_head_sha',repeat('9',40)) FROM public.lf_operation_execution WHERE execution_id='J1'),'ORCH');
INSERT INTO public.lf_operation_execution_steps VALUES('J1','semantic_review','STEP_PASS_WITH_EVIDENCE','{"verdict":"PASS"}','J1'),('J1','judge_record','STEP_PASS_WITH_EVIDENCE','{}','J1');
SELECT pg_temp.put('R1_judge_not_completed',pg_temp.as_authority('lf_t_auditor_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J2')$s$),'ERROR:PG01_REVIEW_ATTEST_JUDGE_INVALID');
SELECT pg_temp.put('R2_subject_not_verified',pg_temp.as_authority('lf_t_auditor_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J3')$s$),'ERROR:PG01_REVIEW_ATTEST_SUBJECT_NOT_VERIFIED');
SELECT pg_temp.put('R3_wrong_head',pg_temp.as_authority('lf_t_auditor_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J4')$s$),'ERROR:PG01_REVIEW_ATTEST_SUBJECT_NOT_VERIFIED');
SELECT pg_temp.put('R4_unknown_judge',pg_temp.as_authority('lf_t_auditor_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('NOPE')$s$),'ERROR:PG01_REVIEW_ATTEST_JUDGE_INVALID');
SELECT pg_temp.put('R5_attest_ok',pg_temp.as_authority('lf_t_auditor_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J1')$s$),'OK');
SELECT pg_temp.put('R6_replay_second_attestation',pg_temp.as_authority('lf_t_auditor2_login','programacion_auditor',$s$INSERT INTO private.lf_pg01_review_attestations_v1(judge_execution_id) VALUES('J1')$s$),'ERROR:duplicate key%');
SELECT pg_temp.put('R7_attestation_binds_digest',(SELECT (a.manifest_sha256=private.fn_lf_pg01_judge_digest_v1('J1')->>'manifest_sha256' AND a.steps_sha256=private.fn_lf_pg01_judge_digest_v1('J1')->>'steps_sha256'
  AND a.session_principal='lf_t_auditor_login' AND a.verifier_session_principal='lf_t_verifier_login' AND a.producer_execution_id='PROFILE')::text FROM private.lf_pg01_review_attestations_v1 a WHERE a.judge_execution_id='J1'),'true');
SELECT set_config('t.r8',pg_temp.as_service($s$UPDATE public.lf_operation_execution_steps SET evidence_payload='{"verdict":"PASS","x":1}' WHERE execution_id='J1' AND step_id='judge_record'$s$),false);
SELECT pg_temp.put('R8_post_attest_tamper_changes_digest',current_setting('t.r8')||'/'||
  (SELECT (a.steps_sha256=private.fn_lf_pg01_judge_digest_v1('J1')->>'steps_sha256')::text FROM private.lf_pg01_review_attestations_v1 a WHERE a.judge_execution_id='J1'),'OK/false');
SELECT pg_temp.put('R9_service_role_cannot_read_attestations',pg_temp.as_service($s$SELECT 1 FROM private.lf_pg01_review_attestations_v1$s$),'ERROR:permission denied%');
-- ===== assertions =====
DO $a$ DECLARE r record; bad text[]:='{}'; n int:=0; BEGIN
 FOR r IN SELECT * FROM res ORDER BY case_id LOOP
  IF r.got LIKE r.expect THEN n:=n+1; ELSE bad:=bad||(r.case_id||' got='||coalesce(r.got,'NULL')||' expect='||r.expect); END IF; END LOOP;
 IF cardinality(bad)>0 THEN RAISE EXCEPTION 'TEST_FAIL:ATTEST passed=% failed=% :: %',n,cardinality(bad),array_to_string(bad,' | '); END IF;
 RAISE NOTICE 'PG01_AUTHORITY_ATTESTATION_TESTS_PASSED:%',n; END $a$;
ROLLBACK;
