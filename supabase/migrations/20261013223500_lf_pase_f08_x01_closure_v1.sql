-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- Close PASE-ATOM-F08-X01 (S28-O1 dormant observability preserve-set) under
-- owner decision 2026-10-13 (Paulo, owner of the unit):
--   * preserve-set verified against the live catalog: cron 3 lf-architecture-v4-monitor
--     and cron 4 lf-architecture-alert-delivery-v4 present and inactive (dormant, not
--     retired); private.lf_architecture_{monitor_runs,alerts,notification_outbox,
--     notification_attempts,notification_receipts}_v4 present; monitor/evaluator/emitter
--     functions v4 present; Edge Function lf-architecture-alert-sink-v4 ACTIVE
--     (checked through the Supabase management API, outside SQL);
--   * GLOBAL-08 retirement input = the 4 families in
--     sandbox/lf_contract_gate_test/post_pase_f08/*_retirement_readiness_v1.json
--     (LF_CONTRACT_CHECK_WORKFLOW, LF_DB_REGRESSION_LEGACY_CARRIER_REFERENCES,
--     PASE_CONTROL_REPAIR_QUARANTINE_V1, VALIDATE_LF_PACKS_LEGACY_CARRIER_REFERENCES),
--     all NO_CASCADE; none references the preserve-set;
--   * no migration on main drops these objects; operational retention only prunes
--     rows and vacuums tables, it does not retire objects;
--   * no explicit S28 supersession exists, so nothing in the set is retirable.
-- Only changes the F08-X01 work item status and records one event.
DO $f08x01$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F08-X01';
  c_exec constant text := 'CLAUDE-PASE-F08-X01-CLOSE-20261013';
  v_status text;
  v_evt boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units u
                  JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
                 WHERE u.plan_code = c_plan AND u.unit_code = c_unit
                   AND u.disposition = 'ASSIGNED' AND w.work_code = u.unit_code)
  THEN RAISE EXCEPTION 'F08_X01_CLOSE_PLAN_UNIT_DRIFT'; END IF;

  -- Live preserve-set evidence (fail closed if any object disappeared or a cron was activated).
  IF (SELECT count(*) FROM cron.job
       WHERE (jobid = 3 AND jobname = 'lf-architecture-v4-monitor' AND NOT active)
          OR (jobid = 4 AND jobname = 'lf-architecture-alert-delivery-v4' AND NOT active)) <> 2
  THEN RAISE EXCEPTION 'F08_X01_CLOSE_CRON_PRESERVE_SET_DRIFT'; END IF;

  IF (SELECT count(*) FROM unnest(ARRAY[
        'private.lf_architecture_monitor_runs_v4',
        'private.lf_architecture_alerts_v4',
        'private.lf_architecture_notification_outbox_v4',
        'private.lf_architecture_notification_attempts_v4',
        'private.lf_architecture_notification_receipts_v4']) t
       WHERE to_regclass(t) IS NOT NULL) <> 5
  THEN RAISE EXCEPTION 'F08_X01_CLOSE_TABLE_PRESERVE_SET_DRIFT'; END IF;

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'private'
         AND p.proname IN ('fn_run_architecture_monitor_v4',
                           'fn_evaluate_architecture_alerts_v4',
                           'fn_emit_architecture_alert_v4')) <> 3
  THEN RAISE EXCEPTION 'F08_X01_CLOSE_FUNCTION_PRESERVE_SET_DRIFT'; END IF;

  SELECT status INTO v_status FROM programacion.engineering_work_items
   WHERE work_code = c_unit FOR UPDATE;
  v_evt := EXISTS (SELECT 1 FROM public.lf_eventos
                    WHERE created_by_execution_id = c_exec AND entidad_codigo = c_unit);

  IF v_status = 'DONE' AND v_evt THEN
    RETURN;  -- already applied
  END IF;
  IF v_status NOT IN ('BACKLOG', 'IN_PROGRESS') OR v_evt THEN
    RAISE EXCEPTION 'F08_X01_CLOSE_PRESTATE_DRIFT status=% event=%', v_status, v_evt;
  END IF;

  UPDATE programacion.engineering_work_items
     SET status = 'DONE',
         started_at = coalesce(started_at, now()),
         completed_at = now(),
         updated_by_execution_id = c_exec
   WHERE work_code = c_unit;

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO', 'ENGINEERING_WORK_ITEM', c_unit,
    'F08-X01 closed: S28-O1 preserve-set verified live and excluded from the GLOBAL-08 retirement input (4 families, NO_CASCADE); no S28 supersession, nothing retired.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version', 'operational-event/v2',
      'purpose', 'Record closure of PASE-ATOM-F08-X01 with live preserve-set and retirement-input evidence',
      'producer', 'CLAUDE:PASE_GLOBAL08',
      'execution_id', c_exec,
      'work_code', c_unit,
      'closure_basis', 'EXIT_CRITERION_VERIFIED_READ_ONLY',
      'decided_by', 'PAULO (owner PASE/POST-PASE), chat 2026-10-13',
      'acceptance_criteria_result', jsonb_build_object(
        'INACTIVE_NE_LEGACY', 'PASS: cron 3/4 inactive and treated as dormant, not legacy',
        'DORMANT_REUSE_FIRST_NE_RETIRE', 'PASS: no retirement proposed for any preserve-set object',
        'PRESERVE_SET_VERIFIED_AGAINST_LIVE_CATALOG', 'PASS: 2 crons, 5 tables, 3 functions, 1 edge function present',
        'RETIREMENT_ONLY_WITH_EXPLICIT_S28_SUPERSESSION', 'PASS: no S28 supersession exists'),
      'preserve_set', jsonb_build_object(
        'cron', jsonb_build_array('3:lf-architecture-v4-monitor:inactive', '4:lf-architecture-alert-delivery-v4:inactive'),
        'tables', jsonb_build_array(
          'private.lf_architecture_monitor_runs_v4', 'private.lf_architecture_alerts_v4',
          'private.lf_architecture_notification_outbox_v4', 'private.lf_architecture_notification_attempts_v4',
          'private.lf_architecture_notification_receipts_v4'),
        'functions', jsonb_build_array(
          'private.fn_run_architecture_monitor_v4', 'private.fn_evaluate_architecture_alerts_v4',
          'private.fn_emit_architecture_alert_v4'),
        'edge_function', 'lf-architecture-alert-sink-v4 (ACTIVE, verified via management API)'),
      'retirement_input', jsonb_build_object(
        'source_dir', 'sandbox/lf_contract_gate_test/post_pase_f08',
        'terminal_manifest', 'PASE_LEGACY_RETIREMENT_terminal_readiness_v1.json',
        'terminal_readback_event_id', 20318,
        'families', jsonb_build_array(
          'LF_CONTRACT_CHECK_WORKFLOW', 'LF_DB_REGRESSION_LEGACY_CARRIER_REFERENCES',
          'PASE_CONTROL_REPAIR_QUARANTINE_V1', 'VALIDATE_LF_PACKS_LEGACY_CARRIER_REFERENCES'),
        'preserve_set_references_found', 0,
        'no_cascade', true),
      'notes', jsonb_build_array(
        'Operational retention (docs/db-space/operational_retention_v1_runbook.md) prunes rows and vacuums monitor_runs_v4/outbox_v4; it does not retire objects.',
        'v3 monitor/evaluator/emitter functions also present; not in any retirement input.'),
      'acceptance_declared', false,
      'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'CLAUDE:PASE_GLOBAL08', c_exec
  );
END
$f08x01$;
