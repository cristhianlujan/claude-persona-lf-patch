-- PASE/POST-PASE (LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1)
-- Close PASE-ATOM-F07-X01 under owner decision 2026-10-13:
--   * typed Train receipt live (event type MIGRATION_TRAIN_RECEIPT_RECORDED,
--     canary receipt event 20803, owner decisions 20800 and 20802);
--   * the fail-closed pre-apply check set (no skipped/neutral) moves to
--     PASE-ATOM-F09-X16, which already requires it as a precondition; the
--     workflow patch is prepared for the Train code owner.
-- Does not change the Train workflow, rulesets or any other unit.
DO $x01$
DECLARE
  c_plan constant text := 'LF_PASE_POST_PASE_GLOBAL_ARCHITECTURE_V1';
  c_exec constant text := 'CLAUDE-PASE-F07-X01-CLOSE-20261013';
  c_x16_criterion constant text := 'FAIL_CLOSED_PRE_APPLY_CHECKS: Train accepts only success for lf-independent-change-admission and ig-runtime-candidate-judge (no skipped/neutral); workflow patch prepared for the Train code owner (moved from F07-X01 by owner decision 2026-10-13)';
  v_x01 text;
  v_x16 jsonb;
  v_evt boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM programacion.engineering_plan_units u
                  JOIN programacion.engineering_work_items w ON w.id = u.work_item_id
                 WHERE u.plan_code = c_plan AND u.unit_code = 'PASE-ATOM-F07-X01'
                   AND u.disposition = 'ASSIGNED' AND w.work_code = u.unit_code)
  THEN RAISE EXCEPTION 'F07_X01_CLOSE_PLAN_UNIT_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_eventos
       WHERE (id IN (20800, 20802) AND evento_tipo = 'PLAN_SNAPSHOT_DETALLADO'
              AND entidad_codigo = 'PASE-ATOM-F07-X01')
          OR (id = 20803 AND evento_tipo = 'MIGRATION_TRAIN_RECEIPT_RECORDED'
              AND payload->>'receipt_schema' = 'LF_MIGRATION_TRAIN_RECEIPT_V1'
              AND payload#>>'{receipt,terminal_status}' = 'COMPLETED')) <> 3
  THEN RAISE EXCEPTION 'F07_X01_CLOSE_EVIDENCE_MISSING'; END IF;

  SELECT status INTO v_x01 FROM programacion.engineering_work_items
   WHERE work_code = 'PASE-ATOM-F07-X01' FOR UPDATE;
  SELECT acceptance_criteria INTO v_x16 FROM programacion.engineering_work_items
   WHERE work_code = 'PASE-ATOM-F09-X16' AND status = 'BACKLOG' FOR UPDATE;
  IF v_x16 IS NULL THEN RAISE EXCEPTION 'F07_X01_CLOSE_X16_DRIFT'; END IF;
  v_evt := EXISTS (SELECT 1 FROM public.lf_eventos
                    WHERE created_by_execution_id = c_exec AND entidad_codigo = 'PASE-ATOM-F07-X01');

  IF v_x01 = 'DONE' AND v_evt THEN
    RETURN;  -- already applied
  END IF;
  IF v_x01 IS DISTINCT FROM 'IN_PROGRESS' OR v_evt THEN
    RAISE EXCEPTION 'F07_X01_CLOSE_PRESTATE_DRIFT status=% event=%', v_x01, v_evt;
  END IF;

  IF NOT v_x16 @> jsonb_build_array(c_x16_criterion) THEN
    UPDATE programacion.engineering_work_items
       SET acceptance_criteria = acceptance_criteria || jsonb_build_array(c_x16_criterion),
           updated_by_execution_id = c_exec
     WHERE work_code = 'PASE-ATOM-F09-X16';
  END IF;

  UPDATE programacion.engineering_work_items
     SET status = 'DONE', completed_at = now(), updated_by_execution_id = c_exec
   WHERE work_code = 'PASE-ATOM-F07-X01';

  INSERT INTO public.lf_eventos(
    evento_tipo, entidad_tipo, entidad_codigo, descripcion, severidad,
    payload, origen, created_by_execution_id
  ) VALUES (
    'PLAN_SNAPSHOT_DETALLADO', 'ENGINEERING_WORK_ITEM', 'PASE-ATOM-F07-X01',
    'X01 closed by owner decision: typed Train receipt live (canary receipt 20803); fail-closed pre-apply checks and POST-PASE receipt verifier carried by F09-X16.',
    'INFO',
    jsonb_build_object(
      'evidence_schema_version', 'operational-event/v2',
      'purpose', 'Record closure of PASE-ATOM-F07-X01 with its evidence and the items carried to F09-X16',
      'producer', 'CLAUDE:PASE_GLOBAL07',
      'execution_id', c_exec,
      'work_code', 'PASE-ATOM-F07-X01',
      'closure_basis', 'OWNER_DECISION_2026-10-13',
      'decided_by', 'PAULO (owner PASE/POST-PASE), chat 2026-10-13',
      'owner_decision_event_ids', jsonb_build_array(20800, 20802),
      'receipt_capability', jsonb_build_object(
        'schema', 'LF_MIGRATION_TRAIN_RECEIPT_V1',
        'event_type', 'MIGRATION_TRAIN_RECEIPT_RECORDED',
        'writer', 'public.lf_record_migration_train_receipt_v1',
        'canary_receipt_event_id', 20803,
        'prs', jsonb_build_array(2483, 2484, 2487)),
      'carried_to_f09_x16', jsonb_build_array(
        'POST_PASE_VERIFIES_F07_X01_TRAIN_RECEIPT',
        'FAIL_CLOSED_PRE_APPLY_CHECKS'),
      'acceptance_declared', false,
      'occurred_at', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    ),
    'CLAUDE:PASE_GLOBAL07', c_exec
  );
END
$x01$;
