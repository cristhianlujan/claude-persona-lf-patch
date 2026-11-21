-- READ-ONLY TEMPLATE for the caller, not executable by the skill itself.
-- Query parameters: $1=source_id, $2=source_version, $3=scope_key,
-- $4=jsonb array of exact normalized rows (ordinal/name/ruc/ubigeo).
-- Uses separate COUNT and row matches. Never infer identity from RUC.
WITH expected AS (
 SELECT (x.row->>'fila_origen')::int AS ordinal,
        x.row->>'nombre' AS nombre,
        x.row->>'ruc' AS ruc,
        x.row->>'ubigeo' AS ubigeo
 FROM jsonb_array_elements($4::jsonb) AS x(row)
), ing AS (
 SELECT i.id,i.source_id,i.source_version,i.scope_key,
        i.archivo_sha256,i.filas_reportadas
 FROM saly.ventas_discovery_ingestas i
 WHERE i.source_id=$1 AND i.source_version=$2 AND i.scope_key=$3
), matches AS (
 SELECT i.id,count(h.id) AS matched_count
 FROM ing i CROSS JOIN expected e
 LEFT JOIN saly.ventas_hallazgos h
   ON h.ingesta_id=i.id AND h.fila_origen=e.ordinal
   AND h.nombre_provisional=e.nombre
   AND h.ruc_literal IS NOT DISTINCT FROM e.ruc
   AND h.ubigeo_candidato=e.ubigeo
 GROUP BY i.id
)
SELECT i.source_id,i.source_version,i.scope_key,
 i.archivo_sha256 AS recorded_hash,
 (SELECT count(*) FROM saly.ventas_hallazgos h WHERE h.ingesta_id=i.id)::int AS stored_count,
 coalesce(m.matched_count,0)::int AS matched_count,
 'saly.ventas_discovery_ingestas:'||i.id::text AS readback_ref
FROM ing i LEFT JOIN matches m ON m.id=i.id;
-- Caller must require zero or exactly one ingesta, and reject partial/ambiguous data.
-- A missing ingesta can be NEW_SNAPSHOT_CANDIDATE only after the catalog/version
-- authority is independently verified. The caller maps it into found=false.
