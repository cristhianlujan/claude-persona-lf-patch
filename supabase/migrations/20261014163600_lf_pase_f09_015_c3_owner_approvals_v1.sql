-- PASE-ATOM-F09-015 owner approvals for Fase C, step 3.
-- Data-only event through ACTUALIZACION_DB_LF + Merge Train; no unit-state transition.
DO $f09ownerapprovals$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_unit constant text := 'PASE-ATOM-F09-015';
  c_work_item constant bigint := 829;
  c_migration_suffix constant text := '_lf_pase_f09_015_c3_owner_approvals_v1';
  c_decision_key constant text := 'PASE-ATOM-F09-015-C3-OWNER-APPROVALS-20261014-1130-LIMA';
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
    RAISE EXCEPTION 'F09_015_C3_OWNER_APPROVAL_UNIT_BINDING_DRIFT';
  END IF;

  SELECT status INTO v_status
    FROM programacion.engineering_work_items
   WHERE id = c_work_item AND work_code = c_unit;
  IF v_status NOT IN ('BACKLOG', 'IN_PROGRESS') THEN
    RAISE EXCEPTION 'F09_015_C3_OWNER_APPROVAL_UNEXPECTED_WORK_ITEM_STATUS:%', v_status;
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
    RAISE EXCEPTION 'F09_015_C3_OWNER_APPROVAL_TRAIN_EXECUTION_NOT_UNIQUE:%', v_exec_count;
  END IF;

  INSERT INTO public.lf_eventos (
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO',
    'ENGINEERING_WORK_ITEM',
    c_unit,
    'Owner confirmations recorded before Fase C merges and C3; no unit closure or runtime activation.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version', 'operational-event/v2',
      'purpose', 'Record owner confirmations for PASE-ATOM-F09-015 Fase C step 3 before any authorized merge or C3 test run.',
      'producer', 'CLAUDE:PASE_GLOBAL09',
      'decision_record_key', c_decision_key,
      'owner_confirmation', 'OWNER_CONFIRMED',
      'execution_id', v_exec,
      'work_item_id', c_work_item,
      'work_code', c_unit,
      'plan_code', c_plan,
      'decided_by', 'CRISTHIAN (owner)',
      'decided_at', '2026-10-14T11:30:00-05:00',
      'approvals', jsonb_build_array(
        jsonb_build_object(
          'approval_id', 1,
          'topic', 'merge_telemetry_pr',
          'owner_confirmation', 'OWNER_CONFIRMED',
          'pr', 2630,
          'evidence', '24 pruebas locales ejecutadas sin fallos',
          'workflow_state', 'PASE workflow disabled on main; recorded in the PR'
        ),
        jsonb_build_object(
          'approval_id', 2,
          'topic', 'merge_router_documentation_pr',
          'owner_confirmation', 'OWNER_CONFIRMED',
          'pr', 2629,
        ),
        jsonb_build_object(
          'approval_id', 3,
          'topic', 'c3_sandbox_execution',
          'owner_confirmation', 'OWNER_CONFIRMED',
          'project_ref', 'mhwmirqcgxxukpctffuv',
          'permanent_test_migration_residue', 'Remains in the migration ledger and main by owner direction.'
        ),
        jsonb_build_object(
          'approval_id', 4,
          'topic', 'train_lane_timing_budget',
          'owner_confirmation', 'OWNER_CONFIRMED',
          'basis_event_id', 20570,
          'decision', 'F09-013 caps from events 20394/20395 do not apply to the Merge Train lane.',
          'measurement_label', 'DIAGNOSTIC_TRAIN_LANE_PRE_F07_X01',
          'official_measurement_deferred_until', 'PASE-ATOM-F07-X01'
        ),
        jsonb_build_object(
          'approval_id', 5,
          'topic', 'ekb_runtime',
          'owner_confirmation', 'OWNER_CONFIRMED',
          'runtime', 'public.lf_write_pipeline_ekb_v1',
        )
      ),
      'execution_order', jsonb_build_array(
        'record_owner_approvals',
        'merge_pr_2630',
        'merge_pr_2629',
        'readback_recorder_and_verifier_on_main',
        'ekb_recurrence_note',
        'c3_success_failure_retry_negative'
      ),
      'router_resolver_ref_inconsistency', 'SUPABASE_MCP remains a report-only finding; do not correct in this unit.',
      'test_migration_residue', 'Remains in the migration ledger and main by owner direction.',
      's28_applies', false,
      'schema_change', false,
      'production_activation', false,
      'unit_state_transition', false,
      'acceptance_declared', false,
      'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'CLAUDE:PASE_GLOBAL09',
    v_exec
  );
END
$f09ownerapprovals$;

