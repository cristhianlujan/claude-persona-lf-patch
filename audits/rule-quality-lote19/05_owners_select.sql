-- SOLO SELECT; SHA-256 de JSONB canónico con orden por texto JSONB. No DDL/DML.

-- O1 | n=261 | sha256=9f4e2cf2b772f61e3e661a3412f1b0ad034ecfa6bc8a409325fe6405ac181782
WITH source_rows AS MATERIALIZED (
SELECT table_schema,table_name,ordinal_position,column_name,data_type FROM information_schema.columns WHERE (table_schema='lf_ops' AND table_name IN('perfiles','perfiles_permisos','permisos','empresa_usuarios_perfiles','empresa_usuarios_permisos','b2b_user_company_profiles','b2b_user_company_permissions','reglas','reglas_pantallas','pantallas_perfiles')) OR (table_schema='saly' AND table_name IN('proyecto','reglas')) OR (table_schema='public' AND table_name IN('lf_activos','v_lf_fuente_operativa','lf_profile_selection_registry_v1','lf_strategy_snapshots')) OR (table_schema='programacion' AND table_name IN('perfiles_calidad','input_family_assessments')) ORDER BY table_schema,table_name,ordinal_position
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows) SELECT jsonb_array_length(rows) AS row_count,encode(sha256(convert_to(rows::text,'UTF8')),'hex') result_sha256,rows AS result_rows FROM packed;


-- O2 | n=13 | sha256=0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d
WITH source_rows AS MATERIALIZED (
SELECT 'lf_ops.perfiles' AS objeto,count(*) AS n,count(*) FILTER(WHERE status='VIGENTE') AS vigentes,count(*) FILTER(WHERE status='CANDIDATO') AS candidatos,count(*) FILTER(WHERE is_active) AS activos FROM lf_ops.perfiles
UNION ALL SELECT 'lf_ops.permisos',count(*),0,0,0 FROM lf_ops.permisos
UNION ALL SELECT 'lf_ops.perfiles_permisos',count(*),0,count(*) FILTER(WHERE status='CANDIDATO'),0 FROM lf_ops.perfiles_permisos
UNION ALL SELECT 'lf_ops.empresa_usuarios_perfiles',count(*),0,0,0 FROM lf_ops.empresa_usuarios_perfiles
UNION ALL SELECT 'lf_ops.empresa_usuarios_permisos',count(*),0,0,0 FROM lf_ops.empresa_usuarios_permisos
UNION ALL SELECT 'lf_ops.b2b_user_company_profiles',count(*),0,0,0 FROM lf_ops.b2b_user_company_profiles
UNION ALL SELECT 'lf_ops.b2b_user_company_permissions',count(*),0,0,0 FROM lf_ops.b2b_user_company_permissions
UNION ALL SELECT 'lf_ops.empresa_usuarios',count(*),0,0,0 FROM lf_ops.empresa_usuarios
UNION ALL SELECT 'public.v_lf_fuente_operativa_PERFIL',count(*),0,0,0 FROM public.v_lf_fuente_operativa WHERE tipo_activo='PERFIL'
UNION ALL SELECT 'public.lf_profile_selection_registry_v1',count(*),0,0,0 FROM public.lf_profile_selection_registry_v1
UNION ALL SELECT 'programacion.perfiles_calidad',count(*),0,0,0 FROM programacion.perfiles_calidad
UNION ALL SELECT 'saly.proyecto',count(*),0,0,0 FROM saly.proyecto
UNION ALL SELECT 'saly.reglas',count(*),0,0,0 FROM saly.reglas ORDER BY objeto
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows) SELECT jsonb_array_length(rows) AS row_count,encode(sha256(convert_to(rows::text,'UTF8')),'hex') result_sha256,rows AS result_rows FROM packed;


-- O3 | n=11 | sha256=43d668a83116b87366bdb76f0e04d03dad69bf6ce47928ba04c631acff7223fb
WITH source_rows AS MATERIALIZED (
WITH desired(schema_name,object_name) AS (VALUES ('rule_quality_l13','projects'),('rule_quality_l13','actors'),('rule_quality_l13','families'),('rule_quality_l13','category_family_map'),('rule_quality_l13','l17_actor_subjects'),('lf_ops','perfiles'),('lf_ops','perfiles_permisos'),('lf_ops','empresa_usuarios_perfiles'),('saly','proyecto'),('saly','perfiles'),('public','lf_profile_selection_registry_v1')) SELECT d.schema_name,d.object_name,exists(SELECT 1 FROM information_schema.tables t WHERE t.table_schema=d.schema_name AND t.table_name=d.object_name) AS exists_in_live_catalog FROM desired d ORDER BY d.schema_name,d.object_name
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows) SELECT jsonb_array_length(rows) AS row_count,encode(sha256(convert_to(rows::text,'UTF8')),'hex') result_sha256,rows AS result_rows FROM packed;


-- O4 | n=32 | sha256=f124e594c0208ccc99b2e193f0ca657a7663e4e1c377b87dc0480670be5f2480
WITH source_rows AS MATERIALIZED (
SELECT 'LF_APP_ROLE' AS fuente,profile_code AS codigo,name AS nombre,status AS estado,profile_scope AS alcance FROM lf_ops.perfiles
UNION ALL SELECT 'LF_AGENT_REGISTRY',profile_code,profile_slug,descriptor_status,source_kind FROM public.lf_profile_selection_registry_v1
UNION ALL SELECT 'LF_CANONICAL_ASSET',codigo_activo,nombre_canonico,estado_operativo,coalesce(owner_name,'OWNER_NAME_NULL') FROM public.v_lf_fuente_operativa WHERE tipo_activo='PERFIL'
UNION ALL SELECT 'PROGRAMACION_QUALITY',perfil_codigo,nombre,estado,'QUALITY_PROFILE' FROM programacion.perfiles_calidad
UNION ALL SELECT 'SALY_PROJECT',codigo,nombre,estado,fase FROM saly.proyecto
ORDER BY fuente,codigo
), packed AS (SELECT coalesce(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows) SELECT jsonb_array_length(rows) AS row_count,encode(sha256(convert_to(rows::text,'UTF8')),'hex') result_sha256,rows AS result_rows FROM packed;
