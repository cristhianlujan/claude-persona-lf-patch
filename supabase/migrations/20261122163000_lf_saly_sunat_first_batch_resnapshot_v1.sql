-- SUNAT actual first batch; update source hashes after official read-only remeasurement.
-- Data loaded ONLY by existing governed writer, never through migration SQL.
BEGIN;
SET LOCAL lock_timeout='4s';
DO $sunat$
DECLARE v_train text; v_old jsonb; v_new jsonb; v_updated integer;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_first_batch_resnapshot_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'SUNAT_INSERT_TRAIN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));
 SELECT config_value::jsonb INTO STRICT v_old FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
 AND valid_from<=now() ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF v_old->'enabled' IS DISTINCT FROM 'false'::jsonb
 OR v_old->>'pilot_status' IS DISTINCT FROM 'PAUSED_SOURCE_SNAPSHOT_CHANGED'
 OR v_old->>'manifest_digest_sha256' IS DISTINCT FROM '3e12083fc487a4d1281e69b0868676fa66f0be42ad3d41966662a610545bd77e'
 OR v_old->>'reduced_rights_status' IS DISTINCT FROM 'PERSISTENCIA_PERMITIDA'
 OR v_old->>'rights_scope' IS DISTINCT FROM 'SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20'
 OR v_old->>'pilot_execution_id' IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'
 OR EXISTS(SELECT 1 FROM public.lf_operation_execution WHERE execution_id='EXEC-SALY-SUNAT-PILOT-20261122-001')
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo WHERE source_id='PE-SUNAT-RUC'
 AND rights_status='PERSISTENCIA_PERMITIDA' AND rights_evidence_ref=v_old->>'rights_evidence_ref'
 AND NOT habilitada AND NOT persist_business_data AND runtime_status='SNAPSHOT_CHANGED_REBASELINE_REQUIRED')<>1
 OR (SELECT count(*) FROM public.lf_operation_registry WHERE operation_code='INGESTA_EMPRESARIAL_SALY' AND status='SANDBOX_ACTIVE')<>1
 OR to_regprocedure('saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)') IS NULL
 THEN RAISE EXCEPTION 'SUNAT_INSERT_PRESTATE_DRIFT'; END IF;
 v_new:=v_old||jsonb_build_object(
   'enabled',true,
   'snapshot_sha256',jsonb_build_array(
     'bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7',
     '2cea288655227dda03d3aaab30c7e63776f3cfb6cc68f75efd56e858865a17d7'),
   'manifest_digest_sha256','23350466e89c654e7736de01f1f0d630fec7874713d7ba101a907da08fb27d00',
   'manifest_evidence_ref','github://cristhianlujan/claude-persona-lf-patch/skills/ai_sales_discovery/tests/evidence/sunat_current_20261122.json',
   'max_rows',1000,'max_bytes',4194304,'max_total_bytes',900000000,
   'expected_rows',478657,'expected_batches',479,
   'pilot_status','AUTHORIZED_ONE_BATCH_RETRY',
   'pilot_scope','ONE_GOVERNED_BATCH_ONLY',
   'pilot_retry_train_execution_id',v_train);
 UPDATE saly.ventas_discovery_catalogo
 SET habilitada=true,persist_business_data=true,runtime_status='CONTROLLED_FIRST_BATCH_PILOT'
 WHERE source_id='PE-SUNAT-RUC' AND rights_status='PERSISTENCIA_PERMITIDA'
 AND NOT habilitada AND NOT persist_business_data
 AND runtime_status='SNAPSHOT_CHANGED_REBASELINE_REQUIRED';
 GET DIAGNOSTICS v_updated=ROW_COUNT;
 IF v_updated<>1 THEN RAISE EXCEPTION 'SUNAT_INSERT_CATALOG_DRIFT'; END IF;
 INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',v_new::text,'JSON','REAL',
 'SUNAT one-time first batch with fresh official verified SHA; no repeat/scheduled load.',
 clock_timestamp());
 IF (SELECT config_value::jsonb FROM public.lf_global_config
     WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
     ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM v_new
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
    WHERE source_id='PE-SUNAT-RUC' AND habilitada AND persist_business_data
    AND runtime_status='CONTROLLED_FIRST_BATCH_PILOT')<>1
 OR has_function_privilege('service_role','saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)','EXECUTE')
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')
 THEN RAISE EXCEPTION 'SUNAT_INSERT_POSTSTATE'; END IF;
END $sunat$;
COMMIT;
