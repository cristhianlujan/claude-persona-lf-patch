-- IG M10.7, CP3: one-screen governed recuration because source is stale.
-- No force-selftest, no direct runtime changes, no production promotion.
DO $t$
DECLARE
  v_auth jsonb;
  v_check jsonb;
  v_enqueue jsonb;
  v_id bigint;
BEGIN
  IF (SELECT id FROM programacion.input_readiness_runs WHERE pantalla_id=43 ORDER BY id DESC LIMIT 1)<>832
  THEN RAISE EXCEPTION 'M107_FOCAL_RUN_DRIFT'; END IF;
  v_auth:=programacion.fn_input_run_source_currentness_v1(832);
  IF v_auth->>'source_current'<>'false' OR v_auth->>'authority'<>'CURRENTNESS_AUTHORITY'
  THEN RAISE EXCEPTION 'M107_NO_STALE_SOURCE_GAP'; END IF;
  IF (SELECT schedule FROM cron.job WHERE jobid=45)<>'30 seconds'
  THEN RAISE EXCEPTION 'M107_CADENCE_NOT_INSTALLED'; END IF;
  IF EXISTS(SELECT 1 FROM programacion.ig_direct_requests_v1 WHERE status='QUEUED')
  THEN RAISE EXCEPTION 'M107_QUEUE_BUSY'; END IF;
  v_check:=programacion.fn_input_governance_execute(43,'MANUAL');
  IF v_check->>'status'<>'CURATOR_RUNTIME_REQUIRED'
  THEN RAISE EXCEPTION 'M107_ROUTE_NOT_MATERIAL:%',v_check->>'status'; END IF;
  BEGIN
    v_enqueue:=programacion.fn_input_governance_queue_submit_v1(43,'MANUAL');
    RAISE EXCEPTION 'M107_ROLLBACK_TEST' USING ERRCODE='PZ122';
  EXCEPTION WHEN SQLSTATE 'PZ122' THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM programacion.ig_direct_requests_v1 WHERE pantalla_id=43 AND consumer='MANUAL' AND status='QUEUED')
  THEN RAISE EXCEPTION 'M107_ROLLBACK_RESIDUE'; END IF;
  v_enqueue:=programacion.fn_input_governance_queue_submit_v1(43,'MANUAL');
  v_id:=(v_enqueue->>'request_id')::bigint;
  IF v_enqueue->>'status'<>'QUEUED' OR NOT EXISTS(
    SELECT 1 FROM programacion.ig_direct_requests_v1
    WHERE id=v_id AND pantalla_id=43 AND consumer='MANUAL' AND status='QUEUED')
  THEN RAISE EXCEPTION 'M107_QUEUE_RECEIPT_FAILED'; END IF;
END $t$;