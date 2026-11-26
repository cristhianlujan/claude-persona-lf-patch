-- SALY SUNAT commercial-only governed terminal close. No ingestion, no ZIP.
-- Exact persisted evidence digest independently read back before migration:
-- d04c722a13298468a8daa97a60284ce8766d4adc1a5a8a730f7b0abc4d63e341
-- Existing PG17 negative/positive/concurrency proof: PR #4763.
-- Gate and TTL on SALY: PR #4785. Historical RUN must stay HOLD.
BEGIN;
SET LOCAL lock_timeout='4s';
SET LOCAL statement_timeout='60s';
DO $saly_sunat_terminal$
DECLARE
 v_run_ref constant text := 'EXEC-SALY-SUNAT-COMMERCIAL-20261123-001';
 v_old_ref constant text := 'EXEC-SALY-SUNAT-PILOT-20261122-001';
 v_expected_digest constant text := 'd04c722a13298468a8daa97a60284ce8766d4adc1a5a8a730f7b0abc4d63e341';
 v_run saly.ventas_discovery_runs%ROWTYPE;
 v_digest text;
 v_result jsonb;
 v_train_count integer;
 v_found integer;
 v_rows bigint;
 v_old_state text;
BEGIN
 SELECT count(*) INTO v_train_count
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
 AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_commercial_terminal_close_v1'
 AND status='IN_PROGRESS';
 IF v_train_count<>1 THEN RAISE EXCEPTION 'SUNAT_TERMINAL_TRAIN_REQUIRED'; END IF;

 SELECT * INTO STRICT v_run FROM saly.ventas_discovery_runs
 WHERE run_ref=v_run_ref FOR UPDATE;
 SELECT estado INTO STRICT v_old_state FROM saly.ventas_discovery_runs
 WHERE run_ref=v_old_ref FOR SHARE;
 IF v_run.estado<>'EN_EJECUCION' OR v_old_state<>'HOLD' THEN
   RAISE EXCEPTION 'SUNAT_TERMINAL_PRESTATE_DRIFT';
 END IF;

 SELECT count(*) INTO v_found FROM saly.ventas_discovery_plan_batches
 WHERE run_id=v_run.id AND estado='FOUND';
 SELECT count(*) INTO v_rows FROM saly.ventas_hallazgos h
 JOIN saly.ventas_discovery_ingestas i ON i.id=h.ingesta_id
 WHERE i.run_ref=v_run_ref AND i.source_id='PE-SUNAT-RUC';
 IF v_found<>3 OR v_rows<>2239 THEN
   RAISE EXCEPTION 'SUNAT_TERMINAL_COUNTS_CHANGED';
 END IF;

 SELECT encode(sha256(convert_to(jsonb_build_object(
   'contract','SALY_SUNAT_CLOSE_V1','run_ref',v_run_ref,
   'plan_hash',v_run.plan_hash,'expected_batches',v_found,'expected_rows',v_rows,
   'effect_receipt_digest',(
      SELECT encode(sha256(convert_to(coalesce(jsonb_agg(
        jsonb_build_object('scope',g.effect_scope,'dispatch',g.dispatch_key,'receipt',g.receipt)
        ORDER BY g.effect_scope)::text,'[]'),'UTF8')),'hex')
      FROM public.lf_operation_effect_guard g WHERE g.execution_id=v_run_ref)
 )::text,'UTF8')),'hex') INTO v_digest;
 IF v_digest IS DISTINCT FROM v_expected_digest THEN
   RAISE EXCEPTION 'SUNAT_TERMINAL_EVIDENCE_CHANGED';
 END IF;

 SELECT saly.ventas_sunat_commercial_close_v1(
   v_run_ref,'SALY_SUNAT_TERMINAL_MERGE_TRAIN_V1',
   'SALY_SUNAT_TERMINAL_TRAIN_V1',v_digest) INTO v_result;
 IF v_result->>'result' IS DISTINCT FROM 'SUCCESS'
 OR (v_result->>'rows')::bigint<>2239
 OR (v_result->>'batches')::integer<>3
 OR (v_result->>'effects')::integer<>3 THEN
   RAISE EXCEPTION 'SUNAT_TERMINAL_UNEXPECTED_RECEIPT %',v_result;
 END IF;

 IF (SELECT count(*) FROM saly.ventas_discovery_runs
     WHERE run_ref=v_run_ref AND estado='CERRADO' AND finished_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM public.lf_operation_execution
     WHERE execution_id=v_run_ref AND status='COMPLETED' AND completed_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM saly.ventas_discovery_runs
     WHERE run_ref=v_old_ref AND estado='HOLD')<>1
 THEN RAISE EXCEPTION 'SUNAT_TERMINAL_READBACK_FAILED'; END IF;
 RAISE NOTICE 'PASS_SALY_SUNAT_TERMINAL_CLOSE rows=2239 batches=3 effects=3 digest=%',v_digest;
END $saly_sunat_terminal$;
COMMIT;
