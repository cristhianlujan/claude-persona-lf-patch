-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- Close F09-013 from the live, read-only acceptance evidence bound to events 21075 and 21014.
-- All status and event writes occur in this single Merge Train migration.
DO $f09_013_close$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-013';
  c_work_item_id constant bigint := 827;
  c_exec constant text := 'CODEX-PASE-F09-013-CLOSE-20261015-001';
  v_status text;
  v_evt boolean;
  v_any_close_evt boolean;
  v_recalibration jsonb;
  v_cutoff timestamptz;
  v_source_count integer;
  v_sample_count integer;
  v_cold_count integer;
  v_hot_count integer;
  v_invalid_count integer;
  v_excess_count integer;
  v_rows integer;
  v_payload jsonb := $payload${"evidence_schema_version":"operational-event/v2","purpose":"Close PASE-ATOM-F09-013 after read-only acceptance of the recalibrated Merge Train overhead budget.","producer":"CODEX:PASE_GLOBAL09","execution_id":"CODEX-PASE-F09-013-CLOSE-20261015-001","plan_code":"LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1","work_code":"PASE-ATOM-F09-013","work_item_id":827,"acceptance_declared":false,"occurred_at":"SET_BY_MIGRATION","closure_code":"PASE-ATOM-F09-013-CLOSURE-V1","source_event_ids":[21075,21014],"source_event_roles":{"acceptance_budget_and_cutoff":21075,"superseded_original_budget":21014},"cutoff_created_at_exclusive":"2026-10-15T15:34:55.167252Z","acceptance_rule":{"sample_target":10,"minimum_cold_samples":2,"classification":"cold: idle gap >=30 minutes; hot: idle gap <=10 minutes; intermediate intervals excluded","percentile_method":"nearest-rank"},"sample_counts":{"valid":13,"cold":5,"hot":8},"execution_ids":["EXEC-DB-TRAIN-PR2756-20261015153600-R38765934330","EXEC-DB-TRAIN-PR2729-20261015163046-R38769511833","EXEC-DB-TRAIN-PR2755-20261015164930-R38772569507","EXEC-DB-TRAIN-PR2765-20261015165426-R38773444592","EXEC-DB-TRAIN-PR2768-20261015175000-R38781864480","EXEC-DB-TRAIN-PR2773-20261015182000-R38784620342","EXEC-DB-TRAIN-PR2776-20261015192200-R38791553403","EXEC-DB-TRAIN-PR2777-20261015193500-R38795797712","EXEC-DB-TRAIN-PR2780-20261015200000-R38802471977","EXEC-DB-TRAIN-PR2781-20261015205500-R38806279399","EXEC-DB-TRAIN-PR2783-20261015213000-R38808733591","EXEC-DB-TRAIN-PR2786-20261015220157-R38814172666","EXEC-DB-TRAIN-PR2788-20261015220844-R38814937617"],"acceptance_criteria_result":{"ACCEPTANCE_SUMMARY":"PASS: 13/13 válidas, 0 excesos","SAMPLE_COUNTS":"PASS: 13 válidas: 5 frías y 8 calientes; mínimos cumplidos."},"percentiles_nearest_rank_ms":{"cold":{"preflight.duration_ms":{"p50":2184.424,"p95":2319.501,"p99":2319.501},"preflight.queries_count":{"p50":4,"p95":4,"p99":4},"preflight.queries_duration_ms":{"p50":2182.377,"p95":2317.021,"p99":2317.021},"preflight.transport_count":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"preflight.transport_duration_ms":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"patch.duration_ms":{"p50":7692.148,"p95":9458.364,"p99":9458.364},"patch.queries_count":{"p50":13,"p95":13,"p99":13},"patch.queries_duration_ms":{"p50":7010.705,"p95":8639.009,"p99":8639.009},"patch.transport_count":{"p50":1,"p95":1,"p99":1},"patch.transport_duration_ms":{"p50":584.847,"p95":715.674,"p99":715.674},"verify.duration_ms":{"p50":723.394,"p95":1282.916,"p99":1282.916},"verify.queries_count":{"p50":2,"p95":2,"p99":2},"verify.queries_duration_ms":{"p50":723.207,"p95":1282.757,"p99":1282.757},"verify.transport_count":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"verify.transport_duration_ms":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"total.duration_ms":{"p50":38358.862,"p95":40344.612,"p99":40344.612}},"hot":{"preflight.duration_ms":{"p50":1836.159,"p95":2805.715,"p99":2805.715},"preflight.queries_count":{"p50":4,"p95":4,"p99":4},"preflight.queries_duration_ms":{"p50":1818.241,"p95":2789.726,"p99":2789.726},"preflight.transport_count":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"preflight.transport_duration_ms":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"patch.duration_ms":{"p50":5494.789,"p95":11552.147,"p99":11552.147},"patch.queries_count":{"p50":13,"p95":13,"p99":13},"patch.queries_duration_ms":{"p50":5005.709,"p95":10752.537,"p99":10752.537},"patch.transport_count":{"p50":1,"p95":1,"p99":1},"patch.transport_duration_ms":{"p50":386.858,"p95":722.845,"p99":722.845},"verify.duration_ms":{"p50":434.294,"p95":932.22,"p99":932.22},"verify.queries_count":{"p50":2,"p95":2,"p99":2},"verify.queries_duration_ms":{"p50":434.151,"p95":932.004,"p99":932.004},"verify.transport_count":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"verify.transport_duration_ms":{"p50":"NOT_OBSERVED","p95":"NOT_OBSERVED","p99":"NOT_OBSERVED"},"total.duration_ms":{"p50":32202.621,"p95":41820.447,"p99":41820.447}}},"frozen_caps_from_event_21075":{"preflight":{"duration_ms":2919,"queries_count":4,"queries_duration_ms":2905,"transport_count":"NOT_APPLICABLE","transport_duration_ms":"NOT_APPLICABLE"},"patch":{"duration_ms":"INFORMATIVE","queries_count":13,"queries_duration_ms":"NOT_APPLICABLE","transport_count":1,"transport_duration_ms":770},"verify":{"duration_ms":1709,"queries_count":2,"queries_duration_ms":1709,"transport_count":"NOT_APPLICABLE","transport_duration_ms":"NOT_APPLICABLE"},"total":{"duration_ms":"INFORMATIVE"}},"capped_metric_excess_count":0,"uncapped_metrics":["patch.duration_ms","patch.queries_duration_ms","total.duration_ms"],"notes":["p99 for each group equals that group's maximum under nearest-rank selection.","Transport metrics for preflight and verify were NOT_OBSERVED and are recorded without synthetic zeroes."]}$payload$::jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
     WHERE u.plan_code = c_plan
       AND u.unit_code = c_unit
       AND u.work_item_id = c_work_item_id
       AND u.disposition = 'ASSIGNED'
       AND w.work_code = u.unit_code
  ) THEN
    RAISE EXCEPTION 'F09_013_CLOSE_PLAN_UNIT_DRIFT';
  END IF;

  SELECT w.status
    INTO v_status
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
   WHERE u.plan_code = c_plan
     AND u.unit_code = c_unit
     AND u.work_item_id = c_work_item_id
     AND u.disposition = 'ASSIGNED'
     AND w.work_code = u.unit_code
   FOR UPDATE OF w;

  v_evt := EXISTS (
    SELECT 1 FROM public.lf_eventos
     WHERE created_by_execution_id = c_exec
       AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
       AND payload->>'closure_code' = 'PASE-ATOM-F09-013-CLOSURE-V1'
  );
  v_any_close_evt := EXISTS (
    SELECT 1 FROM public.lf_eventos
     WHERE evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
       AND payload->>'closure_code' = 'PASE-ATOM-F09-013-CLOSURE-V1'
  );

  IF v_status = 'DONE' AND v_evt THEN
    RETURN;
  END IF;
  IF v_status IS DISTINCT FROM 'IN_PROGRESS' OR v_evt OR v_any_close_evt THEN
    RAISE EXCEPTION 'F09_013_CLOSE_PRESTATE_DRIFT status=% event=% other_event=%',
      v_status, v_evt, v_any_close_evt;
  END IF;

  SELECT count(*)
    INTO v_source_count
    FROM public.lf_eventos
   WHERE id = 21075
     AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
     AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
     AND entidad_codigo = c_unit
     AND payload->>'work_code' = c_unit
     AND payload->>'budget_revision_code' = 'PASE-ATOM-F09-013-TRAIN-LANE-BUDGET-RECALIBRATION-V1'
     AND payload->>'supersedes_event_id' = '21014'
     AND payload->>'evidence_schema_version' = 'operational-event/v2';
  SELECT payload INTO v_recalibration FROM public.lf_eventos WHERE id = 21075;
  IF v_source_count <> 1
     OR (SELECT count(*) FROM public.lf_eventos
          WHERE id = 21014
            AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
            AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
            AND entidad_codigo = c_unit
            AND payload->>'work_code' = c_unit
            AND payload->>'evidence_schema_version' = 'operational-event/v2') <> 1
  THEN
    RAISE EXCEPTION 'F09_013_CLOSE_SOURCE_EVENTS_INVALID';
  END IF;

  v_cutoff := (v_recalibration->>'occurred_at')::timestamptz;
  IF v_cutoff IS DISTINCT FROM '2026-10-15T15:34:55.167252Z'::timestamptz
     OR coalesce((v_recalibration->>'acceptance_declared')::boolean, true)
     OR (v_recalibration->'acceptance_rule'->>'sample_count')::integer IS DISTINCT FROM 10
     OR (v_recalibration->'acceptance_rule'->>'min_cold_samples')::integer IS DISTINCT FROM 2
     OR (v_recalibration->'frozen_caps'->'preflight'->>'duration_ms_cap')::numeric IS DISTINCT FROM 2919
     OR (v_recalibration->'frozen_caps'->'preflight'->>'queries_count_cap')::numeric IS DISTINCT FROM 4
     OR (v_recalibration->'frozen_caps'->'preflight'->>'queries_duration_ms_cap')::numeric IS DISTINCT FROM 2905
     OR (v_recalibration->'frozen_caps'->'patch'->>'queries_count_cap')::numeric IS DISTINCT FROM 13
     OR (v_recalibration->'frozen_caps'->'patch'->>'transport_count_cap')::numeric IS DISTINCT FROM 1
     OR (v_recalibration->'frozen_caps'->'patch'->>'transport_duration_ms_cap')::numeric IS DISTINCT FROM 770
     OR (v_recalibration->'frozen_caps'->'verify'->>'duration_ms_cap')::numeric IS DISTINCT FROM 1709
     OR (v_recalibration->'frozen_caps'->'verify'->>'queries_count_cap')::numeric IS DISTINCT FROM 2
     OR (v_recalibration->'frozen_caps'->'verify'->>'queries_duration_ms_cap')::numeric IS DISTINCT FROM 1709
     OR v_recalibration->'frozen_caps'->'patch'->>'duration_ms_cap' IS DISTINCT FROM 'INFORMATIVE'
     OR v_recalibration->'frozen_caps'->'patch'->>'queries_duration_ms_cap' IS DISTINCT FROM 'NOT_APPLICABLE'
     OR v_recalibration->'frozen_caps'->'total'->>'duration_ms_cap' IS DISTINCT FROM 'INFORMATIVE'
  THEN
    RAISE EXCEPTION 'F09_013_CLOSE_RECALIBRATION_CONTRACT_DRIFT';
  END IF;

  WITH requested(execution_id) AS (
    VALUES
      ('EXEC-DB-TRAIN-PR2756-20261015153600-R38765934330'),
      ('EXEC-DB-TRAIN-PR2729-20261015163046-R38769511833'),
      ('EXEC-DB-TRAIN-PR2755-20261015164930-R38772569507'),
      ('EXEC-DB-TRAIN-PR2765-20261015165426-R38773444592'),
      ('EXEC-DB-TRAIN-PR2768-20261015175000-R38781864480'),
      ('EXEC-DB-TRAIN-PR2773-20261015182000-R38784620342'),
      ('EXEC-DB-TRAIN-PR2776-20261015192200-R38791553403'),
      ('EXEC-DB-TRAIN-PR2777-20261015193500-R38795797712'),
      ('EXEC-DB-TRAIN-PR2780-20261015200000-R38802471977'),
      ('EXEC-DB-TRAIN-PR2781-20261015205500-R38806279399'),
      ('EXEC-DB-TRAIN-PR2783-20261015213000-R38808733591'),
      ('EXEC-DB-TRAIN-PR2786-20261015220157-R38814172666'),
      ('EXEC-DB-TRAIN-PR2788-20261015220844-R38814937617')
  ),
  observed AS (
    SELECT r.execution_id,
           e.status,
           e.created_at,
           e.started_at,
           e.completed_at,
           e.target_code,
           prev.status AS previous_status,
           coalesce(prev.completed_at, prev.updated_at) AS previous_closed_at,
           extract(epoch FROM (e.started_at - coalesce(prev.completed_at, prev.updated_at))) / 60.0 AS idle_gap_minutes,
           count(s.execution_id) FILTER (WHERE s.step_id = 'preflight') AS preflight_rows,
           count(s.execution_id) FILTER (WHERE s.step_id = 'patch') AS patch_rows,
           count(s.execution_id) FILTER (WHERE s.step_id = 'verify') AS verify_rows,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,duration_ms}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'preflight') AS preflight_duration_ms,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,queries,count}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'preflight') AS preflight_queries_count,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,queries,duration_ms}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'preflight') AS preflight_queries_duration_ms,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,queries,count}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'patch') AS patch_queries_count,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,transport,count}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'patch') AS patch_transport_count,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,transport,duration_ms}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'patch') AS patch_transport_duration_ms,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,duration_ms}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'verify') AS verify_duration_ms,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,queries,count}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'verify') AS verify_queries_count,
           max(nullif(s.evidence_payload #>> '{pase_f09_015_telemetry_v1,queries,duration_ms}', 'NOT_OBSERVED')::numeric)
             FILTER (WHERE s.step_id = 'verify') AS verify_queries_duration_ms
      FROM requested r
      LEFT JOIN public.lf_operation_execution e USING (execution_id)
      LEFT JOIN LATERAL (
        SELECT p.status, p.started_at, p.completed_at, p.updated_at
          FROM public.lf_operation_execution p
         WHERE p.execution_id LIKE 'EXEC-DB-TRAIN-%'
           AND (p.started_at, p.execution_id) < (e.started_at, e.execution_id)
         ORDER BY p.started_at DESC NULLS LAST, p.execution_id DESC
         LIMIT 1
      ) prev ON true
      LEFT JOIN public.lf_operation_execution_steps s USING (execution_id)
     GROUP BY r.execution_id, e.status, e.created_at, e.started_at, e.completed_at,
              e.target_code, prev.status, prev.completed_at, prev.updated_at
  )
  SELECT count(*),
         count(*) FILTER (WHERE idle_gap_minutes >= 30),
         count(*) FILTER (WHERE idle_gap_minutes <= 10),
         count(*) FILTER (
           WHERE status IS DISTINCT FROM 'COMPLETED'
              OR created_at IS NULL OR created_at <= v_cutoff
              OR started_at IS NULL OR completed_at IS NULL OR completed_at < started_at
              OR previous_status NOT IN ('COMPLETED', 'BLOCKED')
              OR previous_closed_at IS NULL
              OR idle_gap_minutes IS NULL OR idle_gap_minutes < 0
              OR (idle_gap_minutes > 10 AND idle_gap_minutes < 30)
              OR regexp_replace(coalesce(target_code, ''), '^.*/', '')
                   ~* '^(?:[0-9]{14}_)?lf_pase_f09_015_c3_'
              OR preflight_rows <> 1 OR patch_rows <> 1 OR verify_rows <> 1
              OR preflight_duration_ms IS NULL
              OR preflight_queries_count IS NULL
              OR preflight_queries_duration_ms IS NULL
              OR patch_queries_count IS NULL
              OR patch_transport_count IS NULL
              OR patch_transport_duration_ms IS NULL
              OR verify_duration_ms IS NULL
              OR verify_queries_count IS NULL
              OR verify_queries_duration_ms IS NULL
         ),
         count(*) FILTER (
           WHERE preflight_duration_ms > (v_recalibration->'frozen_caps'->'preflight'->>'duration_ms_cap')::numeric
              OR preflight_queries_count > (v_recalibration->'frozen_caps'->'preflight'->>'queries_count_cap')::numeric
              OR preflight_queries_duration_ms > (v_recalibration->'frozen_caps'->'preflight'->>'queries_duration_ms_cap')::numeric
              OR patch_queries_count > (v_recalibration->'frozen_caps'->'patch'->>'queries_count_cap')::numeric
              OR patch_transport_count > (v_recalibration->'frozen_caps'->'patch'->>'transport_count_cap')::numeric
              OR patch_transport_duration_ms > (v_recalibration->'frozen_caps'->'patch'->>'transport_duration_ms_cap')::numeric
              OR verify_duration_ms > (v_recalibration->'frozen_caps'->'verify'->>'duration_ms_cap')::numeric
              OR verify_queries_count > (v_recalibration->'frozen_caps'->'verify'->>'queries_count_cap')::numeric
              OR verify_queries_duration_ms > (v_recalibration->'frozen_caps'->'verify'->>'queries_duration_ms_cap')::numeric
         )
    INTO v_sample_count, v_cold_count, v_hot_count, v_invalid_count, v_excess_count
    FROM observed;

  IF v_sample_count <> 13 OR v_cold_count <> 5 OR v_hot_count <> 8 OR v_invalid_count <> 0 THEN
    RAISE EXCEPTION 'F09_013_CLOSE_SAMPLE_EVIDENCE_DRIFT samples=% cold=% hot=% invalid=%',
      v_sample_count, v_cold_count, v_hot_count, v_invalid_count;
  END IF;
  IF v_excess_count <> 0 THEN
    RAISE EXCEPTION 'F09_013_CLOSE_BUDGET_EXCESS_DETECTED:%', v_excess_count;
  END IF;

  IF v_payload->>'execution_id' IS DISTINCT FROM c_exec
     OR v_payload->>'work_code' IS DISTINCT FROM c_unit
     OR (v_payload->>'work_item_id')::bigint IS DISTINCT FROM c_work_item_id
     OR v_payload->>'closure_code' IS DISTINCT FROM 'PASE-ATOM-F09-013-CLOSURE-V1'
     OR jsonb_typeof(v_payload->'acceptance_declared') IS DISTINCT FROM 'boolean'
     OR coalesce((v_payload->>'acceptance_declared')::boolean, true)
     OR v_payload->>'occurred_at' IS DISTINCT FROM 'SET_BY_MIGRATION'
     OR v_payload->'source_event_ids' IS DISTINCT FROM '[21075,21014]'::jsonb
     OR jsonb_array_length(v_payload->'execution_ids') IS DISTINCT FROM 13
     OR v_payload->'sample_counts'->>'valid' IS DISTINCT FROM '13'
     OR v_payload->'sample_counts'->>'cold' IS DISTINCT FROM '5'
     OR v_payload->'sample_counts'->>'hot' IS DISTINCT FROM '8'
     OR v_payload->'acceptance_criteria_result'->>'ACCEPTANCE_SUMMARY'
           IS DISTINCT FROM 'PASS: 13/13 válidas, 0 excesos'
     OR v_payload->'acceptance_criteria_result'->>'SAMPLE_COUNTS'
           IS DISTINCT FROM 'PASS: 13 válidas: 5 frías y 8 calientes; mínimos cumplidos.'
     OR v_payload ? 'verdict'
     OR v_payload->'percentiles_nearest_rank_ms' IS NULL
  THEN
    RAISE EXCEPTION 'F09_013_CLOSE_EVENT_ENVELOPE_DRIFT';
  END IF;

  v_payload := jsonb_set(
    v_payload,
    '{occurred_at}',
    to_jsonb(to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
    true
  );

  UPDATE programacion.engineering_work_items
     SET status = 'DONE',
         started_at = coalesce(started_at, clock_timestamp()),
         completed_at = clock_timestamp(),
         updated_by_execution_id = c_exec
   WHERE id = c_work_item_id
     AND work_code = c_unit
     AND status = 'IN_PROGRESS';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'F09_013_CLOSE_WORK_ITEM_UPDATE_COUNT:%', v_rows;
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO',
    'ENGINEERING_WORK_ITEM',
    c_unit,
    'F09-013 closed from the read-only acceptance of 13 post-cutoff executions: 5 cold, 8 hot, with no capped-metric excesses.',
    'INFO',
    v_payload,
    'CODEX:PASE_GLOBAL09',
    c_exec
  );
END
$f09_013_close$;
