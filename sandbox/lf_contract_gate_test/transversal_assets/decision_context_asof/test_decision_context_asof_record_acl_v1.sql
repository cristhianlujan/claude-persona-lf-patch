-- Local, disposable test for 20261027180000_lf_decision_context_asof_record_acl_v1.sql.
-- Run only against a throwaway PostgreSQL (17 is the target). Everything runs in one
-- transaction and ends with ROLLBACK, including roles and default privileges.
--
--   psql -X -v ON_ERROR_STOP=1 -f test_decision_context_asof_record_acl_v1.sql
--
-- The writer body below is the hosted definition read on 2026-10-27 with
-- pg_get_functiondef (prosrc md5 b2b107a86eb8fea55a11ab8f620d9694). The capability
-- tables and the payload validator are minimal stubs; nothing here is hosted evidence.

\set ON_ERROR_STOP 1
BEGIN;

-- Supabase-like roles and default privileges (rolled back at the end).
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $r$;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS private;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA private TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Stubs for the capability registry and the payload validator.
CREATE TABLE public.lf_capability_current(capability_code text PRIMARY KEY, version text, manifest_sha256 text);
CREATE TABLE public.lf_capability_version_registry(capability_code text, version text, manifest_sha256 text, manifest jsonb);
INSERT INTO public.lf_capability_current VALUES
 ('DECISION_CONTEXT_ASOF','1.0.0','28b95beda0dc45e28c1c3e917dd105c7d7974f5f26fee50c0c2636229d425388'),
 ('CURRENTNESS_AUTHORITY','1.0.0','9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'),
 ('CAPABILITY_VERSION_COMPATIBILITY','1.0.0','f2894a7f433ccd1c92f6f1bd4783c3e27b7f9b94ab28b4ab08b6732c92259bf1'),
 ('TYPED_EVIDENCE_REGISTRY','3.0.0','0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da');
INSERT INTO public.lf_capability_version_registry VALUES
 ('DECISION_CONTEXT_ASOF','1.0.0','28b95beda0dc45e28c1c3e917dd105c7d7974f5f26fee50c0c2636229d425388',
  '{"dependencies":{
    "CURRENTNESS_AUTHORITY":{"version":"1.0.0","manifest_sha256":"9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09"},
    "CAPABILITY_VERSION_COMPATIBILITY":{"version":"1.0.0","manifest_sha256":"f2894a7f433ccd1c92f6f1bd4783c3e27b7f9b94ab28b4ab08b6732c92259bf1"},
    "TYPED_EVIDENCE_REGISTRY":{"version":"3.0.0","manifest_sha256":"0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da"}}}');
CREATE FUNCTION private.fn_lf_decision_context_asof_payload_valid_v1(p jsonb) RETURNS boolean
  LANGUAGE sql IMMUTABLE AS $$ SELECT p ? 'decision_ref' $$;

CREATE TABLE private.lf_decision_context_asof_v1(
  context_id uuid NOT NULL DEFAULT extensions.gen_random_uuid() PRIMARY KEY,
  decision_ref text NOT NULL UNIQUE,
  consumer_code text NOT NULL,
  subject_ref text NOT NULL,
  subject_version text NOT NULL,
  decided_at timestamptz NOT NULL,
  effective_at timestamptz NOT NULL,
  context_payload jsonb NOT NULL,
  context_sha256 text NOT NULL UNIQUE CHECK (context_sha256 ~ '^[0-9a-f]{64}$'),
  created_by_execution_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE private.lf_decision_context_asof_v1 ENABLE ROW LEVEL SECURITY;

-- Hosted writer definition (verbatim body).
CREATE OR REPLACE FUNCTION public.fn_lf_decision_context_asof_record_v1(p_context jsonb, p_actor_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
DECLARE
  v_manifest jsonb; v_code text; v_expected_version text; v_expected_sha text; v_live_version text; v_live_sha text;
  v_ref_version text; v_ref_sha text; v_count integer; v_digest text;
  v_existing private.lf_decision_context_asof_v1%rowtype; v_row private.lf_decision_context_asof_v1%rowtype;
BEGIN
  IF nullif(btrim(coalesce(p_actor_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','ACTOR_EXECUTION_ID_MISSING');
  END IF;
  SELECT vr.manifest INTO v_manifest
  FROM public.lf_capability_current c
  JOIN public.lf_capability_version_registry vr
    ON vr.capability_code=c.capability_code AND vr.version=c.version AND vr.manifest_sha256=c.manifest_sha256
  WHERE c.capability_code='DECISION_CONTEXT_ASOF';
  IF NOT FOUND THEN RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','CAPABILITY_NOT_CURRENT'); END IF;
  IF private.fn_lf_decision_context_asof_payload_valid_v1(p_context) IS NOT TRUE THEN
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','CONTEXT_SCHEMA_INVALID');
  END IF;
  FOREACH v_code IN ARRAY ARRAY['CURRENTNESS_AUTHORITY','CAPABILITY_VERSION_COMPATIBILITY','TYPED_EVIDENCE_REGISTRY'] LOOP
    v_expected_version:=v_manifest#>>ARRAY['dependencies',v_code,'version'];
    v_expected_sha:=v_manifest#>>ARRAY['dependencies',v_code,'manifest_sha256'];
    SELECT version,manifest_sha256 INTO v_live_version,v_live_sha FROM public.lf_capability_current WHERE capability_code=v_code;
    SELECT count(*),min(e->>'version'),min(e->>'manifest_sha256') INTO v_count,v_ref_version,v_ref_sha
    FROM jsonb_array_elements(p_context->'authority_refs') e WHERE e->>'capability_code'=v_code;
    IF v_count<>1 OR v_live_version IS DISTINCT FROM v_expected_version OR v_live_sha IS DISTINCT FROM v_expected_sha
       OR v_ref_version IS DISTINCT FROM v_live_version OR v_ref_sha IS DISTINCT FROM v_live_sha THEN
      RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','DEPENDENCY_CURRENTNESS_OR_REFERENCE_DRIFT','dependency',v_code,'expected_version',v_expected_version,'live_version',v_live_version,'expected_manifest_sha256',v_expected_sha,'live_manifest_sha256',v_live_sha,'referenced_version',v_ref_version,'referenced_manifest_sha256',v_ref_sha);
    END IF;
  END LOOP;
  v_digest:=encode(extensions.digest(convert_to(p_context::text,'UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing FROM private.lf_decision_context_asof_v1 WHERE decision_ref=p_context->>'decision_ref';
  IF FOUND THEN
    IF v_existing.context_sha256 IS DISTINCT FROM v_digest THEN
      RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','BLOCKED','code','DECISION_REF_REPLAY_CONFLICT','decision_ref',p_context->>'decision_ref','existing_context_sha256',v_existing.context_sha256,'candidate_context_sha256',v_digest);
    END IF;
    RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','RECORDED','code','IDEMPOTENT_REPLAY','context_id',v_existing.context_id,'decision_ref',v_existing.decision_ref,'consumer_code',v_existing.consumer_code,'subject_ref',v_existing.subject_ref,'subject_version',v_existing.subject_version,'context_sha256',v_existing.context_sha256,'decided_at',v_existing.decided_at,'effective_at',v_existing.effective_at);
  END IF;
  INSERT INTO private.lf_decision_context_asof_v1(decision_ref,consumer_code,subject_ref,subject_version,decided_at,effective_at,context_payload,context_sha256,created_by_execution_id)
  VALUES (p_context->>'decision_ref',p_context->>'consumer_code',p_context#>>'{subject,ref}',p_context#>>'{subject,version}',(p_context#>>'{times,decided_at}')::timestamptz,(p_context#>>'{times,effective_at}')::timestamptz,p_context,v_digest,p_actor_execution_id)
  RETURNING * INTO v_row;
  RETURN jsonb_build_object('schema_version','LF_DECISION_CONTEXT_ASOF_RECEIPT_V1','state','RECORDED','code','NEW_CONTEXT','context_id',v_row.context_id,'decision_ref',v_row.decision_ref,'consumer_code',v_row.consumer_code,'subject_ref',v_row.subject_ref,'subject_version',v_row.subject_version,'context_sha256',v_row.context_sha256,'decided_at',v_row.decided_at,'effective_at',v_row.effective_at);
END $function$;

CREATE FUNCTION pg_temp.ctx(p_ref text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('decision_ref',p_ref,'consumer_code','TEST','subject',jsonb_build_object('ref','S','version','1'),
    'times',jsonb_build_object('decided_at','2026-10-27T00:00:00Z','effective_at','2026-10-27T00:00:00Z'),
    'authority_refs',jsonb_build_array(
      jsonb_build_object('capability_code','CURRENTNESS_AUTHORITY','version','1.0.0','manifest_sha256','9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'),
      jsonb_build_object('capability_code','CAPABILITY_VERSION_COMPATIBILITY','version','1.0.0','manifest_sha256','f2894a7f433ccd1c92f6f1bd4783c3e27b7f9b94ab28b4ab08b6732c92259bf1'),
      jsonb_build_object('capability_code','TYPED_EVIDENCE_REGISTRY','version','3.0.0','manifest_sha256','0fb00eeeb84567129bde17df0fac9f04c136a874518010a21af60c37810134da')))
$$;

CREATE TEMP TABLE t_results(case_id text PRIMARY KEY, passed boolean NOT NULL, detail text);

-- Calls a function as a role through dynamic SQL, so EXECUTE is checked at call time.
CREATE FUNCTION pg_temp.call_as(p_role text, p_ref text, p_actor text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v jsonb; c jsonb := pg_temp.ctx(p_ref);
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE 'SELECT public.fn_lf_decision_context_asof_record_v1($1, $2)' INTO v USING c, p_actor;
    RESET ROLE;
    RETURN 'OK:' || coalesce(v->>'code','?');
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
    RETURN 'DENIED';
  END;
END $$;

SELECT md5(prosrc) AS body_md5_before, prosecdef AS secdef_before, proconfig::text AS config_before
FROM pg_proc WHERE oid='public.fn_lf_decision_context_asof_record_v1(jsonb,text)'::regprocedure \gset

-- 0. Fixture parity with the hosted writer.
INSERT INTO t_results SELECT 'C00_FIXTURE_BODY_EQUALS_HOSTED', :'body_md5_before'='b2b107a86eb8fea55a11ab8f620d9694', :'body_md5_before';

-- 1. Reproduce the finding before the migration: anon and authenticated can record with any actor.
INSERT INTO t_results SELECT 'C01_PRE_ANON_FORGES_ACTOR', r='OK:NEW_CONTEXT', r FROM pg_temp.call_as('anon','pre-anon','ANY-ACTOR-CHOSEN-BY-CALLER') r;
INSERT INTO t_results SELECT 'C02_PRE_AUTHENTICATED_FORGES_ACTOR', r='OK:NEW_CONTEXT', r FROM pg_temp.call_as('authenticated','pre-auth','EXEC-NOT-MINE') r;
INSERT INTO t_results SELECT 'C03_PRE_STORED_ACTOR_IS_CALLER_CHOSEN',
  (SELECT created_by_execution_id='ANY-ACTOR-CHOSEN-BY-CALLER' FROM private.lf_decision_context_asof_v1 WHERE decision_ref='pre-anon'), NULL;

-- 2. Apply the migration under test (exact bytes from the repository).
\ir ../../../../supabase/migrations/20261027180000_lf_decision_context_asof_record_acl_v1.sql

-- 3. Effective privileges after the migration.
INSERT INTO t_results SELECT 'C04_POST_ANON_DENIED', r='DENIED', r FROM pg_temp.call_as('anon','post-anon','ANY-ACTOR') r;
INSERT INTO t_results SELECT 'C05_POST_AUTHENTICATED_DENIED', r='DENIED', r FROM pg_temp.call_as('authenticated','post-auth','ANY-ACTOR') r;
-- C06 is a consistency check only: a denied call never reaches the body.
INSERT INTO t_results SELECT 'C06_POST_NO_ROW_FROM_DENIED_CALLS',
  NOT EXISTS (SELECT 1 FROM private.lf_decision_context_asof_v1 WHERE decision_ref IN ('post-anon','post-auth')), NULL;
INSERT INTO t_results SELECT 'C07_POST_SERVICE_ROLE_RECORDS', r='OK:NEW_CONTEXT', r FROM pg_temp.call_as('service_role','post-svc','EXEC-LEGIT-SERVICE') r;
INSERT INTO t_results SELECT 'C08_POST_SERVICE_ROLE_IDEMPOTENT_REPLAY', r='OK:IDEMPOTENT_REPLAY', r FROM pg_temp.call_as('service_role','post-svc','EXEC-LEGIT-SERVICE') r;
INSERT INTO t_results SELECT 'C09_POST_PUBLIC_NOT_IN_ACL',
  NOT EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid='public.fn_lf_decision_context_asof_record_v1(jsonb,text)'::regprocedure AND a.grantee=0), NULL;
INSERT INTO t_results SELECT 'C10_POST_BODY_MODE_SEARCH_PATH_UNCHANGED',
  md5(prosrc)=:'body_md5_before' AND prosecdef=:'secdef_before'::boolean AND proconfig::text=:'config_before', md5(prosrc)
  FROM pg_proc WHERE oid='public.fn_lf_decision_context_asof_record_v1(jsonb,text)'::regprocedure;
INSERT INTO t_results SELECT 'C11_POST_PRE_FIX_ROWS_UNTOUCHED',
  (SELECT count(*) FROM private.lf_decision_context_asof_v1 WHERE decision_ref IN ('pre-anon','pre-auth'))=2, NULL;
-- Residual boundary, asserted on purpose: service_role can still name any actor.
INSERT INTO t_results SELECT 'C12_RESIDUAL_SERVICE_ROLE_DECLARES_ACTOR', r='OK:NEW_CONTEXT', r FROM pg_temp.call_as('service_role','post-svc-any','ANY-ACTOR-DECLARED-BY-SERVICE') r;

-- 4. Inherited grant: a role that grants EXECUTE through membership must make the
--    migration fail closed, because the ACL text alone no longer proves anything.
CREATE ROLE lf_asof_test_inherited NOLOGIN;
GRANT EXECUTE ON FUNCTION public.fn_lf_decision_context_asof_record_v1(jsonb,text) TO lf_asof_test_inherited;
GRANT lf_asof_test_inherited TO authenticated;
INSERT INTO t_results SELECT 'C13_INHERITED_GRANT_IS_EFFECTIVE',
  has_function_privilege('authenticated','public.fn_lf_decision_context_asof_record_v1(jsonb,text)','EXECUTE'), NULL;
SAVEPOINT inherited_negative;
\set ON_ERROR_STOP 0
\ir ../../../../supabase/migrations/20261027180000_lf_decision_context_asof_record_acl_v1.sql
-- LAST_ERROR_MESSAGE is not reset by a later success, so ERROR is checked too.
\set inherited_failed :ERROR
\set inherited_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP 1
ROLLBACK TO SAVEPOINT inherited_negative;
INSERT INTO t_results SELECT 'C14_MIGRATION_FAILS_CLOSED_ON_INHERITED_GRANT_AUTHENTICATED',
  :'inherited_failed'::boolean AND :'inherited_msg'='LF_ASOF_RECORD_ACL_AUTHENTICATED_STILL_EFFECTIVE',
  'error=' || :'inherited_failed' || ' ' || :'inherited_msg';
REVOKE lf_asof_test_inherited FROM authenticated;
GRANT lf_asof_test_inherited TO anon;
SAVEPOINT inherited_negative_anon;
\set ON_ERROR_STOP 0
\ir ../../../../supabase/migrations/20261027180000_lf_decision_context_asof_record_acl_v1.sql
\set inherited_anon_failed :ERROR
\set inherited_anon_msg :LAST_ERROR_MESSAGE
\set ON_ERROR_STOP 1
ROLLBACK TO SAVEPOINT inherited_negative_anon;
INSERT INTO t_results SELECT 'C15_MIGRATION_FAILS_CLOSED_ON_INHERITED_GRANT_ANON',
  :'inherited_anon_failed'::boolean AND :'inherited_anon_msg'='LF_ASOF_RECORD_ACL_ANON_STILL_EFFECTIVE',
  'error=' || :'inherited_anon_failed' || ' ' || :'inherited_anon_msg';

-- Report and fail on any miss.
SELECT case_id, passed, detail FROM t_results ORDER BY case_id;
DO $f$ DECLARE n int; t int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT passed), count(*) INTO n, t FROM t_results;
  IF t <> 16 OR n <> 0 THEN RAISE EXCEPTION 'DECISION_CONTEXT_ASOF_RECORD_ACL_TEST_FAILED failed=% total=%', n, t; END IF;
  RAISE NOTICE 'DECISION_CONTEXT_ASOF_RECORD_ACL_TEST_PASS %/%', t, t;
END $f$;

ROLLBACK;
