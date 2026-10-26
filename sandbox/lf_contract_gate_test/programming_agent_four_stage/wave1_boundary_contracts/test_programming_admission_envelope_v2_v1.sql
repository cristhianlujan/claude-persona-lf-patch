\set ON_ERROR_STOP on
-- Point 4 tests: the REAL D7 ledger (20261026173901) plus the V2 resolver migration,
-- both loaded from their files, with receipts written through the REAL D7 writer.
-- Disposable PostgreSQL only; run from repo root; everything is rolled back.
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF;
END $r$;
GRANT USAGE ON SCHEMA private, extensions TO service_role, supabase_read_only_user;
-- Minimal prerequisites required by the D7 migration prechecks.
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY, context_sha256 text NOT NULL);
CREATE TABLE public.lf_operation_execution(
  execution_id text PRIMARY KEY, operation_code text NOT NULL, target_type text NOT NULL,
  target_code text NOT NULL, target_repo text, target_path text, status text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
  manifest jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), created_by_execution_id text NOT NULL DEFAULT 'TEST',
  updated_by_execution_id text, idempotency_key text, request_sha256 text, lease_owner text,
  lease_expires_at timestamptz, lease_fence bigint NOT NULL DEFAULT 0,
  checkpoint_seq bigint NOT NULL DEFAULT 0, checkpoint_payload jsonb NOT NULL DEFAULT '{}');
CREATE TABLE public.lf_operation_execution_steps(
  execution_id text NOT NULL, step_order integer NOT NULL DEFAULT 1, step_id text NOT NULL,
  status text NOT NULL, evidence_ref text, evidence_payload jsonb NOT NULL DEFAULT '{}',
  observed_at timestamptz NOT NULL DEFAULT now(), notes text,
  created_by_execution_id text NOT NULL DEFAULT 'TEST', created_at timestamptz NOT NULL DEFAULT now(),
  updated_by_execution_id text, updated_at timestamptz);

-- Load both migrations from disk; strip only the outer BEGIN/COMMIT so this test owns the rollback.
CREATE TEMP TABLE src_lines(n bigint GENERATED ALWAYS AS IDENTITY, line text);
\copy src_lines(line) FROM 'supabase/migrations/20261026173901_lf_programming_context_handoff_receipt_ledger_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM src_lines
\gexec
TRUNCATE src_lines;
\copy src_lines(line) FROM 'supabase/migrations/20261027091000_lf_programming_admission_envelope_v2_resolver_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM src_lines
\gexec

CREATE TEMP TABLE results(case_id text PRIMARY KEY);

-- 01. Restricted role first (PL/pgSQL does not re-check EXECUTE after a role change).
DO $t$ DECLARE denied boolean := false; BEGIN
  PERFORM set_config('role','service_role',true);
  BEGIN
    PERFORM private.fn_lf_programming_context_handoff_receipt_resolve_v2('{}'::jsonb);
  EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  PERFORM set_config('role','none',true);
  IF denied IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:01_service_role_can_execute'; END IF;
  INSERT INTO results VALUES ('01');
END $t$;

-- Fixtures -------------------------------------------------------------------
CREATE FUNCTION pg_temp.c1() RETURNS uuid LANGUAGE sql AS $q$ SELECT 'aaaaaaaa-0000-4000-8000-000000000001'::uuid $q$;
CREATE FUNCTION pg_temp.c2() RETURNS uuid LANGUAGE sql AS $q$ SELECT 'aaaaaaaa-0000-4000-8000-000000000002'::uuid $q$;
CREATE FUNCTION pg_temp.sha(p uuid) RETURNS text LANGUAGE sql AS $q$
  SELECT encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex') $q$;
CREATE FUNCTION pg_temp.digest() RETURNS text LANGUAGE sql AS $q$
  SELECT 'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8' $q$;
INSERT INTO private.lf_decision_context_asof_v1 VALUES (pg_temp.c1(), pg_temp.sha(pg_temp.c1())), (pg_temp.c2(), pg_temp.sha(pg_temp.c2()));
INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest)
VALUES ('EXEC-TRAIN-TEST','ACTUALIZACION_DB_LF','MIGRATION','test','IN_PROGRESS','{"producer":"lf-migration-merge-train"}');

CREATE FUNCTION pg_temp.binding(p_ctx uuid, p_target text, p_scopes jsonb DEFAULT '["S1"]') RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('context_id',p_ctx::text,'context_sha256',pg_temp.sha(p_ctx),'target_ref',p_target,
    'requested_scope_ids',p_scopes,'producer_execution_ref','EXEC-PRODUCER','entry_contract_digest_sha256',pg_temp.digest()) $q$;
CREATE FUNCTION pg_temp.receipt(p_ctx uuid, p_verdict text DEFAULT 'ACCEPT') RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('schema_version','PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1','context_id',p_ctx::text,
    'context_sha256',pg_temp.sha(p_ctx),'snapshot_schema_digest_sha256',repeat('1',64),
    'receiver_schema_digest_sha256',pg_temp.digest(),'material_projection_sha256',repeat('2',64),
    'validated_material_paths',jsonb_build_array('requirements'),'verdict',p_verdict) $q$;
CREATE FUNCTION pg_temp.judge(p_id text, p_ctx uuid, p_op text DEFAULT 'REVISION_INDEPENDIENTE_ESTRATEGIA_LF',
  p_status text DEFAULT 'COMPLETED', p_subject text DEFAULT NULL, p_review text DEFAULT 'PASS') RETURNS void LANGUAGE sql AS $q$
  INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest)
  VALUES (p_id,p_op,'PROGRAMMING_ANALYSIS_PACKAGE','A9',p_status,jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE',
    'subject_sha256',coalesce(p_subject,pg_temp.sha(p_ctx)),'subject_ref','PROGRAMMING_ANALYSIS_PACKAGE/'||p_ctx::text));
  INSERT INTO public.lf_operation_execution_steps(execution_id,step_order,step_id,status,evidence_payload) VALUES
    (p_id,3,'semantic_review',CASE WHEN p_review='PASS' THEN 'STEP_PASS_WITH_EVIDENCE' ELSE 'STEP_FAIL' END,jsonb_build_object('verdict',p_review)),
    (p_id,4,'judge_record','STEP_PASS_WITH_EVIDENCE','{}');
$q$;
CREATE FUNCTION pg_temp.env(p_ctx uuid, p_judge text, p_over jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('schema_version','PROGRAMMING_ADMISSION_ENVELOPE_V2','entry_contract_digest_sha256',pg_temp.digest(),
    'context_id',p_ctx::text,'context_sha256',pg_temp.sha(p_ctx),
    'judge',jsonb_build_object('capability_code','INDEPENDENT_ASSURANCE','capability_version','2.0.1','execution_id',p_judge,'subject_sha256',pg_temp.sha(p_ctx)),
    'admitted_scope_ids',jsonb_build_array('S1','S2'),
    'valid_from',to_char((now()-interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'valid_until',to_char((now()+interval '1 hour') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'definition_refs',jsonb_build_array(jsonb_build_object('definition_ref','product://B2B-AUTH-001','definition_sha256',repeat('3',64))),
    'issued_by_execution_id','EXEC-ISSUER') || p_over $q$;
-- Write one receipt through the REAL writer; target_ref makes each binding unique.
CREATE FUNCTION pg_temp.put(p_target text, p_env jsonb, p_ctx uuid DEFAULT NULL, p_verdict text DEFAULT 'ACCEPT') RETURNS jsonb LANGUAGE sql AS $q$
  SELECT private.fn_lf_programming_context_handoff_receipt_record_v1(
    pg_temp.receipt(coalesce(p_ctx,pg_temp.c1()),p_verdict), p_env, pg_temp.binding(coalesce(p_ctx,pg_temp.c1()),p_target), 'EXEC-TRAIN-TEST') $q$;
CREATE FUNCTION pg_temp.v2(p_target text, p_ctx uuid DEFAULT NULL, p_scopes jsonb DEFAULT '["S1"]') RETURNS jsonb LANGUAGE sql AS $q$
  SELECT private.fn_lf_programming_context_handoff_receipt_resolve_v2(pg_temp.binding(coalesce(p_ctx,pg_temp.c1()),p_target,p_scopes)) $q$;
CREATE FUNCTION pg_temp.expect(p_case text, p_r jsonb, p_reason text, p_admissible boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $q$
BEGIN
  IF p_r->>'reason' IS DISTINCT FROM p_reason OR (p_r->>'admissible')::boolean IS DISTINCT FROM p_admissible THEN
    RAISE EXCEPTION 'TEST_FAIL:% expected % admissible=% got %', p_case, p_reason, p_admissible, p_r;
  END IF;
END $q$;

SELECT pg_temp.judge('EXEC-JUDGE-OK', pg_temp.c1());
SELECT pg_temp.judge('EXEC-JUDGE-OK2', pg_temp.c2());

-- 02. Missing receipt: reason preserved, found=false, only the receipt check evaluated.
DO $t$ DECLARE r jsonb; BEGIN
  r := pg_temp.v2('NOT-WRITTEN');
  PERFORM pg_temp.expect('02_missing', r, 'PG01_V2_RECEIPT_NOT_FOUND');
  IF (r->>'found')::boolean IS DISTINCT FROM false OR jsonb_array_length(r->'checks') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST_FAIL:02_missing_shape %', r; END IF;
  INSERT INTO results VALUES ('02');
END $t$;

-- 03. Complete, valid envelope with the provider closed: never admissible.
DO $t$ BEGIN
  PERFORM pg_temp.put('T-OK', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK'));
  PERFORM pg_temp.expect('03_closed_provider', pg_temp.v2('T-OK'), 'PG01_V2_DEFINITION_CURRENTNESS_NOT_VERIFIED');
  INSERT INTO results VALUES ('03');
END $t$;

-- Replace the provider INSIDE THIS TEST ONLY to reach the remaining branches.
CREATE OR REPLACE FUNCTION private.fn_lf_programming_definition_currentness_v1(p_definition_refs jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $q$ SELECT '{"verified":true,"reason":"TEST_ONLY"}'::jsonb $q$;

-- 04. Everything valid -> admissible; resolve_v1 on the same row stays closed (V2 adds, V1 unchanged).
DO $t$ DECLARE r jsonb; BEGIN
  r := pg_temp.v2('T-OK');
  PERFORM pg_temp.expect('04_admitted', r, 'PG01_V2_ADMITTED', true);
  IF (r->>'hashes_verified')::boolean IS DISTINCT FROM true OR r @> '{"checks":[{"pass":false}]}' THEN
    RAISE EXCEPTION 'TEST_FAIL:04_checks %', r; END IF;
  INSERT INTO results VALUES ('04');
END $t$;
DO $t$ DECLARE r jsonb; BEGIN
  r := private.fn_lf_programming_context_handoff_receipt_resolve_v1(pg_temp.binding(pg_temp.c1(),'T-OK'));
  IF (r->>'admissible')::boolean IS DISTINCT FROM false THEN RAISE EXCEPTION 'TEST_FAIL:05_v1_changed %', r; END IF;
  INSERT INTO results VALUES ('05');
END $t$;

-- 06. Receipt verdict BLOCK.
DO $t$ BEGIN
  PERFORM pg_temp.put('T-BLOCK', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK'), NULL, 'BLOCK');
  PERFORM pg_temp.expect('06_block', pg_temp.v2('T-BLOCK'), 'PG01_V2_RECEIPT_NOT_ACCEPT');
  INSERT INTO results VALUES ('06');
END $t$;

-- 07. Envelope shape: wrong schema, extra key, missing key, bad judge capability, empty scopes, bad definition sha.
DO $t$ DECLARE e jsonb := pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK'); BEGIN
  PERFORM pg_temp.put('T-SCHEMA', e || '{"schema_version":"PROGRAMMING_ADMISSION_ENVELOPE_V1"}');
  PERFORM pg_temp.expect('07_schema', pg_temp.v2('T-SCHEMA'), 'PG01_V2_ENVELOPE_INVALID');
  PERFORM pg_temp.put('T-EXTRA', e || '{"extra":1}');
  PERFORM pg_temp.expect('07_extra', pg_temp.v2('T-EXTRA'), 'PG01_V2_ENVELOPE_INVALID');
  PERFORM pg_temp.put('T-MISSING', e - 'issued_by_execution_id');
  PERFORM pg_temp.expect('07_missing', pg_temp.v2('T-MISSING'), 'PG01_V2_ENVELOPE_INVALID');
  PERFORM pg_temp.put('T-CAP', jsonb_set(e,'{judge,capability_version}','"2.0.0"'));
  PERFORM pg_temp.expect('07_capability', pg_temp.v2('T-CAP'), 'PG01_V2_ENVELOPE_INVALID');
  PERFORM pg_temp.put('T-NOSCOPES', e || '{"admitted_scope_ids":[]}');
  PERFORM pg_temp.expect('07_empty_scopes', pg_temp.v2('T-NOSCOPES'), 'PG01_V2_ENVELOPE_INVALID');
  PERFORM pg_temp.put('T-DEFSHA', e || jsonb_build_object('definition_refs',jsonb_build_array(jsonb_build_object('definition_ref','x','definition_sha256','abc'))));
  PERFORM pg_temp.expect('07_definition_sha', pg_temp.v2('T-DEFSHA'), 'PG01_V2_ENVELOPE_INVALID');
  INSERT INTO results VALUES ('07');
END $t$;

-- 08. Context / contract mismatch (envelope points to another context).
DO $t$ BEGIN
  PERFORM pg_temp.put('T-CTX', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK') || jsonb_build_object('context_sha256',pg_temp.sha(pg_temp.c2())));
  PERFORM pg_temp.expect('08_context', pg_temp.v2('T-CTX'), 'PG01_V2_CONTEXT_OR_CONTRACT_MISMATCH');
  INSERT INTO results VALUES ('08');
END $t$;

-- 09. Judge: missing, not completed, wrong operation, other subject, semantic review FAIL, judge for another package.
DO $t$ BEGIN
  PERFORM pg_temp.judge('EXEC-JUDGE-RUNNING', pg_temp.c1(), p_status => 'IN_PROGRESS');
  PERFORM pg_temp.judge('EXEC-JUDGE-OTHEROP', pg_temp.c1(), p_op => 'EJECUCION_PERFIL_LF');
  PERFORM pg_temp.judge('EXEC-JUDGE-OTHERSUBJ', pg_temp.c1(), p_subject => repeat('9',64));
  PERFORM pg_temp.judge('EXEC-JUDGE-FAIL', pg_temp.c1(), p_review => 'FAIL');
  PERFORM pg_temp.put('T-J-NONE', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-DOES-NOT-EXIST'));
  PERFORM pg_temp.expect('09_judge_missing', pg_temp.v2('T-J-NONE'), 'PG01_V2_JUDGE_INVALID');
  PERFORM pg_temp.put('T-J-RUN', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-RUNNING'));
  PERFORM pg_temp.expect('09_judge_running', pg_temp.v2('T-J-RUN'), 'PG01_V2_JUDGE_INVALID');
  PERFORM pg_temp.put('T-J-OP', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OTHEROP'));
  PERFORM pg_temp.expect('09_judge_operation', pg_temp.v2('T-J-OP'), 'PG01_V2_JUDGE_INVALID');
  PERFORM pg_temp.put('T-J-SUBJ', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OTHERSUBJ'));
  PERFORM pg_temp.expect('09_judge_subject', pg_temp.v2('T-J-SUBJ'), 'PG01_V2_JUDGE_INVALID');
  PERFORM pg_temp.put('T-J-FAIL', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-FAIL'));
  PERFORM pg_temp.expect('09_judge_review_fail', pg_temp.v2('T-J-FAIL'), 'PG01_V2_JUDGE_STEPS_INVALID');
  PERFORM pg_temp.put('T-J-OTHERPKG', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK2'));
  PERFORM pg_temp.expect('09_judge_other_package', pg_temp.v2('T-J-OTHERPKG'), 'PG01_V2_JUDGE_INVALID');
  INSERT INTO results VALUES ('09');
END $t$;

-- 10. Requested scope outside the admitted ones.
DO $t$ BEGIN
  PERFORM pg_temp.put('T-SCOPE', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK') || '{"admitted_scope_ids":["S2"]}');
  PERFORM pg_temp.expect('10_scope', pg_temp.v2('T-SCOPE'), 'PG01_V2_SCOPE_NOT_ADMITTED');
  INSERT INTO results VALUES ('10');
END $t$;

-- 11. Validity: not yet valid, expired, window over 24 h, malformed timestamp.
DO $t$ DECLARE e jsonb := pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK');
  f text := 'YYYY-MM-DD"T"HH24:MI:SS"Z"'; BEGIN
  PERFORM pg_temp.put('T-FUTURE', e || jsonb_build_object('valid_from',to_char((now()+interval '1 hour') at time zone 'UTC',f),
                                                          'valid_until',to_char((now()+interval '2 hour') at time zone 'UTC',f)));
  PERFORM pg_temp.expect('11_not_yet', pg_temp.v2('T-FUTURE'), 'PG01_V2_NOT_YET_VALID');
  PERFORM pg_temp.put('T-EXPIRED', e || jsonb_build_object('valid_from',to_char((now()-interval '3 hour') at time zone 'UTC',f),
                                                           'valid_until',to_char((now()-interval '1 hour') at time zone 'UTC',f)));
  PERFORM pg_temp.expect('11_expired', pg_temp.v2('T-EXPIRED'), 'PG01_V2_EXPIRED');
  PERFORM pg_temp.put('T-LONG', e || jsonb_build_object('valid_from',to_char((now()-interval '1 hour') at time zone 'UTC',f),
                                                        'valid_until',to_char((now()+interval '30 hour') at time zone 'UTC',f)));
  PERFORM pg_temp.expect('11_window', pg_temp.v2('T-LONG'), 'PG01_V2_VALIDITY_INVALID');
  PERFORM pg_temp.put('T-BADTS', e || '{"valid_from":"2026-13-45T99:00:00Z"}');
  PERFORM pg_temp.expect('11_bad_timestamp', pg_temp.v2('T-BADTS'), 'PG01_V2_VALIDITY_INVALID');
  INSERT INTO results VALUES ('11');
END $t$;

-- 12. Revocations: by binding key (only that binding) and by context (every binding of that context).
DO $t$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.put('T-REV-B', pg_temp.env(pg_temp.c1(),'EXEC-JUDGE-OK'));
  r := pg_temp.v2('T-REV-B');
  INSERT INTO private.lf_programming_admission_revocations_v1(binding_key_sha256,reason_code,revoked_by_execution_id)
  VALUES (r#>>'{record,binding_key_sha256}','TEST_REVOKE','EXEC-REVOKER');
  PERFORM pg_temp.expect('12_revoked_binding', pg_temp.v2('T-REV-B'), 'PG01_V2_REVOKED');
  PERFORM pg_temp.expect('12_other_binding_unaffected', pg_temp.v2('T-OK'), 'PG01_V2_ADMITTED', true);
  PERFORM pg_temp.put('T-REV-C1', pg_temp.env(pg_temp.c2(),'EXEC-JUDGE-OK2'), pg_temp.c2());
  PERFORM pg_temp.put('T-REV-C2', pg_temp.env(pg_temp.c2(),'EXEC-JUDGE-OK2'), pg_temp.c2());
  PERFORM pg_temp.expect('12_before_context_revoke', pg_temp.v2('T-REV-C1', pg_temp.c2()), 'PG01_V2_ADMITTED', true);
  INSERT INTO private.lf_programming_admission_revocations_v1(context_id,reason_code,revoked_by_execution_id)
  VALUES (pg_temp.c2(),'TEST_REVOKE','EXEC-REVOKER');
  PERFORM pg_temp.expect('12_revoked_context_1', pg_temp.v2('T-REV-C1', pg_temp.c2()), 'PG01_V2_REVOKED');
  PERFORM pg_temp.expect('12_revoked_context_2', pg_temp.v2('T-REV-C2', pg_temp.c2()), 'PG01_V2_REVOKED');
  INSERT INTO results VALUES ('12');
END $t$;

-- 13. Revocations are append-only, and need exactly one target.
DO $t$ DECLARE blocked boolean; BEGIN
  blocked := false;
  BEGIN UPDATE private.lf_programming_admission_revocations_v1 SET reason_code='X';
  EXCEPTION WHEN OTHERS THEN blocked := SQLERRM LIKE 'PROGRAMACION_V2_REVOCATION_APPEND_ONLY:%'; END;
  IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:13_update'; END IF;
  blocked := false;
  BEGIN DELETE FROM private.lf_programming_admission_revocations_v1;
  EXCEPTION WHEN OTHERS THEN blocked := SQLERRM LIKE 'PROGRAMACION_V2_REVOCATION_APPEND_ONLY:%'; END;
  IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:13_delete'; END IF;
  blocked := false;
  BEGIN INSERT INTO private.lf_programming_admission_revocations_v1(binding_key_sha256,context_id,reason_code,revoked_by_execution_id)
        VALUES (repeat('a',64),pg_temp.c1(),'X','E');
  EXCEPTION WHEN check_violation THEN blocked := true; END;
  IF blocked IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAIL:13_two_targets'; END IF;
  INSERT INTO results VALUES ('13');
END $t$;

-- 14. No privilege leaks on the new objects.
DO $t$ BEGIN
  IF has_table_privilege('service_role','private.lf_programming_admission_revocations_v1','SELECT')
     OR has_table_privilege('supabase_read_only_user','private.lf_programming_admission_revocations_v1','INSERT')
     OR has_function_privilege('anon','private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)','EXECUTE')
     OR has_function_privilege('authenticated','private.fn_lf_programming_definition_currentness_v1(jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'TEST_FAIL:14_privileges'; END IF;
  INSERT INTO results VALUES ('14');
END $t$;

DO $t$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM results;
  IF n IS DISTINCT FROM 14 THEN RAISE EXCEPTION 'TEST_FAIL:COUNT_%', n; END IF;
  RAISE NOTICE 'PROGRAMMING_ADMISSION_ENVELOPE_V2_TESTS_PASSED:%', n;
END $t$;
ROLLBACK;
