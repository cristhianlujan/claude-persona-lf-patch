-- LOTE 27 | BORRADOR VERIFICACION FUTURA: NO EJECUTADO.
-- Prohibicion del L27: CERO SUPABASE, NI SELECT NUEVO.
-- Fuente historica para n=45 y 0 asignaciones: L19 O2 SHA-256
-- 0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d
-- y L21 S21_01 SHA-256:
-- 4a4eb9eecd7182a6f432f2df1b927733531dc26a58617eb422926f2870c6c933
-- 16 resource_type y cero permisos pricing: AFIRMACION DEL DUEÑO,
-- NO VERIFICADA INDEPENDIENTEMENTE POR SELECT DE L27.
--
-- Este script SOLO CONSULTA; no concede permisos ni define un modelo de permisos.
-- La búsqueda por términos es INDICATIVA, no prueba semántica de inexistencia.
--
-- P27_01 -- PERMISOS Y TIPOS DE RECURSO / CANDIDATOS PRICING (NO EJECUTADO)
WITH source_rows AS MATERIALIZED (
 SELECT
   count(*)::integer AS permisos_total,
   count(DISTINCT to_jsonb(p)->>'resource_type')::integer AS resource_types_distintos,
   count(*) FILTER (WHERE (
       coalesce(to_jsonb(p)->>'resource_type','')||' '||
       coalesce(to_jsonb(p)->>'permission_code','')||' '||
       coalesce(to_jsonb(p)->>'code','')||' '||
       coalesce(to_jsonb(p)->>'name','')||' '||
       coalesce(to_jsonb(p)->>'resource','')||' '||
       coalesce(to_jsonb(p)->>'action','')
     ) ~* '(pricing|precio|cotiza|tarifa|montos|price|quotation)')::integer
     AS posibles_permisos_precio_por_nombre,
   coalesce(
     jsonb_agg(to_jsonb(p) ORDER BY to_jsonb(p)::text)
       FILTER (WHERE (
       coalesce(to_jsonb(p)->>'resource_type','')||' '||
       coalesce(to_jsonb(p)->>'permission_code','')||' '||
       coalesce(to_jsonb(p)->>'code','')||' '||
       coalesce(to_jsonb(p)->>'name','')||' '||
       coalesce(to_jsonb(p)->>'resource','')||' '||
       coalesce(to_jsonb(p)->>'action','')
       ) ~* '(pricing|precio|cotiza|tarifa|montos|price|quotation)'),
     '[]'::jsonb) AS coincidencias_indicativas
 FROM lf_ops.permisos p
),
packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows)
    ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows
)
SELECT 'P27_01_NOT_EXECUTED' AS probe,
 jsonb_array_length(rows) n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- P27_02 -- ASIGNACIONES A USUARIOS EN TABLAS CONOCIDAS (NO EJECUTADO)
WITH source_rows AS MATERIALIZED (
 SELECT
  (SELECT count(*)::integer FROM lf_ops.empresa_usuarios_perfiles) AS empresa_usuarios_perfiles,
  (SELECT count(*)::integer FROM lf_ops.b2b_user_company_profiles) AS b2b_user_company_profiles,
  (SELECT count(*)::integer FROM lf_ops.empresa_usuarios_permisos) AS empresa_usuarios_permisos,
  (SELECT count(*)::integer FROM lf_ops.b2b_user_company_permissions) AS b2b_user_company_permissions
),
packed AS (
 SELECT coalesce(jsonb_agg(to_jsonb(source_rows)
    ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) rows FROM source_rows
)
SELECT 'P27_02_NOT_EXECUTED' AS probe,
 jsonb_array_length(rows) n,
 encode(sha256(convert_to(rows::text,'UTF8')),'hex') AS sha256_result,
 rows AS result_rows FROM packed;

-- RESULTADO P27_01/P27_02: NO_EJECUTADO; SHA-256 NO_EXISTE.
-- Antes de afirmar que 16 tipos no incluyen pricing, confirmar permisos
-- efectivos por CODIGO+RECURSO+ROL (no solo coincidencia textual) en un lote autorizado.
