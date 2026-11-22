-- SALY SUNAT physical bulk delete, *armed but not run on migration*.
-- Parent: commercial eligibility PR #4621 must be merged first.
-- Runtime requires governed cancellation, discovery RUN HOLD, and SUNAT source policy disabled.
-- Each authorized call deletes at most 1000 records inside one transaction.
-- Ingest receipts, hashes, and original reported row counts remain immutable.
BEGIN;
SET LOCAL lock_timeout='3s';

DO $pre$
BEGIN
 IF to_regclass('saly.ventas_sunat_elegibilidad_v1') IS NULL
    OR to_regclass('saly.ventas_hallazgos') IS NULL
    OR to_regclass('saly.ventas_discovery_ingestas') IS NULL
    OR to_regclass('saly.ventas_sunat_purge_queue_v1') IS NOT NULL
    OR to_regprocedure('saly.ventas_sunat_purge_step_v1(text,integer)') IS NOT NULL
 THEN RAISE EXCEPTION 'SALY_SUNAT_PURGE_PRESTATE_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_operation_execution
     WHERE operation_code='ACTUALIZACION_DB_LF'
       AND target_type='MIGRATION'
       AND target_code LIKE '%lf_saly_sunat_bulk_delete_v1'
       AND status='IN_PROGRESS')<>1
 THEN RAISE EXCEPTION 'SALY_SUNAT_PURGE_TRAIN_REQUIRED'; END IF;
END $pre$;

-- Minimal immutable provenance, not a second copy of SUNAT JSON.
CREATE TABLE saly.ventas_sunat_purge_queue_v1 (
  run_ref text NOT NULL,
  hallazgo_id uuid PRIMARY KEY,
  ingesta_id uuid NOT NULL,
  motivo text NOT NULL CHECK (motivo IN (
      'EXCLUIDA_SIN_DATO_EMPLEADOS',
      'EXCLUIDA_MENOS_50_EMPLEADOS',
      'EXCLUIDA_ESTADO',
      'EXCLUIDA_CONDICION')),
  staged_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  CHECK (run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')
);
CREATE INDEX ventas_sunat_purge_pending_v1
ON saly.ventas_sunat_purge_queue_v1(run_ref,removed_at,hallazgo_id);
REVOKE ALL ON saly.ventas_sunat_purge_queue_v1
FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;

-- This is not a run-control API: an independent governed operation must
-- transition the historical RUN and disable its writer BEFORE purging.
CREATE FUNCTION saly.ventas_sunat_purge_guard_v1(p_run_ref text)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER
SET search_path=pg_catalog,saly,public AS $guard$
DECLARE v_run_status text; v_op_status text; v_lease timestamptz; v_config jsonb;
BEGIN
 IF p_run_ref IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'
 THEN RAISE EXCEPTION 'SUNAT_PURGE_RUN_SCOPE'; END IF;
 SELECT r.estado,o.status,o.lease_expires_at INTO
        v_run_status,v_op_status,v_lease
 FROM saly.ventas_discovery_runs r
 JOIN public.lf_operation_execution o ON o.execution_id=r.run_ref
 WHERE r.run_ref=p_run_ref
 FOR SHARE OF r,o;
 IF NOT FOUND OR v_run_status IS DISTINCT FROM 'HOLD'
    OR v_op_status IS NULL
    OR v_op_status NOT IN ('CANCELLED','ABANDONED','SUPERSEDED')
    OR (v_lease IS NOT NULL AND v_lease>now())
 THEN RAISE EXCEPTION 'SUNAT_PURGE_RUN_NOT_SAFELY_STOPPED'; END IF;

 SELECT config_value::jsonb INTO v_config
 FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
 AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
 ORDER BY valid_from DESC LIMIT 1;
 IF NOT FOUND OR v_config->'enabled' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'SUNAT_PURGE_SOURCE_NOT_DISABLED'; END IF;
 IF coalesce(v_config->>'max_rows','') !~ '^[1-9][0-9]{0,6}$'
 THEN RAISE EXCEPTION 'SUNAT_PURGE_POLICY_BATCH_LIMIT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.ventas_unidades_operativas)
 THEN RAISE EXCEPTION 'SUNAT_PURGE_DEPENDENT_UNITS'; END IF;
 RETURN (v_config->>'max_rows')::integer;
END $guard$;

-- One-time snapshot of candidate ids (one JSON scan). Do not recalculate
-- eligibility on every chunk: that was measured to exhaust Disk I/O.
CREATE FUNCTION saly.ventas_sunat_purge_prepare_v1(p_run_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path=pg_catalog,saly,public AS $prepare$
DECLARE v_inserted integer; v_pending bigint; v_total bigint; v_limit integer;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 v_limit:=saly.ventas_sunat_purge_guard_v1(p_run_ref);
 IF EXISTS(SELECT 1 FROM saly.ventas_sunat_purge_queue_v1
           WHERE run_ref=p_run_ref)
 THEN
   SELECT count(*),count(*) FILTER(WHERE removed_at IS NULL)
   INTO v_total,v_pending FROM saly.ventas_sunat_purge_queue_v1
   WHERE run_ref=p_run_ref;
   RETURN jsonb_build_object('result','ALREADY_PREPARED',
     'originally_selected',v_total,'remaining',v_pending);
 END IF;
 INSERT INTO saly.ventas_sunat_purge_queue_v1(run_ref,hallazgo_id,ingesta_id,motivo)
 SELECT p_run_ref,v.hallazgo_id,v.ingesta_id,v.clasificacion_comercial
 FROM saly.ventas_sunat_elegibilidad_v1 v
 WHERE v.run_ref=p_run_ref AND v.clasificacion_comercial<>'ELEGIBLE';
 GET DIAGNOSTICS v_inserted=ROW_COUNT;
 -- The historical manifest and source hashes are unchanged intentionally.
 RETURN jsonb_build_object('result','PREPARED','candidates',v_inserted,
   'limit_per_call',v_limit,'run_ref',p_run_ref);
END $prepare$;

-- Each call is one bounded physical DELETE + atomic provenance update.
-- Uses indexed UUIDs, NOT a repeated 136K JSON scan.
CREATE FUNCTION saly.ventas_sunat_purge_step_v1(
  p_run_ref text,p_max_rows integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER
SET search_path=pg_catalog,saly,public AS $step$
DECLARE v_target integer; v_deleted integer; v_marked integer;
        v_remaining bigint; v_staged bigint; v_limit integer;
BEGIN
 IF p_max_rows IS NULL OR p_max_rows<1
 THEN RAISE EXCEPTION 'SUNAT_PURGE_BATCH_LIMIT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 v_limit:=saly.ventas_sunat_purge_guard_v1(p_run_ref);
 IF p_max_rows>v_limit THEN RAISE EXCEPTION 'SUNAT_PURGE_BATCH_LIMIT'; END IF;
 IF NOT EXISTS(SELECT 1 FROM saly.ventas_sunat_purge_queue_v1
               WHERE run_ref=p_run_ref)
 THEN RAISE EXCEPTION 'SUNAT_PURGE_NOT_PREPARED'; END IF;

 WITH target AS MATERIALIZED (
    SELECT hallazgo_id FROM saly.ventas_sunat_purge_queue_v1
    WHERE run_ref=p_run_ref AND removed_at IS NULL
    ORDER BY hallazgo_id LIMIT p_max_rows FOR UPDATE
 ), deleted AS (
    DELETE FROM saly.ventas_hallazgos h USING target t
    WHERE h.id=t.hallazgo_id
      -- Fail closed if a record became eligible since staging.
      AND NOT (
         CASE WHEN (h.captura_empresarial #>> '{capture,normalized,workers_integer_literal}')
                      ~ '^[0-9]{1,9}$'
              THEN (h.captura_empresarial #>> '{capture,normalized,workers_integer_literal}')::integer>=50
              ELSE false END
         AND upper(btrim(coalesce(h.captura_empresarial #>> '{capture,observations,monthly,raw,Estado}','')))='ACTIVO'
         AND upper(btrim(coalesce(h.captura_empresarial #>> '{capture,observations,reduced,raw,estado}','')))='ACTIVO'
         AND upper(btrim(coalesce(h.captura_empresarial #>> '{capture,observations,monthly,raw,Condicion}','')))='HABIDO'
         AND upper(btrim(coalesce(h.captura_empresarial #>> '{capture,observations,reduced,raw,condicion}','')))='HABIDO')
    RETURNING h.id
 ), marked AS (
    UPDATE saly.ventas_sunat_purge_queue_v1 p SET removed_at=now()
    FROM deleted d WHERE p.hallazgo_id=d.id AND p.run_ref=p_run_ref
    RETURNING p.hallazgo_id
 )
 SELECT (SELECT count(*) FROM target),(SELECT count(*) FROM deleted),
        (SELECT count(*) FROM marked)
 INTO v_target,v_deleted,v_marked;
 IF v_target<>v_deleted OR v_target<>v_marked
 THEN RAISE EXCEPTION 'SUNAT_PURGE_TARGET_COUNT_DRIFT'; END IF;
 SELECT count(*),count(*) FILTER(WHERE removed_at IS NULL)
 INTO v_staged,v_remaining
 FROM saly.ventas_sunat_purge_queue_v1 WHERE run_ref=p_run_ref;
 RETURN jsonb_build_object('result','BATCH_DELETED','deleted',v_deleted,
     'total_staged',v_staged,'remaining',v_remaining);
END $step$;

REVOKE ALL ON FUNCTION saly.ventas_sunat_purge_guard_v1(text),
 saly.ventas_sunat_purge_prepare_v1(text),
 saly.ventas_sunat_purge_step_v1(text,integer)
FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;

COMMENT ON TABLE saly.ventas_sunat_purge_queue_v1 IS
'Physical-delete reconciliation ledger for the specific historical SUNAT run; no original JSON. Never repurpose as the commercial lead table.';
COMMENT ON FUNCTION saly.ventas_sunat_purge_step_v1(text,integer) IS
'Privileged governed operator only. At most SUNAT_POLICY_V1.max_rows UUIDs per transaction. Requires RUN HOLD, terminal operation, disabled SUNAT source, no dependent units. Always read back before another chunk.';
COMMIT;
