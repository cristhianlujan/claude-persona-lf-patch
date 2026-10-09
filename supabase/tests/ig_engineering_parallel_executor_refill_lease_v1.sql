-- Rollback-only, failure-closed regression for ENGINEERING_PARALLEL_EXECUTOR_V1.
-- Run AFTER the corresponding migration is applied. No fixture persists.
DO $ig_executor_test$
DECLARE
  v_start jsonb;
  v_finish jsonb;
  v_run bigint;
  v_unit text;
  v_lane integer;
  v_max_turns integer;
  v_checkpoint_done_before integer;
  v_checkpoint_done_after integer;
  v_rollback_ok boolean:=false;
BEGIN
  SELECT count(*)::integer INTO v_checkpoint_done_before
  FROM programacion.engineering_work_checkpoints c
  JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND c.status='DONE';

  BEGIN
    v_start := programacion.fn_engineering_parallel_executor_start_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','IG_EXECUTOR_REFILL_ROLLBACK_TEST');
    v_run := (v_start->>'run_id')::bigint;
    v_max_turns := (v_start->>'max_turns_per_lane')::integer;
    IF v_max_turns<=2 THEN
      RAISE EXCEPTION 'FAIL_LEGACY_TURN_CAP:%',v_max_turns;
    END IF;
    IF (v_start->>'max_lanes')::integer<>4 THEN
      RAISE EXCEPTION 'FAIL_LANE_COUNT';
    END IF;
    IF jsonb_array_length(v_start->'lanes')<1 THEN
      RAISE EXCEPTION 'FAIL_NO_ELIGIBLE_TEST_UNIT';
    END IF;
    v_unit := v_start#>>'{lanes,0,unit_code}';
    v_lane := (v_start#>>'{lanes,0,lane_no}')::integer;

    -- Unit-local yield + false context_admit must REFILL a different eligible unit.
    v_finish := programacion.fn_engineering_parallel_executor_complete_and_refill_v1(
      v_run,v_lane,1,'YIELDED',
      jsonb_build_object('terminal_action','STOP_ACTION_SPEC_INCOMPLETE',
        'execution_allowed',false,
        'continuation_contract',jsonb_build_object('global_stop',false)),
      false,'CURRENT_UNIT_YIELDED_NO_GLOBAL_STOP');
    IF v_finish->>'executor_outcome'<>'YIELDED'
      OR v_finish->>'scheduler_refill_admitted'<>'true'
      OR jsonb_typeof(v_finish->'next') IS DISTINCT FROM 'object'
      OR v_finish#>>'{next,unit_code}'=v_unit THEN
      RAISE EXCEPTION 'FAIL_YIELD_DID_NOT_REFILL_DIFFERENT_UNIT';
    END IF;

    -- A real global stop must NOT allocate another unit.
    v_finish := programacion.fn_engineering_parallel_executor_complete_and_refill_v1(
      v_run,v_lane,2,'YIELDED',
      jsonb_build_object('terminal_action','STOP_ACTION_SPEC_INCOMPLETE',
        'execution_allowed',false,
        'continuation_contract',jsonb_build_object('global_stop',true)),
      false,'GLOBAL_STOP_EXPLICIT');
    IF v_finish->>'scheduler_refill_admitted'<>'false'
      OR coalesce(jsonb_typeof(v_finish->'next'),'null') <> 'null' THEN
      RAISE EXCEPTION 'FAIL_GLOBAL_STOP_REFILLED';
    END IF;

    RAISE EXCEPTION 'IG_EXECUTOR_TEST_INTENTIONAL_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'IG_EXECUTOR_TEST_INTENTIONAL_ROLLBACK' THEN
      RAISE;
    END IF;
    v_rollback_ok:=true;
  END;

  SELECT count(*)::integer INTO v_checkpoint_done_after
  FROM programacion.engineering_work_checkpoints c
  JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND c.status='DONE';

  IF NOT v_rollback_ok OR v_checkpoint_done_before<>v_checkpoint_done_after
     OR EXISTS(SELECT 1 FROM programacion.engineering_parallel_pilot_runs
               WHERE actor='IG_EXECUTOR_REFILL_ROLLBACK_TEST') THEN
    RAISE EXCEPTION 'FAIL_TEST_ROLLBACK_OR_CHECKPOINT_LEAK';
  END IF;
  RAISE NOTICE 'PASS_IG_EXECUTOR_REFILL_LEASE_V1: 4 lanes, dynamic turns, unit-local refill, explicit global stop, no test residue';
END;
$ig_executor_test$;
