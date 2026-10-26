\set ON_ERROR_STOP on
-- Integration check: the admission gate against the REAL D7 reader
-- (migration 20261026173901), not a stub. Disposable PostgreSQL only; ROLLBACK at the end.
-- The service_role call runs first and in its own DO block: within one transaction
-- PL/pgSQL caches an already-initialized call and does not re-check EXECUTE after a
-- role change, which would make the privilege check pass falsely.
BEGIN;
DO $r$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF;
END $r$;
CREATE SCHEMA private; CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA private, extensions TO service_role, supabase_read_only_user;
-- Minimal prerequisites of the real D7 migration (only what its prechecks require).
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY);
CREATE TABLE public.lf_operation_execution(execution_id text PRIMARY KEY);
CREATE TABLE public.lf_router_action_registry (asset_type text, action_code text, operation_code text, operation_resolution text,
 requires_existing_target boolean, requires_missing_target boolean, write_allowed boolean, status text, notes text,
 created_by_execution_id text, updated_by_execution_id text, created_at timestamptz, updated_at timestamptz);
INSERT INTO public.lf_router_action_registry(asset_type,action_code,operation_code,status,write_allowed)
 VALUES('REPOSITORY_ARTIFACT','CODE_DEVELOPMENT','DESARROLLO_CODIGO_AGENTE_LF','CANDIDATO_READ_ONLY',false);
GRANT SELECT ON public.lf_router_action_registry TO service_role, supabase_read_only_user;
CREATE TEMP TABLE l(n bigint GENERATED ALWAYS AS IDENTITY, line text);
\copy l(line) FROM 'supabase/migrations/20261026173901_lf_programming_context_handoff_receipt_ledger_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM l
\gexec
TRUNCATE l;
\copy l(line) FROM 'supabase/migrations/20261026230000_lf_programming_development_admission_gate_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM l
\gexec
DO $t1$ DECLARE h jsonb := jsonb_build_object('context_id','c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c','context_sha256',repeat('a',64),
  'target_ref','T','requested_scope_ids',jsonb_build_array('S1'),'producer_execution_ref','EXEC-P',
  'entry_contract_digest_sha256','d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'); g jsonb;
BEGIN
  PERFORM set_config('role','service_role',true);
  g := public.lf_programming_admission_gate_v1(h);
  PERFORM set_config('role','none',true);
  IF g->>'reason' IS DISTINCT FROM 'PG01_GATE_READER_NOT_GRANTED' THEN RAISE EXCEPTION 'REAL_D7_FAIL:not_granted %', g; END IF;
  RAISE NOTICE 'REAL_D7 service_role first: %', g->>'reason';
END $t1$;
DO $t2$ DECLARE h jsonb := jsonb_build_object('context_id','c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c','context_sha256',repeat('a',64),
  'target_ref','T','requested_scope_ids',jsonb_build_array('S1'),'producer_execution_ref','EXEC-P',
  'entry_contract_digest_sha256','d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'); g jsonb;
BEGIN
  g := public.lf_programming_admission_gate_v1(h);
  IF g->>'reason' IS DISTINCT FROM 'PG01_RECEIPT_NOT_FOUND' THEN RAISE EXCEPTION 'REAL_D7_FAIL:not_found %', g; END IF;
  g := public.lf_programming_admission_gate_v1(jsonb_set(h,'{context_id}','"C4F7D9E4-3D29-4D12-950B-0B7EF25E7C5C"'));
  IF g->>'reason' IS DISTINCT FROM 'PG01_GATE_BINDING_INVALID' THEN RAISE EXCEPTION 'REAL_D7_FAIL:uppercase %', g; END IF;
  RAISE NOTICE 'PROGRAMMING_DEVELOPMENT_ADMISSION_REAL_D7_OK';
END $t2$;
ROLLBACK;
