-- Lote19; evidencia SOLO SELECT de esquema de heartbeat y conteo de lease/status.

-- H1 n=45 result_sha256=89087ac3d2f71277ef6f82c587d092e910e0b0b2bc33b377d917ae98ebc58385
WITH source_rows AS MATERIALIZED (
SELECT table_schema,table_name,column_name,data_type FROM information_schema.columns WHERE (table_schema='public' AND table_name IN('lf_operation_execution','lf_operation_execution_steps','lf_operation_effect_guard')) OR (table_schema IN('public','lf_ops','saly','programacion') AND column_name ILIKE '%heartbeat%') ORDER BY table_schema,table_name,ordinal_position
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) raw FROM source_rows) SELECT jsonb_array_length(raw) AS n,encode(sha256(convert_to(raw::text,'UTF8')),'hex') AS result_sha256,raw AS result_rows FROM packed;

-- H2 n=1 result_sha256=5b1d438c7d1de6335f54f1a1e398a6dec90a8255bfe3d13c8e42276d31a91d40
WITH source_rows AS MATERIALIZED (
SELECT status,count(*) AS total,count(*) FILTER(WHERE lease_owner IS NOT NULL) AS has_lease_owner,count(*) FILTER(WHERE lease_expires_at IS NOT NULL AND lease_expires_at <= now()) AS expired_lease,count(*) FILTER(WHERE lease_expires_at > now()) AS valid_lease,count(*) FILTER(WHERE lease_expires_at IS NULL) AS without_expiry FROM public.lf_operation_execution WHERE status='IN_PROGRESS' GROUP BY status
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) raw FROM source_rows) SELECT jsonb_array_length(raw) AS n,encode(sha256(convert_to(raw::text,'UTF8')),'hex') AS result_sha256,raw AS result_rows FROM packed;

