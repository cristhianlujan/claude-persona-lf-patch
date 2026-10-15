-- M10.7 / internal, authorized LF performance repair.
-- Scope: cadence of existing pg_cron worker only. No access grants,
-- security bypass, new credentials, new job, code replacement or timeout increase.
-- Current state: job 45 every 60s, existing worker stops after ~30s.
-- EKB IG-SQL-WORKER-BUDGET-OVERRUN-001 prohibits restoring 95s worker.
DO $m107$
DECLARE
  v_job bigint;
  v_original text;
  v_trial int;
BEGIN
  SELECT jobid,schedule INTO STRICT v_job,v_original
  FROM cron.job
  WHERE command='select programacion.fn_input_governance_queue_worker_v1();'
    AND active=true AND username='postgres' AND database='postgres';
  IF v_original<>'* * * * *'
    OR (SELECT count(*) FROM cron.job WHERE jobid=v_job)<>1
    OR md5(pg_get_functiondef(
      'programacion.fn_input_governance_queue_worker_v1()'::regprocedure))
      <>'cef11206002aeb4d03e3c68d7738199b'
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
        WHERE work_item_id=478 AND status='DONE')<>2
  THEN RAISE EXCEPTION 'IG_M107_CADENCE_BASELINE_DRIFT'; END IF;

  FOR v_trial IN 1..2 LOOP
    BEGIN
      PERFORM cron.alter_job(v_job, schedule=>'30 seconds');
      IF (SELECT schedule FROM cron.job WHERE jobid=v_job)<>'30 seconds'
      THEN RAISE EXCEPTION 'IG_M107_CADENCE_READBACK_FAILED'; END IF;
      IF v_trial=1 THEN
        RAISE EXCEPTION 'IG_M107_ROLLBACK_TRIAL' USING ERRCODE='PZ120';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ120' THEN
      IF v_trial<>1 THEN RAISE; END IF;
    END;
    IF v_trial=1 AND
       (SELECT schedule FROM cron.job WHERE jobid=v_job)<>v_original
    THEN RAISE EXCEPTION 'IG_M107_CADENCE_ROLLBACK_RESIDUE'; END IF;
  END LOOP;
  IF (SELECT count(*) FROM cron.job
      WHERE command='select programacion.fn_input_governance_queue_worker_v1();'
        AND active=true)<>1
  THEN RAISE EXCEPTION 'IG_M107_DUPLICATE_JOB'; END IF;
END
$m107$;
