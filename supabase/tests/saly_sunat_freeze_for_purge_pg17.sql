\set ON_ERROR_STOP on
-- Disposable PG17 ONLY. One historical run, no genuine SUNAT personal/company data.
CREATE SCHEMA saly;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,
 target_type text NOT NULL,
 target_code text NOT NULL,
 status text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 lease_expires_at timestamptz
);
CREATE TABLE public.lf_global_config(
 scope text NOT NULL,
 config_key text NOT NULL,
 config_value text NOT NULL,
 value_type text NOT NULL,
 value_status text NOT NULL,
 description text,
 valid_from timestamptz NOT NULL,
 UNIQUE(scope,config_key,valid_from)
);
CREATE TABLE saly.ventas_discovery_catalogo(
 source_id text PRIMARY KEY,
 habilitada boolean NOT NULL,
 persist_business_data boolean NOT NULL,
 runtime_status text NOT NULL,
 rights_status text NOT NULL
);
CREATE TABLE saly.ventas_discovery_runs(
 id uuid PRIMARY KEY,
 run_ref text NOT NULL UNIQUE,
 estado text NOT NULL CHECK(estado IN ('PREPARADO','EN_EJECUCION','PARTIAL','HOLD'))
);
CREATE TABLE saly.ventas_discovery_ingestas (
 id uuid PRIMARY KEY,
 source_id text NOT NULL
);
INSERT INTO public.lf_operation_execution
(execution_id,operation_code,target_type,target_code,status,lease_expires_at)
VALUES
 ('EXEC-DB-TRAIN-SYNTH-FREEZE','ACTUALIZACION_DB_LF','MIGRATION',
  '20261123001500_lf_saly_sunat_ingest_freeze_for_purge_v1','IN_PROGRESS',NULL),
 ('EXEC-SALY-SUNAT-PILOT-20261122-001','INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE',
  'PE-SUNAT-RUC','IN_PROGRESS',now()-interval '5 minutes');
INSERT INTO public.lf_global_config VALUES(
 'SALY_DISCOVERY','SUNAT_POLICY_V1',
 '{"enabled":true,"pilot_execution_id":"EXEC-SALY-SUNAT-PILOT-20261122-001","source_id":"PE-SUNAT-RUC","max_rows":1000}',
 'JSON','REAL','synthetic policy',now()-interval '1 hour');
INSERT INTO saly.ventas_discovery_catalogo VALUES
 ('PE-SUNAT-RUC',true,true,'CONTROLLED_SEQUENTIAL_INGESTION','PERSISTENCIA_PERMITIDA');
INSERT INTO saly.ventas_discovery_runs VALUES
 ('00000000-0000-4000-8000-000000000001','EXEC-SALY-SUNAT-PILOT-20261122-001','EN_EJECUCION');
INSERT INTO saly.ventas_discovery_ingestas VALUES
 ('00000000-0000-4000-8000-000000000002','PE-SUNAT-RUC');

-- Run the EXACT repo migration. Guarded one-transaction freeze, no delete.
\i supabase/migrations/20261123001500_lf_saly_sunat_ingest_freeze_for_purge_v1.sql

DO $assert$
BEGIN
 IF (SELECT estado FROM saly.ventas_discovery_runs
     WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')<>'HOLD'
    OR (SELECT count(*) FROM public.lf_global_config
     WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1')<>2
    OR (SELECT config_value::jsonb->>'enabled'
     FROM public.lf_global_config
     WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
     ORDER BY valid_from DESC LIMIT 1)<>'false'
    OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
     WHERE source_id='PE-SUNAT-RUC' AND NOT habilitada AND NOT persist_business_data
       AND runtime_status='PURGE_FREEZE_OLD_MANIFEST')<>1
    OR (SELECT count(*) FROM saly.ventas_discovery_ingestas
     WHERE source_id='PE-SUNAT-RUC')<>1
    OR (SELECT status FROM public.lf_operation_execution
      WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001')<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'SYNTHETIC_FREEZE_READBACK_FAILED'; END IF;
 RAISE NOTICE 'PASS_SUNAT_FREEZE_POLICY_FALSE_RUN_HOLD_CATALOG_DISABLED_ORIGINAL_OPERATION_UNTOUCHED';
END $assert$;
