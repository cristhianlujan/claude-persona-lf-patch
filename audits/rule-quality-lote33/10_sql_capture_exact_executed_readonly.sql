-- L33 / consulta efectivamente ejecutada para el corte 235.
-- 2026-11-13 08:36:22.461152+00
-- Fuente: Supabase PG17.6, rol supabase_read_only_user.
-- Derivada de L32/05_freeze_cohorte_asof_readonly.sql F0/F1/F2.
-- Lectura, una sola transacción REPEATABLE READ READ ONLY.
-- Reejecutar produce NUEVO corte y hashes, NO replica el anterior.
-- NO es un recibo firmado de Operaciones; NO DML/DDL ni modificación de RUN.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
WITH frozen AS MATERIALIZED (
 SELECT r.execution_id,r.operation_code,r.status,r.started_at,r.updated_at,
        encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') AS row_sha256
 FROM public.lf_operation_execution r WHERE r.status='IN_PROGRESS'
), profile AS MATERIALIZED (
 SELECT r.execution_id,r.operation_code,r.status,
        encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') AS row_sha256
 FROM public.lf_operation_execution r WHERE r.operation_code='EJECUCION_PERFIL_LF'
), f AS (
 SELECT count(*) AS n,count(DISTINCT execution_id) AS unique_n,
   coalesce(jsonb_agg(execution_id ORDER BY execution_id COLLATE "C"),'[]'::jsonb) AS ids_json,
   coalesce(jsonb_agg(jsonb_build_object(
      'run_id',execution_id,'operation_code',operation_code,'status',status,
      'started_at',started_at,'updated_at',updated_at,'row_sha256',row_sha256
   ) ORDER BY execution_id COLLATE "C"),'[]'::jsonb) AS preimage_json,
   'run_id'||E'\n'||coalesce(string_agg(execution_id||E'\n','' ORDER BY execution_id COLLATE "C"),'') AS csv_ids
 FROM frozen
), p AS (
 SELECT count(*) AS n,count(DISTINCT execution_id) AS unique_n,
   coalesce(jsonb_agg(jsonb_build_object(
      'run_id',execution_id,'operation_code',operation_code,'status',status,
      'row_sha256',row_sha256
   ) ORDER BY execution_id COLLATE "C"),'[]'::jsonb) AS all_61_json
 FROM profile
)
SELECT transaction_timestamp() AS as_of_utc,pg_current_snapshot()::text AS mvcc_snapshot,
 current_user AS db_actor,current_database() AS database_name,
 current_setting('server_version') AS pg_version,
 current_setting('transaction_read_only') AS transaction_read_only,
 current_setting('transaction_isolation') AS isolation,
 f.n AS frozen_count,f.unique_n AS frozen_distinct_count,
 encode(sha256(convert_to(f.ids_json::text,'UTF8')),'hex') AS membership_jsonb_sha256,
 encode(sha256(convert_to(f.preimage_json::text,'UTF8')),'hex') AS preimage_manifest_jsonb_sha256,
 encode(sha256(convert_to(f.csv_ids,'UTF8')),'hex') AS ids_csv_sha256,
 f.ids_json::text AS membership_jsonb_text,
 f.preimage_json::text AS preimage_jsonb_text,
 f.csv_ids AS csv_ids_raw_text,
 p.n AS profile_count_all_statuses,p.unique_n AS profile_distinct_count,
 encode(sha256(convert_to(p.all_61_json::text,'UTF8')),'hex') AS profile61_jsonb_sha256,
 p.all_61_json::text AS profile61_jsonb_text
FROM f CROSS JOIN p;
ROLLBACK;
