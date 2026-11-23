-- Governed one-shot SUNAT writer freeze before destructive SALY purge.
-- Source provenance, immutable catalog rights and signed manifest remain untouched.
-- Must be applied through ACTUALIZACION_DB_LF / LF Merge Train only.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='30s';

DO $freeze$
DECLARE
  v_train text;
  v_prev jsonb;
  v_next jsonb;
  v_run uuid;
  v_updated integer;
  v_opstatus text;
  v_lease timestamptz;
  v_bcount bigint;
BEGIN
  SELECT execution_id INTO v_train FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND target_type='MIGRATION'
    AND target_code LIKE '%lf_saly_sunat_ingest_freeze_for_purge_v1'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC LIMIT 1;
  IF v_train IS NULL THEN RAISE EXCEPTION 'SUNAT_FREEZE_TRAIN_REQUIRED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
  PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));

  SELECT config_value::jsonb INTO STRICT v_prev FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
    AND value_type='JSON' AND value_status='REAL'
    AND valid_from<=now()
  ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
  IF v_prev->'enabled' IS DISTINCT FROM 'true'::jsonb
    OR v_prev->>'pilot_execution_id' IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'
    OR v_prev->>'source_id' IS DISTINCT FROM 'PE-SUNAT-RUC'
  THEN RAISE EXCEPTION 'SUNAT_FREEZE_POLICY_DRIFT'; END IF;

  SELECT status,lease_expires_at INTO STRICT v_opstatus,v_lease
  FROM public.lf_operation_execution
  WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001'
    AND operation_code='INGESTA_EMPRESARIAL_SALY'
  FOR SHARE;
  IF v_opstatus IS DISTINCT FROM 'IN_PROGRESS' OR
     v_lease IS NULL OR v_lease>=now()
  THEN RAISE EXCEPTION 'SUNAT_FREEZE_INGEST_LEASE_ACTIVE_OR_OP_DRIFT'; END IF;

  SELECT id INTO STRICT v_run FROM saly.ventas_discovery_runs
  WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' AND estado='EN_EJECUCION'
  FOR UPDATE;

  SELECT count(*) INTO v_bcount FROM saly.ventas_discovery_ingestas
  WHERE source_id='PE-SUNAT-RUC';
  IF v_bcount<1 THEN RAISE EXCEPTION 'SUNAT_FREEZE_NO_SOURCE_INGESTS'; END IF;

  -- Immutable historical catalog flags are referenced by existing ingestas
  -- through saly_l28_ingesta_catalog_rights_fk; NEVER flip them.
  -- Writer is blocked by SUNAT_POLICY_V1.enabled=false, tested against
  -- saly.ventas_sunat_ingesta_context_v1, not by altering history.
  IF (SELECT count(*) FROM saly.ventas_discovery_catalogo
      WHERE source_id='PE-SUNAT-RUC'
        AND habilitada AND persist_business_data
        AND runtime_status='CONTROLLED_SEQUENTIAL_INGESTION'
        AND rights_status='PERSISTENCIA_PERMITIDA')<>1
  THEN RAISE EXCEPTION 'SUNAT_FREEZE_CATALOG_DRIFT'; END IF;

  v_next:=v_prev||jsonb_build_object(
    'enabled',false,
    'pilot_status','PAUSED_FOR_APPROVED_COMMERCIAL_PURGE',
    'pilot_pause_execution_id',v_train,
    'pilot_prior_batch_count',v_bcount,
    'old_manifest_replay_allowed',false
  );
  INSERT INTO public.lf_global_config(
     scope,config_key,config_value,value_type,value_status,description,valid_from)
  VALUES (
    'SALY_DISCOVERY','SUNAT_POLICY_V1',v_next::text,'JSON','REAL',
    'Freeze prior PE-SUNAT-RUC manifest before governed delete of commercial-ineligible records',
    now());

  UPDATE saly.ventas_discovery_runs SET estado='HOLD'
  WHERE id=v_run AND estado='EN_EJECUCION';
  GET DIAGNOSTICS v_updated=ROW_COUNT;
  IF v_updated<>1 THEN RAISE EXCEPTION 'SUNAT_FREEZE_RUN_STATE_DRIFT'; END IF;

  IF (SELECT config_value::jsonb->'enabled'
    FROM public.lf_global_config
    WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
    AND value_status='REAL'
    ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM 'false'::jsonb
  OR (SELECT estado FROM saly.ventas_discovery_runs WHERE id=v_run) IS DISTINCT FROM 'HOLD'
  OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
      WHERE source_id='PE-SUNAT-RUC'
      AND habilitada AND persist_business_data
      AND runtime_status='CONTROLLED_SEQUENTIAL_INGESTION')<>1
  OR (SELECT count(*) FROM saly.ventas_discovery_ingestas
      WHERE source_id='PE-SUNAT-RUC')<>v_bcount
  THEN RAISE EXCEPTION 'SUNAT_FREEZE_READBACK_FAILED'; END IF;
END $freeze$;
COMMIT;
