-- F09-015 closure: observed C3 success, failure, retry and fail-closed negative evidence.
DO $f09_015$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-015';
  c_exec constant text := 'CLAUDE-PASE-F09-015-CLOSE-20261014-001';
  v_status text;
  v_evt boolean;
  v_rows integer;
  v_payload jsonb := $f09_015_payload${"evidence_schema_version":"operational-event/v2","purpose":"Registrar hechos medidos y referencias para reconstruir los cuatro caminos C3 de F09-015.","producer":"CLAUDE:PASE_GLOBAL09","execution_id":"CLAUDE-PASE-F09-015-CLOSE-20261014-001","plan_code":"LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1","work_code":"PASE-ATOM-F09-015","work_item_id":829,"acceptance_declared":false,"c3_paths":[{"path_id":"c3_success","pr":2691,"run_id":"38640583039","execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","execution_state":"COMPLETED","migration_name":"lf_pase_f09_015_c3_success_v1","migration_version":"20261014212500","merge_sha":"2602ccbe45af9ca097dd91050ae26e3b3435e3a0","steps":[{"stage":"preflight","started_at":"2026-10-14T21:29:30.007453Z","finished_at":"2026-10-14T21:29:31.287812Z","duration_ms":1280.359,"query_count":4,"query_bytes":2353,"query_duration_ms":1277.626,"transport_count":null,"transport_bytes":null,"transport_duration_ms":null,"envelope_compact_utf8_bytes":767,"envelope_jsonb_rendered_bytes":811,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38640583039:preflight"},{"stage":"patch","started_at":"2026-10-14T21:29:32.218321Z","finished_at":"2026-10-14T21:29:37.266045Z","duration_ms":5047.724,"query_count":13,"query_bytes":5857,"query_duration_ms":4626.665,"transport_count":1,"transport_bytes":9882,"transport_duration_ms":312.998,"envelope_compact_utf8_bytes":734,"envelope_jsonb_rendered_bytes":778,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38640583039:patch"},{"stage":"verify","started_at":"2026-10-14T21:30:01.992452Z","finished_at":"2026-10-14T21:30:02.936395Z","duration_ms":943.943,"query_count":2,"query_bytes":527,"query_duration_ms":943.785,"transport_count":null,"transport_bytes":null,"transport_duration_ms":null,"envelope_compact_utf8_bytes":761,"envelope_jsonb_rendered_bytes":805,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38640583039:verify"}]},{"path_id":"c3_failure","pr":2693,"run_id":"38641270448","execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","execution_state":"BLOCKED","migration_name":"lf_pase_f09_015_c3_failure_v1","migration_version":"20261014213307","merge_sha":"sin merge","steps":[{"stage":"preflight","started_at":"2026-10-14T21:34:51.625397Z","finished_at":"2026-10-14T21:34:52.568876Z","duration_ms":943.479,"query_count":4,"query_bytes":2353,"query_duration_ms":941.062,"transport_count":null,"transport_bytes":null,"transport_duration_ms":null,"envelope_compact_utf8_bytes":765,"envelope_jsonb_rendered_bytes":809,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38641270448:preflight"},{"stage":"patch","started_at":"2026-10-14T21:34:53.209228Z","finished_at":"2026-10-14T21:34:54.864549Z","duration_ms":1655.321,"query_count":10,"query_bytes":3158,"query_duration_ms":1465.138,"transport_count":1,"transport_bytes":9882,"transport_duration_ms":91.659,"envelope_compact_utf8_bytes":1078,"envelope_jsonb_rendered_bytes":1129,"evidence_locator":"github-run:exact-apply-receipt"}]},{"path_id":"c3_retry","pr":2693,"run_id":"38645579600","execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","execution_state":"COMPLETED","migration_name":"lf_pase_f09_015_c3_failure_v1","migration_version":"20261014221201","merge_sha":"5d84fe7ca2f52b720902d2bc3e90fbe9fc8e534e","steps":[{"stage":"preflight","started_at":"2026-10-14T22:10:09.678586Z","finished_at":"2026-10-14T22:10:12.152269Z","duration_ms":2473.683,"query_count":4,"query_bytes":2353,"query_duration_ms":2461.375,"transport_count":null,"transport_bytes":null,"transport_duration_ms":null,"envelope_compact_utf8_bytes":767,"envelope_jsonb_rendered_bytes":811,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38645579600:preflight"},{"stage":"patch","started_at":"2026-10-14T22:10:13.430348Z","finished_at":"2026-10-14T22:10:20.561052Z","duration_ms":7130.704,"query_count":13,"query_bytes":5857,"query_duration_ms":6455.541,"transport_count":1,"transport_bytes":9882,"transport_duration_ms":579.856,"envelope_compact_utf8_bytes":734,"envelope_jsonb_rendered_bytes":778,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38645579600:patch"},{"stage":"verify","started_at":"2026-10-14T22:10:49.356431Z","finished_at":"2026-10-14T22:10:49.680891Z","duration_ms":324.46,"query_count":2,"query_bytes":527,"query_duration_ms":324.309,"transport_count":null,"transport_bytes":null,"transport_duration_ms":null,"envelope_compact_utf8_bytes":760,"envelope_jsonb_rendered_bytes":804,"evidence_locator":"LF-MIGRATION-TRAIN-RUN-38645579600:verify"}]},{"path_id":"c3_negative_required_step_missing","pr":2691,"run_id":"38640583039","execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","execution_state":"COMPLETED","migration_name":"lf_pase_f09_015_c3_success_v1","migration_version":"20261014212500","merge_sha":"2602ccbe45af9ca097dd91050ae26e3b3435e3a0","method":"Se quitó patch solo del snapshot en memoria; comprobación de solo lectura.","missing_step":"patch","verifier_error_code":"PASE_F09_015_REQUIRED_STEP_MISSING:patch","step_evidence_table":"public.lf_operation_execution_steps"}],"retry_chain":{"grouping_key":["pr","migration_name_without_14_digit_version"],"pr":2693,"migration_name":"lf_pase_f09_015_c3_failure_v1","ordered_by":["created_at","execution_id"],"attempts":[{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","created_at":"2026-10-14T21:34:51.790740Z","migration_version":"20261014213307","execution_state":"BLOCKED"},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","created_at":"2026-10-14T22:10:10.112665Z","migration_version":"20261014221201","execution_state":"COMPLETED"}]},"step_evidence_source":"public.lf_operation_execution_steps, indexed by execution_id; per-step evidence remains in those rows.","telemetry_envelope_bytes":{"serialization":"compact sorted-key JSON UTF-8; JSONB rendered size recorded for readback","minimum_observed":734,"maximum_observed":1078,"limit":2560,"measurements":[{"execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","stage":"preflight","compact_utf8_bytes":767,"jsonb_rendered_bytes":811},{"execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","stage":"patch","compact_utf8_bytes":734,"jsonb_rendered_bytes":778},{"execution_id":"EXEC-DB-TRAIN-PR2691-20261014212500-R38640583039","stage":"verify","compact_utf8_bytes":761,"jsonb_rendered_bytes":805},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","stage":"preflight","compact_utf8_bytes":765,"jsonb_rendered_bytes":809},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014213307-R38641270448","stage":"patch","compact_utf8_bytes":1078,"jsonb_rendered_bytes":1129},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","stage":"preflight","compact_utf8_bytes":767,"jsonb_rendered_bytes":811},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","stage":"patch","compact_utf8_bytes":734,"jsonb_rendered_bytes":778},{"execution_id":"EXEC-DB-TRAIN-PR2693-20261014221201-R38645579600","stage":"verify","compact_utf8_bytes":760,"jsonb_rendered_bytes":804}]},"owner_decisions":{"origin":"GO de Cristhian transmitido por Paulo","received_at_lima":"2026-10-14T16:43:32-05:00","D1":{"amends_event_id":20909,"rule":"retry_chains agrupa por (pr, migration_name sin prefijo de 14 dígitos), ordenado por created_at y execution_id; cada intento conserva migration_version."},"D2":{"rule":"La evidencia de paso fallido permanece en el recibo; el tratamiento con bloqueo de enforcement en la fila del paso queda dentro de lo aprobado por el owner."}},"related_prs":[{"pr":2630,"reference":"Recorder, exact_apply, pase_f09_015_telemetry.py y verificador incorporados a main."},{"pr":2648,"reference":"Hotfix de fallback exacto ante fallo del dry-run."},{"pr":2697,"merge_sha":"26b466d130f66be7f3a4b7b13632e6d725449254","reference":"retry_chains agrupa por PR+migration_name."}],"resolved_finding":"retry_chains por PR+versión se rompía cuando avanzaba el piso y el Train reasignaba la versión; D1 lo resuelve al agrupar por PR+migration_name y conservar la versión por intento.","preexisting_test_finding":{"test":"sandbox/lf_contract_gate_test/db_write_transport/test_lf_migration_exact_apply.py","line":55,"commits":["7920da960","6bd147fba"],"observation":"El mismo AssertionError aparece en main limpio y candidato porque la prueba usa backslash-n literal donde espera newline decodificado; no se modificó."},"router_route":"ACT-0001: DB / UPDATE / MIGRATION → ACTUALIZACION_DB_LF; DB_WRITE_TRANSPORT → MIGRATION_VIA_MERGE_TRAIN","source_event_ids":[20909,20916],"occurred_at":"SET_BY_MIGRATION"}$f09_015_payload$::jsonb;
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
     OR coalesce((v_payload->>'acceptance_declared')::boolean, true)
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
