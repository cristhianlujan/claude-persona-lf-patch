-- Readback only: before/after source snapshots in the actual SALY schema.
-- Compare the old PTE source fingerprint with its recorded baseline; a new source is a separate group.
SELECT i.source_id,i.source_version,i.scope_key,
       count(h.id) AS filas,
       count(DISTINCT h.ruc_candidato) AS ruc_distintos,
       count(h.id) FILTER (WHERE h.ruc_candidato IS NULL) AS sin_ruc_candidato,
       encode(sha256(convert_to(coalesce(string_agg(
         jsonb_build_array(h.fila_origen,h.external_ref,h.nombre_provisional,
           h.ruc_literal,h.ruc_candidato,h.ubigeo_candidato,h.estado_identidad)::text,
         E'\n' ORDER BY h.fila_origen,h.external_ref),''),'UTF8')),'hex') AS snapshot_fingerprint
FROM saly.ventas_discovery_ingestas i
LEFT JOIN saly.ventas_hallazgos h ON h.ingesta_id=i.id
GROUP BY i.id,i.source_id,i.source_version,i.scope_key
ORDER BY i.source_id;
