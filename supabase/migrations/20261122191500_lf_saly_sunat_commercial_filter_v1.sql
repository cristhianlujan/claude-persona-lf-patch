-- SALY SUNAT commercial gate, derived only: no deletion, no change to pinned payloads.
-- Eligibility is evaluated at read time, so old and future ingested batches use one filter.
-- Raw monthly/reduced observations, hashes, manifest, counts and PTE are preserved.
BEGIN;
SET LOCAL lock_timeout = '4s';
-- Statement timeout is owned by the canonical Train/session policy.

DO $pre$
DECLARE v_train int;
BEGIN
 SELECT count(*) INTO v_train
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION'
   AND target_code LIKE '%lf_saly_sunat_commercial_filter_v1'
   AND status='IN_PROGRESS';
 IF v_train<>1 THEN RAISE EXCEPTION 'SALY_SUNAT_FILTER_TRAIN_REQUIRED'; END IF;
 IF to_regclass('saly.ventas_sunat_elegibilidad_v1') IS NOT NULL
 OR to_regclass('saly.ventas_sunat_comercial_v1') IS NOT NULL
 OR to_regclass('saly.ventas_hallazgos') IS NULL
 OR to_regclass('saly.ventas_discovery_ingestas') IS NULL
 OR NOT EXISTS (SELECT 1 FROM saly.ventas_discovery_catalogo
                WHERE source_id='PE-SUNAT-RUC')
 THEN RAISE EXCEPTION 'SALY_SUNAT_FILTER_PRESTATE_DRIFT'; END IF;
END $pre$;

-- The raw ingestion remains exact, audit-safe and replay-safe.
-- Fail closed on nulls, unknown statuses, disagreement or non-HABIDO condition.
CREATE VIEW saly.ventas_sunat_elegibilidad_v1
WITH (security_invoker = true, security_barrier = true) AS
SELECT h.id AS hallazgo_id,
       h.ingesta_id,
       i.run_ref,
       i.batch_key,
       h.ruc_candidato AS ruc,
       h.nombre_provisional AS razon_social,
       h.captura_empresarial #>> '{capture,normalized,workers_integer_literal}' AS nrotrab_literal,
       s.estado_mensual,
       s.estado_reducido,
       s.condicion_mensual,
       s.condicion_reducida,
       CASE
         WHEN upper(btrim(coalesce(s.estado_mensual,''))) IS DISTINCT FROM 'ACTIVO'
           OR upper(btrim(coalesce(s.estado_reducido,''))) IS DISTINCT FROM 'ACTIVO'
           THEN 'EXCLUIDA_ESTADO'
         WHEN upper(btrim(coalesce(s.condicion_mensual,''))) IS DISTINCT FROM 'HABIDO'
           OR upper(btrim(coalesce(s.condicion_reducida,''))) IS DISTINCT FROM 'HABIDO'
           THEN 'EXCLUIDA_CONDICION'
         ELSE 'ELEGIBLE'
       END AS clasificacion_comercial
FROM saly.ventas_hallazgos h
JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
CROSS JOIN LATERAL (
  SELECT h.captura_empresarial #>> '{capture,observations,monthly,raw,Estado}' AS estado_mensual,
         h.captura_empresarial #>> '{capture,observations,reduced,raw,estado}' AS estado_reducido,
         h.captura_empresarial #>> '{capture,observations,monthly,raw,Condicion}' AS condicion_mensual,
         h.captura_empresarial #>> '{capture,observations,reduced,raw,condicion}' AS condicion_reducida
) s
WHERE i.source_id='PE-SUNAT-RUC';

-- Only this projection is the SALY commercial entry point.
CREATE VIEW saly.ventas_sunat_comercial_v1
WITH (security_invoker = true, security_barrier = true) AS
SELECT hallazgo_id,ingesta_id,run_ref,batch_key,ruc,razon_social,nrotrab_literal,
       estado_mensual,estado_reducido,condicion_mensual,condicion_reducida
FROM saly.ventas_sunat_elegibilidad_v1
WHERE clasificacion_comercial='ELEGIBLE';

REVOKE ALL ON saly.ventas_sunat_elegibilidad_v1,saly.ventas_sunat_comercial_v1
FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON VIEW saly.ventas_sunat_elegibilidad_v1 IS
'Internal SUNAT provenance-backed eligibility classification; no raw deletion or reclassification of identity. Both official sources must say ACTIVO and HABIDO.';
COMMENT ON VIEW saly.ventas_sunat_comercial_v1 IS
'Internal derived commercial-only SUNAT selection; applies automatically to all persisted batches. New business consumers must use this view, not raw hallazgos. No public grants.';

DO $post$
DECLARE v_raw bigint; v_class bigint; v_eligible bigint; v_comercial bigint;
BEGIN
 IF (SELECT count(*) FROM pg_views
     WHERE schemaname='saly' AND viewname IN
        ('ventas_sunat_elegibilidad_v1','ventas_sunat_comercial_v1'))<>2
 OR has_table_privilege('anon','saly.ventas_sunat_comercial_v1','SELECT')
 OR has_table_privilege('authenticated','saly.ventas_sunat_comercial_v1','SELECT')
 OR has_table_privilege('service_role','saly.ventas_sunat_comercial_v1','SELECT')
 THEN RAISE EXCEPTION 'SALY_SUNAT_FILTER_ACL_DRIFT'; END IF;
 SELECT count(*) INTO v_raw FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE i.source_id='PE-SUNAT-RUC';
 SELECT count(*),count(*) FILTER(WHERE clasificacion_comercial='ELEGIBLE')
 INTO v_class,v_eligible FROM saly.ventas_sunat_elegibilidad_v1;
 SELECT count(*) INTO v_comercial FROM saly.ventas_sunat_comercial_v1;
 IF v_raw<>v_class OR v_eligible<>v_comercial OR
 EXISTS (SELECT 1 FROM saly.ventas_sunat_comercial_v1
         WHERE upper(btrim(coalesce(estado_mensual,'')))<>'ACTIVO'
            OR upper(btrim(coalesce(estado_reducido,'')))<>'ACTIVO'
            OR upper(btrim(coalesce(condicion_mensual,'')))<>'HABIDO'
            OR upper(btrim(coalesce(condicion_reducida,'')))<>'HABIDO')
 THEN RAISE EXCEPTION 'SALY_SUNAT_FILTER_READBACK_DRIFT'; END IF;
 RAISE NOTICE 'SALY_SUNAT_FILTER_READBACK raw=%,eligible=%,excluded=%',
   v_raw,v_eligible,v_raw-v_eligible;
END $post$;
COMMIT;
