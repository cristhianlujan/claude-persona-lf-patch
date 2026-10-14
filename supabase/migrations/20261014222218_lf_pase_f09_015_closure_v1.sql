-- F09-015 closure: observed C3 success, failure, retry and fail-closed negative evidence.
DO $f09_015$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-015';
  c_exec constant text := 'CLAUDE-PASE-F09-015-CLOSE-20261014-001';
  v_status text;
  v_evt boolean;
  v_rows integer;
  v_payload jsonb := $f09_015_payload${"evidence_schema_version":"operational-event/v2","purpose":"Cerrar PASE-ATOM-F09-015 con evidencia de cuatro caminos C3 reconstruida desde ejecuciones del Train, ledger y verificador fail-closed.","producer":"CLAUDE:PASE_GLOBAL09","execution_id":"CLAUDE-PASE-F09-015-CLOSE-20261014-001","plan_code":"LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1","work_code":"PASE-ATOM-F09-015","work_item_id":829,"acceptance_declared":true,"c3_summary":{"verified_paths":"4/4","source_project_ref":"mhwmirqcgxxukpctffuv","success":{"pr":2691,"run_id":"38640583039","execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","execution_status":"COMPLETED","migration_name":"lf_pase_f09_015_c3_success_v1","migration_version":"20261014212500","verdict":"PASS","merge_sha":"2602ccbe45af9ca097dd91050ae26e3b3435e3a0","steps":[{"stage":"preflight","status":"PASS_CLEAN","started_at":"2026-10-14T21:29:30.007453Z","finished_at":"2026-10-14T21:29:31.287812Z","duration_ms":1280.359,"queries":{"bytes":2353,"count":4,"duration_ms":1277.626},"transport":{"bytes":"NOT_OBSERVED","count":"NOT_OBSERVED","duration_ms":"NOT_OBSERVED"},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38640583039:preflight","envelope_bytes_compact_utf8":767,"jsonb_rendered_bytes":811},{"stage":"patch","status":"PASS_CLEAN","started_at":"2026-10-14T21:29:32.218321Z","finished_at":"2026-10-14T21:29:37.266045Z","duration_ms":5047.724,"queries":{"bytes":5857,"count":13,"duration_ms":4626.665},"transport":{"bytes":9882,"count":1,"duration_ms":312.998},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38640583039:patch","envelope_bytes_compact_utf8":734,"jsonb_rendered_bytes":778},{"stage":"verify","status":"PASS_CLEAN","started_at":"2026-10-14T21:30:01.992452Z","finished_at":"2026-10-14T21:30:02.936395Z","duration_ms":943.943,"queries":{"bytes":527,"count":2,"duration_ms":943.785},"transport":{"bytes":"NOT_OBSERVED","count":"NOT_OBSERVED","duration_ms":"NOT_OBSERVED"},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38640583039:verify","envelope_bytes_compact_utf8":761,"jsonb_rendered_bytes":805}]},"failure":{"pr":2693,"run_id":"38641270448","execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","execution_status":"BLOCKED","migration_name":"lf_pase_f09_015_c3_failure_v1","migration_version":"20261014213307","ledger_registered":false,"verdict":"PRE-APPLY STOP; no apply or merge","steps":[{"stage":"preflight","status":"PASS_CLEAN","started_at":"2026-10-14T21:34:51.625397Z","finished_at":"2026-10-14T21:34:52.568876Z","duration_ms":943.479,"queries":{"bytes":2353,"count":4,"duration_ms":941.062},"transport":{"bytes":"NOT_OBSERVED","count":"NOT_OBSERVED","duration_ms":"NOT_OBSERVED"},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38641270448:preflight","envelope_bytes_compact_utf8":765,"jsonb_rendered_bytes":809},{"stage":"patch","status":"BLOCKED_BY_ENFORCEMENT","started_at":"2026-10-14T21:34:53.209228Z","finished_at":"2026-10-14T21:34:54.864549Z","duration_ms":1655.321,"queries":{"bytes":3158,"count":10,"duration_ms":1465.138},"transport":{"bytes":9882,"count":1,"duration_ms":91.659},"decision":"BLOCKED_BY_ENFORCEMENT","failure":{"code":"EXACT_APPLY_FALLBACK_FAILED","message":"EXACT_APPLY_FALLBACK_FAILED:psql:/tmp/tmp9bu7g3r1.sql:16: ERROR: P0001: LF_F09_015_C3_INTENTIONAL_FAILURE\\nCONTEXT: PL/pgSQL function inline_code_block line 1 at RAISE\\nLOCATION: exec_stmt_raise, pl_exec.c:3911","sqlstate":"NOT_OBSERVED","evidence_locator":"github-run:exact-apply-receipt"},"evidence_locator":"github-run:exact-apply-receipt","envelope_bytes_compact_utf8":1078,"jsonb_rendered_bytes":1129}]},"retry":{"pr":2693,"run_id":"38645579600","execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","execution_status":"COMPLETED","migration_name":"lf_pase_f09_015_c3_failure_v1","migration_version":"20261014221201","verdict":"PASS","merge_sha":"5d84fe7ca2f52b720902d2bc3e90fbe9fc8e534e","steps":[{"stage":"preflight","status":"PASS_CLEAN","started_at":"2026-10-14T22:10:09.678586Z","finished_at":"2026-10-14T22:10:12.152269Z","duration_ms":2473.683,"queries":{"bytes":2353,"count":4,"duration_ms":2461.375},"transport":{"bytes":"NOT_OBSERVED","count":"NOT_OBSERVED","duration_ms":"NOT_OBSERVED"},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38645579600:preflight","envelope_bytes_compact_utf8":767,"jsonb_rendered_bytes":811},{"stage":"patch","status":"PASS_CLEAN","started_at":"2026-10-14T22:10:13.430348Z","finished_at":"2026-10-14T22:10:20.561052Z","duration_ms":7130.704,"queries":{"bytes":5857,"count":13,"duration_ms":6455.541},"transport":{"bytes":9882,"count":1,"duration_ms":579.856},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38645579600:patch","envelope_bytes_compact_utf8":734,"jsonb_rendered_bytes":778},{"stage":"verify","status":"PASS_CLEAN","started_at":"2026-10-14T22:10:49.356431Z","finished_at":"2026-10-14T22:10:49.680891Z","duration_ms":324.46,"queries":{"bytes":527,"count":2,"duration_ms":324.309},"transport":{"bytes":"NOT_OBSERVED","count":"NOT_OBSERVED","duration_ms":"NOT_OBSERVED"},"decision":"PASS_CLEAN","failure":null,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38645579600:verify","envelope_bytes_compact_utf8":760,"jsonb_rendered_bytes":804}]},"negative":{"pr":2691,"run_id":"38640583039","execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","operation":"Remove patch only from actual success snapshot in memory; no DB write or new Train run.","verdict":"FAIL_CLOSED","error":"PASE_F09_015_REQUIRED_STEP_MISSING:patch"}},"retry_chains":{"source":"retry_chains in main after #2697","groups":[{"pr":"2693","migration_name":"lf_pase_f09_015_c3_failure_v1","ordered_by":["created_at","execution_id"],"attempts":[{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","created_at":"2026-10-14T21:34:51.790740Z","migration_version":"20261014213307","status":"BLOCKED"},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","created_at":"2026-10-14T22:10:10.112665Z","migration_version":"20261014221201","status":"COMPLETED"}]}]},"telemetry_envelope_measurement":{"serialization":"compact sorted-key JSON, UTF-8 bytes; also records PostgreSQL JSONB rendered byte count for readback.","max_bytes_observed":1078,"min_bytes_observed":734,"limit_bytes":2560,"within_limit":true,"pr2691_jsonb_rendered_range_bytes":[778,811],"steps":[{"execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","step":"preflight","compact_utf8_bytes":767,"jsonb_rendered_bytes":811},{"execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","step":"patch","compact_utf8_bytes":734,"jsonb_rendered_bytes":778},{"execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","step":"verify","compact_utf8_bytes":761,"jsonb_rendered_bytes":805},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","step":"preflight","compact_utf8_bytes":765,"jsonb_rendered_bytes":809},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","step":"patch","compact_utf8_bytes":1078,"jsonb_rendered_bytes":1129},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","step":"preflight","compact_utf8_bytes":767,"jsonb_rendered_bytes":811},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","step":"patch","compact_utf8_bytes":734,"jsonb_rendered_bytes":778},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","step":"verify","compact_utf8_bytes":760,"jsonb_rendered_bytes":804}]},"owner_decisions":{"origin":"GO de Cristhian, transmitido por Paulo","received_at_lima":"2026-10-14T16:43:32-05:00","D1":{"amends_event_id":20909,"rule":"retry_chains groups by (pr, migration_name without 14-digit version), ordered by created_at and execution_id; each attempt retains migration_version."},"D2":{"rule":"Failed-step evidence remains in receipt; a step row BLOCKED_BY_ENFORCEMENT is acceptable."}},"related_prs":[{"pr":2630,"topic":"Train telemetry recorder/verifier already in main"},{"pr":2648,"topic":"exact fallback hotfix already in main"},{"pr":2697,"topic":"retry_chains groups by PR and migration name","merge_sha":"26b466d130f66be7f3a4b7b13632e6d725449254"}],"resolved_finding":{"finding":"retry_chains by PR+version breaks when the version floor advances and the Train reassigns the retry version.","resolution":"D1 groups by PR+migration_name and retains each attempt migration_version."},"preexisting_test_finding":{"test":"sandbox/lf_contract_gate_test/db_write_transport/test_lf_migration_exact_apply.py","line":55,"commits":["7920da960","6bd147fba"],"observed":"same single AssertionError on clean main and candidate; preserved_tail expects decoded newline while test input contains literal backslash-n.","status":"PREEXISTING_NOT_MODIFIED"},"router":{"router":"ACT-0001","operation_code":"ACTUALIZACION_DB_LF","target_hint":"DB","action_hint":"UPDATE","asset_type_hint":"MIGRATION","status":"READY_TO_EXECUTE","transport":"MIGRATION_VIA_MERGE_TRAIN"},"source_event_ids":[20909,20916],"occurred_at":"SET_BY_MIGRATION"}$f09_015_payload$::jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
     WHERE u.plan_code = c_plan
       AND u.unit_code = c_unit
       AND u.work_item_id = 829
       AND u.disposition = 'ASSIGNED'
       AND w.work_code = u.unit_code
  ) THEN
    RAISE EXCEPTION 'F09_015_CLOSE_PLAN_UNIT_DRIFT';
  END IF;

  SELECT w.status
    INTO v_status
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
   WHERE u.plan_code = c_plan
     AND u.unit_code = c_unit
     AND u.work_item_id = 829
     AND u.disposition = 'ASSIGNED'
     AND w.work_code = u.unit_code
   FOR UPDATE OF w;

  v_evt := EXISTS (
    SELECT 1 FROM public.lf_eventos
     WHERE created_by_execution_id = c_exec
       AND entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
       AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
  );

  IF v_status = 'DONE' AND v_evt THEN
    RETURN;
  END IF;
  IF v_status IS NULL OR v_status NOT IN ('BACKLOG', 'IN_PROGRESS') OR v_evt THEN
    RAISE EXCEPTION 'F09_015_CLOSE_PRESTATE_DRIFT status=% event=%', v_status, v_evt;
  END IF;

  IF v_payload->>'execution_id' IS DISTINCT FROM c_exec
     OR v_payload->>'work_code' IS DISTINCT FROM c_unit
     OR (v_payload->>'work_item_id')::bigint IS DISTINCT FROM 829
     OR jsonb_typeof(v_payload->'acceptance_declared') IS DISTINCT FROM 'boolean'
     OR NOT coalesce((v_payload->>'acceptance_declared')::boolean, false)
     OR v_payload->>'occurred_at' IS DISTINCT FROM 'SET_BY_MIGRATION' THEN
    RAISE EXCEPTION 'F09_015_CLOSE_EVENT_ENVELOPE_DRIFT';
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
   WHERE id = 829 AND status IN ('BACKLOG', 'IN_PROGRESS');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'F09_015_CLOSE_WORK_ITEM_UPDATE_COUNT:%', v_rows;
  END IF;

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO',
    'ENGINEERING_WORK_ITEM',
    c_unit,
    'F09-015 closed from four observed C3 paths, D1/D2 owner GO, and Train/readback evidence.',
    'INFO',
    v_payload,
    'CLAUDE:PASE_GLOBAL09',
    c_exec
  );
END
$f09_015$;
