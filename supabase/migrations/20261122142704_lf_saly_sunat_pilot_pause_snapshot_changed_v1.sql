-- Pause one-shot SUNAT pilot after official reduced source changed.
-- No business records were inserted; rights decision remains valid.
BEGIN;
SET LOCAL lock_timeout='4s';
DO $pause$
DECLARE v_exec text; v_prior jsonb; v_next jsonb; v_updated int;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_pilot_pause_snapshot_changed_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'SUNAT_PAUSE_TRAIN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));
 SELECT config_value::jsonb INTO STRICT v_prior
 FROM public.lf_global_config WHERE scope='SALY_DISCOVERY'
 AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
 AND valid_from<=now() ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF v_prior->'enabled' IS DISTINCT FROM 'true'::jsonb
 OR v_prior->>'pilot_scope' IS DISTINCT FROM 'ONE_GOVERNED_BATCH_ONLY'
 OR v_prior->>'pilot_execution_id' IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'
 OR v_prior->>'manifest_digest_sha256' IS DISTINCT FROM '3e12083fc487a4d1281e69b0868676fa66f0be42ad3d41966662a610545bd77e'
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC'
  AND habilitada AND persist_business_data AND runtime_status='CONTROLLED_FIRST_BATCH_PILOT')<>1
 THEN RAISE EXCEPTION 'SUNAT_PAUSE_PRESTATE'; END IF;
 v_next:=v_prior||jsonb_build_object('enabled',false,
 'pilot_status','PAUSED_SOURCE_SNAPSHOT_CHANGED',
 'pilot_failed_run','45032432469',
 'pilot_pause_execution_id',v_exec);
 UPDATE saly.ventas_discovery_catalogo SET habilitada=false,persist_business_data=false,
 runtime_status='SNAPSHOT_CHANGED_REBASELINE_REQUIRED'
 WHERE source_id='PE-SUNAT-RUC' AND habilitada AND persist_business_data
 AND runtime_status='CONTROLLED_FIRST_BATCH_PILOT';
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>1 THEN RAISE EXCEPTION 'SUNAT_PAUSE_CATALOG_DRIFT'; END IF;
 INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',v_next::text,'JSON','REAL',
 'SUNAT first batch paused: official snapshot changed; rebaseline required before restart.',
 clock_timestamp());
 IF (SELECT config_value::jsonb->'enabled' FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
  ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM 'false'::jsonb
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC'
 AND NOT habilitada AND NOT persist_business_data AND rights_status='PERSISTENCIA_PERMITIDA')<>1
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')
 THEN RAISE EXCEPTION 'SUNAT_PAUSE_POSTSTATE'; END IF;
END $pause$;
COMMIT;
