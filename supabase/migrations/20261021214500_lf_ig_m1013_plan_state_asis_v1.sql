-- IG M10.13 / PLAN_STATE_ASIS only.
-- Exact one-time observation of the canonical IG ledger; no domain/runtime changes.
-- Route: PR -> CI -> PASE -> LF Migration Merge Train -> Supabase readback.
BEGIN;

DO $ig_m1013_plan_state$
DECLARE
  v_assigned integer;
  v_done integer;
  v_m10_total integer;
  v_m10_other_done integer;
  v_unmet integer;
  v_open_blockers integer;
  v_checkpoint_total integer;
  v_checkpoint_done integer;
  v_current_status text;
  v_progress numeric;
  v_spec jsonb;
  v_result jsonb;
BEGIN
  SELECT count(*) FILTER (WHERE u.disposition='ASSIGNED'),
         count(*) FILTER (WHERE u.disposition='ASSIGNED' AND w.status='DONE'),
         count(*) FILTER (WHERE u.disposition='ASSIGNED' AND u.unit_code LIKE 'M10.%'),
         count(*) FILTER (WHERE u.disposition='ASSIGNED' AND u.unit_code LIKE 'M10.%'
                             AND u.unit_code<>'M10.13' AND w.status='DONE')
    INTO v_assigned,v_done,v_m10_total,v_m10_other_done
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';

  SELECT status INTO v_current_status
  FROM programacion.engineering_work_items WHERE id=474 FOR UPDATE;

  SELECT count(*), count(*) FILTER (WHERE status='DONE')
  INTO v_checkpoint_total,v_checkpoint_done
  FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=474;

  SELECT count(*) INTO v_unmet
  FROM programacion.fn_engineering_effective_dependencies_v1(474) d
  WHERE d.is_unmet;

  SELECT programacion.fn_engineering_effective_open_blocker_count_v1(474)
  INTO v_open_blockers;

  IF v_assigned <> 171 OR v_done <> 170
     OR v_m10_total <> 14 OR v_m10_other_done <> 13
     OR v_current_status IS DISTINCT FROM 'BACKLOG'
     OR v_checkpoint_total <> 7 OR v_checkpoint_done <> 0
     OR v_unmet <> 0 OR v_open_blockers <> 0
     OR NOT EXISTS (
       SELECT 1 FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=474 AND checkpoint_code='PLAN_STATE_ASIS'
         AND sequence_no=1 AND status='PENDING' AND evidence_ref IS NULL
     )
  THEN
    RAISE EXCEPTION 'M1013_PLAN_STATE_PRESTATE_DRIFT assigned=% done=% m10=% m10_others=% work=% checkpoints=% done_cp=% deps=% blockers=%',
      v_assigned,v_done,v_m10_total,v_m10_other_done,v_current_status,
      v_checkpoint_total,v_checkpoint_done,v_unmet,v_open_blockers;
  END IF;

  v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.13','PLAN_STATE_ASIS');

  IF v_spec->>'status' IS DISTINCT FROM 'READY'
     OR v_spec->>'action_kind' IS DISTINCT FROM 'OBSERVE_ONCE'
     OR v_spec->>'mutation_policy' IS DISTINCT FROM 'NO_DOMAIN_MUTATION'
  THEN
    RAISE EXCEPTION 'M1013_PLAN_STATE_SPEC_DRIFT:%',v_spec;
  END IF;

  v_result := programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'M10.13','PLAN_STATE_ASIS','DONE',
    'supabase://programacion.engineering_plan_units/IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.13#PLAN_STATE_ASIS',
    'GPT_NATIVE:M10.13:PLAN_STATE_ASIS',
    'Observed canonical ledger: 171 assigned, 170 DONE, 14 assigned M10.x, the 13 other M10.x DONE; M10.13 BACKLOG 0/7; 0 unmet dependencies; 0 effective blockers. No runtime/production change.'
  );

  IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_result#>>'{transition,new_status}' IS DISTINCT FROM 'DONE'
  THEN RAISE EXCEPTION 'M1013_PLAN_STATE_TRANSITION_FAILED:%',v_result; END IF;

  SELECT status INTO v_current_status
  FROM programacion.engineering_work_items WHERE id=474;

  SELECT count(*) FILTER (WHERE status='DONE')
  INTO v_checkpoint_done
  FROM programacion.engineering_work_checkpoints WHERE work_item_id=474;

  SELECT progress_pct INTO v_progress
  FROM programacion.v_engineering_work_progress WHERE id=474;

  IF v_current_status IS DISTINCT FROM 'IN_PROGRESS'
     OR v_checkpoint_done <> 1
     OR v_progress <= 0 OR v_progress >= 100
  THEN
    RAISE EXCEPTION 'M1013_PLAN_STATE_POSTCHECK_FAILED status=% done=% progress=%',
      v_current_status,v_checkpoint_done,v_progress;
  END IF;
END
$ig_m1013_plan_state$;
COMMIT;
