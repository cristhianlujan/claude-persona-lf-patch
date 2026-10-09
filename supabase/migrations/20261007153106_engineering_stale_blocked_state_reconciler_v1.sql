create or replace function programacion.fn_engineering_stale_blocked_state_reconcile_v1(
  p_plan_code text,p_unit_code text,p_apply boolean default true
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_work_item_id bigint; v_status text; v_cp text;
  v_blockers int:=0; v_unmet int:=0; v_result jsonb;
begin
  select pu.work_item_id,w.status into v_work_item_id,v_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code and pu.disposition='ASSIGNED';

  if v_work_item_id is null then
    return jsonb_build_object('schema_version','ENGINEERING_STALE_BLOCKED_STATE_RECONCILER_V1',
      'status','UNIT_NOT_FOUND','state_changed',false);
  end if;

  if v_status<>'BLOCKED' then
    return jsonb_build_object('schema_version','ENGINEERING_STALE_BLOCKED_STATE_RECONCILER_V1',
      'status','NOT_APPLICABLE','work_status',v_status,'state_changed',false);
  end if;

  v_blockers:=programacion.fn_engineering_effective_open_blocker_count_v1(v_work_item_id);
  select count(*)::int into v_unmet
  from programacion.fn_engineering_effective_dependencies_v1(v_work_item_id) d
  where d.is_unmet;

  select c.checkpoint_code into v_cp
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.status not in ('DONE','NOT_APPLICABLE')
  order by c.sequence_no limit 1;

  if v_blockers>0 or v_unmet>0 or v_cp is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_STALE_BLOCKED_STATE_RECONCILER_V1',
      'status','PRESERVED_REAL_BLOCKED_STATE',
      'open_blockers',v_blockers,'unmet_dependencies',v_unmet,
      'current_checkpoint',v_cp,'state_changed',false
    );
  end if;

  if not p_apply then
    return jsonb_build_object(
      'schema_version','ENGINEERING_STALE_BLOCKED_STATE_RECONCILER_V1',
      'status','DRY_RUN_READY','current_checkpoint',v_cp,'state_changed',false
    );
  end if;

  v_result:=programacion.fn_engineering_checkpoint_transition_v1(
    p_plan_code,p_unit_code,v_cp,'IN_PROGRESS',
    'supabase://programacion.fn_engineering_stale_blocked_state_reconcile_v1#0-blockers;0-unmet',
    'ENGINEERING_STALE_BLOCKED_STATE_RECONCILER_V1',
    'Reconciled stale BLOCKED work-item state without advancing checkpoint.'
  );

  return jsonb_build_object(
    'schema_version','ENGINEERING_STALE_BLOCKED_STATE_RECONCILER_V1',
    'status','RECONCILED_TO_IN_PROGRESS',
    'current_checkpoint',v_cp,
    'bootstrap',v_result,
    'state_changed',true
  );
end; $$;