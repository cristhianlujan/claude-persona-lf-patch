\set ON_ERROR_STOP on
-- Execute from the repository root with psql on an empty disposable PostgreSQL 17.
-- The lab Router has different source text; only the *expected MD5 constant* is
-- substituted in a temporary, memory-loaded copy of the production migration.
-- Production migration and its source-drift guard remain unchanged on disk.
BEGIN;
CREATE SCHEMA private;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO service_role, supabase_read_only_user;
CREATE TABLE public.lf_router_action_registry (
  asset_type text, action_code text, operation_code text, operation_resolution text,
  requires_existing_target boolean, requires_missing_target boolean, write_allowed boolean,
  status text, notes text, created_by_execution_id text, updated_by_execution_id text,
  created_at timestamptz, updated_at timestamptz
);
INSERT INTO public.lf_router_action_registry(asset_type,action_code,operation_code,status,write_allowed)
VALUES ('REPOSITORY_ARTIFACT','CODE_DEVELOPMENT','DESARROLLO_CODIGO_AGENTE_LF','CANDIDATO_READ_ONLY',false);
CREATE OR REPLACE FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v1(p_binding jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path TO 'pg_catalog','private' AS $f$
BEGIN
  -- Mirrors the live D7 reader: invalid bindings RAISE (lowercase-only uuid).
  IF (p_binding->>'context_id') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION 'PG01_RECEIPT_BINDING_INVALID';
  END IF;
  IF p_binding->>'target_ref'='READER-ERROR' THEN
    RAISE EXCEPTION 'SIMULATED_READER_FAILURE';
  END IF;
  IF p_binding->>'target_ref'='NOT-FOUND' THEN
    RETURN jsonb_build_object('found',false,'admissible',false,'reason','PG01_RECEIPT_NOT_FOUND');
  ELSIF p_binding->>'target_ref'='ADMIT-TEST-ONLY' THEN
    RETURN jsonb_build_object('found',true,'admissible',true,'reason','TEST_ONLY',
      'receipt',jsonb_build_object('SECRET','DO_NOT_EXPOSE'),
      'envelope',jsonb_build_object('SECRET','DO_NOT_EXPOSE'));
  END IF;
  RETURN jsonb_build_object('found',true,'hashes_verified',true,'admissible',false,
      'reason','PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED',
      'record',jsonb_build_object('receipt',jsonb_build_object('SECRET','DO_NOT_EXPOSE')));
END $f$;
REVOKE ALL ON FUNCTION private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)
 FROM PUBLIC, anon, authenticated, service_role, supabase_read_only_user;

-- Minimal fixture with exact inherited PROGRAMACION block and both anchors.
CREATE OR REPLACE FUNCTION public.lf_router_route_v1(
  p_stage1 jsonb, p_caller jsonb DEFAULT '{}'::jsonb,
  p_nivel2_consentido boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'pg_catalog', 'public'
AS $router$
DECLARE
  v_rs jsonb; v jsonb; v_formas text[]; v_hint text; v_cands jsonb;
  v_n int; v_l2 jsonb; v_d jsonb; v_schema text; v_channel text;
  v_business text; v_scope jsonb; v_transversal text; v_is_v2 boolean := false;
  v_base jsonb; v_profile_selection_request jsonb;
BEGIN
    v_schema := p_stage1->>'schema_version';
    v_channel := p_stage1->>'channel';
    v_scope := p_stage1->'scope';
    v_base := jsonb_build_object('schema_version','LF_ROUTER_ROUTE_V1','router','ACT-0001',
      'stage1_schema_version',v_schema,'downstream_execution_allowed',false);
    IF v_channel='PROGRAMACION' THEN
      RETURN v_base || jsonb_build_object(
        'paso','PROGRAMACION_PRECHECK_DEFINICION',
        'precondicion_requerida','EXACT_CANONICAL_DEFINITION_REF_AND_CURRENTNESS',
        'si_definicion_falta_o_difiere','PRODUCTO_PRIMERO',
        'si_definicion_vigente','PROGRAMACION_ADMISION_REQUERIDA',
        'contrato_entrada_despues_precheck','PROGRAMMING_ENTRY_CONTRACT_V1',
        'upstream_requerido_despues_precheck','ANALYSIS_IMPLEMENTATION_PACKAGE_V1',
        'alcance_requiere_ready',v_scope IS NOT NULL,
        'motivo_es','Antes de Programacion se verifica la definicion funcional canonica. Si falta o difiere, Producto la corrige primero; si coincide, continua la admision tecnica.',
        'siguiente_paso_es','Verificar la fuente canonica y su currentness; solo con definicion vigente continuar a PG-01.'
      );
    END IF;

    IF v_channel='OPERACIONES' THEN
      RETURN v_base || jsonb_build_object('paso','OPERACIONES');
    END IF;
    RETURN v_base || jsonb_build_object('paso','NO_ROUTE');
END;
$router$;

CREATE TEMP TABLE test_baseline AS
SELECT public.lf_router_route_v1('{"schema_version":"TEST_STAGE1_V2","channel":"PROGRAMACION"}'::jsonb) AS result;

-- Load SQL as lines without interpretation of quotes/backslashes (CSV reads blank
-- lines as NULL, so they are restored with coalesce). The control
-- character field separators are never present in this authored migration.
CREATE TEMP TABLE test_migration_lines (line_no bigint GENERATED ALWAYS AS IDENTITY, line text);
\copy test_migration_lines(line) FROM 'supabase/migrations/20261026210000_lf_router_programming_admission_dispatch_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')

-- Apply the entire production DDL; only adapt source-drift MD5 for the stub,
-- strip outer transaction delimiters to respect this test's BEGIN/ROLLBACK.
SELECT replace(replace(replace(
         string_agg(coalesce(line,''),E'\n' ORDER BY line_no),
         '42828a549c0e4ce15e45c902816fa9ea',
         md5(pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean)'::regprocedure))),
         E'BEGIN;\n',''), E'\nCOMMIT;','') AS migration_sql
FROM test_migration_lines
\gexec

CREATE TEMP TABLE test_passed (name text PRIMARY KEY);
CREATE OR REPLACE FUNCTION pg_temp.binding(p_target text DEFAULT 'NORMAL')
RETURNS jsonb LANGUAGE sql STABLE AS $q$
 SELECT jsonb_build_object(
   'context_id','c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
   'context_sha256',repeat('a',64),'target_ref',p_target,
   'requested_scope_ids',jsonb_build_array('scope-1'),
   'producer_execution_ref','PRODUCER-1',
   'entry_contract_digest_sha256','d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8');
$q$;
CREATE OR REPLACE FUNCTION pg_temp.call_router(p_binding jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $q$
 SELECT public.lf_router_route_v1(
  '{"schema_version":"TEST_STAGE1_V2","channel":"PROGRAMACION"}'::jsonb,
  jsonb_build_object('programming_handoff',p_binding));
$q$;

DO $$ BEGIN
 IF (SELECT result FROM test_baseline) IS DISTINCT FROM
    public.lf_router_route_v1('{"schema_version":"TEST_STAGE1_V2","channel":"PROGRAMACION"}'::jsonb)
 THEN RAISE EXCEPTION 'TEST_FAIL:01_legacy_exact'; END IF;
 INSERT INTO test_passed VALUES ('01');
END $$;

DO $$ DECLARE v jsonb; k text; BEGIN
 FOREACH k IN ARRAY ARRAY['context_id','context_sha256','target_ref','requested_scope_ids',
   'producer_execution_ref','entry_contract_digest_sha256'] LOOP
   v := pg_temp.call_router(pg_temp.binding()-k);
   IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO'
     OR v->>'codigo' IS DISTINCT FROM 'PG01_ROUTER_BINDING_INVALID'
   THEN RAISE EXCEPTION 'TEST_FAIL:02_missing_%',k; END IF;
 END LOOP;
 IF pg_temp.call_router(jsonb_set(pg_temp.binding(),'{context_id}','"not-uuid"'))
   ->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO' THEN
    RAISE EXCEPTION 'TEST_FAIL:02_uuid'; END IF;
 IF pg_temp.call_router(jsonb_set(pg_temp.binding(),'{requested_scope_ids}','[1]'))
   ->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO' THEN
    RAISE EXCEPTION 'TEST_FAIL:02_scopes'; END IF;
 INSERT INTO test_passed VALUES ('02');
END $$;

DO $$ BEGIN
 IF pg_temp.call_router(jsonb_set(pg_temp.binding(),'{entry_contract_digest_sha256}',
    to_jsonb(repeat('e',64))))->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO'
 THEN RAISE EXCEPTION 'TEST_FAIL:03_digest'; END IF;
 INSERT INTO test_passed VALUES ('03');
END $$;

DO $$ DECLARE v jsonb; BEGIN
 v:=pg_temp.call_router(pg_temp.binding('NOT-FOUND'));
 IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_BLOQUEADA'
    OR v->>'retorno' IS DISTINCT FROM 'RETURN_TO_ANALYSIS_NO_CODE'
    OR v->>'reason' IS DISTINCT FROM 'PG01_RECEIPT_NOT_FOUND'
 THEN RAISE EXCEPTION 'TEST_FAIL:04_absent'; END IF;
 INSERT INTO test_passed VALUES ('04');
END $$;

DO $$ DECLARE v jsonb; BEGIN
 v:=pg_temp.call_router(pg_temp.binding('NORMAL'));
 IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_BLOQUEADA'
    OR v->>'retorno' IS DISTINCT FROM 'BLOCK_NO_CODE'
    OR v->>'reason' IS DISTINCT FROM 'PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED'
 THEN RAISE EXCEPTION 'TEST_FAIL:05_closed'; END IF;
 INSERT INTO test_passed VALUES ('05');
END $$;

DO $$ DECLARE v jsonb; BEGIN
 v:=pg_temp.call_router(pg_temp.binding('ADMIT-TEST-ONLY'));
 IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_OPERACION_NO_ACTIVA'
    OR v->>'operation_status' IS DISTINCT FROM 'CANDIDATO_READ_ONLY'
 THEN RAISE EXCEPTION 'TEST_FAIL:06_inactive'; END IF;
 INSERT INTO test_passed VALUES ('06');
END $$;

DO $$ DECLARE v jsonb; BEGIN
 UPDATE public.lf_router_action_registry SET status='ACTIVE'
 WHERE operation_code='DESARROLLO_CODIGO_AGENTE_LF';
 v:=pg_temp.call_router(pg_temp.binding('ADMIT-TEST-ONLY'));
 IF v->>'paso' IS DISTINCT FROM 'DISPATCHED'
   OR v#>>'{despacho,operation_code}' IS DISTINCT FROM 'DESARROLLO_CODIGO_AGENTE_LF'
   OR v#>>'{despacho,entry_contract}' IS DISTINCT FROM 'PROGRAMMING_ENTRY_CONTRACT_V1'
   OR (v->>'downstream_execution_allowed')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'TEST_FAIL:07_dispatch'; END IF;
 INSERT INTO test_passed VALUES ('07');
END $$;

DO $$ DECLARE v jsonb; BEGIN
 v:=public.lf_router_programming_admission_gate_v1(pg_temp.binding('ADMIT-TEST-ONLY'));
 IF v ? 'receipt' OR v ? 'envelope' OR v ? 'record'
 OR (SELECT count(*) FROM jsonb_object_keys(v)) <> 4
 OR v->>'schema_version' IS DISTINCT FROM 'LF_ROUTER_PROGRAMMING_ADMISSION_GATE_V1'
 THEN RAISE EXCEPTION 'TEST_FAIL:08_leak'; END IF;
 INSERT INTO test_passed VALUES ('08');
END $$;

DO $$ BEGIN
 IF has_function_privilege('anon','public.lf_router_programming_admission_gate_v1(jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','public.lf_router_programming_admission_gate_v1(jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'TEST_FAIL:09_acl'; END IF;
 INSERT INTO test_passed VALUES ('09');
END $$;
DO $$ DECLARE v jsonb; BEGIN
 v:=pg_temp.call_router(jsonb_set(pg_temp.binding(),'{context_id}','"C4F7D9E4-3D29-4D12-950B-0B7EF25E7C5C"'));
 IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO' THEN
   RAISE EXCEPTION 'TEST_FAIL:10_uppercase_uuid_must_not_reach_reader'; END IF;
 v:=pg_temp.call_router('null'::jsonb);
 IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_HANDOFF_INVALIDO' THEN
   RAISE EXCEPTION 'TEST_FAIL:10_null_handoff'; END IF;
 INSERT INTO test_passed VALUES ('10');
END $$;

DO $$ DECLARE v jsonb; BEGIN
 v:=pg_temp.call_router(pg_temp.binding('READER-ERROR'));
 IF v->>'paso' IS DISTINCT FROM 'PROGRAMACION_ADMISION_BLOQUEADA'
    OR v->>'reason' IS DISTINCT FROM 'PG01_ROUTER_ADMISSION_UNDETERMINED'
    OR v->>'retorno' IS DISTINCT FROM 'BLOCK_NO_CODE'
 THEN RAISE EXCEPTION 'TEST_FAIL:11_reader_error_fail_closed'; END IF;
 INSERT INTO test_passed VALUES ('11');
END $$;

DO $$ DECLARE n int; BEGIN
 SELECT count(*) INTO n FROM test_passed;
 IF n<>11 THEN RAISE EXCEPTION 'TEST_FAIL:total_%',n; END IF;
 RAISE NOTICE 'ROUTER_PROGRAMMING_DISPATCH_TESTS_PASSED:%',n;
END $$;
ROLLBACK;
