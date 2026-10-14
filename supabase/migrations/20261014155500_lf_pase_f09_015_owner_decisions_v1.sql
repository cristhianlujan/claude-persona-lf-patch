-- PASE/POST-PASE owner decisions for PASE-ATOM-F09-015.
-- Data-only event through ACTUALIZACION_DB_LF + Merge Train; no work-item state transition.
BEGIN;

DO $f09owner$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-015';
  c_work_item constant bigint := 829;
  c_migration_suffix constant text := '_lf_pase_f09_015_owner_decisions_v1';
  c_decision_key constant text := 'PASE-ATOM-F09-015-OWNER-DECISIONS-20261014';
  v_status text;
  v_exec_count integer;
  v_exec text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
     WHERE u.plan_code = c_plan
       AND u.unit_code = c_unit
       AND u.work_item_id = c_work_item
       AND u.disposition = 'ASSIGNED'
       AND w.work_code = c_unit
  ) THEN
    RAISE EXCEPTION 'F09_015_OWNER_DECISION_UNIT_BINDING_DRIFT';
  END IF;

  SELECT status INTO v_status
    FROM programacion.engineering_work_items
   WHERE id = c_work_item AND work_code = c_unit;
  IF v_status NOT IN ('BACKLOG', 'IN_PROGRESS') THEN
    RAISE EXCEPTION 'F09_015_OWNER_DECISION_UNEXPECTED_WORK_ITEM_STATUS:%', v_status;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.lf_eventos
     WHERE entidad_tipo = 'ENGINEERING_WORK_ITEM'
       AND entidad_codigo = c_unit
       AND payload->>'decision_record_key' = c_decision_key
  ) THEN
    RETURN;
  END IF;

  SELECT count(*)::integer, min(execution_id)
    INTO v_exec_count, v_exec
    FROM public.lf_operation_execution
   WHERE operation_code = 'ACTUALIZACION_DB_LF'
     AND target_type = 'MIGRATION'
     AND right(target_code, length(c_migration_suffix)) = c_migration_suffix
     AND target_repo = 'cristhianlujan/claude-persona-lf-patch'
     AND right(target_path, length(c_migration_suffix || '.sql')) = c_migration_suffix || '.sql'
     AND status = 'IN_PROGRESS'
     AND execution_id LIKE 'EXEC-DB-TRAIN-PR%';
  IF v_exec_count <> 1 OR v_exec IS NULL THEN
    RAISE EXCEPTION 'F09_015_OWNER_DECISION_TRAIN_EXECUTION_NOT_UNIQUE:%', v_exec_count;
  END IF;

  INSERT INTO public.lf_eventos (
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO',
    'ENGINEERING_WORK_ITEM',
    c_unit,
    'Owner decisions recorded for PASE-ATOM-F09-015; no unit closure or runtime activation.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version', 'operational-event/v2',
      'purpose', 'Record the owner-approved design decisions before Fase C instrumentation and C3.',
      'producer', 'CLAUDE:PASE_GLOBAL09',
      'decision_record_key', c_decision_key,
      'execution_id', v_exec,
      'work_item_id', c_work_item,
      'work_code', c_unit,
      'plan_code', c_plan,
      'decided_by', 'CRISTHIAN (owner)',
      'decided_at', '2026-10-14T10:47:00-05:00',
      'decisions', jsonb_build_array(
        jsonb_build_object(
          'decision_id', 1,
          'topic', 'telemetry_envelope_bytes',
          'status', 'ACCEPTED',
          'decision', 'Exclude the telemetry envelope from the F09-013 byte growth ratio 1.0.',
          'envelope_max_bytes_per_step', 2560,
          'encoding', 'UTF-8',
          'serialization', 'serialized JSON',
          'over_limit', 'REJECT; do not adjust the cap'
        ),
        jsonb_build_object(
          'decision_id', 2,
          'topic', 'failed_step_row',
          'status', 'ACCEPTED',
          'decision', 'A failed step may emit its own row only on the failure path.',
          'f09_013_zero_delta_scope', 'SUCCESS_PATH'
        ),
        jsonb_build_object(
          'decision_id', 3,
          'topic', 'retry_reconstruction',
          'status', 'ACCEPTED',
          'decision', 'Reconstruct retry chains at read time by same PR and migration version, ordered by time; emitter does not calculate attempts or query prior runs.',
          'envelope_fields_removed', jsonb_build_array('attempt_number', 'retry_of_execution_id')
        ),
        jsonb_build_object(
          'decision_id', 4,
          'topic', 'evidence_ledger',
          'status', 'OPEN_QUESTION',
          'decision', 'Absence of Evidence Ledger rows is not an anomaly; leave as an owner question. No implementation in this phase.'
        ),
        jsonb_build_object(
          'decision_id', 5,
          'topic', 'router_read_only_connector',
          'status', 'ACCEPTED',
          'decision', 'Read-only connector reads are outside Router.'
        )
      ),
      'router_claude_md_text_accepted',
      'Read-only database inspection through the Supabase RO connector is outside Router routing. Limit it to the authorized inspection scope and do not use it to write. Every database write must resolve Router first and follow ACTUALIZACION_DB_LF through the Merge Train.',
      'router_startup_line_accepted',
      'Read-only inspection: use the Supabase RO connector outside Router; do not write. For any write, resolve Router first and use ACTUALIZACION_DB_LF via the Merge Train.',
      's28_applies', false,
      'schema_change', false,
      'production_activation', false,
      'acceptance_declared', false,
      'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'CLAUDE:PASE_GLOBAL09',
    v_exec
  );
END
$f09owner$;

COMMIT;
