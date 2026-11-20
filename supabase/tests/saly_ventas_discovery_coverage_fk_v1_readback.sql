-- L28 read-only readback AFTER governed migration. No production mutation.
SELECT obj AS tabla,to_regclass('saly.'||obj) IS NOT NULL AS desplegada
FROM unnest(ARRAY[
 'ventas_discovery_catalogo','ventas_discovery_runs',
 'ventas_discovery_plan_fuentes','ventas_discovery_plan_batches',
 'ventas_discovery_ejecuciones','ventas_discovery_consultas',
 'ventas_discovery_ingestas','ventas_hallazgos','ventas_unidades_operativas']) obj ORDER BY obj;

SELECT c.relname AS tabla,c.relrowsecurity AS rls
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='saly' AND c.relname IN (
 'ventas_discovery_catalogo','ventas_discovery_runs',
 'ventas_discovery_plan_fuentes','ventas_discovery_plan_batches',
 'ventas_discovery_ejecuciones','ventas_discovery_consultas',
 'ventas_discovery_ingestas','ventas_hallazgos','ventas_unidades_operativas')
ORDER BY c.relname;

SELECT conrelid::regclass::text AS tabla, conname,confrelid::regclass::text AS referencia
FROM pg_constraint
WHERE contype='f' AND connamespace='saly'::regnamespace
 AND conrelid IN (
 'saly.ventas_discovery_plan_fuentes'::regclass,
 'saly.ventas_discovery_plan_batches'::regclass,
 'saly.ventas_discovery_ejecuciones'::regclass,
 'saly.ventas_discovery_consultas'::regclass,
 'saly.ventas_discovery_ingestas'::regclass,
 'saly.ventas_hallazgos'::regclass)
ORDER BY tabla,conname;

SELECT table_name,grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='saly'
 AND table_name IN ('ventas_discovery_catalogo','ventas_discovery_runs',
 'ventas_discovery_plan_fuentes','ventas_discovery_plan_batches',
 'ventas_discovery_ejecuciones','ventas_discovery_consultas')
 AND grantee IN ('PUBLIC','anon','authenticated') ORDER BY table_name,grantee;

-- Coverage diagnostics: snapshot is incomplete until every catalogued source
-- has a planning decision; COUNT DISTINCT over all source scopes is intentional.
SELECT r.run_ref,r.estado,
 COUNT(DISTINCT c.source_id) AS fuentes_catalogadas,
 COUNT(DISTINCT pf.source_id) AS fuentes_planificadas,
 COUNT(DISTINCT pf.source_id) FILTER (WHERE pf.seleccion='UNASSESSED') AS sin_evaluar,
 COUNT(DISTINCT e.source_id) FILTER (WHERE e.estado IN ('FOUND','EMPTY')) AS fuentes_consultadas,
 COUNT(DISTINCT pf.source_id) FILTER (WHERE pf.seleccion IN ('REQUIRED','IN_SCOPE')
  AND e.id IS NULL) AS fuentes_requeridas_sin_ejecucion
FROM saly.ventas_discovery_runs r
LEFT JOIN saly.ventas_discovery_catalogo c ON c.catalog_version=r.catalog_version
LEFT JOIN saly.ventas_discovery_plan_fuentes pf
 ON pf.run_id=r.id AND pf.source_id=c.source_id
LEFT JOIN saly.ventas_discovery_ejecuciones e
 ON e.run_id=pf.run_id AND e.source_id=pf.source_id AND e.scope_key=pf.scope_key
GROUP BY r.id,r.run_ref,r.estado ORDER BY r.run_ref;

-- Source/receipt linkage: count only on exact join; records are not CRM entities.
SELECT i.run_ref,i.catalog_version,i.source_id,i.connector_id,i.substep_code,
 i.scope_key,i.batch_key,i.query_hash,
 COUNT(h.id) AS hallazgos,
 COUNT(h.id) FILTER (WHERE h.ruc_candidato IS NULL) AS sin_ruc,
 COUNT(DISTINCT h.ruc_candidato) AS ruc_distintos
FROM saly.ventas_discovery_ingestas i
JOIN saly.ventas_discovery_consultas q ON q.id=i.consulta_id
LEFT JOIN saly.ventas_hallazgos h ON h.ingesta_id=i.id
GROUP BY i.id ORDER BY i.run_ref,i.source_id,i.batch_key;
