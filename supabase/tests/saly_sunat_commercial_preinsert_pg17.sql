\set ON_ERROR_STOP on
-- PostgreSQL 17 disposable synthetic schema. Never use any SALY production DB.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE supabase_read_only_user NOLOGIN;
CREATE SCHEMA saly;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,operation_code text NOT NULL,
 target_type text NOT NULL,target_code text NOT NULL,status text NOT NULL
);
CREATE TABLE public.lf_global_config(
 scope text,config_key text,config_value text,value_type text,
 value_status text,valid_from timestamptz
);
CREATE TABLE saly.ventas_discovery_runs(run_ref text PRIMARY KEY,estado text);
CREATE TABLE saly.ventas_discovery_ingestas(
 id uuid PRIMARY KEY,run_ref text,source_id text
);
CREATE TABLE saly.ventas_hallazgos(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ingesta_id uuid NOT NULL REFERENCES saly.ventas_discovery_ingestas(id),
 ruc_candidato text,captura_empresarial jsonb
);
CREATE FUNCTION saly.ventas_sunat_ingesta_core_v1(uuid,text)
RETURNS uuid LANGUAGE sql AS $$ SELECT $1 $$;
-- Exact JSONB canonicalizer from governed SALY runtime.
CREATE FUNCTION saly.ventas_capture_canonical_v1(v jsonb)
 RETURNS text LANGUAGE sql IMMUTABLE STRICT
 SET search_path TO 'pg_catalog','saly' AS $canonical$
 SELECT CASE jsonb_typeof(v)
 WHEN 'object' THEN (SELECT '{'||coalesce(string_agg(to_json(k)::text||':'||
 saly.ventas_capture_canonical_v1(value),',' ORDER BY k COLLATE "C"),'')||'}'
 FROM jsonb_each(v) e(k,value))
 WHEN 'array' THEN (SELECT '['||coalesce(string_agg(saly.ventas_capture_canonical_v1(value),
 ',' ORDER BY n),'')||']' FROM jsonb_array_elements(v) WITH ORDINALITY e(value,n))
 ELSE v::text END
$canonical$;
INSERT INTO public.lf_operation_execution
(execution_id,operation_code,target_type,target_code,status) VALUES
('EXEC-DB-TRAIN-SYNTH','ACTUALIZACION_DB_LF','MIGRATION',
 '20261123011000_lf_saly_sunat_commercial_preinsert_guard_v1','IN_PROGRESS'),
('EXEC-SALY-SUNAT-PILOT-20261122-001','INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE','PE-SUNAT-RUC','IN_PROGRESS'),
('EXEC-SALY-SUNAT-COMMERCIAL-TEST-001','INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE','PE-SUNAT-RUC','IN_PROGRESS');
INSERT INTO saly.ventas_discovery_runs VALUES
('EXEC-SALY-SUNAT-PILOT-20261122-001','HOLD'),
('EXEC-SALY-SUNAT-COMMERCIAL-TEST-001','EN_EJECUCION');
INSERT INTO saly.ventas_discovery_ingestas VALUES
('00000000-0000-4000-8000-000000000001','EXEC-SALY-SUNAT-PILOT-20261122-001','PE-SUNAT-RUC'),
('00000000-0000-4000-8000-000000000002','EXEC-SALY-SUNAT-COMMERCIAL-TEST-001','PE-SUNAT-RUC'),
('00000000-0000-4000-8000-000000000003','PTE-RUN-SYNTH','PE-PTE');
INSERT INTO public.lf_global_config VALUES
('SALY_DISCOVERY','SUNAT_POLICY_V1',
 '{"enabled":false,"old_manifest_replay_allowed":false}','JSON','REAL',now()-interval '1 hour'),
('SALY_DISCOVERY','SUNAT_COMMERCIAL_MIN_WORKERS_V1','50','INTEGER','REAL',now()-interval '1 hour');

-- Install EXACT production migration from the same branch.
\i supabase/migrations/20261123011000_lf_saly_sunat_commercial_preinsert_guard_v1.sql

-- Fixture-only helper: fabricate versioned capture with correct per-capture SHA.
CREATE FUNCTION public.test_sunat_insert(
 p_ingesta uuid,p_ruc text,p_workers integer,
 p_estado_m text DEFAULT 'ACTIVO',p_estado_r text DEFAULT 'ACTIVO',
 p_condicion_m text DEFAULT 'HABIDO',p_condicion_r text DEFAULT 'HABIDO'
) RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_capture jsonb;v_hash text;
BEGIN
 v_capture:=jsonb_build_object(
  'version','sunat.company.v1','source','SUNAT',
  'normalized',jsonb_build_object('ruc',p_ruc,
      'razon_social','Synthetic source','workers_integer_literal',p_workers),
  'observations',jsonb_build_object(
      'monthly',jsonb_build_object('raw',jsonb_build_object('Estado',p_estado_m,
      'Condicion',p_condicion_m)),
      'reduced',jsonb_build_object('raw',jsonb_build_object('estado',p_estado_r,
      'condicion',p_condicion_r)))
 );
 v_hash:=encode(sha256(convert_to(saly.ventas_capture_canonical_v1(v_capture),'UTF8')),'hex');
 INSERT INTO saly.ventas_hallazgos(ingesta_id,ruc_candidato,captura_empresarial)
 VALUES(p_ingesta,p_ruc,jsonb_build_object('capture',v_capture,'capture_sha256',v_hash));
END $helper$;
CREATE FUNCTION public.test_expect_rejection(p_sql text,p_expected text)
RETURNS void LANGUAGE plpgsql AS $reject$
DECLARE v_caught boolean:=false;
BEGIN
 BEGIN
  EXECUTE p_sql;
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM p_expected THEN
   RAISE EXCEPTION 'TEST_WRONG_REJECTION:% GOT:%',p_expected,SQLERRM;
  END IF;
  v_caught:=true;
 END;
 IF NOT v_caught THEN RAISE EXCEPTION 'TEST_EXPECTED_REJECTION_MISSING:%',p_expected; END IF;
END $reject$;

BEGIN;
-- PTE bypass (source-specific guard), even while SUNAT source is frozen.
INSERT INTO saly.ventas_hallazgos(ingesta_id,ruc_candidato,captura_empresarial)
VALUES ('00000000-0000-4000-8000-000000000003','20000000009',NULL);
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000001',50)$$,
 'SUNAT_COMMERCIAL_POLICY_NOT_ACTIVE');
-- Activate separate synthetic new RUN only after trigger is already installed.
INSERT INTO public.lf_global_config VALUES
('SALY_DISCOVERY','SUNAT_POLICY_V1',
 '{"enabled":true,"commercial_mode":true,"commercial_run_ref":"EXEC-SALY-SUNAT-COMMERCIAL-TEST-001","old_manifest_replay_allowed":false}',
 'JSON','REAL',now());
SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000001',50);
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000002',49)$$,
 'SUNAT_COMMERCIAL_NOT_ELIGIBLE');
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000003',90,'BAJA DE OFICIO')$$,
 'SUNAT_COMMERCIAL_NOT_ELIGIBLE');
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000004',90,'ACTIVO','ACTIVO','NO HABIDO')$$,
 'SUNAT_COMMERCIAL_NOT_ELIGIBLE');
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000005',NULL)$$,
 'SUNAT_COMMERCIAL_CAPTURE_SHAPE');
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000001',90)$$,
 'SUNAT_COMMERCIAL_RUC_ALREADY_REGISTERED');
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000002','20000000009',90)$$,
 'SUNAT_COMMERCIAL_RUC_ALREADY_REGISTERED');
SELECT public.test_expect_rejection(
 $$SELECT public.test_sunat_insert('00000000-0000-4000-8000-000000000001','20000000006',90)$$,
 'SUNAT_COMMERCIAL_NEW_RUN_REQUIRED');
DO $final_check$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_hallazgos)<>2
 OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ingesta_id=
     '00000000-0000-4000-8000-000000000002')<>1
 THEN RAISE EXCEPTION 'TEST_COMMERCIAL_SURVIVORS_WRONG'; END IF;
 RAISE NOTICE 'PASS_SUNAT_EARLY_AND_DB_COMMERCIAL_GUARD_PTE_SAFE_50_VALID_49_NULL_BAD_STATUS_NO_HABIDO_DUPLICATE_OLD_RUN';
END $final_check$;
ROLLBACK;
DO $rolled_back$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_hallazgos)<>0
 OR (SELECT count(*) FROM public.lf_global_config WHERE config_key='SUNAT_POLICY_V1')<>1
 THEN RAISE EXCEPTION 'TEST_COMMERCIAL_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'PASS_SUNAT_COMMERCIAL_PREINSERT_PG17_ROLLBACK';
END $rolled_back$;
