create or replace function programacion.fn_engineering_parallel_executor_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_legacy jsonb;
begin
  v_legacy := programacion.fn_engineering_parallel_pilot_start_v1(
    p_plan_code,
    coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  );

  return (v_legacy - 'pilot_contract' - 'execution_scope')
    || jsonb_build_object(
      'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
      'execution_scope','UNIT_TO_TERMINAL',
      'unit_loop',jsonb_build_array(
        'BOOTSTRAP_V3',
        'EXECUTE_CURRENT_PACKET',
        'HEARTBEAT_WHEN_REQUIRED',
        'CHECKPOINT_TRANSITION',
        'USE_RETURNED_BOOTSTRAP',
        'REPEAT_UNTIL_UNIT_TERMINAL_OR_YIELD'
      ),
      'success_guard','WORK_ITEM_DONE_AND_REQUIRED_CHECKPOINTS_TERMINAL',
      'legacy_scheduler_storage',true
    );
end;
$$;

create or replace function programacion.fn_engineering_parallel_executor_complete_and_refill_v1(
  p_run_id bigint,
  p_lane_no integer,
  p_turn_no integer,
  p_outcome text,
  p_bootstrap jsonb,
  p_context_admit boolean,
  p_context_reason text default null
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_plan_code text;
  v_unit_code text;
  v_work_item_id bigint;
  v_work_status text;
  v_required_open integer;
  v_legacy_outcome text;
  v_result jsonb;
begin
  if p_outcome not in ('SUCCESS','YIELDED','ERROR') then
    raise exception 'Unsupported executor outcome: %',p_outcome;
  end if;

  select lr.plan_code,lr.unit_code,pu.work_item_id,w.status
    into v_plan_code,v_unit_code,v_work_item_id,v_work_status
  from programacion.engineering_parallel_pilot_lane_runs lr
  join programacion.engineering_plan_units pu
    on pu.plan_code=lr.plan_code and pu.unit_code=lr.unit_code
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where lr.run_id=p_run_id
    and lr.lane_no=p_lane_no
    and lr.turn_no=p_turn_no
    and lr.status='RUNNING';

  if v_unit_code is null then
    raise exception 'Active executor lane turn not found: run %, lane %, turn %',
      p_run_id,p_lane_no,p_turn_no;
  end if;

  select count(*)::integer
    into v_required_open
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id
    and c.required
    and c.status not in ('DONE','NOT_APPLICABLE');

  if p_outcome='SUCCESS'
     and (v_work_status <> 'DONE' or v_required_open <> 0) then
    raise exception
      'UNIT_NOT_TERMINAL: %/% status=% required_open=%; SUCCESS forbidden until unit terminal',
      v_plan_code,v_unit_code,coalesce(v_work_status,'NULL'),v_required_open;
  end if;

  v_legacy_outcome := case when p_outcome='SUCCESS' then 'SUCCESS' else 'ERROR' end;

  v_result := programacion.fn_engineering_parallel_pilot_complete_and_refill_v1(
    p_run_id,
    p_lane_no,
    p_turn_no,
    v_legacy_outcome,
    p_bootstrap,
    p_context_admit,
    p_context_reason
  );

  if p_outcome='YIELDED' then
    update programacion.engineering_parallel_pilot_lane_runs
       set result_summary='UNIT_YIELDED',
           context_reason=coalesce(nullif(p_context_reason,''),'CURRENT_UNIT_YIELDED')
     where run_id=p_run_id
       and lane_no=p_lane_no
       and turn_no=p_turn_no;
  elsif p_outcome='ERROR' then
    update programacion.engineering_parallel_pilot_lane_runs
       set result_summary='UNIT_EXECUTION_ERROR'
     where run_id=p_run_id
       and lane_no=p_lane_no
       and turn_no=p_turn_no;
  else
    update programacion.engineering_parallel_pilot_lane_runs
       set result_summary='UNIT_TERMINAL_SUCCESS'
     where run_id=p_run_id
       and lane_no=p_lane_no
       and turn_no=p_turn_no;
  end if;

  return v_result || jsonb_build_object(
    'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
    'execution_scope','UNIT_TO_TERMINAL',
    'executor_outcome',p_outcome,
    'unit_status_after',v_work_status,
    'required_checkpoints_open_after',v_required_open
  );
end;
$$;

create or replace function programacion.fn_engineering_parallel_executor_status_v1(
  p_run_id bigint
)
returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
select jsonb_build_object(
  'executor_contract','ENGINEERING_PARALLEL_EXECUTOR_V1',
  'execution_scope','UNIT_TO_TERMINAL',
  'run_id',r.id,
  'plan_code',r.plan_code,
  'status',r.status,
  'max_lanes',r.max_lanes,
  'max_turns_per_lane',r.max_turns_per_lane,
  'max_total_runs',r.max_lanes*r.max_turns_per_lane,
  'started_at',r.started_at,
  'finished_at',r.finished_at,
  'summary',coalesce(r.summary,'{}'::jsonb) || jsonb_build_object(
    'checkpoints_completed',
      coalesce((select sum(coalesce(lrx.checkpoints_done_delta,0))
                from programacion.engineering_parallel_pilot_lane_runs lrx
                where lrx.run_id=r.id),0),
    'units_terminal_success',
      (select count(*) from programacion.engineering_parallel_pilot_lane_runs lrx
       where lrx.run_id=r.id and lrx.result_summary='UNIT_TERMINAL_SUCCESS'),
    'units_yielded',
      (select count(*) from programacion.engineering_parallel_pilot_lane_runs lrx
       where lrx.run_id=r.id and lrx.result_summary='UNIT_YIELDED'),
    'unit_execution_errors',
      (select count(*) from programacion.engineering_parallel_pilot_lane_runs lrx
       where lrx.run_id=r.id and lrx.result_summary='UNIT_EXECUTION_ERROR')
  ),
  'lanes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'lane_no',lr.lane_no,
      'turn_no',lr.turn_no,
      'unit_code',lr.unit_code,
      'status',case
        when lr.result_summary='UNIT_YIELDED' then 'YIELDED'
        when lr.result_summary='UNIT_EXECUTION_ERROR' then 'ERROR'
        else lr.status
      end,
      'started_at',lr.started_at,
      'finished_at',lr.finished_at,
      'bootstrap_terminal_action',lr.bootstrap_terminal_action,
      'bootstrap_engine_variant',lr.bootstrap_engine_variant,
      'bootstrap_execution_allowed',lr.bootstrap_execution_allowed,
      'context_admit',lr.context_admit,
      'context_reason',lr.context_reason,
      'result_summary',lr.result_summary,
      'checkpoint_total',lr.checkpoint_total,
      'checkpoints_done_before',lr.checkpoints_done_before,
      'checkpoints_done_after',lr.checkpoints_done_after,
      'checkpoints_done_delta',lr.checkpoints_done_delta
    ) order by lr.lane_no,lr.turn_no)
    from programacion.engineering_parallel_pilot_lane_runs lr
    where lr.run_id=r.id
  ),'[]'::jsonb)
)
from programacion.engineering_parallel_pilot_runs r
where r.id=p_run_id;
$$;

comment on function programacion.fn_engineering_parallel_pilot_start_v1(text,text)
is 'LEGACY compatibility scheduler storage entrypoint. Canonical executable entrypoint: fn_engineering_parallel_executor_start_v1.';

comment on function programacion.fn_engineering_parallel_pilot_complete_and_refill_v1(bigint,integer,integer,text,jsonb,boolean,text)
is 'LEGACY compatibility completion primitive. Canonical executable completion guard: fn_engineering_parallel_executor_complete_and_refill_v1.';

comment on function programacion.fn_engineering_parallel_pilot_status_v1(bigint)
is 'LEGACY bootstrap-only status. Canonical executable status: fn_engineering_parallel_executor_status_v1.';
