-- Upgrade already-successful one-batch SUNAT ingestion to sequential completion of
-- remaining 478 batches, same operation/source/snapshot/writer, NO payload in migration.
BEGIN;
SET LOCAL lock_timeout='4s';
DO $saly_sunat$
DECLARE v_train text; v_policy jsonb; v_next jsonb; v_found integer;
BEGIN
 SELECT execution_id INTO v_train FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_sequential_authorization_v1'
 AND status='IN_PROGRESS' ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_TRAIN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));
 SELECT config_value::jsonb INTO STRICT v_policy FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
 AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF v_policy->'enabled' IS DISTINCT FROM 'true'::jsonb
 OR v_policy->>'source_id' IS DISTINCT FROM 'PE-SUNAT-RUC'
 OR v_policy->>'pilot_scope' IS DISTINCT FROM 'ONE_GOVERNED_BATCH_ONLY'
 OR v_policy->>'manifest_digest_sha256' IS DISTINCT FROM
    '23350466e89c654e7736de01f1f0d630fec7874713d7ba101a907da08fb27d00'
 OR v_policy->'snapshot_sha256' IS DISTINCT FROM
    '["bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7","2cea288655227dda03d3aaab30c7e63776f3cfb6cc68f75efd56e858865a17d7"]'::jsonb
 OR v_policy->>'reduced_rights_status' IS DISTINCT FROM 'PERSISTENCIA_PERMITIDA'
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')<>1
 OR (SELECT coalesce(sum(filas_reportadas),0) FROM saly.ventas_discovery_ingestas WHERE source_id='PE-SUNAT-RUC')<>1000
 OR (SELECT count(*) FROM saly.ventas_hallazgos h JOIN saly.ventas_discovery_ingestas i
  ON i.id=h.ingesta_id WHERE i.source_id='PE-SUNAT-RUC')<>1000
 OR (SELECT count(*) FROM saly.ventas_discovery_runs
  WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001'
  AND plan_hash=v_policy->>'manifest_digest_sha256')<>1
 OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
  JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
  WHERE r.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001')<>479
 OR (SELECT count(*) FROM saly.ventas_discovery_plan_batches b
  JOIN saly.ventas_discovery_runs r ON r.id=b.run_id
  WHERE r.run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' AND b.estado='FOUND')<>1
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
  WHERE source_id='PE-SUNAT-RUC' AND habilitada AND persist_business_data
  AND rights_status='PERSISTENCIA_PERMITIDA'
  AND runtime_status='CONTROLLED_FIRST_BATCH_PILOT')<>1
 THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_PRESTATE'; END IF;
 v_next:=v_policy||jsonb_build_object(
  'pilot_scope','SEQUENTIAL_ALL_REMAINING_479',
  'pilot_status','SEQUENTIAL_AUTHORIZED_ONE_BATCH_AT_A_TIME',
  'sequential_train_execution_id',v_train,
  'sequential_target_batches',479,
  'sequential_resume_from',2);
 UPDATE saly.ventas_discovery_catalogo
 SET runtime_status='CONTROLLED_SEQUENTIAL_INGESTION'
 WHERE source_id='PE-SUNAT-RUC' AND habilitada AND persist_business_data
 AND runtime_status='CONTROLLED_FIRST_BATCH_PILOT';
 GET DIAGNOSTICS v_found=ROW_COUNT;
 IF v_found<>1 THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_CATALOG'; END IF;
 INSERT INTO public.lf_global_config(scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',v_next::text,'JSON','REAL',
 'SUNAT sequential batch 2..479 on already-pinned official data and existing writer, no parallelism.',
 clock_timestamp());
 IF (SELECT config_value::jsonb FROM public.lf_global_config
  WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
  ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM v_next
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
  WHERE source_id='PE-SUNAT-RUC' AND runtime_status='CONTROLLED_SEQUENTIAL_INGESTION')<>1
 OR has_function_privilege('service_role','saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'SUNAT_SEQUENTIAL_POSTSTATE'; END IF;
END $saly_sunat$;
COMMIT;
