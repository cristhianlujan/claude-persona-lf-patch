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
 v_train_id text;
 v_exec public.lf_operation_execution%ROWTYPE;
 v_found integer;
 v_rows bigint;
 v_old_state text;
BEGIN
 SELECT count(*),min(execution_id) INTO v_train_count,v_train_id
 FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF'
 AND target_type='MIGRATION'
 AND target_code LIKE '%lf_saly_sunat_commercial_terminal_close_v1'
 AND status='IN_PROGRESS';
 IF v_train_count<>1 THEN RAISE EXCEPTION 'SUNAT_TERMINAL_TRAIN_REQUIRED'; END IF;

 PERFORM pg_advisory_xact_lock(hashtextextended('SALY:PE-SUNAT-RUC:SEQUENTIAL',0));
 PERFORM pg_advisory_xact_lock(hashtextextended('SALY_DISCOVERY:SUNAT_POLICY_V1',0));
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

 -- BEGIN EXACT ZERO-EXPECTED-POLICY RECONCILIATION (also exercised by PG17).
 -- The INSERT snapshot trigger only materializes a non-NULL aggregate; the
 -- later terminal guard requires the key even for a candidate with no policies.
 -- Reconcile only the original approved commercial execution, never fabricate
 -- a version, backdate a snapshot, relax the trigger, or touch historical RUN.
 SELECT * INTO STRICT v_exec FROM public.lf_operation_execution
 WHERE execution_id=v_run_ref FOR UPDATE;
 IF v_exec.operation_code IS DISTINCT FROM 'INGESTA_EMPRESARIAL_SALY'
 OR v_exec.status IS DISTINCT FROM 'IN_PROGRESS'
 OR v_exec.target_type IS DISTINCT FROM 'DISCOVERY_SOURCE'
 OR v_exec.target_code IS DISTINCT FROM 'PE-SUNAT-RUC'
 OR v_exec.manifest ? 'operation_policy_snapshots'
 OR v_exec.manifest ? 'operation_policy_snapshot_at'
 OR v_exec.manifest ? 'operation_policy_snapshot_reconciliation'
 OR v_exec.manifest->'sunat_plan'->>'manifest_digest_sha256' IS DISTINCT FROM v_run.plan_hash
 OR NOT EXISTS (SELECT 1 FROM public.lf_operation_registry o
     WHERE o.operation_code=v_exec.operation_code
       AND o.status='SANDBOX_ACTIVE' AND o.lifecycle_state_code='OP_CANDIDATE'
       AND o.created_at<=v_exec.started_at AND o.updated_at<=v_exec.started_at)
 OR EXISTS (SELECT 1 FROM public.lf_operation_policy_bindings b
     WHERE b.operation_code=v_exec.operation_code)
 OR EXISTS (SELECT 1 FROM public.lf_router_action_registry a
     WHERE a.operation_code=v_exec.operation_code)
 OR EXISTS (SELECT 1 FROM public.v_lf_operation_policy_snapshot s
     WHERE s.operation_code=v_exec.operation_code)
 OR (SELECT count(*) FROM pg_trigger
     WHERE tgrelid='public.lf_operation_execution'::regclass
       AND tgname IN ('trg_00_lf_operation_policy_snapshot_v1','trg_01_lf_operation_policy_snapshot_guard_v1')
       AND tgenabled='O')<>2
 THEN RAISE EXCEPTION 'SUNAT_TERMINAL_POLICY_RECONCILIATION_PRESTATE'; END IF;

 -- Reproduce the actual production failure and verify the lease change rolls
 -- back in its subtransaction before any repair. Do not catch unrelated errors.
 BEGIN
   PERFORM saly.ventas_sunat_commercial_close_v1(
     v_run_ref,'SALY_SUNAT_TERMINAL_MERGE_TRAIN_V1',
     'SALY_SUNAT_TERMINAL_TRAIN_V1',v_digest);
   RAISE EXCEPTION 'SUNAT_TERMINAL_EXPECTED_POLICY_REJECTION_NOT_OBSERVED';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   IF SQLERRM IS DISTINCT FROM format(
       'BLOCK_OPERATION_POLICY_MISSING execution=%s operation=%s',
       v_run_ref,v_exec.operation_code) THEN RAISE; END IF;
   RAISE NOTICE 'PASS_SUNAT_TERMINAL_REPRODUCED SQLSTATE=P0001 BLOCK_OPERATION_POLICY_MISSING';
 END;
 IF NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
    WHERE e.execution_id=v_run_ref AND e.status=v_exec.status
      AND e.lease_fence=v_exec.lease_fence
      AND e.lease_owner IS NOT DISTINCT FROM v_exec.lease_owner
      AND e.lease_expires_at IS NOT DISTINCT FROM v_exec.lease_expires_at
      AND e.manifest=v_exec.manifest)
 OR NOT EXISTS (SELECT 1 FROM saly.ventas_discovery_runs r
    WHERE r.run_ref=v_run_ref AND r.estado='EN_EJECUCION' AND r.finished_at IS NULL)
 THEN RAISE EXCEPTION 'SUNAT_TERMINAL_NEGATIVE_ROLLBACK_FAILED'; END IF;

 -- The canonical policy view and both binding sources contain zero rows for
 -- this unchanged candidate. Represent that exact empty set explicitly; the
 -- reconciliation timestamp is NOT an operation-start snapshot timestamp.
 UPDATE public.lf_operation_execution e
 SET manifest=e.manifest||jsonb_build_object(
       'operation_policy_snapshots',coalesce((SELECT jsonb_object_agg(s.policy_role,
           jsonb_build_object('policy_code',s.policy_code,'policy_version',s.policy_version,
             'policy_sha',s.policy_sha,'effective_at',s.effective_at))
         FROM public.v_lf_operation_policy_snapshot s
         WHERE s.operation_code=e.operation_code),'{}'::jsonb),
       'operation_policy_snapshot_reconciliation',jsonb_build_object(
         'mode','EXPLICIT_ZERO_EXPECTED_POLICY_SET',
         'source','public.v_lf_operation_policy_snapshot',
         'expected_count',0,'observed_at',now(),
         'original_started_at',v_exec.started_at,'train_execution_id',v_train_id)),
     updated_by_execution_id=v_train_id
 WHERE e.execution_id=v_run_ref AND e.status='IN_PROGRESS'
   AND e.manifest=v_exec.manifest
   AND NOT EXISTS(SELECT 1 FROM public.lf_operation_policy_bindings b WHERE b.operation_code=e.operation_code)
   AND NOT EXISTS(SELECT 1 FROM public.lf_router_action_registry a WHERE a.operation_code=e.operation_code)
   AND NOT EXISTS(SELECT 1 FROM public.v_lf_operation_policy_snapshot s WHERE s.operation_code=e.operation_code);
 IF NOT FOUND OR (SELECT manifest->'operation_policy_snapshots'
     FROM public.lf_operation_execution WHERE execution_id=v_run_ref) IS DISTINCT FROM '{}'::jsonb
 THEN RAISE EXCEPTION 'SUNAT_TERMINAL_POLICY_RECONCILIATION_READBACK'; END IF;
 -- END EXACT ZERO-EXPECTED-POLICY RECONCILIATION.

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
