-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- F09-013: freeze the Merge Train lane budget from five calibration executions
-- (owner decisions E1-E4, 2026-10-14) before any acceptance sample. No unit closure.
DO $f09_013_freeze$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-013';
  c_exec constant text := 'CLAUDE-PASE-F09-013-TRAIN-BUDGET-FREEZE-20261014-001';
  v_status text;
  v_evt boolean;
  v_payload jsonb := $payload${"evidence_schema_version":"operational-event/v2","purpose":"Freeze the F09-013 Merge Train lane budget from five calibration executions before any acceptance sample","producer":"CLAUDE:PASE_GLOBAL09","execution_id":"CLAUDE-PASE-F09-013-TRAIN-BUDGET-FREEZE-20261014-001","plan_code":"LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1","work_code":"PASE-ATOM-F09-013","work_item_id":827,"acceptance_declared":false,"occurred_at":"SET_BY_MIGRATION","lane":"MERGE_TRAIN","owner_decisions":{"origin":"GO de Cristhian transmitido por Paulo, 2026-10-14","E1":"Train-lane budget uses telemetry already in main (pase_f09_015_telemetry_v1 per step preflight/patch/verify: duration_ms, queries.count, queries.duration_ms, transport.count, transport.duration_ms) plus total = completed_at - started_at; the six-stage model of #2689 is not used; event 20395 does not apply to this lane.","E2":"Cold = first Train run after >=30 min without runs; warm = starts <=10 min after the previous run; in-between runs are excluded from acceptance. Acceptance needs 10 samples with at least 2 cold; p50/p95/p99 reported per group.","E3":"Calibration = first 5 COMPLETED EXEC-DB-TRAIN-* executions created at or after 2026-10-14T19:06:43Z (after hotfix #2648), excluding lf_pase_f09_015_c3_* targets and failed runs.","E4":"Runtime lane waits for governed REFRESCO_RUNTIME_PERFIL_LF deploy on main >= 8053af1f plus canary."},"budget_rule":{"source_event_id":20394,"time_cap":"CEIL(MAX(p99_ms*1.25, p99_ms+1))","count_cap":"max observed count (no growth)","percentile_method":"nearest-rank; with n=5 the p99 equals the maximum","not_observed":"metrics reported NOT_OBSERVED carry no cap and are never recorded as 0"},"calibration_executions":[{"execution_id":"EXEC-DB-TRAIN-PR2649-20261014191500-R38622141590","pr":2649,"started_at":"2026-10-14T19:16:43.882432Z","completed_at":"2026-10-14T19:17:17.360719Z","total_ms":33478.287,"cold_warm_class":"COLD","steps":{"preflight":{"duration_ms":1719.448,"queries_count":4,"queries_duration_ms":1717.073,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"},"patch":{"duration_ms":5220.214,"queries_count":13,"queries_duration_ms":4824.079,"transport_count":1,"transport_duration_ms":303.22},"verify":{"duration_ms":1112.554,"queries_count":2,"queries_duration_ms":1112.376,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"}}},{"execution_id":"EXEC-DB-TRAIN-PR2641-20261014192335-R38623183075","pr":2641,"started_at":"2026-10-14T19:24:06.818545Z","completed_at":"2026-10-14T19:24:41.906274Z","total_ms":35087.729,"cold_warm_class":"WARM","steps":{"preflight":{"duration_ms":2294.508,"queries_count":4,"queries_duration_ms":2283.755,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"},"patch":{"duration_ms":8159.586,"queries_count":13,"queries_duration_ms":7502.529,"transport_count":1,"transport_duration_ms":575.562},"verify":{"duration_ms":287.844,"queries_count":2,"queries_duration_ms":287.707,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"}}},{"execution_id":"EXEC-DB-TRAIN-PR2651-20261014193500-R38624154855","pr":2651,"started_at":"2026-10-14T19:30:27.033641Z","completed_at":"2026-10-14T19:30:58.693218Z","total_ms":31659.577,"cold_warm_class":"WARM","steps":{"preflight":{"duration_ms":959.42,"queries_count":4,"queries_duration_ms":956.797,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"},"patch":{"duration_ms":3649.405,"queries_count":13,"queries_duration_ms":3283.043,"transport_count":1,"transport_duration_ms":255.477},"verify":{"duration_ms":1326.905,"queries_count":2,"queries_duration_ms":1326.751,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"}}},{"execution_id":"EXEC-DB-TRAIN-PR2654-20261014194500-R38624754083","pr":2654,"started_at":"2026-10-14T19:34:39.935438Z","completed_at":"2026-10-14T19:35:15.468105Z","total_ms":35532.667,"cold_warm_class":"WARM","steps":{"preflight":{"duration_ms":1870.502,"queries_count":4,"queries_duration_ms":1867.927,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"},"patch":{"duration_ms":5199.699,"queries_count":13,"queries_duration_ms":4727.782,"transport_count":1,"transport_duration_ms":365.842},"verify":{"duration_ms":1160.81,"queries_count":2,"queries_duration_ms":1160.669,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"}}},{"execution_id":"EXEC-DB-TRAIN-PR2655-20261014194501-R38624940410","pr":2655,"started_at":"2026-10-14T19:36:34.025229Z","completed_at":"2026-10-14T19:37:04.236850Z","total_ms":30211.621,"cold_warm_class":"WARM","steps":{"preflight":{"duration_ms":1926.639,"queries_count":4,"queries_duration_ms":1913.939,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"},"patch":{"duration_ms":5512.085,"queries_count":13,"queries_duration_ms":5060.53,"transport_count":1,"transport_duration_ms":376.131},"verify":{"duration_ms":349.072,"queries_count":2,"queries_duration_ms":348.922,"transport_count":"NOT_OBSERVED","transport_duration_ms":"NOT_OBSERVED"}}}],"frozen_caps":{"preflight":{"duration_ms_cap":2869,"queries_count_cap":4,"queries_duration_ms_cap":2855,"transport_count_cap":"NOT_OBSERVED","transport_duration_ms_cap":"NOT_OBSERVED"},"patch":{"duration_ms_cap":10200,"queries_count_cap":13,"queries_duration_ms_cap":9379,"transport_count_cap":1,"transport_duration_ms_cap":720},"verify":{"duration_ms_cap":1659,"queries_count_cap":2,"queries_duration_ms_cap":1659,"transport_count_cap":"NOT_OBSERVED","transport_duration_ms_cap":"NOT_OBSERVED"},"total":{"duration_ms_cap":44416,"definition":"lf_operation_execution.completed_at - started_at"}},"acceptance_rule":{"sample_count":10,"min_cold_samples":2,"eligible":"EXEC-DB-TRAIN-* COMPLETED with created_at after this migration is applied; excludes lf_pase_f09_015_c3_* targets","report":"p50/p95/p99 per step and total, split cold/warm"},"known_limitation":"Three of the five calibration runs are lightweight probe migrations; if acceptance exceeds caps for that reason it is recorded as a finding and recalibration needs a new rule frozen before measuring.","references":{"telemetry_prs":[2630,2648,2697],"not_applicable_budget_event":20395,"constraint_event":20570},"unit_state_transition":false}$payload$::jsonb;
BEGIN
  SELECT w.status
    INTO v_status
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
   WHERE u.plan_code = c_plan
     AND u.unit_code = c_unit
     AND u.work_item_id = 827
     AND u.disposition = 'ASSIGNED'
     AND w.work_code = u.unit_code;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'F09_013_FREEZE_PLAN_UNIT_DRIFT';
  END IF;

  v_evt := EXISTS (
    SELECT 1 FROM public.lf_eventos
     WHERE created_by_execution_id = c_exec
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
       AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
  );
  IF v_evt THEN
    RETURN;
  END IF;
  IF v_status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'F09_013_FREEZE_PRESTATE_DRIFT status=%', v_status;
  END IF;

  IF v_payload->>'execution_id' IS DISTINCT FROM c_exec
     OR v_payload->>'work_code' IS DISTINCT FROM c_unit
     OR jsonb_typeof(v_payload->'acceptance_declared') IS DISTINCT FROM 'boolean'
     OR coalesce((v_payload->>'acceptance_declared')::boolean, true)
     OR v_payload->>'occurred_at' IS DISTINCT FROM 'SET_BY_MIGRATION' THEN
    RAISE EXCEPTION 'F09_013_FREEZE_EVENT_ENVELOPE_DRIFT';
  END IF;

  v_payload := jsonb_set(
    v_payload,
    '{occurred_at}',
    to_jsonb(to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),
    true
  );

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO',
    'ENGINEERING_WORK_ITEM',
    c_unit,
    'F09-013 Merge Train lane budget frozen from five calibration executions before acceptance sampling.',
    'INFO',
    v_payload,
    'CLAUDE:PASE_GLOBAL09',
    c_exec
  );
END
$f09_013_freeze$;
