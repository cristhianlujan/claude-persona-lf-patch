\set ON_ERROR_STOP on
-- One-use DISPOSABLE PG17 fixture. Uses the exact deployed commercial view DDL
-- extracted from the repository migration by the CI test step.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE supabase_read_only_user NOLOGIN;
CREATE SCHEMA saly;
CREATE TABLE public.lf_operation_execution(
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,
 target_type text NOT NULL,
 target_code text NOT NULL,
 status text NOT NULL,
 lease_expires_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.lf_global_config(
 scope text NOT NULL, config_key text NOT NULL,
 config_value text NOT NULL, value_type text NOT NULL,
 value_status text NOT NULL,valid_from timestamptz NOT NULL,
 description text
);
CREATE TABLE saly.ventas_discovery_runs(run_ref text PRIMARY KEY,estado text NOT NULL);
CREATE TABLE saly.ventas_discovery_ingestas(
 id uuid PRIMARY KEY,source_id text NOT NULL,run_ref text NOT NULL,
 batch_key text NOT NULL, filas_reportadas integer NOT NULL
);
CREATE TABLE saly.ventas_hallazgos(
 id uuid PRIMARY KEY,
 ingesta_id uuid NOT NULL REFERENCES saly.ventas_discovery_ingestas(id),
 ruc_candidato text,
 nombre_provisional text,
 captura_empresarial jsonb
);
CREATE TABLE saly.ventas_unidades_operativas(
 registro_id uuid REFERENCES saly.ventas_hallazgos(id) ON DELETE RESTRICT
);
INSERT INTO public.lf_operation_execution
(execution_id,operation_code,target_type,target_code,status,lease_expires_at)
VALUES ('EXEC-DB-TRAIN-LOCAL-PURGE','ACTUALIZACION_DB_LF','MIGRATION',
 '20261123003500_lf_saly_sunat_bulk_physical_delete_v1','IN_PROGRESS',NULL),
 ('EXEC-SALY-SUNAT-PILOT-20261122-001','INGESTA_EMPRESARIAL_SALY',
 'DISCOVERY_SOURCE','PE-SUNAT-RUC','IN_PROGRESS',now()-interval '5 minutes');
INSERT INTO public.lf_global_config VALUES
 ('SALY_DISCOVERY','SUNAT_POLICY_V1',
  '{"enabled":false,"pilot_execution_id":"EXEC-SALY-SUNAT-PILOT-20261122-001","source_id":"PE-SUNAT-RUC","old_manifest_replay_allowed":false,"max_rows":1000}',
  'JSON','REAL',now()-interval '1 hour','frozen synthetic source'),
 ('SALY_DISCOVERY','SUNAT_COMMERCIAL_MIN_WORKERS_V1','50',
  'INTEGER','REAL',now()-interval '1 hour','threshold');
INSERT INTO saly.ventas_discovery_runs VALUES
 ('EXEC-SALY-SUNAT-PILOT-20261122-001','HOLD');
INSERT INTO saly.ventas_discovery_ingestas
(id,source_id,run_ref,batch_key,filas_reportadas)
SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
'PE-SUNAT-RUC','EXEC-SALY-SUNAT-PILOT-20261122-001',
'SYNTHETIC-'||n,1000 FROM generate_series(1,136) n;

-- Exactly 136,000 synthetic company rows: 5,275 admitted and 130,725 rejected.
INSERT INTO saly.ventas_hallazgos
(id,ingesta_id,ruc_candidato,nombre_provisional,captura_empresarial)
SELECT gen_random_uuid(),
('00000000-0000-4000-8000-'||lpad((((n-1)/1000)+1)::text,12,'0'))::uuid,
lpad(n::text,11,'0'),
'TEST-'||n,
jsonb_build_object('capture',jsonb_build_object(
 'normalized',jsonb_build_object('workers_integer_literal',
   CASE WHEN n<=5275 THEN 50 ELSE 49 END),
 'observations',jsonb_build_object(
   'monthly',jsonb_build_object('raw',jsonb_build_object('Estado','ACTIVO','Condicion','HABIDO')),
   'reduced',jsonb_build_object('raw',jsonb_build_object('estado','ACTIVO','condicion','HABIDO'))
 )))
FROM generate_series(1,136000) n;

\i /tmp/saly-sunat-commercial-views.sql
DO $classification$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1
     WHERE clasificacion_comercial='ELEGIBLE')<>5275
 OR (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1
     WHERE clasificacion_comercial<>'ELEGIBLE')<>130725
 THEN RAISE EXCEPTION 'PG17_SYNTHETIC_CLASSIFICATION_DRIFT'; END IF;
 RAISE NOTICE 'PASS_SYNTHETIC_136000_5275_130725_CLASSIFICATION';
END $classification$;
