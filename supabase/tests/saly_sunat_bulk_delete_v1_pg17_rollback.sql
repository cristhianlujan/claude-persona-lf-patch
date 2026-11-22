\set ON_ERROR_STOP on
-- Disposable PostgreSQL 17 ONLY. Never connect to LF/SALY production.
-- Apply EXACT parent PR #4621 and child PR #4622 source, then test rollback.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE supabase_read_only_user NOLOGIN;
CREATE SCHEMA saly;

CREATE TABLE public.lf_operation_execution (
 execution_id text PRIMARY KEY,
 operation_code text NOT NULL,
 target_type text NOT NULL,
 target_code text NOT NULL,
 status text NOT NULL,
 lease_expires_at timestamptz
);
CREATE TABLE public.lf_global_config (
 scope text NOT NULL,
 config_key text NOT NULL,
 config_value text NOT NULL,
 value_type text NOT NULL DEFAULT 'JSON',
 value_status text NOT NULL,
 description text,
 valid_from timestamptz NOT NULL
);
CREATE TABLE saly.ventas_discovery_catalogo (source_id text PRIMARY KEY);
CREATE TABLE saly.ventas_discovery_runs (run_ref text PRIMARY KEY, estado text NOT NULL);
CREATE TABLE saly.ventas_discovery_ingestas (
 id uuid PRIMARY KEY,
 source_id text NOT NULL,
 run_ref text NOT NULL,
 batch_key text NOT NULL
);
CREATE TABLE saly.ventas_hallazgos (
 id uuid PRIMARY KEY,
 ingesta_id uuid NOT NULL REFERENCES saly.ventas_discovery_ingestas(id),
 ruc_candidato text,
 nombre_provisional text NOT NULL,
 captura_empresarial jsonb
);
CREATE TABLE saly.ventas_unidades_operativas (
 id uuid PRIMARY KEY,
 registro_id uuid
);
INSERT INTO public.lf_operation_execution
(execution_id,operation_code,target_type,target_code,status,lease_expires_at)
VALUES
 ('TEST-TRAIN-FILTER','ACTUALIZACION_DB_LF','MIGRATION',
  'supabase/migrations/20261122191500_lf_saly_sunat_commercial_filter_v1','IN_PROGRESS',NULL),
 ('TEST-TRAIN-PURGE','ACTUALIZACION_DB_LF','MIGRATION',
  'supabase/migrations/20261122222000_lf_saly_sunat_bulk_delete_v1','IN_PROGRESS',NULL),
 ('EXEC-SALY-SUNAT-PILOT-20261122-001','INGESTA_EMPRESARIAL_SALY','DISCOVERY_SOURCE',
  'PE-SUNAT-RUC','IN_PROGRESS',NULL);
INSERT INTO public.lf_global_config
(scope,config_key,config_value,value_status,valid_from)
VALUES ('SALY_DISCOVERY','SUNAT_POLICY_V1','{"enabled":true,"max_rows":1000}','REAL',now());
INSERT INTO saly.ventas_discovery_catalogo VALUES ('PE-SUNAT-RUC');
INSERT INTO saly.ventas_discovery_runs VALUES
 ('EXEC-SALY-SUNAT-PILOT-20261122-001','EN_EJECUCION');
INSERT INTO saly.ventas_discovery_ingestas VALUES
 ('00000000-0000-4000-8000-000000000001','PE-SUNAT-RUC',
  'EXEC-SALY-SUNAT-PILOT-20261122-001','SYNTHETIC-BATCH-1');

WITH rows (ruc,nrotrab,estado_m,estado_r,cond_m,cond_r) AS (
 VALUES
 ('20000000001',49,'ACTIVO','ACTIVO','HABIDO','HABIDO'),
 ('20000000002',50,'ACTIVO','ACTIVO','HABIDO','HABIDO'),
 ('20000000003',NULL::integer,'ACTIVO','ACTIVO','HABIDO','HABIDO'),
 ('20000000004',75,'ACTIVO','ACTIVO','NO HABIDO','HABIDO'),
 ('20000000005',90,'ACTIVO','BAJA DE OFICIO','HABIDO','HABIDO')
)
INSERT INTO saly.ventas_hallazgos
(id,ingesta_id,ruc_candidato,nombre_provisional,captura_empresarial)
SELECT gen_random_uuid(),'00000000-0000-4000-8000-000000000001'::uuid,
 ruc,'TEST-'||ruc,
 jsonb_build_object('capture', jsonb_build_object(
  'normalized',jsonb_build_object('workers_integer_literal',nrotrab),
  'observations',jsonb_build_object(
    'monthly',jsonb_build_object('raw',jsonb_build_object('Estado',estado_m,'Condicion',cond_m)),
    'reduced',jsonb_build_object('raw',jsonb_build_object('estado',estado_r,'condicion',cond_r))
  )))
FROM rows;

-- Parent migration exactly as checked in, including ACLs and readback.
\i supabase/migrations/20261122191500_lf_saly_sunat_commercial_filter_v1.sql
-- Child migration exactly as checked in; no deletion should occur on installation.
\i supabase/migrations/20261122222000_lf_saly_sunat_bulk_delete_v1.sql

DO $verify_install$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_hallazgos)<>5
  OR (SELECT count(*) FROM saly.ventas_sunat_comercial_v1)<>1
  OR (SELECT count(*) FROM saly.ventas_sunat_purge_queue_v1)<>0
  OR (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_ESTADO')<>1
  OR (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_CONDICION')<>1
  OR (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_MENOS_50_EMPLEADOS')<>1
  OR (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1 WHERE clasificacion_comercial='EXCLUIDA_SIN_DATO_EMPLEADOS')<>1
 THEN RAISE EXCEPTION 'TEST_INSTALL_OR_CLASSIFICATION_FAILED'; END IF;
 IF has_function_privilege('service_role','saly.ventas_sunat_purge_step_v1(text,integer)','EXECUTE')
  OR has_function_privilege('anon','saly.ventas_sunat_purge_step_v1(text,integer)','EXECUTE')
  OR has_function_privilege('authenticated','saly.ventas_sunat_purge_step_v1(text,integer)','EXECUTE')
 THEN RAISE EXCEPTION 'TEST_PURGE_ACCESS_WIDENED'; END IF;
 RAISE NOTICE 'PASS_INSTALL_AND_VIEW_5_ROWS_1_ELIGIBLE_4_REJECTED';
END $verify_install$;

-- Helpers exist only in this disposable database, never in the migration.
CREATE FUNCTION public.test_expect_purge_error(p_call text,p_expected text)
RETURNS void LANGUAGE plpgsql AS $test$
DECLARE v_caught boolean:=false;
BEGIN
 BEGIN
  EXECUTE p_call;
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'TEST_UNEXPECTED_ERROR: expected %, got %',p_expected,SQLERRM;
  END IF;
  v_caught:=true;
 END;
 IF NOT v_caught THEN RAISE EXCEPTION 'TEST_ERROR_NOT_RAISED:%',p_expected; END IF;
END $test$;

-- Each mutating test is transactionally rolled back in the disposable PG17 DB.
BEGIN;
 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001')$$,
  'SUNAT_PURGE_RUN_NOT_SAFELY_STOPPED');

 UPDATE saly.ventas_discovery_runs SET estado='HOLD';
 UPDATE public.lf_operation_execution SET status='CANCELLED'
 WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001';
 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001')$$,
  'SUNAT_PURGE_SOURCE_NOT_DISABLED');
 UPDATE public.lf_global_config SET config_value='{"enabled":false,"max_rows":1000}'
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1';

 INSERT INTO saly.ventas_unidades_operativas
 VALUES (gen_random_uuid(),NULL);
 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001')$$,
  'SUNAT_PURGE_DEPENDENT_UNITS');
 DELETE FROM saly.ventas_unidades_operativas;

 -- Lease, missing/invalid policy thresholds, and altered source data fail closed.
 UPDATE public.lf_operation_execution SET lease_expires_at=now()+interval '5 minutes'
 WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001';
 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001')$$,
  'SUNAT_PURGE_RUN_NOT_SAFELY_STOPPED');
 UPDATE public.lf_operation_execution SET lease_expires_at=NULL
 WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001';
 UPDATE public.lf_global_config SET config_value='{"enabled":false,"max_rows":"INVALID"}'
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1';
 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001')$$,
  'SUNAT_PURGE_POLICY_BATCH_LIMIT');
 UPDATE public.lf_global_config SET config_value='{"enabled":false,"max_rows":1000}'
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1';

 DO $test_prepared$
 DECLARE r jsonb;
 BEGIN
  r:=saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001');
  IF r->>'result'<>'PREPARED' OR (r->>'candidates')::integer<>4
   OR (SELECT count(*) FROM saly.ventas_sunat_purge_queue_v1)<>4
  THEN RAISE EXCEPTION 'TEST_PREPARE_WRONG_RESULT:%',r; END IF;
  r:=saly.ventas_sunat_purge_prepare_v1('EXEC-SALY-SUNAT-PILOT-20261122-001');
  IF r->>'result'<>'ALREADY_PREPARED' OR (r->>'originally_selected')::integer<>4
  THEN RAISE EXCEPTION 'TEST_PREPARE_NOT_IDEMPOTENT:%',r; END IF;
  RAISE NOTICE 'PASS_PREPARE_ONCE_4_REJECTED';
 END $test_prepared$;

 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_step_v1('EXEC-SALY-SUNAT-PILOT-20261122-001',1001)$$,
  'SUNAT_PURGE_BATCH_LIMIT');
 -- If an already-staged row becomes eligible, the batch must ROLLBACK,
 -- never silently mark it as removed.
 UPDATE saly.ventas_hallazgos
 SET captura_empresarial=jsonb_set(captura_empresarial,
      '{capture,normalized,workers_integer_literal}','50'::jsonb)
 WHERE ruc_candidato='20000000003';
 SELECT public.test_expect_purge_error(
  $$SELECT saly.ventas_sunat_purge_step_v1('EXEC-SALY-SUNAT-PILOT-20261122-001',1000)$$,
  'SUNAT_PURGE_TARGET_COUNT_DRIFT');
 UPDATE saly.ventas_hallazgos
 SET captura_empresarial=jsonb_set(captura_empresarial,
      '{capture,normalized,workers_integer_literal}','null'::jsonb)
 WHERE ruc_candidato='20000000003';
 DO $first_batch$
 DECLARE r jsonb;
 BEGIN
   r:=saly.ventas_sunat_purge_step_v1('EXEC-SALY-SUNAT-PILOT-20261122-001',2);
   IF (r->>'deleted')::integer<>2 OR (r->>'remaining')::integer<>2
   THEN RAISE EXCEPTION 'TEST_FIRST_BATCH:%',r; END IF;
   r:=saly.ventas_sunat_purge_step_v1('EXEC-SALY-SUNAT-PILOT-20261122-001',2);
   IF (r->>'deleted')::integer<>2 OR (r->>'remaining')::integer<>0
   THEN RAISE EXCEPTION 'TEST_SECOND_BATCH:%',r; END IF;
   r:=saly.ventas_sunat_purge_step_v1('EXEC-SALY-SUNAT-PILOT-20261122-001',2);
   IF (r->>'deleted')::integer<>0 OR (r->>'remaining')::integer<>0
   THEN RAISE EXCEPTION 'TEST_REPLAY_EMPTY:%',r; END IF;
 END $first_batch$;
 DO $test_deleted$
 BEGIN
   IF (SELECT count(*) FROM saly.ventas_hallazgos)<>1
    OR (SELECT count(*) FROM saly.ventas_hallazgos WHERE ruc_candidato='20000000002')<>1
    OR (SELECT count(*) FROM saly.ventas_sunat_comercial_v1)<>1
    OR (SELECT count(*) FROM saly.ventas_sunat_purge_queue_v1 WHERE removed_at IS NOT NULL)<>4
    OR (SELECT count(*) FROM saly.ventas_discovery_ingestas)<>1
   THEN RAISE EXCEPTION 'TEST_DELETE_READBACK_MISMATCH'; END IF;
   RAISE NOTICE 'PASS_BULK_DELETE_4_REJECTED_1_ELIGIBLE_MANIFEST_INTACT';
 END $test_deleted$;
ROLLBACK;

DO $test_rollback$
BEGIN
 IF (SELECT count(*) FROM saly.ventas_hallazgos)<>5
 OR (SELECT count(*) FROM saly.ventas_sunat_purge_queue_v1)<>0
 OR (SELECT estado FROM saly.ventas_discovery_runs LIMIT 1)<>'EN_EJECUCION'
 OR (SELECT status FROM public.lf_operation_execution
     WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001')<>'IN_PROGRESS'
 THEN RAISE EXCEPTION 'TEST_ROLLBACK_FAILED'; END IF;
 RAISE NOTICE 'PASS_PG17_DISPOSABLE_ROLLBACK_5_ORIGINAL_ROWS';
END $test_rollback$;
