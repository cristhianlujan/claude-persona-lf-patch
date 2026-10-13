-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- Close PASE-ATOM-F09-X15 with native-first observability reuse, measured-gap
-- disposition, and owner-approved shutdown of temporary DEBUG logging.
DO $f09x15$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-X15';
  c_exec constant text := 'CLAUDE-PASE-F09-X15-CLOSE-20261013';
  v_status text;
  v_evt boolean;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
     WHERE u.plan_code = c_plan
       AND u.unit_code = c_unit
       AND u.disposition = 'ASSIGNED'
       AND w.work_code = u.unit_code
  ) THEN
    RAISE EXCEPTION 'F09_X15_CLOSE_PLAN_UNIT_DRIFT';
  END IF;

  IF to_regclass('private.lf_worker_heartbeat_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'F09_X15_CLOSE_HEARTBEAT_TABLE_MUST_NOT_EXIST';
  END IF;

  IF (SELECT count(*) FROM public.lf_log_config WHERE log_key = 'DEBUG') <> 1 THEN
    RAISE EXCEPTION 'F09_X15_CLOSE_DEBUG_CONFIG_MISSING_OR_DUPLICATED';
  END IF;
  IF (SELECT retention_days FROM public.lf_log_config WHERE log_key = 'DEBUG') <> 15 THEN
    RAISE EXCEPTION 'F09_X15_CLOSE_DEBUG_RETENTION_DRIFT';
  END IF;

  SELECT w.status
    INTO v_status
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
   WHERE u.plan_code = c_plan
     AND u.unit_code = c_unit
     AND u.disposition = 'ASSIGNED'
     AND w.work_code = u.unit_code
   FOR UPDATE OF w;
  v_evt := EXISTS (
    SELECT 1 FROM public.lf_eventos
     WHERE created_by_execution_id = c_exec
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
  );

  IF v_status = 'DONE' AND v_evt THEN
    RETURN;
  END IF;
  IF v_status NOT IN ('BACKLOG', 'IN_PROGRESS') OR v_evt THEN
    RAISE EXCEPTION 'F09_X15_CLOSE_PRESTATE_DRIFT status=% event=%', v_status, v_evt;
  END IF;

  UPDATE public.lf_log_config
     SET enabled = false,
         nivel_minimo = 'INFO',
         updated_at = now(),
         updated_reason = 'Fin de activación temporal RCA Ruta de Claridad (26/05); sin filas en lf_log_operativo desde 2026-06-30. Disposición F09-X15, owner Paulo 2026-10-13.'
   WHERE log_key = 'DEBUG';

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
    'F09-X15 closed: native-first observability reuse documented, measured gap returned to F09-015, heartbeat remains uncreated, temporary DEBUG disabled.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version', 'operational-event/v2',
      'purpose', 'Close PASE-ATOM-F09-X15 with an observability source/reuse decision and DEBUG disposition',
      'producer', 'CLAUDE:PASE_GLOBAL09',
      'execution_id', c_exec,
      'work_code', c_unit,
      'closure_basis', 'EXIT_CRITERION_VERIFIED_READ_ONLY',
      'decided_by', 'PAULO (owner PASE/POST-PASE), chat 2026-10-13',
      'reuse_map', jsonb_build_array(
        jsonb_build_object(
          'source', 'GitHub Actions nativo',
          'answers', 'workflow, job, check, resultado, duración, intento y SHA',
          'limit', 'No atribuye queries ni transporte.'),
        jsonb_build_object(
          'source', 'pg_stat_statements',
          'answers', 'Conteo y tiempo agregados por query; stats_reset=2026-10-10.',
          'limit', 'No correlaciona por ejecución.'),
        jsonb_build_object(
          'source', 'lf_eventos',
          'answers', 'Decisiones y evidencia en payload, con created_by_execution_id; incluye MIGRATION_TRAIN_RECEIPT_RECORDED.',
          'limit', 'No es una serie temporal por etapa ni de consultas/transporte.'),
        jsonb_build_object(
          'source', 'lf_operation_execution y lf_operation_execution_steps',
          'answers', 'Estado y tiempos globales; los pasos solo tienen observed_at.',
          'limit', 'Sin duración ni contadores por paso.'),
        jsonb_build_object(
          'source', 'Recibos del Train',
          'answers', 'PR, head, versión, run, paridad, merge y autoridad del Router.',
          'limit', 'No miden consultas o transporte por etapa.'),
        jsonb_build_object(
          'source', 'EVIDENCE_LEDGER',
          'answers', 'Enlace durable por ejecución, SHA, proveedor y hashes.',
          'limit', 'No es una serie de tiempos.'),
        jsonb_build_object(
          'source', 'Heartbeat del worker en journald',
          'answers', 'Ciclos, trabajo, errores y reconexiones cada 15 min.',
          'limit', 'Solo señal: no es durable ni da veredicto.')
      ),
      'measured_gap', 'No hay duración por etapa ni conteo de queries o transporte correlacionado a una ejecución exacta. El hueco pasa a F09-015 como entrada, no como capacidad nueva.',
      'debug_disposition', jsonb_build_object(
        'status', 'DISABLED',
        'previous_enabled', true,
        'previous_nivel_minimo', 'DEBUG',
        'activated_at', '2026-05-26',
        'lf_log_operativo_rows', 104,
        'lf_log_operativo_last_row', '2026-06-30',
        'retention_days_preserved', 15),
      'heartbeat', jsonb_build_object(
        'status', 'NOT_CREATED',
        'deferred_to', 'Fase 4 / T4.1 del plan de reducción de logs v3',
        'blocked_until', 'Cierre de Fase 3 mediante deploy gobernado REFRESCO_RUNTIME_PERFIL_LF',
        's28_amendment', false,
        'authority', 'Solo señal; no estado ni veredicto.'),
      'aligned_with_log_plan_phase_4', true,
      'acceptance_criteria_result', jsonb_build_object(
        'NATIVE_FIRST_THEN_GAP_ONLY', 'PASS: every F09-015 question maps to an existing source or measured gap only',
        'NO_NEW_OBSERVABILITY_TABLE_WITHOUT_MEASURED_GAP_AND_S28_AMENDMENT', 'PASS: no table is created without a measured gap and explicit S28 amendment',
        'HEARTBEAT_SIGNAL_NEVER_STATE_OR_VERDICT_AUTHORITY', 'PASS: heartbeat remains a signal and never state or verdict authority',
        'DEBUG_DRIFT_DISPOSED', 'PASS: DEBUG is disabled at INFO and retention_days remains 15',
        'GATE_CHECK_OBSERVABILITY_REMAINS_INTERNAL_CHECK_NOT_CAPABILITY', 'PASS: observability remains an internal check, not a capability',
        'ALIGNED_WITH_LOG_PLAN_PHASE_4', 'PASS: aligned with Phase 4/T4.1 and respects the Phase 3 dependency'),
      'acceptance_declared', false,
      'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'CLAUDE:PASE_GLOBAL09', c_exec
  );
END
$f09x15$;
