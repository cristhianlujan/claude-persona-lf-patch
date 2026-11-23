-- SALY U07 read-only per-channel registered inventory.
-- Counts from social publications (not searches, crawl attempts or SUNAT hallazgos).
-- Min/max = publication date America/Lima; no post => NULL range.
WITH expected(grupo,canal,source_id,orden) AS (
 VALUES
 ('RED_SOCIAL','Facebook','PE-FACEBOOK',1),
 ('RED_SOCIAL','Instagram','PE-INSTAGRAM',2),
 ('RED_SOCIAL','LinkedIn','PE-LINKEDIN',3),
 ('RED_SOCIAL','TikTok','PE-TIKTOK',4),
 ('RED_SOCIAL','YouTube','PE-YOUTUBE',5),
 ('OTRO_DIGITAL','Diario Correo / noticias','PE-NEWS-FACTS-CORREO',10),
 ('OTRO_DIGITAL','Webs corporativas','PE-WEBS-CORPORATIVAS',11),
 ('OTRO_DIGITAL','Revistas digitales','PE-REVISTAS-DIGITALES',12),
 ('OTRO_DIGITAL','Foros','PE-FOROS',13),
 ('OTRO_DIGITAL','Otros medios digitales','PE-OTROS-MEDIOS',14)
), stored AS (
 SELECT source_id,count(*)::bigint as registros,min(published_at) as desde,max(published_at) as hasta
 FROM saly.ventas_social_publicaciones_v1 GROUP BY source_id
), concurrence AS (
 SELECT confirming_source_id as source_id,count(*)::bigint as coincidencias
 FROM saly.ventas_social_concurrencias_v1 GROUP BY confirming_source_id
), known AS (
 SELECT grupo,canal,source_id,orden FROM expected
 UNION ALL
 SELECT CASE WHEN p.source_id ILIKE ANY(ARRAY['%FACEBOOK%','%INSTAGRAM%','%LINKEDIN%','%TIKTOK%','%YOUTUBE%','%TWITTER%'])
   THEN 'RED_SOCIAL' ELSE 'OTRO_DIGITAL' END,p.source_id,p.source_id,99
 FROM (SELECT source_id FROM saly.ventas_social_publicaciones_v1
       UNION SELECT confirming_source_id as source_id FROM saly.ventas_social_concurrencias_v1) p
 WHERE NOT EXISTS (SELECT 1 FROM expected e WHERE e.source_id=p.source_id)
)
SELECT a.grupo,a.canal,a.source_id,
  COALESCE(s.registros,0) as registros_registrados,
  (s.desde AT TIME ZONE 'America/Lima')::date as desde_publicacion,
  (s.hasta AT TIME ZONE 'America/Lima')::date as hasta_publicacion,
  COALESCE(k.coincidencias,0) as concurrencias_intercanal,
  CASE WHEN c.source_id IS NULL THEN 'NO_REGISTRADA'
       WHEN c.habilitada THEN 'REGISTRADA_HABILITADA'
       ELSE 'REGISTRADA_NO_HABILITADA' END as estado_catalogo
FROM known a
LEFT JOIN stored s USING(source_id)
LEFT JOIN concurrence k USING(source_id)
LEFT JOIN LATERAL(
 SELECT source_id,habilitada FROM saly.ventas_discovery_catalogo c
 WHERE c.source_id=a.source_id ORDER BY c.created_at DESC LIMIT 1
) c ON true
ORDER BY CASE WHEN a.grupo='RED_SOCIAL' THEN 0 ELSE 1 END,a.orden,a.canal;