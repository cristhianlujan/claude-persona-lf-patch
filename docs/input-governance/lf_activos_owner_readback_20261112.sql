-- LF · owner_name de public.lf_activos: READBACK / DRY-RUN únicamente.
-- No DDL, DML ni llamada a escritores. Ejecutar antes y después del cambio oficial IG.
-- 2026-11-12, referencia histórica: 238 filas; 82 propuestas de cambio.
-- La simulación NO autoriza reclasificar identidades ni corregir archivados.

-- 1. Evidencia de población y distribución REAL.
SELECT count(*) AS total,
       count(*) FILTER (WHERE archived_at IS NULL) AS no_archivados,
       count(*) FILTER (WHERE owner_name IS NULL OR btrim(owner_name) = '') AS sin_owner,
       count(*) FILTER (WHERE owner_name='LF_GOVERNANCE') AS owner_sistema_canonico,
       count(*) FILTER (WHERE owner_name='Cristhian') AS owner_manual_textual,
       count(*) FILTER (WHERE owner_name='SUPER_ADMIN') AS guard_erroneo_como_owner,
       count(DISTINCT owner_name) AS valores_no_nulos,
       md5(string_agg(
         id::text||':'||codigo_activo||':'||coalesce(owner_name,'<NULL>')
         ||':'||coalesce(archived_at::text,'ACTIVE'), '|' ORDER BY id
       )) AS owner_snapshot_md5
FROM public.lf_activos;

-- 2. Mapa de variantes. Repetir antes/después para detectar residuos.
SELECT coalesce(owner_name,'<NULL>') AS owner_name, count(*) AS cantidad,
       count(*) FILTER (WHERE archived_at IS NOT NULL) AS archivados,
       count(*) FILTER (WHERE created_by_execution_id='UNKNOWN') AS origen_sin_run
FROM public.lf_activos
GROUP BY owner_name
ORDER BY cantidad DESC, owner_name;

-- 3. Simulación NO vinculante. Cada fila debe clasificarse con evidencia de procedencia.
WITH plan AS (
  SELECT id,codigo_activo,owner_name,archived_at,
         CASE WHEN owner_name IN ('Cristhian','Cristhian Lujan')
              THEN 'Cristhian' ELSE 'LF_GOVERNANCE' END AS target_owner
  FROM public.lf_activos
)
SELECT count(*) AS total,
       count(*) FILTER (WHERE owner_name IS DISTINCT FROM target_owner) AS candidatos,
       count(*) FILTER (WHERE owner_name IS DISTINCT FROM target_owner AND archived_at IS NULL) AS candidatos_activos,
       count(*) FILTER (WHERE owner_name IS DISTINCT FROM target_owner AND archived_at IS NOT NULL) AS candidatos_archivados,
       count(*) FILTER (WHERE target_owner='LF_GOVERNANCE') AS proyectados_sistema,
       count(*) FILTER (WHERE target_owner='Cristhian') AS proyectados_manual
FROM plan;

-- 4. Readback de guard efectivo. Debe existir prueba real de prevención futura.
SELECT t.tgname, pg_get_triggerdef(t.oid) AS definicion
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname='lf_activos' AND NOT t.tgisinternal
ORDER BY t.tgname;

-- 5. Cierre de datos SOLO cuando oficial IG aporte recibos de 100% de cambios.
-- Esto no comprueba recibos ni juicio semántico; son verificaciones necesarias, no suficientes.
SELECT count(*) AS residuales_no_canonicos_o_nulos
FROM public.lf_activos
WHERE owner_name IS NULL
   OR btrim(owner_name)=''
   OR owner_name NOT IN ('LF_GOVERNANCE','Cristhian');
