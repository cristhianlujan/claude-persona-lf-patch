-- SALY SUNAT: one governed, atomic, physical bulk DELETE of ineligible historical captures.
-- Explicit Cristhian approval 2026-11-22. No write outside Migration Merge Train.
-- Remove only SUNAT PE-SUNAT-RUC captures belonging to the approved historical RUN;
-- keep ingesta receipts/manifests/hashes immutable, and maintain durable deletion ledger.
BEGIN;
SET LOCAL lock_timeout='4s';
SET LOCAL statement_timeout='15min';

DO $preflight$
DECLARE
 v_training text;
 v_source jsonb;
 v_threshold integer;
 v_run_status text;
 v_op_status text;
 v_lease timestamptz;
 v_orig bigint;
 v_eligible bigint;
 v_excluded bigint;
BEGIN
 SELECT execution_id INTO v_training
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
 AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_bulk_physical_delete_v1'
 AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_training IS NULL THEN RAISE EXCEPTION 'SUNAT_DELETE_TRAIN_REQUIRED'; END IF;
 IF to_regclass('saly.ventas_sunat_bulk_delete_ledger_v1') IS NOT NULL
 OR to_regclass('saly.ventas_sunat_elegibilidad_v1') IS NULL
 THEN RAISE EXCEPTION 'SUNAT_DELETE_MIGRATION_ALREADY_OR_VIEW_MISSING'; END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));

 SELECT r.estado,o.status,o.lease_expires_at
 INTO v_run_status,v_op_status,v_lease
 FROM saly.ventas_discovery_runs r
 JOIN public.lf_operation_execution o ON o.execution_id=r.run_ref
 WHERE r.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001'
 AND o.operation_code='INGESTA_EMPRESARIAL_SALY'
 FOR SHARE OF r,o;
 IF NOT FOUND OR v_run_status IS DISTINCT FROM 'HOLD'
 OR v_op_status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_lease IS NULL OR v_lease>=now()
 THEN RAISE EXCEPTION 'SUNAT_DELETE_RUN_NOT_FROZEN'; END IF;

 SELECT config_value::jsonb INTO v_source FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
 AND value_type='JSON' AND value_status='REAL'
 AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF NOT FOUND OR v_source->'enabled' IS DISTINCT FROM 'false'::jsonb
 OR v_source->>'pilot_execution_id' IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'
 OR v_source->>'source_id' IS DISTINCT FROM 'PE-SUNAT-RUC'
 OR v_source->>'old_manifest_replay_allowed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'SUNAT_DELETE_SOURCE_NOT_DISABLED'; END IF;

 SELECT config_value::integer INTO v_threshold
 FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'
 AND value_type='INTEGER' AND value_status='REAL'
 AND config_value ~ '^[1-9][0-9]{0,7}$'
 AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1;
 IF v_threshold IS DISTINCT FROM 50
 THEN RAISE EXCEPTION 'SUNAT_DELETE_THRESHOLD_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM saly.ventas_unidades_operativas)
 THEN RAISE EXCEPTION 'SUNAT_DELETE_DOWNSTREAM_DEPENDENTS'; END IF;

 SELECT count(*) INTO v_orig FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE i.source_id='PE-SUNAT-RUC'
 AND i.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001';
 IF v_orig<>136000 THEN RAISE EXCEPTION 'SUNAT_DELETE_BASELINE_DRIFT:%',v_orig; END IF;

 SELECT count(*) FILTER (WHERE clasificacion_comercial='ELEGIBLE'),
        count(*) FILTER (WHERE clasificacion_comercial<>'ELEGIBLE')
 INTO v_eligible,v_excluded
 FROM saly.ventas_sunat_elegibilidad_v1
 WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001';
 IF v_eligible<>5275 OR v_excluded<>130725 OR v_eligible+v_excluded<>v_orig
 THEN RAISE EXCEPTION 'SUNAT_DELETE_CLASSIFICATION_DRIFT:%:%',v_eligible,v_excluded; END IF;
END $preflight$;

CREATE TABLE saly.ventas_sunat_bulk_delete_ledger_v1(
 hallazgo_id uuid PRIMARY KEY,
 ingesta_id uuid NOT NULL,
 run_ref text NOT NULL CHECK (run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001'),
 motivo text NOT NULL CHECK (motivo IN (
 'EXCLUIDA_SIN_DATO_EMPLEADOS',
 'EXCLUIDA_MENOS_50_EMPLEADOS',
 'EXCLUIDA_ESTADO',
 'EXCLUIDA_CONDICION'
 )),
 deleted_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON saly.ventas_sunat_bulk_delete_ledger_v1
 FROM PUBLIC,anon,authenticated,service_role,supabase_read_only_user;

-- One read of normalized eligibility; no repeated full JSON scans.
INSERT INTO saly.ventas_sunat_bulk_delete_ledger_v1(hallazgo_id,ingesta_id,run_ref,motivo)
SELECT hallazgo_id,ingesta_id,run_ref,clasificacion_comercial
FROM saly.ventas_sunat_elegibilidad_v1
WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001'
AND clasificacion_comercial<>'ELEGIBLE';

-- Physical DELETE by UUIDs generated ONLY by approved SUNAT eligibility.
-- One set-based statement avoids 130,725 individual deletes.
DO $delete$
DECLARE v_selected integer;v_removed integer;v_survivors bigint;
        v_ingestas bigint;v_reporting bigint;
BEGIN
 SELECT count(*) INTO v_selected FROM saly.ventas_sunat_bulk_delete_ledger_v1;
 IF v_selected<>130725 THEN RAISE EXCEPTION 'SUNAT_DELETE_LEDGER_DRIFT:%',v_selected; END IF;
 DELETE FROM saly.ventas_hallazgos h
 USING saly.ventas_sunat_bulk_delete_ledger_v1 l
 WHERE h.id=l.hallazgo_id AND h.ingesta_id=l.ingesta_id;
 GET DIAGNOSTICS v_removed=ROW_COUNT;
 IF v_removed<>v_selected THEN RAISE EXCEPTION 'SUNAT_DELETE_REMOVED_DRIFT:%',v_removed; END IF;

 SELECT count(*) INTO v_survivors FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON h.ingesta_id=i.id
 WHERE i.source_id='PE-SUNAT-RUC' AND i.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001';
 IF v_survivors<>5275 THEN RAISE EXCEPTION 'SUNAT_DELETE_SURVIVORS_DRIFT:%',v_survivors; END IF;
 SELECT count(*),coalesce(sum(filas_reportadas),0)
 INTO v_ingestas,v_reporting
 FROM saly.ventas_discovery_ingestas
 WHERE source_id='PE-SUNAT-RUC' AND run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001';
 IF v_ingestas<>136 OR v_reporting<>136000
 THEN RAISE EXCEPTION 'SUNAT_DELETE_HISTORICAL_RECEIPTS_DRIFT:%:%',v_ingestas,v_reporting; END IF;
 IF EXISTS(
   SELECT 1 FROM saly.ventas_sunat_elegibilidad_v1
   WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001'
   AND clasificacion_comercial<>'ELEGIBLE'
 ) THEN RAISE EXCEPTION 'SUNAT_DELETE_INELIGIBLE_SURVIVED'; END IF;
 RAISE NOTICE 'PASS_SALY_SUNAT_PHYSICAL_DELETE_RETAINED_5275_DELETED_130725_INGESTS_136';
END $delete$;

COMMENT ON TABLE saly.ventas_sunat_bulk_delete_ledger_v1 IS
'Immutable minimal tombstone ledger for explicitly approved 2026-11-22 SUNAT physical deletion. Original ingesta headers, declared row counts and hashes intentionally retained.';
COMMIT;
