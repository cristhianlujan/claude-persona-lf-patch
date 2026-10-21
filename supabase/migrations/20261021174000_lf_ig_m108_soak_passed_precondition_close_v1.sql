-- IG M10.8 SOAK_PASSED_PRECONDITION closure.
-- Exact declared readback confirmed M10.7 DONE.
-- No production activation and no domain mutation beyond checkpoint ledger.

BEGIN;

DO $close$
DECLARE
  v_m107_status text;
  v_m108_status text;
  v_cp record;
  v_transition jsonb;
  v_progress numeric;
BEGIN
  SELECT w.status
    INTO v_m107_status
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.disposition='ASSIGNED'
    AND u.unit_code='M10.7';

  SELECT w.status
    INTO v_m108_status
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.disposition='ASSIGNED'
    AND u.unit_code='M10.8';

  IF v_m107_status IS DISTINCT FROM 'DONE'
     OR v_m108_status IS DISTINCT FROM 'IN_PROGRESS'
  THEN
    RAISE EXCEPTION 'M108_SOAK_PRECONDITION_STATE_DRIFT:m107=% m108=%',
      v_m107_status,v_m108_status;
  END IF;

  SELECT status,evidence_ref,assertion_receipt_sha256
    INTO v_cp
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=479
    AND checkpoint_code='SOAK_PASSED_PRECONDITION'
  FOR UPDATE;

  IF v_cp.status IS DISTINCT FROM 'PENDING'
     OR v_cp.evidence_ref IS NOT NULL
     OR v_cp.assertion_receipt_sha256 IS NOT NULL
  THEN
    RAISE EXCEPTION 'M108_SOAK_PRECONDITION_CP_DRIFT:%',row_to_json(v_cp);
  END IF;

  v_transition := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.8',
    'SOAK_PASSED_PRECONDITION',
    'DONE',
    'supabase://programacion.engineering_plan_units+engineering_work_items?plan=IG_CURATOR_VALIDATOR_REFACTOR_V2;M10.7=DONE;M10.8=IN_PROGRESS',
    'GPT_NATIVE:M10.8:SOAK_PASSED_PRECONDITION',
    'Exact declared readback PASS: M10.7 work item PAULO-165 status=DONE; M10.8 PAULO-166 status=IN_PROGRESS. No production authorization implied.'
  );

  IF v_transition#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_transition#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN
    RAISE EXCEPTION 'M108_SOAK_PRECONDITION_TRANSITION_FAIL:%',v_transition;
  END IF;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress
  WHERE id=479;

  IF v_progress IS DISTINCT FROM 35.00 THEN
    RAISE EXCEPTION 'M108_SOAK_PRECONDITION_PROGRESS_FAIL:%',v_progress;
  END IF;
END
$close$;

COMMIT;
