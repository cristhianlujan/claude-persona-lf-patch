\set ON_ERROR_STOP on
BEGIN;
DO $roles$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF;
END $roles$;
CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA private TO service_role, supabase_read_only_user;
-- Mirrors live Supabase (verified 26-oct): both roles have USAGE on extensions and EXECUTE on extensions.digest.
GRANT USAGE ON SCHEMA extensions TO service_role, supabase_read_only_user;
CREATE TABLE public.lf_router_action_registry (
 asset_type text, action_code text, operation_code text, operation_resolution text,
 requires_existing_target boolean, requires_missing_target boolean, write_allowed boolean,
 status text, notes text, created_by_execution_id text, updated_by_execution_id text,
 created_at timestamptz, updated_at timestamptz
);
INSERT INTO public.lf_router_action_registry(asset_type,action_code,operation_code,status,write_allowed)
VALUES('REPOSITORY_ARTIFACT','CODE_DEVELOPMENT','DESARROLLO_CODIGO_AGENTE_LF','CANDIDATO_READ_ONLY',false);
GRANT SELECT ON public.lf_router_action_registry TO service_role,supabase_read_only_user;
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY, operation_code text NOT NULL, target_type text NOT NULL, target_code text NOT NULL, status text NOT NULL, manifest jsonb NOT NULL);
GRANT SELECT ON public.lf_operation_execution TO service_role,supabase_read_only_user;
CREATE FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v2(p_binding jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path TO 'pg_catalog','private' AS $f$
BEGIN
 IF (p_binding->>'context_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  RAISE EXCEPTION 'PG01_RECEIPT_BINDING_INVALID';
 END IF;
 IF p_binding->>'target_ref'='READER-ERROR' THEN RAISE EXCEPTION 'SIMULATED_READER_FAILURE'; END IF;
 IF p_binding->>'target_ref'='NOT-FOUND' THEN
  RETURN jsonb_build_object('found',false,'admissible',false,'reason','PG01_V2_RECEIPT_NOT_FOUND');
 ELSIF p_binding->>'target_ref'='ADMIT-TEST-ONLY' THEN
  RETURN jsonb_build_object('found',true,'admissible',true,'reason','TEST_ONLY',
    'receipt',jsonb_build_object('SECRET','DO_NOT_EXPOSE'),
    'envelope',jsonb_build_object('SECRET','DO_NOT_EXPOSE'));
 END IF;
 RETURN jsonb_build_object('found',true,'hashes_verified',true,'admissible',false,
    'reason','PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED',
    'record',jsonb_build_object('receipt',jsonb_build_object('SECRET','DO_NOT_EXPOSE')));
END $f$;
REVOKE ALL ON FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)
FROM PUBLIC, anon, authenticated, service_role, supabase_read_only_user;

-- Apply migration from disk. Remove outer transaction statements only because
-- this test transaction must own the rollback.
CREATE TEMP TABLE test_migration_lines (line_no bigint GENERATED ALWAYS AS IDENTITY, line text);
\copy test_migration_lines(line) FROM 'supabase/migrations/20261026230000_lf_programming_development_admission_gate_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY line_no),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM test_migration_lines
\gexec

CREATE FUNCTION pg_temp.router_binding(p_overrides jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE b jsonb;
BEGIN
 b := jsonb_build_object('channel','PROGRAMACION','channel_effect_authority',false,
  'channel_precondition', jsonb_build_object('code','PROGRAMACION_PRECHECK_DEFINICION',
    'precondition_required','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
    'if_definition_missing_or_differs','PRODUCTO_PRIMERO',
    'if_definition_current','PROGRAMACION_ADMISION_REQUERIDA',
    'programming_entry_contract','PROGRAMMING_ENTRY_CONTRACT_V1',
    'upstream_required','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
    'required_before_profile_execution',false,'required_before_channel_effect',true,
    'profile_execution_role','READ_ONLY_CHANNEL_ADMINISTRATION'));
 b := b || p_overrides;
 b := b || jsonb_build_object('binding_sha256','sha256:' || encode(extensions.digest(convert_to((b-'binding_sha256')::text,'UTF8'),'sha256'),'hex'));
 RETURN b;
END $f$;
CREATE FUNCTION pg_temp.profile_execution(p_id text,p_binding jsonb,p_channel text DEFAULT 'PROGRAMACION',p_status text DEFAULT 'COMPLETED')
RETURNS void LANGUAGE sql AS $f$
 INSERT INTO public.lf_operation_execution(execution_id,operation_code,target_type,target_code,status,manifest)
 VALUES(p_id,'EJECUCION_PERFIL_LF','PERFIL','PROFILE',p_status,
 jsonb_build_object('router_profile_handoff',jsonb_build_object('channel',p_channel,
   'semantic_request',jsonb_build_object('router_action_binding',p_binding))))
 ON CONFLICT(execution_id) DO UPDATE SET manifest=excluded.manifest,status=excluded.status;
$f$;
CREATE FUNCTION pg_temp.handoff(p_target text DEFAULT 'NORMAL') RETURNS jsonb LANGUAGE sql AS $f$
 SELECT jsonb_build_object('context_id','c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
 'context_sha256',repeat('a',64),'target_ref',p_target,'requested_scope_ids',jsonb_build_array('S1'),
 'producer_execution_ref','EXEC-PROFILE-TEST','entry_contract_digest_sha256',
 'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8');
$f$;
-- Restricted-role negative check first, before owner invokes either PL/pgSQL function.
DO $t$ DECLARE r jsonb; b jsonb; BEGIN
 b:=pg_temp.router_binding(); PERFORM pg_temp.profile_execution('EXEC-PROFILE-TEST',b);
 PERFORM set_config('role','supabase_read_only_user',true);
 r:=public.lf_programming_admission_gate_v1(pg_temp.handoff());
 PERFORM set_config('role','none',true);
 IF r->>'reason' IS DISTINCT FROM 'PG01_GATE_READER_NOT_GRANTED' THEN RAISE EXCEPTION 'TEST_FAIL:00_restricted %',r; END IF;
END $t$;
CREATE TEMP TABLE passed(test_no integer PRIMARY KEY);

DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(NULL,pg_temp.handoff(),'EXEC-PROFILE-TEST');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_NOT_OBJECT' THEN RAISE EXCEPTION 'TEST_FAIL:01_binding_not_object'; END IF;
 INSERT INTO passed VALUES(1); END $$;
DO $$ DECLARE b jsonb; r jsonb; BEGIN
 b:=pg_temp.router_binding(); b:=jsonb_set(b,'{channel}','"PRODUCTO"');
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff(),'EXEC-PROFILE-TEST');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_SHA_MISMATCH' THEN RAISE EXCEPTION 'TEST_FAIL:02_sha'; END IF;
 INSERT INTO passed VALUES(2); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding('{"channel":"PRODUCTO"}'),pg_temp.handoff(),'EXEC-PROFILE-TEST');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_CHANNEL_MISMATCH' THEN RAISE EXCEPTION 'TEST_FAIL:03_channel'; END IF;
 INSERT INTO passed VALUES(3); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding('{"channel_effect_authority":true}'),pg_temp.handoff(),'EXEC-PROFILE-TEST');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_EFFECT_AUTHORITY_UNEXPECTED' THEN RAISE EXCEPTION 'TEST_FAIL:04_effect'; END IF;
 INSERT INTO passed VALUES(4); END $$;
DO $$ DECLARE b jsonb; p jsonb; r jsonb; field text; BEGIN
 FOREACH field IN ARRAY ARRAY['code','required_before_channel_effect','programming_entry_contract'] LOOP
  p:=pg_temp.router_binding()->'channel_precondition';
  p:=jsonb_set(p,ARRAY[field],CASE WHEN field='required_before_channel_effect' THEN 'false'::jsonb ELSE '"WRONG"'::jsonb END);
  b:=pg_temp.router_binding(jsonb_build_object('channel_precondition',p));
  r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff(),'EXEC-PROFILE-TEST');
  IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_PRECONDITION_MISMATCH' THEN RAISE EXCEPTION 'TEST_FAIL:05_precondition_%',field; END IF;
 END LOOP; INSERT INTO passed VALUES(5); END $$;
DO $$ DECLARE h jsonb; r jsonb; field text; BEGIN
 FOREACH field IN ARRAY ARRAY['context_id','context_sha256','target_ref','requested_scope_ids','producer_execution_ref','entry_contract_digest_sha256'] LOOP
  h:=pg_temp.handoff()-field;
  r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),h,'EXEC-PROFILE-TEST');
  IF r->>'codigo' IS DISTINCT FROM 'PG01_GATE_BINDING_INVALID' THEN RAISE EXCEPTION 'TEST_FAIL:06_missing_%',field; END IF;
 END LOOP;
 FOREACH h IN ARRAY ARRAY[jsonb_set(pg_temp.handoff(),'{context_id}','"C4F7D9E4-3D29-4D12-950B-0B7EF25E7C5C"'),
   jsonb_set(pg_temp.handoff(),'{requested_scope_ids}','[""]'), 'null'::jsonb] LOOP
   r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),h,'EXEC-PROFILE-TEST');
   IF r->>'codigo' IS DISTINCT FROM 'PG01_GATE_BINDING_INVALID' THEN RAISE EXCEPTION 'TEST_FAIL:06_invalid_value'; END IF;
 END LOOP;
 INSERT INTO passed VALUES(6); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),jsonb_set(pg_temp.handoff(),'{entry_contract_digest_sha256}',to_jsonb(repeat('f',64))),'EXEC-PROFILE-TEST');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_GATE_BINDING_INVALID' THEN RAISE EXCEPTION 'TEST_FAIL:07_digest'; END IF;
 INSERT INTO passed VALUES(7); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),pg_temp.handoff('NOT-FOUND'),'EXEC-PROFILE-TEST');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_BLOQUEADA' OR r->>'retorno' IS DISTINCT FROM 'RETURN_TO_ANALYSIS_NO_CODE' THEN RAISE EXCEPTION 'TEST_FAIL:08_not_found'; END IF;
 INSERT INTO passed VALUES(8); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),pg_temp.handoff(),'EXEC-PROFILE-TEST');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_BLOQUEADA' OR r->>'retorno' IS DISTINCT FROM 'BLOCK_NO_CODE' THEN RAISE EXCEPTION 'TEST_FAIL:09_closed'; END IF;
 INSERT INTO passed VALUES(9); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),pg_temp.handoff('READER-ERROR'),'EXEC-PROFILE-TEST');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_GATE_ADMISSION_UNDETERMINED' THEN RAISE EXCEPTION 'TEST_FAIL:10_reader_error'; END IF;
 INSERT INTO passed VALUES(10); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_development_admission_v1(pg_temp.router_binding(),pg_temp.handoff('ADMIT-TEST-ONLY'),'EXEC-PROFILE-TEST');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_OPERACION_NO_ACTIVA' OR r->>'operation_status' IS DISTINCT FROM 'CANDIDATO_READ_ONLY' THEN RAISE EXCEPTION 'TEST_FAIL:11_inactive'; END IF;
 INSERT INTO passed VALUES(11); END $$;
DO $$ DECLARE r jsonb; b jsonb; BEGIN
 UPDATE public.lf_router_action_registry SET status='ACTIVE'; b:=pg_temp.router_binding();
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff('ADMIT-TEST-ONLY'),'EXEC-PROFILE-TEST');
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_DESARROLLO_ADMITIDO' OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb
 OR r#>>'{admision,router_binding_sha256}' IS DISTINCT FROM b->>'binding_sha256' OR r#>>'{admision,source_execution_id}' IS DISTINCT FROM 'EXEC-PROFILE-TEST' THEN RAISE EXCEPTION 'TEST_FAIL:12_admission'; END IF;
 UPDATE public.lf_router_action_registry SET status='CANDIDATO_READ_ONLY';
 INSERT INTO passed VALUES(12); END $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.lf_programming_admission_gate_v1(pg_temp.handoff('ADMIT-TEST-ONLY'));
 IF (SELECT count(*) FROM jsonb_object_keys(r))<>4 OR r ? 'record' OR r ? 'receipt' OR r ? 'envelope'
 OR r::text LIKE '%DO_NOT_EXPOSE%' THEN RAISE EXCEPTION 'TEST_FAIL:13_no_leak'; END IF;
 INSERT INTO passed VALUES(13); END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM pg_proc WHERE oid IN (
 'public.lf_programming_admission_gate_v1(jsonb)'::regprocedure,
 'public.lf_programming_development_admission_v1(jsonb,jsonb,text)'::regprocedure) AND NOT prosecdef)<>2
 OR has_function_privilege('anon','public.lf_programming_admission_gate_v1(jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_programming_admission_gate_v1(jsonb)','EXECUTE')
 OR has_function_privilege('anon','public.lf_programming_development_admission_v1(jsonb,jsonb,text)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_programming_development_admission_v1(jsonb,jsonb,text)','EXECUTE')
 THEN RAISE EXCEPTION 'TEST_FAIL:14_security'; END IF;
 INSERT INTO passed VALUES(14); END $$;
DO $$ DECLARE r jsonb; b jsonb; h jsonb; BEGIN
 b:=pg_temp.router_binding(); h:=pg_temp.handoff();
 PERFORM set_config('role','service_role',true);
 r:=public.lf_programming_development_admission_v1(b,h,'EXEC-PROFILE-TEST');
 PERFORM set_config('role','none',true);
 IF r->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_BLOQUEADA' OR r->>'codigo' IS DISTINCT FROM 'PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED' THEN RAISE EXCEPTION 'TEST_FAIL:15_privilege'; END IF;
 INSERT INTO passed VALUES(15); END $$;
DO $$ DECLARE r jsonb; BEGIN
 FOR r IN SELECT public.lf_programming_development_admission_v1(pg_temp.router_binding(),h,'EXEC-PROFILE-TEST')
 FROM (VALUES (pg_temp.handoff()),(pg_temp.handoff('NOT-FOUND')),(pg_temp.handoff('ADMIT-TEST-ONLY')),(NULL::jsonb)) t(h) LOOP
  IF r->>'paso' NOT LIKE 'PROGRAMACION_%' OR r ? 'reason' THEN RAISE EXCEPTION 'TEST_FAIL:16_convention'; END IF;
 END LOOP; INSERT INTO passed VALUES(16); END $$;
DO $$ DECLARE r jsonb; b jsonb; BEGIN
 b:=pg_temp.router_binding();
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff(),'EXEC-MISSING');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_NOT_ISSUED_BY_EXECUTION' THEN RAISE EXCEPTION 'TEST_FAIL:17_missing'; END IF;
 INSERT INTO passed VALUES(17); END $$;
DO $$ DECLARE r jsonb; b jsonb; BEGIN
 b:=pg_temp.router_binding();
 PERFORM pg_temp.profile_execution('EXEC-PROFILE-OTHER',pg_temp.router_binding('{"extra":"x"}'));
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff(),'EXEC-PROFILE-OTHER');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_NOT_ISSUED_BY_EXECUTION' THEN RAISE EXCEPTION 'TEST_FAIL:18_binding_mismatch'; END IF;
 INSERT INTO passed VALUES(18); END $$;
DO $$ DECLARE r jsonb; b jsonb; BEGIN
 b:=pg_temp.router_binding(); PERFORM pg_temp.profile_execution('EXEC-PROFILE-RUN',b,'PROGRAMACION','IN_PROGRESS');
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff(),'EXEC-PROFILE-RUN');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_NOT_ISSUED_BY_EXECUTION' THEN RAISE EXCEPTION 'TEST_FAIL:19_inprogress'; END IF;
 INSERT INTO passed VALUES(19); END $$;
DO $$ DECLARE r jsonb; b jsonb; BEGIN
 b:=pg_temp.router_binding(); PERFORM pg_temp.profile_execution('EXEC-PROFILE-PRODUCT',b,'PRODUCTO');
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff(),'EXEC-PROFILE-PRODUCT');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_NOT_ISSUED_BY_EXECUTION' THEN RAISE EXCEPTION 'TEST_FAIL:20_wrong_channel'; END IF;
 INSERT INTO passed VALUES(20); END $$;
DO $$ DECLARE r jsonb; b jsonb; BEGIN
 b:=pg_temp.router_binding(); PERFORM pg_temp.profile_execution('EXEC-PROFILE-SECOND',b);
 UPDATE public.lf_router_action_registry SET status='ACTIVE';
 r:=public.lf_programming_development_admission_v1(b,pg_temp.handoff('ADMIT-TEST-ONLY'),'EXEC-PROFILE-SECOND');
 IF r->>'codigo' IS DISTINCT FROM 'PG01_HANDOFF_SOURCE_EXECUTION_MISMATCH'
 OR r->'downstream_execution_allowed' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'TEST_FAIL:21_cross_execution_handoff %',r;
 END IF;
 UPDATE public.lf_router_action_registry SET status='CANDIDATO_READ_ONLY';
 INSERT INTO passed VALUES(21); END $$;
DO $$ DECLARE n integer; BEGIN
 SELECT count(*) INTO n FROM passed;
 IF n IS DISTINCT FROM 21 THEN RAISE EXCEPTION 'TEST_FAIL:TOTAL_%',n; END IF;
 RAISE NOTICE 'PROGRAMMING_DEVELOPMENT_ADMISSION_TESTS_PASSED:%',n;
END $$;
ROLLBACK;
