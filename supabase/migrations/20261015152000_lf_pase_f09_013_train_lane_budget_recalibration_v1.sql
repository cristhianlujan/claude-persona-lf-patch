-- F09-013: recalibrate Train-lane limits to cover Train overhead only.
-- Data-only operational-event/v2 registration; no plan-state transition.
DO $f09_013_budget_recalibration$
DECLARE
  c_unit constant text := 'PASE-ATOM-F09-013';
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_exec constant text := 'CLAUDE-PASE-F09-013-TRAIN-BUDGET-RECALIBRATION-20261015-001';
  c_event_code constant text := 'PASE-ATOM-F09-013-TRAIN-LANE-BUDGET-RECALIBRATION-V1';
  v_previous jsonb;
  v_payload jsonb;
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
    FROM public.lf_eventos
   WHERE id = 21014
     AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
     AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
     AND entidad_codigo = c_unit
     AND payload->>'work_code' = c_unit
     AND payload->>'evidence_schema_version' = 'operational-event/v2';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'F09_013_RECALIBRATION_SOURCE_EVENT_INVALID:%', v_count;
  END IF;

  v_payload := jsonb_build_object(
    'evidence_schema_version', 'operational-event/v2',
    'budget_revision_code', c_event_code,
    'execution_id', c_exec,
    'producer', 'CLAUDE:PASE_GLOBAL09',
    'plan_code', c_plan,
    'work_code', c_unit,
    'purpose', 'Recalibrate the F09-013 Merge Train lane budget to measure Train overhead only after the prior total and aggregate patch-duration caps were exceeded by SQL apply time.',
    'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'supersedes_event_id', 21014,
    'acceptance_declared', false,
    'unit_state_transition', false,
    'diagnostic', jsonb_build_object(
      'sample_set', '2026-10-15 read-only acceptance using evaluator from PR #2713 without changes',
      'valid_samples', 23,
      'cold_samples', 8,
      'hot_samples', 15,
      'existing_samples_reused_for_new_acceptance', false,
      'cause', 'The patch step exposes aggregate query telemetry; the migration-apply query cannot be isolated from the other patch queries in the step receipt. Heavy SQL apply time dominates patch and total duration. Preflight and verify remain overhead signals.'
    ),
    'recalibration_rule', jsonb_build_object(
      'scope', 'TRAIN_OVERHEAD_ONLY',
      'time_cap_formula', 'CEIL(MAX(p99_ms*1.25,p99_ms+50))',
      'percentile_method', 'nearest-rank; for the five E3 calibration executions, p99 equals the maximum observed value',
      'count_cap', 'maximum observed count across the same five E3 calibration executions',
      'uncapped_metric_values', jsonb_build_object(
        'INFORMATIVE', 'Report the observed percentile without applying a cap.',
        'NOT_APPLICABLE', 'No cap applies because the metric cannot be isolated from SQL apply time or was not observed for the full step.'
      ),
      'patch_query_apply_isolation', 'NOT_AVAILABLE_IN_STEP_OR_TRAIN_RECEIPT'
    ),
    'frozen_caps', jsonb_build_object(
      'preflight', jsonb_build_object(
        'duration_ms_cap', 2869,
        'queries_count_cap', 4,
        'queries_duration_ms_cap', 2855,
        'transport_count_cap', 'NOT_APPLICABLE',
        'transport_duration_ms_cap', 'NOT_APPLICABLE'
      ),
      'patch', jsonb_build_object(
        'duration_ms_cap', 'INFORMATIVE',
        'queries_count_cap', 13,
        'queries_duration_ms_cap', 'NOT_APPLICABLE',
        'transport_count_cap', 1,
        'transport_duration_ms_cap', 720
      ),
      'verify', jsonb_build_object(
        'duration_ms_cap', 1659,
        'queries_count_cap', 2,
        'queries_duration_ms_cap', 1659,
        'transport_count_cap', 'NOT_APPLICABLE',
        'transport_duration_ms_cap', 'NOT_APPLICABLE'
      ),
      'total', jsonb_build_object(
        'definition', 'lf_operation_execution.completed_at - started_at',
        'duration_ms_cap', 'INFORMATIVE',
        'scope', 'Includes PR SQL apply time outside the Train overhead budget.'
      )
    ),
    'calibration', jsonb_build_object(
      'decision', 'Reuse exactly the five calibration executions selected by E3 in superseded event 21014; do not add or substitute runs.',
      'source_event_id', 21014,
      'owner_decision', 'E3',
      'p99_values', jsonb_build_object(
        'preflight', jsonb_build_object(
          'duration_ms', 2294.508,
          'queries_count', 4,
          'queries_duration_ms', 2283.755
        ),
        'patch', jsonb_build_object(
          'queries_count', 13,
          'transport_count', 1,
          'transport_duration_ms', 575.562
        ),
        'verify', jsonb_build_object(
          'duration_ms', 1326.905,
          'queries_count', 2,
          'queries_duration_ms', 1326.751
        )
      ),
      'executions', jsonb_build_array(
        'EXEC-DB-TRAIN-PR2649-20261014191500-R38622141590',
        'EXEC-DB-TRAIN-PR2641-20261014192335-R38623183075',
        'EXEC-DB-TRAIN-PR2651-20261014193500-R38624154855',
        'EXEC-DB-TRAIN-PR2654-20261014194500-R38624754083',
        'EXEC-DB-TRAIN-PR2655-20261014194501-R38624940410'
      )
    ),
    'acceptance_rule', jsonb_build_object(
      'eligible', 'EXEC-DB-TRAIN-* with status COMPLETED and created_at strictly greater than this event row created_at; excludes lf_pase_f09_015_c3_* targets.',
      'sample_count', 10,
      'min_cold_samples', 2,
      'classification', 'Keep E2 exactly: cold is first Train run after at least 30 minutes without runs; hot starts within 10 minutes after the previous run; exclude intervals between 10 and 30 minutes.',
      'report', 'p50/p95/p99 per step and total, split cold/hot; total and uncapped patch duration/query duration remain informative.',
      'pre_event_23_samples_are_acceptance', false
    )
  );

  SELECT count(*) INTO v_count
    FROM public.lf_eventos
   WHERE created_by_execution_id = c_exec
     AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
     AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
     AND entidad_codigo = c_unit;
  IF v_count > 1 THEN
    RAISE EXCEPTION 'F09_013_RECALIBRATION_EVENT_DUPLICATED:%', v_count;
  END IF;

  IF v_count = 1 THEN
    SELECT payload INTO v_previous
      FROM public.lf_eventos
     WHERE created_by_execution_id = c_exec
       AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit;
    IF v_previous->>'budget_revision_code' IS DISTINCT FROM c_event_code
       OR v_previous->>'supersedes_event_id' IS DISTINCT FROM '21014'
       OR v_previous->>'acceptance_declared' IS DISTINCT FROM 'false'
       OR v_previous->>'unit_state_transition' IS DISTINCT FROM 'false' THEN
      RAISE EXCEPTION 'F09_013_RECALIBRATION_EVENT_IDEMPOTENCY_DRIFT';
    END IF;
  ELSE
    INSERT INTO public.lf_eventos(
      evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
      payload, origen, created_by_execution_id
    ) VALUES (
      'PLAN_SNAPSHOT_DETALLADO', 'ENGINEERING_WORK_ITEM', c_unit,
      'F09-013 Train lane budget recalibration prepared; acceptance remains undeclared and unit state unchanged.',
      'INFO', v_payload, 'CLAUDE:PASE_GLOBAL09', c_exec
    );
  END IF;
END
$f09_013_budget_recalibration$;
