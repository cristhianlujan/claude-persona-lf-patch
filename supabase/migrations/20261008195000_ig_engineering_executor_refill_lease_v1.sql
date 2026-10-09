-- IG parallel executor: unit-local yield != global stop; plan-bounded refill; expired claims.
-- Non-production activation not implied. No unit checkpoint is marked DONE here.
-- Uses the live Supabase source definitions frozen at repair time.

alter table programacion.engineering_parallel_pilot_runs
  drop constraint engineering_parallel_pilot_runs_max_turns_per_lane_check;
alter table programacion.engineering_parallel_pilot_runs
  add constraint engineering_parallel_pilot_runs_max_turns_per_lane_check check(max_turns_per_lane >= 1);
alter table programacion.engineering_parallel_pilot_lane_runs
  drop constraint engineering_parallel_pilot_lane_runs_turn_no_check;
alter table programacion.engineering_parallel_pilot_lane_runs
  add constraint engineering_parallel_pilot_lane_runs_turn_no_check check(turn_no >= 1);

create or replace function programacion.fn_engineering_parallel_lease_reconcile_v1(p_plan_code text)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $lease$
declare
  v_lane record;
  v_done integer;
  v_reclaimed integer := 0;
  v_runs_stopped integer := 0;
begin
  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_EXECUTOR:'||p_plan_code));
  -- 24-hour grace beyond expiry protects long material steps from premature reclaim.
  for v_lane in
    select lr.id,lr.unit_code,lr.checkpoints_done_before
    from programacion.engineering_parallel_pilot_lane_runs lr
    join programacion.engineering_parallel_pilot_runs r on r.id=lr.run_id
    where r.plan_code=p_plan_code and r.status='RUNNING'
      and lr.status='RUNNING'
      and lr.lease_expires_at < now()-interval '24 hours'
    for update of lr
  loop
    select count(*) filter(where c.status='DONE')::integer into v_done
    from programacion.engineering_work_checkpoints c
    join programacion.engineering_plan_units pu on pu.work_item_id=c.work_item_id
    where pu.plan_code=p_plan_code and pu.unit_code=v_lane.unit_code;
    update programacion.engineering_parallel_pilot_lane_runs
       set status='ERROR',finished_at=now(),
           result_summary='UNIT_YIELDED_LEASE_EXPIRED',
           context_admit=false,
           context_reason='LEASE_EXPIRED_24H_NO_ACTIVE_WORKER_CONFIRMATION',
           checkpoints_done_after=v_done,
           checkpoints_done_delta=greatest(v_done-coalesce(v_lane.checkpoints_done_before,0),0)
     where id=v_lane.id and status='RUNNING';
    v_reclaimed:=v_reclaimed+1;
  end loop;
  update programacion.engineering_parallel_pilot_runs r
     set status='STOPPED',finished_at=now(),
         summary=coalesce(r.summary,'{}'::jsonb)||
           jsonb_build_object('reason','STALE_LEASE_RECONCILED','expired_lanes_released',true)
   where r.plan_code=p_plan_code and r.status='RUNNING'
     and exists(select 1 from programacion.engineering_parallel_pilot_lane_runs x
       where x.run_id=r.id and x.result_summary='UNIT_YIELDED_LEASE_EXPIRED')
     and not exists(select 1 from programacion.engineering_parallel_pilot_lane_runs x
       where x.run_id=r.id and x.status='RUNNING');
  get diagnostics v_runs_stopped = row_count;
  return jsonb_build_object('schema_version','ENGINEERING_LEASE_RECONCILE_V1',
    'expired_lanes_reclaimed',v_reclaimed,'runs_stopped',v_runs_stopped,
    'no_checkpoint_auto_completion',true);
end;
$lease$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_pilot_pick_unit_v1(p_plan_code text, p_run_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_unit text;
begin
  perform programacion.fn_engineering_parallel_lease_reconcile_v1(p_plan_code);
  perform programacion.fn_engineering_plan_stale_blocked_reconcile_prepass_v1(p_plan_code);
  perform programacion.fn_engineering_plan_blocker_repair_prepass_v2(p_plan_code);

  select pu.unit_code
    into v_unit
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and w.status in ('BACKLOG','READY','IN_PROGRESS')
    and programacion.fn_engineering_effective_open_blocker_count_v1(w.id)=0
    and not exists (
      select 1
      from programacion.fn_engineering_effective_dependencies_v1(w.id) d
      where d.is_unmet
    )
    and not exists (
      select 1
      from programacion.engineering_parallel_pilot_lane_runs lr
      where lr.plan_code=p_plan_code
        and lr.unit_code=pu.unit_code
        and lr.status='RUNNING'
    )
    and not exists (
      select 1
      from programacion.engineering_parallel_pilot_lane_runs lr
      where lr.run_id=p_run_id
        and lr.unit_code=pu.unit_code
    )
  order by
    case w.priority
      when 'P0' then 0
      when 'P1' then 1
      when 'P2' then 2
      when 'P3' then 3
      else 9
    end,
    pu.id
  limit 1;

  return v_unit;
end; $function$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_scheduler_storage_start_v1(p_plan_code text, p_actor text DEFAULT 'ENGINEERING_PARALLEL_EXECUTOR_V1'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_run_id bigint;
  v_lane integer;
  v_unit text;
  v_work_item_id bigint;
  v_checkpoint_total integer;
  v_done_before integer;
  v_lanes jsonb := '[]'::jsonb;
  v_frontier jsonb := '[]'::jsonb;
  v_turns integer;
begin
  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_EXECUTOR:'||p_plan_code));

  -- Budget is bounded by the plan's real assigned work, not by a legacy 2-turn pilot.
  select greatest(1,count(*)::integer) into v_turns
  from programacion.engineering_plan_units u
  join programacion.engineering_work_items w on w.id=u.work_item_id
  where u.plan_code=p_plan_code and u.disposition='ASSIGNED'
    and w.status in ('BACKLOG','READY','IN_PROGRESS','BLOCKED');

  insert into programacion.engineering_parallel_pilot_runs(
    plan_code,status,max_lanes,max_turns_per_lane,actor
  ) values (
    p_plan_code,'RUNNING',4,v_turns,coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_EXECUTOR_V1')
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'unit_code',f.unit_code,
        'work_code',f.work_code,
        'work_status',f.work_status,
        'unlocks_count',f.unlocks_count,
        'max_depth',f.max_depth,
        'blocker_count',f.blocker_count,
        'blockers',f.blockers,
        'running_elsewhere',f.running_elsewhere,
        'executable',f.executable,
        'selection_reason',f.selection_reason
      )
      order by f.executable desc, f.unlocks_count desc, f.work_item_id
    ),
    '[]'::jsonb
  )
  into v_frontier
  from programacion.fn_engineering_parallel_dependency_frontier_v1(p_plan_code) f;

  if jsonb_array_length(v_lanes)=0 then
    update programacion.engineering_parallel_pilot_runs
       set status='DONE',finished_at=now(),
           summary=jsonb_build_object(
             'reason',
             case
               when jsonb_array_length(v_frontier)>0 then 'NO_EXECUTABLE_FRONTIER'
               else 'NO_ELIGIBLE_UNITS'
             end,
             'checkpoints_completed',0,
             'dependency_frontier',v_frontier
           )
     where id=v_run_id;
  end if;

  return jsonb_build_object(
    'scheduler_storage_contract','ENGINEERING_PARALLEL_SCHEDULER_STORAGE_V1',
    'run_id',v_run_id,
    'max_lanes',4,
    'max_turns_per_lane',v_turns,
    'max_total_runs',4*v_turns,
    'lane_count',jsonb_array_length(v_lanes),
    'lanes',v_lanes,
    'dependency_frontier',v_frontier
  );
end;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_scheduler_storage_complete_and_refill_v(p_run_id bigint, p_lane_no integer, p_turn_no integer, p_outcome text, p_bootstrap jsonb, p_context_admit boolean, p_context_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
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
  v_max_turns integer;
  v_max_lanes integer;
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

  select r.max_turns_per_lane,r.max_lanes into v_max_turns,v_max_lanes
  from programacion.engineering_parallel_pilot_runs r where r.id=p_run_id;

  if p_turn_no < coalesce(v_max_turns,1) and coalesce(p_context_admit,false) then
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
             'contract_max_total_runs',v_max_turns*v_max_lanes,
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

CREATE OR REPLACE FUNCTION programacion.fn_engineering_parallel_executor_complete_and_refill_v1(p_run_id bigint, p_lane_no integer, p_turn_no integer, p_outcome text, p_bootstrap jsonb, p_context_admit boolean, p_context_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'programacion', 'public', 'pg_catalog'
AS $function$
declare
  v_plan_code text;
  v_unit_code text;
  v_work_item_id bigint;
  v_work_status text;
  v_required_open integer;
  v_storage_outcome text;
  v_result jsonb;
  v_refill_admitted boolean;
  v_global_stop boolean;
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

  v_storage_outcome := case when p_outcome='SUCCESS' then 'SUCCESS' else 'ERROR' end;

  -- A unit-local yield/error does not stop independent lanes. An explicit global
  -- stop still prevents refill; legacy context_admit is retained as telemetry.
  v_global_stop := coalesce((p_bootstrap->'continuation_contract'->>'global_stop')::boolean,false)
    or coalesce(p_context_reason,'') ~* '^(GLOBAL_STOP|CONTEXT_BUDGET_EXHAUSTED|USER_CANCELLED)';
  v_refill_admitted := not v_global_stop and
    (coalesce(p_context_admit,false) or p_outcome in ('YIELDED','ERROR'));

  v_result := programacion.fn_engineering_parallel_scheduler_storage_complete_and_refill_v1(
    p_run_id,
    p_lane_no,
    p_turn_no,
    v_storage_outcome,
    p_bootstrap,
    v_refill_admitted,
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
    'scheduler_refill_admitted',v_refill_admitted,
    'context_admit_requested',p_context_admit,
    'unit_status_after',v_work_status,
    'required_checkpoints_open_after',v_required_open
  );
end;
$function$;
