\set ON_ERROR_STOP on
-- Point 3 tests against the REAL return functions, rebuilt from the repo migrations
-- that produced them (20261025014719 + 20261026180000 + 20261026180500 for classify,
-- 20261025004001 for prepare). The rebuild is checked against the live md5s, so the
-- migration under test is applied unmodified (no md5 substitution). Run from repo root
-- on an empty disposable PostgreSQL; everything is rolled back.
BEGIN;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DO $r$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF;
END $r$;
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
-- Test-only stub: the terminal authority receipt is out of scope here.
CREATE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(text)
RETURNS jsonb LANGUAGE sql AS $s$ SELECT '{"status":"READY"}'::jsonb $s$;

CREATE TEMP TABLE src_lines(n bigint GENERATED ALWAYS AS IDENTITY, line text);
CREATE TEMP TABLE src(name text PRIMARY KEY, body text);
\copy src_lines(line) FROM 'supabase/migrations/20261025004001_lf_profile_result_router_return_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
INSERT INTO src SELECT 'base', string_agg(coalesce(line,''),E'\n' ORDER BY n) FROM src_lines; TRUNCATE src_lines;
\copy src_lines(line) FROM 'supabase/migrations/20261025014719_lf_srcr_return_router_after_repair_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
INSERT INTO src SELECT 'srcr', string_agg(coalesce(line,''),E'\n' ORDER BY n) FROM src_lines; TRUNCATE src_lines;
\copy src_lines(line) FROM 'supabase/migrations/20261026180000_lf_profile_result_positive_continue_router_return_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
INSERT INTO src SELECT 'cont1', string_agg(coalesce(line,''),E'\n' ORDER BY n) FROM src_lines; TRUNCATE src_lines;
\copy src_lines(line) FROM 'supabase/migrations/20261026180500_lf_profile_positive_continuation_router_return_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
INSERT INTO src SELECT 'cont2', string_agg(coalesce(line,''),E'\n' ORDER BY n) FROM src_lines; TRUNCATE src_lines;
\copy src_lines(line) FROM 'supabase/migrations/20261027090000_lf_programming_analysis_return_to_development_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
INSERT INTO src SELECT 'under_test', string_agg(coalesce(line,''),E'\n' ORDER BY n) FROM src_lines;

-- slice(text, start marker, end marker): from the start marker through the end marker.
CREATE FUNCTION pg_temp.slice(t text, a text, b text) RETURNS text LANGUAGE sql IMMUTABLE AS $q$
  SELECT substring(t from strpos(t,a) for strpos(substring(t from strpos(t,a)), b) + length(b) - 1)
$q$;

SELECT pg_temp.slice(body,'CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_classify_v1','$function$;') FROM src WHERE name='srcr'
\gexec
SELECT pg_temp.slice(body,'CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_prepare_v1','$function$;') FROM src WHERE name='base'
\gexec
-- Live ACL (verified 26-oct): EXECUTE only for postgres, service_role and supabase_read_only_user.
REVOKE ALL ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text),
  public.lf_profile_result_router_return_prepare_v1(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text),
  public.lf_profile_result_router_return_prepare_v1(text) TO service_role, supabase_read_only_user;
SELECT pg_temp.slice(body,'DO $precheck$','$precheck$;') FROM src WHERE name='cont1'
\gexec
SELECT pg_temp.slice(body,'DO $patch$','$patch$;') FROM src WHERE name='cont1'
\gexec
SELECT pg_temp.slice(body,'DO $precheck$','$precheck$;') FROM src WHERE name='cont2'
\gexec
SELECT pg_temp.slice(body,'DO $patch$','$patch$;') FROM src WHERE name='cont2'
\gexec

DO $chk$ BEGIN
  IF md5(pg_get_functiondef('public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure))
       IS DISTINCT FROM '7517e452f5fa3ab2686c073bd6604b78'
     OR md5(pg_get_functiondef('public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure))
       IS DISTINCT FROM '8bf503bf17f038a18124783c038d9793' THEN
    RAISE EXCEPTION 'TEST_SETUP:rebuild_does_not_match_live_md5';
  END IF;
END $chk$;

-- Apply the migration under test exactly as written (outer BEGIN/COMMIT removed).
SELECT replace(replace(body,E'BEGIN;\n',''),E'\nCOMMIT;','') FROM src WHERE name='under_test'
\gexec

CREATE TEMP TABLE test_results(test_name text PRIMARY KEY);
CREATE FUNCTION pg_temp.h() RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('context_id','00000000-0000-0000-0000-000000000001','context_sha256',repeat('a',64),
    'target_ref','X','requested_scope_ids',jsonb_build_array('S1'),'producer_execution_ref','E1',
    'entry_contract_digest_sha256',repeat('b',64)) $q$;
CREATE FUNCTION pg_temp.binding() RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('channel','PROGRAMACION','channel_effect_authority',false,
    'channel_precondition',jsonb_build_object('code','PROGRAMACION_PRECHECK_DEFINICION'),
    'binding_sha256','sha256:'||repeat('c',64)) $q$;
CREATE FUNCTION pg_temp.seed(p_id text, p_manifest jsonb, p_output jsonb) RETURNS void LANGUAGE sql AS $q$
  INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest)
    VALUES (p_id,'EJECUCION_PERFIL_LF','PERFIL','PERFIL-TEST','COMPLETED',p_manifest);
  INSERT INTO public.lf_operation_execution_steps(execution_id,step_id,status,evidence_payload)
    VALUES (p_id,'execute_profile','STEP_PASS_WITH_EVIDENCE',jsonb_build_object('profile_output',p_output));
$q$;
CREATE FUNCTION pg_temp.manifest(p_channel text, p_binding jsonb) RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('router_profile_handoff',jsonb_strip_nulls(jsonb_build_object(
    'channel',p_channel,'literal_request','pedido de prueba','return_to_router_after_profile_result',true,
    'semantic_request',CASE WHEN p_binding IS NULL THEN NULL ELSE jsonb_build_object('router_action_binding',p_binding) END))) $q$;

DO $t$ DECLARE r jsonb; BEGIN
  r:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','status','COMPLETE','programming_handoff',pg_temp.h()),
    'pedido','E1','PERFIL-TEST');
  IF r->>'next_action' IS DISTINCT FROM 'ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION'
     OR r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_PROGRAMMING_ANALYSIS_READY'
     OR r ? 'router_return_request' OR r->'programming_handoff' IS DISTINCT FROM pg_temp.h() THEN
    RAISE EXCEPTION 'TEST_FAIL:01_typed_return %', r; END IF;
  INSERT INTO test_results VALUES ('01');
END $t$;

DO $t$ DECLARE r jsonb; k text; BEGIN
  r:=public.lf_profile_result_router_return_classify_v1('{"output_type":"PROGRAMMING_ANALYSIS_PACKAGE_READY"}','pedido','E1','PERFIL-TEST');
  IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_PROGRAMMING_HANDOFF_INVALID' THEN RAISE EXCEPTION 'TEST_FAIL:02_missing_handoff'; END IF;
  FOREACH k IN ARRAY ARRAY['context_id','context_sha256','target_ref','requested_scope_ids','producer_execution_ref','entry_contract_digest_sha256'] LOOP
    r:=public.lf_profile_result_router_return_classify_v1(
      jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','programming_handoff',pg_temp.h()-k),'pedido','E1','PERFIL-TEST');
    IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_PROGRAMMING_HANDOFF_INVALID' THEN RAISE EXCEPTION 'TEST_FAIL:02_missing_%',k; END IF;
  END LOOP;
  INSERT INTO test_results VALUES ('02');
END $t$;

DO $t$ DECLARE r jsonb; o jsonb; BEGIN
  FOREACH o IN ARRAY ARRAY[
    '{"status":"BLOCKED"}'::jsonb, '{"status":"NEEDS_INPUT"}'::jsonb, '{"self_verdict":"NEEDS_ADJUSTMENT"}'::jsonb,
    '{"blocked":true}'::jsonb, '{"missing_inputs":["x"]}'::jsonb] LOOP
    r:=public.lf_profile_result_router_return_classify_v1(
      o||jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','programming_handoff',pg_temp.h()),'pedido','E1','PERFIL-TEST');
    IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_PROGRAMMING_ANALYSIS_CONTRADICTORY' THEN RAISE EXCEPTION 'TEST_FAIL:03_contradictory %', o; END IF;
  END LOOP;
  INSERT INTO test_results VALUES ('03');
END $t$;

DO $t$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.seed('E-PRODUCTO', pg_temp.manifest('PRODUCTO', pg_temp.binding()),
    jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','status','COMPLETE','programming_handoff',pg_temp.h()));
  r:=public.lf_profile_result_router_return_prepare_v1('E-PRODUCTO');
  IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_PROGRAMMING_CHANNEL_MISMATCH' THEN RAISE EXCEPTION 'TEST_FAIL:04_channel %', r; END IF;
  INSERT INTO test_results VALUES ('04');
END $t$;

DO $t$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.seed('E-NOBIND', pg_temp.manifest('PROGRAMACION', NULL),
    jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','status','COMPLETE','programming_handoff',pg_temp.h()));
  r:=public.lf_profile_result_router_return_prepare_v1('E-NOBIND');
  IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_ROUTER_BINDING_NOT_AVAILABLE' THEN RAISE EXCEPTION 'TEST_FAIL:05_no_binding %', r; END IF;
  PERFORM pg_temp.seed('E-NOSHA', pg_temp.manifest('PROGRAMACION', pg_temp.binding()-'binding_sha256'),
    jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','status','COMPLETE','programming_handoff',pg_temp.h()));
  r:=public.lf_profile_result_router_return_prepare_v1('E-NOSHA');
  IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_ROUTER_BINDING_NOT_AVAILABLE' THEN RAISE EXCEPTION 'TEST_FAIL:05_no_sha %', r; END IF;
  INSERT INTO test_results VALUES ('05');
END $t$;

DO $t$ DECLARE r jsonb; BEGIN
  PERFORM pg_temp.seed('E-OK', pg_temp.manifest('PROGRAMACION', pg_temp.binding()),
    jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','status','COMPLETE','programming_handoff',pg_temp.h()));
  r:=public.lf_profile_result_router_return_prepare_v1('E-OK');
  IF r->>'next_action' IS DISTINCT FROM 'ENTER_PROGRAMMING_DEVELOPMENT_ADMISSION'
     OR r#>>'{programming_admission_request,entrypoint}' IS DISTINCT FROM 'public.lf_programming_development_admission_v1'
     OR r#>'{programming_admission_request,router_action_binding}' IS DISTINCT FROM pg_temp.binding()
     OR r#>'{programming_admission_request,programming_handoff}' IS DISTINCT FROM pg_temp.h()
     OR r#>>'{programming_admission_request,source_execution_id}' IS DISTINCT FROM 'E-OK'
     OR r ? 'router_return_request' THEN
    RAISE EXCEPTION 'TEST_FAIL:06_exact_request %', r; END IF;
  INSERT INTO test_results VALUES ('06');
END $t$;

-- Regression on the REAL continuation path (typed routing contract, not output_type).
DO $t$ DECLARE r jsonb; BEGIN
  r:=public.lf_profile_result_router_return_classify_v1(
    '{"status":"COMPLETE","verdict":"PASS","pipeline_action":"CONTINUE","routing":{"via":"ORCHESTRATOR","pipeline_action":"CONTINUE","resolution_target":"NEXT"}}',
    'pedido','E1','PERFIL-TEST');
  IF r->>'next_action' IS DISTINCT FROM 'REENTER_ROUTER_STAGE1' THEN RAISE EXCEPTION 'TEST_FAIL:07_legacy_continue %', r; END IF;
  PERFORM pg_temp.seed('E-LEGACY', pg_temp.manifest('PROGRAMACION', pg_temp.binding()),
    '{"status":"COMPLETE","verdict":"PASS","pipeline_action":"CONTINUE","routing":{"via":"ORCHESTRATOR","pipeline_action":"CONTINUE","resolution_target":"NEXT"}}');
  r:=public.lf_profile_result_router_return_prepare_v1('E-LEGACY');
  IF r->>'next_action' IS DISTINCT FROM 'REENTER_ROUTER_STAGE1' OR r ? 'programming_admission_request' THEN
    RAISE EXCEPTION 'TEST_FAIL:07_legacy_prepare %', r; END IF;
  INSERT INTO test_results VALUES ('07');
END $t$;

DO $t$ DECLARE r jsonb; BEGIN
  r:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PROGRAMMING_ANALYSIS_PACKAGE_READY','target_profile','OTRO','programming_handoff',pg_temp.h()),
    'pedido','E1','PERFIL-TEST');
  IF r->>'code' IS DISTINCT FROM 'PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN' THEN RAISE EXCEPTION 'TEST_FAIL:08_target_profile %', r; END IF;
  INSERT INTO test_results VALUES ('08');
END $t$;

DO $t$ BEGIN
  IF NOT has_function_privilege('service_role','public.lf_profile_result_router_return_prepare_v1(text)','EXECUTE')
     OR has_function_privilege('anon','public.lf_profile_result_router_return_prepare_v1(text)','EXECUTE')
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='public.lf_profile_result_router_return_prepare_v1(text)'::regprocedure) THEN
    RAISE EXCEPTION 'TEST_FAIL:09_acl_unchanged'; END IF;
  INSERT INTO test_results VALUES ('09');
END $t$;

DO $t$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM test_results;
  IF n IS DISTINCT FROM 9 THEN RAISE EXCEPTION 'TEST_FAIL:COUNT_%', n; END IF;
  RAISE NOTICE 'PROGRAMMING_ANALYSIS_RETURN_TESTS_PASSED:%', n;
END $t$;
ROLLBACK;
