-- M10.7 controlled one-screen measurement request, not a runtime activation.
-- Route: governed SQL queue -> existing 30-second worker. The worker produces
-- real end-to-end phase timings. This changes no rules, triggers or timeouts.
DO $bench$
DECLARE
 v_current jsonb; v_admission jsonb; v_submit jsonb; v_request_id bigint;
 v_prior bigint; v_last bigint;
BEGIN
  IF (SELECT count(*) FROM cron.job WHERE jobname='ig-direct-sql-worker-v1'
          AND active AND schedule='30 seconds'
          AND command='select programacion.fn_input_governance_queue_worker_v1();')<>1 THEN
    RAISE EXCEPTION 'M107_BENCH_SQL_WORKER_NOT_GOVERNED';
  END IF;
  IF EXISTS (SELECT 1 FROM programacion.ig_direct_requests_v1
      WHERE status='QUEUED') THEN
    RAISE EXCEPTION 'M107_BENCH_QUEUE_BUSY';
  END IF;
  IF EXISTS (SELECT 1 FROM programacion.input_readiness_runs
      WHERE pantalla_id=43 AND status IN ('CURATING','VALIDATING')) THEN
    RAISE EXCEPTION 'M107_BENCH_ALREADY_RUNNING';
  END IF;
  SELECT max(id) INTO v_prior FROM programacion.ig_direct_requests_v1
    WHERE pantalla_id=43 AND consumer='MANUAL';
  SELECT max(id) INTO v_last FROM programacion.input_readiness_runs
    WHERE pantalla_id=43;
  IF v_last<>933 OR (SELECT status FROM programacion.input_readiness_runs
      WHERE id=v_last)<>'COMPLETED' THEN
    RAISE EXCEPTION 'M107_BENCH_HISTORICAL_BASELINE_CHANGED:%',v_last;
  END IF;
  v_current:=programacion.fn_input_run_source_currentness_v1(933);
  IF v_current->>'source_current' IS DISTINCT FROM 'false'
      OR v_current->>'authority' IS DISTINCT FROM 'CURRENTNESS_AUTHORITY' THEN
    RAISE EXCEPTION 'M107_BENCH_RECURATION_NOT_REQUIRED';
  END IF;
  v_admission:=programacion.fn_input_governance_execute(43,'MANUAL');
  IF v_admission->>'status' IS DISTINCT FROM 'CURATOR_RUNTIME_REQUIRED' THEN
    RAISE EXCEPTION 'M107_BENCH_ROUTE_NOT_ADMITTED:%',left(v_admission::text,400);
  END IF;
  v_submit:=programacion.fn_input_governance_queue_submit_v1(43,'MANUAL');
  v_request_id:=(v_submit->>'request_id')::bigint;
  IF v_submit->>'status' IS DISTINCT FROM 'QUEUED'
      OR (v_prior IS NOT NULL AND v_request_id<=v_prior)
      OR NOT EXISTS(SELECT 1 FROM programacion.ig_direct_requests_v1
                    WHERE id=v_request_id AND status='QUEUED'
                      AND pantalla_id=43 AND consumer='MANUAL'
                      AND step_count=0) THEN
    RAISE EXCEPTION 'M107_BENCH_QUEUE_RECEIPT_INVALID';
  END IF;
  IF (SELECT count(*) FROM programacion.ig_direct_requests_v1
     WHERE status='QUEUED')<>1 THEN
    RAISE EXCEPTION 'M107_BENCH_EXTRA_QUEUE_WORK';
  END IF;
END $bench$;
