-- ENGINEERING_PARALLEL_EXECUTOR_V1: raise scheduler width from 2 to 4 lanes.
-- Scope: lane capacity only. max_turns_per_lane remains 2.

create or replace function programacion.fn_engineering_parallel_scheduler_storage_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_run_id bigint;
  v_lane integer;
  v_unit text;
  v_work_item_id bigint;
  v_checkpoint_total integer;
  v_done_before integer;
  v_lanes jsonb := '[]'::jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_EXECUTOR:'||p_plan_code));

  insert into programacion.engineering_parallel_pilot_runs(
    plan_code,status,max_lanes,max_turns_per_lane,actor
  ) values (
    p_plan_code,'RUNNING',4,2,coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
  )
  returning id into v_run_id;

  for v_lane in 1..4 loop
    v_unit:=programacion.fn_engineering_parallel_pilot_pick_unit_v1(p_plan_code,v_run_id);
    if v_unit is null then
      exit;
    end if;

    select pu.work_item_id
      into v_work_item_id
    from programacion.engineering_plan_units pu
    where pu.plan_code=p_plan_code
      and pu.unit_code=v_unit
    limit 1;

    select count(*)::integer,
           count(*) filter (where c.status='DONE')::integer
      into v_checkpoint_total,v_done_before
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id;

    insert into programacion.engineering_parallel_pilot_lane_runs(
      run_id,lane_no,turn_no,plan_code,unit_code,status,
      checkpoint_total,checkpoints_done_before
    ) values (
      v_run_id,v_lane,1,p_plan_code,v_unit,'RUNNING',
      v_checkpoint_total,v_done_before
    );

    v_lanes:=v_lanes || jsonb_build_array(
      jsonb_build_object(
        'lane_no',v_lane,
        'turn_no',1,
        'unit_code',v_unit,
        'status','RUNNING',
        'checkpoint_total',v_checkpoint_total,
        'checkpoints_done_before',v_done_before
      )
    );
  end loop;

  if jsonb_array_length(v_lanes)=0 then
    update programacion.engineering_parallel_pilot_runs
       set status='DONE',finished_at=now(),
           summary=jsonb_build_object(
             'reason','NO_ELIGIBLE_UNITS',
             'checkpoints_completed',0
           )
     where id=v_run_id;
  end if;

  return jsonb_build_object(
    'scheduler_storage_contract','ENGINEERING_PARALLEL_SCHEDULER_STORAGE_V1',
    'run_id',v_run_id,
    'max_lanes',4,
    'max_turns_per_lane',2,
    'max_total_runs',8,
    'lane_count',jsonb_array_length(v_lanes),
    'lanes',v_lanes
  );
end;
$function$;

create or replace function programacion.fn_engineering_parallel_scheduler_storage_complete_and_refill_v1(
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
as $function$
declare
  v_plan_code text;
  v_unit text;
  v_work_item_id bigint;
  v_done_before integer;
  v_done_after integer;
  v_checkpoint_total integer;
  v_done_delta integer;
  v_next_unit text;
  v_next_turn integer;
  v_next_work_item_id bigint;
  v_next_checkpoint_total integer;
  v_next_done_before integer;
  v_next jsonb;
  v_active integer;
  v_run_status text;
begin
  if p_outcome not in ('SUCCESS','ERROR') then
    raise exception 'Unsupported scheduler storage outcome: %',p_outcome;
  end if;

  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_EXECUTOR_RUN:'||p_run_id::text));

  select lr.plan_code,lr.unit_code,lr.checkpoints_done_before,lr.checkpoint_total,
         pu.work_item_id
    into v_plan_code,v_unit,v_done_before,v_checkpoint_total,v_work_item_id
  from programacion.engineering_parallel_pilot_lane_runs lr
  join programacion.engineering_plan_units pu
    on pu.plan_code=lr.plan_code
   and pu.unit_code=lr.unit_code
  where lr.run_id=p_run_id
    and lr.lane_no=p_lane_no
    and lr.turn_no=p_turn_no
    and lr.status='RUNNING'
  for update of lr;

  if v_plan_code is null then
    raise exception 'Active lane turn not found: run %, lane %, turn %',
      p_run_id,p_lane_no,p_turn_no;
  end if;

  select count(*) filter (where c.status='DONE')::integer
    into v_done_after
  from programacion.engineering_work_checkpoints c
  where c.work_item_id=v_work_item_id;

  v_done_before:=coalesce(v_done_before,v_done_after,0);
  v_done_after:=coalesce(v_done_after,0);
  v_done_delta:=greatest(v_done_after-v_done_before,0);

  update programacion.engineering_parallel_pilot_lane_runs
     set status=p_outcome,
         finished_at=now(),
         bootstrap_terminal_action=p_bootstrap->>'terminal_action',
         bootstrap_engine_variant=p_bootstrap->>'engine_variant',
         bootstrap_execution_allowed=coalesce((p_bootstrap->>'execution_allowed')::boolean,false),
         result_summary=case
           when p_outcome='SUCCESS' then 'BOOTSTRAP_RETURNED'
           else 'BOOTSTRAP_ERROR'
         end,
         context_admit=p_context_admit,
         context_reason=p_context_reason,
         checkpoints_done_after=v_done_after,
         checkpoints_done_delta=v_done_delta
   where run_id=p_run_id
     and lane_no=p_lane_no
     and turn_no=p_turn_no;

  if p_turn_no < 2 and coalesce(p_context_admit,false) then
    v_next_turn:=p_turn_no+1;
    v_next_unit:=programacion.fn_engineering_parallel_pilot_pick_unit_v1(v_plan_code,p_run_id);

    if v_next_unit is not null then
      select pu.work_item_id
        into v_next_work_item_id
      from programacion.engineering_plan_units pu
      where pu.plan_code=v_plan_code
        and pu.unit_code=v_next_unit
      limit 1;

      select count(*)::integer,
             count(*) filter (where c.status='DONE')::integer
        into v_next_checkpoint_total,v_next_done_before
      from programacion.engineering_work_checkpoints c
      where c.work_item_id=v_next_work_item_id;

      insert into programacion.engineering_parallel_pilot_lane_runs(
        run_id,lane_no,turn_no,plan_code,unit_code,status,
        checkpoint_total,checkpoints_done_before
      ) values (
        p_run_id,p_lane_no,v_next_turn,v_plan_code,v_next_unit,'RUNNING',
        v_next_checkpoint_total,v_next_done_before
      );

      v_next:=jsonb_build_object(
        'lane_no',p_lane_no,
        'turn_no',v_next_turn,
        'unit_code',v_next_unit,
        'status','RUNNING',
        'checkpoint_total',v_next_checkpoint_total,
        'checkpoints_done_before',v_next_done_before
      );
    end if;
  end if;

  select count(*) into v_active
  from programacion.engineering_parallel_pilot_lane_runs
  where run_id=p_run_id and status='RUNNING';

  if v_active=0 then
    update programacion.engineering_parallel_pilot_runs
       set status='DONE',
           finished_at=now(),
           summary=jsonb_build_object(
             'completed_lane_runs',
             (select count(*) from programacion.engineering_parallel_pilot_lane_runs
               where run_id=p_run_id and status in ('SUCCESS','ERROR')),
             'contract_max_total_runs',8,
             'checkpoints_completed',
             (select coalesce(sum(checkpoints_done_delta),0)
                from programacion.engineering_parallel_pilot_lane_runs
               where run_id=p_run_id)
           )
     where id=p_run_id;
  end if;

  select status into v_run_status
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id;

  return jsonb_build_object(
    'scheduler_storage_contract','ENGINEERING_PARALLEL_SCHEDULER_STORAGE_V1',
    'run_id',p_run_id,
    'lane_no',p_lane_no,
    'completed_turn',p_turn_no,
    'completed_unit',v_unit,
    'outcome',p_outcome,
    'context_admit',p_context_admit,
    'checkpoint_total',v_checkpoint_total,
    'checkpoints_done_before',v_done_before,
    'checkpoints_done_after',v_done_after,
    'checkpoints_done_delta',v_done_delta,
    'next',v_next,
    'active_lanes',v_active,
    'run_status',v_run_status
  );
end;
$function$;

update public.lf_error_knowledge
set evidencia=concat_ws(E'\n',nullif(evidencia,''),'[FOUR_LANE_CONFIG_20261007] ENGINEERING_PARALLEL_EXECUTOR_V1 scheduler storage configured max_lanes=4, max_turns_per_lane=2, max_total_runs=8.'),
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-PARALLEL-EXECUTOR-V1-001';
