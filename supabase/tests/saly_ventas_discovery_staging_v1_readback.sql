-- SALY Ventas Lote 26: readback de los hallazgos canonicos (integra L20 / L25).
-- Ejecutar solo despues de migracion gobernada; L20 antiguo CREATE TABLE debe ser revisado.
-- Cada consulta es read-only. No sustituye PG17 BEGIN/ROLLBACK ni revisiones de CI.
SELECT n.n AS objeto, to_regclass('saly.'||n.n) IS NOT NULL AS existe
FROM unnest(ARRAY[
  'ventas_discovery_ingestas',
  'ventas_hallazgos',
  'ventas_unidades_operativas'
]) n(n) ORDER BY n.n;

SELECT c.relname AS tabla,c.relrowsecurity AS rls_habilitado
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='saly' AND c.relname IN
 ('ventas_discovery_ingestas','ventas_hallazgos','ventas_unidades_operativas')
ORDER BY c.relname;

SELECT table_name,grantee,privilege_type FROM information_schema.role_table_grants
WHERE table_schema='saly'
 AND table_name IN ('ventas_discovery_ingestas','ventas_hallazgos','ventas_unidades_operativas')
 AND grantee IN ('anon','authenticated','PUBLIC') ORDER BY table_name,grantee;

-- Tras importar un lote PTE aprobado: 2.336 registros de referencia (no pre-sertificados).
-- El filtro es por ingesta, no por total global; otras fuentes pueden coexistir.
SELECT i.id,i.source_code,i.source_version,i.estado,i.derechos_verificados,
 i.archivo_sha256,i.filas_reportadas,COUNT(r.id) AS filas_insertadas,
 COUNT(r.id) FILTER (WHERE nullif(btrim(coalesce(r.ruc_literal,'')),'') IS NULL) AS sin_ruc,
 COUNT(DISTINCT r.ruc_candidato) AS ruc_distintos,
 COUNT(r.id) FILTER (WHERE r.ubigeo_candidato LIKE '15%') AS lima,
 COUNT(r.id) FILTER (WHERE r.ubigeo_candidato LIKE '11%') AS ica
FROM saly.ventas_discovery_ingestas i
LEFT JOIN saly.ventas_hallazgos r ON r.ingesta_id=i.id
WHERE i.source_code='PE-PTE-ENTIDADES'
GROUP BY i.id ORDER BY i.creada_en DESC;

SELECT r.ingesta_id,r.ruc_candidato,COUNT(*) AS repeticiones
FROM saly.ventas_hallazgos r
WHERE r.ruc_candidato IS NOT NULL
GROUP BY r.ingesta_id,r.ruc_candidato HAVING COUNT(*)>1
ORDER BY repeticiones DESC,r.ruc_candidato;

SELECT COUNT(*) AS unidades_sin_registro
FROM saly.ventas_unidades_operativas u
LEFT JOIN saly.ventas_hallazgos r ON r.id=u.registro_id
WHERE r.id IS NULL;
