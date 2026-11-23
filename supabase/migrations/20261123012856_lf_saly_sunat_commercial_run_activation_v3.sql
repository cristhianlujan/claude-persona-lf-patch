-- SALY SUNAT: activate exactly one new commercial RUN from pinned official data.
-- Owner-authorized 2026-11-22: >=50 employees and ACTIVO/HABIDO in both pads.
-- Existing historical 136 batches and the deleted-row ledger stay untouched.
-- The source payload is NOT in this migration. Main-only native runner loads it.
BEGIN;
SET LOCAL lock_timeout='4s';
SET LOCAL statement_timeout='50s';

DO $saly_commercial_activate$
DECLARE
 v_train text;
 v_old jsonb;
 v_new jsonb;
 v_min_workers text;
 v_roster bigint;
 v_roster_sha text;
 v_old_batches bigint;
 v_old_reported bigint;
 v_current_sunat bigint;
 v_qa_manifest text;
BEGIN
 SELECT execution_id INTO v_train
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
   AND target_type='MIGRATION'
   AND target_code LIKE '%lf_saly_sunat_commercial_run_activation_v3'
   AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_train IS NULL THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_TRAIN_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));

 SELECT config_value::jsonb INTO STRICT v_old
 FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1'
   AND value_type='JSON' AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1 FOR SHARE;
 IF v_old->'enabled' IS DISTINCT FROM 'false'::jsonb
    OR v_old->>'source_id' IS DISTINCT FROM 'PE-SUNAT-RUC'
    OR v_old->>'rights_scope' IS DISTINCT FROM 'SALY_B2B_INTERNAL_BUSINESS_FACTS_LIMA_ICA_RUC20'
    OR v_old->>'reduced_rights_status' IS DISTINCT FROM 'PERSISTENCIA_PERMITIDA'
    OR v_old->>'pilot_execution_id' IS DISTINCT FROM 'EXEC-SALY-SUNAT-PILOT-20261122-001'
    OR v_old->>'manifest_digest_sha256' IS DISTINCT FROM
       '23350466e89c654e7736de01f1f0d630fec7874713d7ba101a907da08fb27d00'
    OR v_old->'snapshot_sha256' IS DISTINCT FROM
       '["bf875a7fdf80c16dfee03210759f497b50a5b9c69a4774ed6fbb92e6dceed0a7","2cea288655227dda03d3aaab30c7e63776f3cfb6cc68f75efd56e858865a17d7"]'::jsonb
    OR v_old->'old_manifest_replay_allowed' IS DISTINCT FROM 'false'::jsonb
    OR v_old->>'pilot_status' IS DISTINCT FROM 'PAUSED_FOR_APPROVED_COMMERCIAL_PURGE'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_OLD_SOURCE_POLICY_DRIFT'; END IF;

 SELECT config_value INTO v_min_workers FROM public.lf_global_config
 WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_COMMERCIAL_MIN_WORKERS_V1'
   AND value_type='INTEGER' AND value_status='REAL' AND valid_from<=now()
 ORDER BY valid_from DESC LIMIT 1;
 IF NOT FOUND OR v_min_workers IS DISTINCT FROM '50'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_MIN_WORKERS_DRIFT'; END IF;

 IF (SELECT count(*) FROM saly.ventas_discovery_runs
     WHERE run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001' AND estado='HOLD')<>1
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_runs
           WHERE run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')
 OR EXISTS(SELECT 1 FROM public.lf_operation_execution
           WHERE execution_id='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')
 OR (SELECT count(*) FROM saly.ventas_discovery_catalogo
     WHERE source_id='PE-SUNAT-RUC' AND habilitada AND persist_business_data
      AND rights_status='PERSISTENCIA_PERMITIDA'
      AND rights_evidence_ref=v_old->>'rights_evidence_ref')<>1
 OR (SELECT count(*) FROM public.lf_operation_registry
     WHERE operation_code='INGESTA_EMPRESARIAL_SALY' AND status='SANDBOX_ACTIVE')<>1
 OR (SELECT count(*) FROM public.lf_operation_contracts
     WHERE operation_code='INGESTA_EMPRESARIAL_SALY'
       AND contract_code='SALY_BUSINESS_INGESTION_V1' AND status='ACTIVE_ENFORCEMENT')<>1
 OR to_regprocedure('saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)') IS NULL
 OR to_regprocedure('saly.ventas_sunat_plan_prepare_v1(text,text,bigint,jsonb)') IS NULL
 OR NOT EXISTS(SELECT 1 FROM pg_trigger
         WHERE tgrelid='saly.ventas_hallazgos'::regclass
           AND tgname='trg_saly_sunat_commercial_admission_v1' AND tgenabled='O')
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_RUN_PRESTATE_DRIFT'; END IF;

 SELECT count(*),coalesce(sum(filas_reportadas),0)
 INTO v_old_batches,v_old_reported FROM saly.ventas_discovery_ingestas
 WHERE source_id='PE-SUNAT-RUC' AND run_ref='EXEC-SALY-SUNAT-PILOT-20261122-001';
 SELECT count(*) INTO v_current_sunat FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE i.source_id='PE-SUNAT-RUC';
 IF v_old_batches<>136 OR v_old_reported<>136000 OR v_current_sunat<>5275
 OR (SELECT count(*) FROM saly.ventas_sunat_bulk_delete_ledger_v1)<>130725
 OR (SELECT count(*) FROM saly.ventas_sunat_elegibilidad_v1
     WHERE clasificacion_comercial<>'ELEGIBLE')<>0
 OR EXISTS(SELECT 1 FROM saly.ventas_unidades_operativas)
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_HISTORICAL_ROWS_DRIFT'; END IF;

 -- Current ALREADY-REGISTERED roster across both SUNAT and PTE, exact order.
 WITH prior AS (
   SELECT DISTINCT h.ruc_candidato AS ruc FROM saly.ventas_hallazgos h
   WHERE h.ruc_candidato ~ '^20[0-9]{9}$'
 )
 SELECT count(*),
   encode(sha256(convert_to('['||coalesce(string_agg(to_json(ruc)::text,',' ORDER BY ruc),'')||']','UTF8')),'hex')
 INTO v_roster,v_roster_sha FROM prior;
 IF v_roster<>5434 OR v_roster_sha IS DISTINCT FROM
    '24dc6c6c9239e1b95a028a5148c42cc4a0047dea9d8660c5de877b25efa058a8'
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_EXISTING_ROSTER_DRIFT'; END IF;

 -- Captured from full, pinned source QA (479 raw batches, remaining 343).
 v_qa_manifest:='40300fa68d60cf5d0147dc985cef6183694768f8798aa4ef1020bdc6180d5595';
 v_new:=v_old||jsonb_build_object(
   'enabled',true,
   'commercial_mode',true,
   'commercial_run_ref','EXEC-SALY-SUNAT-COMMERCIAL-20261123-001',
   'old_manifest_replay_allowed',false,
   'original_manifest_digest_sha256',v_old->>'manifest_digest_sha256',
   'historical_found_batches',136,
   'commercial_source_raw_remaining_rows',342657,
   'commercial_source_excluded_rows',340390,
   'commercial_source_duplicate_existing',28,
   'commercial_existing_roster_count',v_roster,
   'existing_rucs_sha256',v_roster_sha,
   'commercial_source_qa_run','45093635474',
   'commercial_policy_ref','SALY_DISCOVERY/SUNAT_COMMERCIAL_MIN_WORKERS_V1',
   'commercial_authorization_ref','owner_approval_chat_20261122_early_filter_and_new_records',
   'commercial_activation_train_execution_id',v_train,
   'pilot_scope','NEW_COMMERCIAL_RUN_ONLY',
   'manifest_digest_sha256',v_qa_manifest,
   'batch_digest_sha256','53857c092011a416c08cd924e48736d777c6e2d654bfb826ba5866c8a2e30256',
   'max_rows',1000,
   'max_bytes',4194304,
   'max_total_bytes',4194304,
   'expected_rows',2239,
   'expected_batches',3,
   'commercial_expected_total_bytes',3531076
 );

 INSERT INTO public.lf_global_config(
   scope,config_key,config_value,value_type,value_status,description,valid_from)
 VALUES('SALY_DISCOVERY','SUNAT_POLICY_V1',v_new::text,'JSON','REAL',
   'Governed 2239 new SUNAT commercial-only companies from source-pinned verified manifest, excludes 28 PTE repeats, 3 sequential batches, original RUN remains HOLD',
   clock_timestamp());

 IF (SELECT config_value::jsonb FROM public.lf_global_config
    WHERE scope='SALY_DISCOVERY' AND config_key='SUNAT_POLICY_V1' AND value_status='REAL'
    ORDER BY valid_from DESC LIMIT 1) IS DISTINCT FROM v_new
 OR EXISTS(SELECT 1 FROM saly.ventas_discovery_runs
    WHERE run_ref='EXEC-SALY-SUNAT-COMMERCIAL-20261123-001')
 OR (SELECT count(*) FROM saly.ventas_discovery_ingestas
    WHERE source_id='PE-SUNAT-RUC')<>136
 OR (SELECT count(*) FROM saly.ventas_hallazgos h
    JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
    WHERE i.source_id='PE-SUNAT-RUC')<>5275
 OR has_function_privilege('service_role','saly.ventas_sunat_batch_execute_v1(text,text,bigint,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'SUNAT_COMMERCIAL_ACTIVATION_READBACK_FAILED'; END IF;
END $saly_commercial_activate$;
COMMIT;
