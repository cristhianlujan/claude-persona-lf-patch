-- LOTE 21 / SOLO SELECT. Fuentes directas Supabase mhwmirqcgxxukpctffuv.
-- Hash: SHA256 UTF8 del JSONB array completo ordenado por representación JSONB textual de cada fila.
-- Los resultados son un corte; fechas y volúmenes son mutables.

-- S21_01 count=1 sha256=4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933
WITH source_rows AS MATERIALIZED (
SELECT
 (SELECT count(*) FROM lf_ops.reglas) AS lf_total,
 (SELECT count(*) FROM lf_ops.reglas WHERE estado='VIGENTE') AS lf_vigente,
 (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO') AS lf_candidato,
 (SELECT count(*) FROM saly.reglas) AS saly_total,
 (SELECT count(*) FROM saly.reglas WHERE vigente IS TRUE) AS saly_vigente,
 (SELECT count(*) FROM lf_ops.perfiles) AS app_profiles,
 (SELECT count(*) FROM lf_ops.permisos) AS app_permissions,
 (SELECT count(*) FROM lf_ops.perfiles_permisos) AS app_profile_permissions,
 (SELECT count(*) FROM lf_ops.empresa_usuarios_perfiles) AS assigned_user_profiles,
 (SELECT count(*) FROM lf_ops.b2b_user_company_profiles) AS assigned_company_profiles,
 (SELECT count(*) FROM saly.proyecto) AS saly_projects,
 (SELECT count(*) FROM public.lf_operation_execution WHERE status='IN_PROGRESS') AS runs_in_progress,
 (SELECT count(*) FROM public.lf_operation_execution WHERE status='IN_PROGRESS' AND lease_expires_at<=now()) AS expired_leases,
 (SELECT count(*) FROM public.lf_operation_execution WHERE status='IN_PROGRESS' AND now()-started_at>interval '30 days') AS runs_gt_30d
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS payload FROM source_rows) SELECT jsonb_array_length(payload) AS row_count, encode(sha256(convert_to(payload::text,'UTF8')),'hex') AS result_sha256, payload AS result_rows FROM packed;

-- S21_02 count=9 sha256=0a8624c58887c553249137fe556594d311ced96ced7ed4cf12d7af0fa34c7090
WITH source_rows AS MATERIALIZED (
WITH wanted(table_schema,table_name,column_name) AS (VALUES
 ('lf_ops','reglas','reviewed_at'),('lf_ops','reglas','next_review_at'),('lf_ops','reglas','successor_rule_code'),('lf_ops','reglas','effective_to'),
 ('saly','reglas','reviewed_at'),('saly','reglas','next_review_at'),('saly','reglas','successor_rule_code'),('saly','reglas','effective_to'),('saly','reglas','lifecycle_state'))
 SELECT w.table_schema,w.table_name,w.column_name,c.data_type,(c.column_name IS NOT NULL) AS exists_live
 FROM wanted w LEFT JOIN information_schema.columns c
 ON (c.table_schema,c.table_name,c.column_name)=(w.table_schema,w.table_name,w.column_name)
 ORDER BY w.table_schema,w.table_name,w.column_name
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS payload FROM source_rows) SELECT jsonb_array_length(payload) AS row_count, encode(sha256(convert_to(payload::text,'UTF8')),'hex') AS result_sha256, payload AS result_rows FROM packed;

-- S21_03 count=12 sha256=3cff7e13769ed846a69c274f88e4f89cabea989a13c2c6488a6e7acc0ca371ee
WITH source_rows AS MATERIALIZED (
SELECT 'SECURITY_POLICY' AS source,policy_code AS code,status,security_policy_id AS numeric_id FROM lf_ops.politicas_seguridad WHERE security_policy_id IN (3,19,20)
 UNION ALL SELECT 'AUTH_RULE',codigo,estado,NULL::bigint FROM lf_ops.reglas WHERE codigo IN
 ('B2B-RULE-AUTH-003','B2B-RULE-AUTH-018','B2B-RULE-AUTH-019','B2B-RULE-AUTH-022',
 'B2B-RULE-AUTH-026','B2B-RULE-AUTH-033','B2B-RULE-AUTH-034','B2B-RULE-AUTH-044','B2B-RULE-AUTH-045')
 ORDER BY source,code
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS payload FROM source_rows) SELECT jsonb_array_length(payload) AS row_count, encode(sha256(convert_to(payload::text,'UTF8')),'hex') AS result_sha256, payload AS result_rows FROM packed;

-- S21_04 count=4 sha256=344c5611f98c1933f8e6337e53e24b74e3cdda4af7e045ba96335878e7e97016
WITH source_rows AS MATERIALIZED (
SELECT n.nspname AS schema_name,p.proname AS function_name,
 pg_get_function_identity_arguments(p.oid) AS arg_types,p.prosecdef AS security_definer,
 p.provolatile AS volatility
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('lf_rule_promotion_apply_batch_v1','lf_rule_promotion_decide_batch_v1','lf_rule_promotion_report_v1','lf_rule_promotion_guard_v1')
 ORDER BY p.proname
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS payload FROM source_rows) SELECT jsonb_array_length(payload) AS row_count, encode(sha256(convert_to(payload::text,'UTF8')),'hex') AS result_sha256, payload AS result_rows FROM packed;

-- S21_05 count=7 sha256=44e9708a9659dcec3d11e9dcc4ff304a025c23606cce150852058b7a08512f83
WITH source_rows AS MATERIALIZED (
WITH desired(schema_name,table_name) AS (VALUES ('rule_quality_l13','projects'),('rule_quality_l13','actors'),('rule_quality_l13','category_family_map'),('rule_quality_l13','families'),('lf_ops','perfiles'),('lf_ops','perfiles_permisos'),('saly','proyecto'))
 SELECT d.schema_name,d.table_name,exists(SELECT 1 FROM information_schema.tables t WHERE (t.table_schema,t.table_name)=(d.schema_name,d.table_name)) AS exists_live
 FROM desired d ORDER BY d.schema_name,d.table_name
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS payload FROM source_rows) SELECT jsonb_array_length(payload) AS row_count, encode(sha256(convert_to(payload::text,'UTF8')),'hex') AS result_sha256, payload AS result_rows FROM packed;

-- S21_06 count=16 sha256=30967bfb310f175f85bbd171c91a350a6b5c8712b81df662919e607e331f0313
WITH source_rows AS MATERIALIZED (
SELECT 'LF' AS project,codigo AS rule_code,estado AS status FROM lf_ops.reglas WHERE codigo IN('B2B-RULE-AUTH-018','B2B-RULE-AUTH-022')
 UNION ALL SELECT 'SALY',codigo,CASE WHEN vigente THEN 'VIGENTE' ELSE 'NO_VIGENTE' END FROM saly.reglas
 ORDER BY project,rule_code
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS payload FROM source_rows) SELECT jsonb_array_length(payload) AS row_count, encode(sha256(convert_to(payload::text,'UTF8')),'hex') AS result_sha256, payload AS result_rows FROM packed;
