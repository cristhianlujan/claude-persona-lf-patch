\set ON_ERROR_STOP on
-- Integration check: the admission gate against the REAL readers, not stubs:
-- D7 ledger (20261026173901) -> V2 resolver (20261027091000, PR #3181) -> gate (this PR).
-- Disposable PostgreSQL only; ROLLBACK at the end.
-- Each restricted-role call runs first and in its own DO block: within one transaction
-- PL/pgSQL caches an already-initialized call and does not re-check EXECUTE after a
-- role change, which would make a privilege check pass falsely.
BEGIN;
DO $r$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_read_only_user') THEN CREATE ROLE supabase_read_only_user NOLOGIN; END IF;
END $r$;
CREATE SCHEMA private; CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
-- Mirrors live Supabase (verified 26-oct): both roles have USAGE on private and extensions.
GRANT USAGE ON SCHEMA private, extensions TO service_role, supabase_read_only_user;
-- Minimal prerequisites required by the three migrations' prechecks.
CREATE TABLE private.lf_decision_context_asof_v1(context_id uuid PRIMARY KEY, context_sha256 text);
CREATE TABLE public.lf_operation_execution(
  execution_id text PRIMARY KEY, operation_code text NOT NULL DEFAULT 'X', target_type text NOT NULL DEFAULT 'X',
  target_code text NOT NULL DEFAULT 'X', target_repo text, target_path text, status text NOT NULL DEFAULT 'X',
  started_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz, manifest jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  created_by_execution_id text NOT NULL DEFAULT 'TEST', updated_by_execution_id text, idempotency_key text,
  request_sha256 text, lease_owner text, lease_expires_at timestamptz, lease_fence bigint NOT NULL DEFAULT 0,
  checkpoint_seq bigint NOT NULL DEFAULT 0, checkpoint_payload jsonb NOT NULL DEFAULT '{}');
CREATE TABLE public.lf_operation_execution_steps(execution_id text NOT NULL, step_order integer NOT NULL DEFAULT 1,
  step_id text NOT NULL, status text NOT NULL, evidence_payload jsonb NOT NULL DEFAULT '{}');
GRANT SELECT ON public.lf_operation_execution TO service_role, supabase_read_only_user;
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
\copy l(line) FROM 'supabase/migrations/20261027091000_lf_programming_admission_envelope_v2_resolver_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM l
\gexec
TRUNCATE l;
\copy l(line) FROM 'supabase/migrations/20261026230000_lf_programming_development_admission_gate_v1.sql' WITH (FORMAT csv, DELIMITER E'\x01', QUOTE E'\x02', ESCAPE E'\x03')
SELECT replace(replace(string_agg(coalesce(line,''),E'\n' ORDER BY n),E'BEGIN;\n',''),E'\nCOMMIT;','') FROM l
\gexec

CREATE FUNCTION pg_temp.h(p_ctx text DEFAULT 'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c') RETURNS jsonb LANGUAGE sql AS $q$
  SELECT jsonb_build_object('context_id',p_ctx,'context_sha256',repeat('a',64),
  'target_ref','T','requested_scope_ids',jsonb_build_array('S1'),'producer_execution_ref','EXEC-P',
  'entry_contract_digest_sha256','d2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8') $q$;

-- 1. supabase_read_only_user has no EXECUTE on resolve_v2 -> explicit code, no crash.
DO $t1$ DECLARE g jsonb; BEGIN
  PERFORM set_config('role','supabase_read_only_user',true);
  g := public.lf_programming_admission_gate_v1(pg_temp.h());
  PERFORM set_config('role','none',true);
  IF g->>'reason' IS DISTINCT FROM 'PG01_GATE_READER_NOT_GRANTED' THEN RAISE EXCEPTION 'REAL_FAIL:1_readonly_not_granted %', g; END IF;
END $t1$;

-- 2. service_role (decision 4: the agent) reaches the REAL V2 resolver, which finds no receipt.
DO $t2$ DECLARE g jsonb; BEGIN
  PERFORM set_config('role','service_role',true);
  g := public.lf_programming_admission_gate_v1(pg_temp.h());
  PERFORM set_config('role','none',true);
  IF g->>'reason' IS DISTINCT FROM 'PG01_V2_RECEIPT_NOT_FOUND' OR (g->>'admissible')::boolean IS DISTINCT FROM false
     OR (SELECT count(*) FROM jsonb_object_keys(g)) IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'REAL_FAIL:2_service_role_v2 %', g; END IF;
END $t2$;

-- 3. Owner: same result; an uppercase context_id is stopped before reaching the readers.
DO $t3$ DECLARE g jsonb; BEGIN
  g := public.lf_programming_admission_gate_v1(pg_temp.h());
  IF g->>'reason' IS DISTINCT FROM 'PG01_V2_RECEIPT_NOT_FOUND' THEN RAISE EXCEPTION 'REAL_FAIL:3_owner %', g; END IF;
  g := public.lf_programming_admission_gate_v1(pg_temp.h('C4F7D9E4-3D29-4D12-950B-0B7EF25E7C5C'));
  IF g->>'reason' IS DISTINCT FROM 'PG01_GATE_BINDING_INVALID' THEN RAISE EXCEPTION 'REAL_FAIL:3_uppercase %', g; END IF;
  IF has_function_privilege('supabase_read_only_user','private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)','EXECUTE')
     OR NOT has_function_privilege('service_role','private.fn_lf_programming_context_handoff_receipt_resolve_v2(jsonb)','EXECUTE')
     OR has_function_privilege('service_role','private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'REAL_FAIL:3_acl'; END IF;
  RAISE NOTICE 'PROGRAMMING_DEVELOPMENT_ADMISSION_REAL_READERS_OK';
END $t3$;
ROLLBACK;
