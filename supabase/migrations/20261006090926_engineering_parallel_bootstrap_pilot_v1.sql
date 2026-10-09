
create table if not exists programacion.engineering_parallel_pilot_runs (
  id bigint generated always as identity primary key,
  plan_code text not null,
  status text not null default 'RUNNING'
    check (status in ('RUNNING','DONE','STOPPED')),
  max_lanes integer not null default 2 check (max_lanes = 2),
  max_turns_per_lane integer not null default 2 check (max_turns_per_lane = 2),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  actor text not null,
  summary jsonb not null default '{}'::jsonb
);

create table if not exists programacion.engineering_parallel_pilot_lane_runs (
  id bigint generated always as identity primary key,
  run_id bigint not null references programacion.engineering_parallel_pilot_runs(id) on delete cascade,
  lane_no integer not null check (lane_no between 1 and 2),
  turn_no integer not null check (turn_no between 1 and 2),
  plan_code text not null,
  unit_code text not null,
  status text not null default 'RUNNING'
    check (status in ('RUNNING','SUCCESS','ERROR','STOP_CONTEXT','NO_CANDIDATE')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  lease_expires_at timestamptz not null default (now() + interval '15 minutes'),
  bootstrap_terminal_action text,
  bootstrap_engine_variant text,
  bootstrap_execution_allowed boolean,
  result_summary text,
  context_admit boolean,
  context_reason text,
  unique (run_id,lane_no,turn_no),
  unique (run_id,unit_code)
);

create unique index if not exists uq_engineering_parallel_pilot_active_unit
on programacion.engineering_parallel_pilot_lane_runs(plan_code,unit_code)
where status='RUNNING';

alter table programacion.engineering_parallel_pilot_runs enable row level security;
alter table programacion.engineering_parallel_pilot_lane_runs enable row level security;

revoke all on programacion.engineering_parallel_pilot_runs from anon, authenticated;
revoke all on programacion.engineering_parallel_pilot_lane_runs from anon, authenticated;

create or replace function programacion.fn_engineering_parallel_pilot_pick_unit_v1(
  p_plan_code text,
  p_run_id bigint
) returns text
language plpgsql
as $$
declare
  v_unit_code text;
begin
  update programacion.engineering_parallel_pilot_lane_runs
     set status='ERROR',
         finished_at=coalesce(finished_at,now()),
         result_summary=coalesce(result_summary,'LEASE_EXPIRED')
   where status='RUNNING'
     and lease_expires_at < now();

  select pu.unit_code
    into v_unit_code
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w
    on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code
    and pu.disposition='ASSIGNED'
    and w.status in ('BACKLOG','READY')
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

  return v_unit_code;
end;
$$;

create or replace function programacion.fn_engineering_parallel_pilot_start_v1(
  p_plan_code text,
  p_actor text default 'ENGINEERING_PARALLEL_PILOT_V1'
) returns jsonb
language plpgsql
as $$
declare
  v_run_id bigint;
  v_lane integer;
  v_unit text;
  v_lanes jsonb := '[]'::jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_PILOT:'||p_plan_code));

  insert into programacion.engineering_parallel_pilot_runs(
    plan_code,status,max_lanes,max_turns_per_lane,actor
  ) values (
    p_plan_code,'RUNNING',2,2,coalesce(nullif(p_actor,''),'ENGINEERING_PARALLEL_PILOT_V1')
  )
  returning id into v_run_id;

  for v_lane in 1..2 loop
    v_unit:=programacion.fn_engineering_parallel_pilot_pick_unit_v1(p_plan_code,v_run_id);
    if v_unit is null then
      exit;
    end if;

    insert into programacion.engineering_parallel_pilot_lane_runs(
      run_id,lane_no,turn_no,plan_code,unit_code,status
    ) values (
      v_run_id,v_lane,1,p_plan_code,v_unit,'RUNNING'
    );

    v_lanes:=v_lanes || jsonb_build_array(
      jsonb_build_object(
        'lane_no',v_lane,
        'turn_no',1,
        'unit_code',v_unit,
        'status','RUNNING'
      )
    );
  end loop;

  if jsonb_array_length(v_lanes)=0 then
    update programacion.engineering_parallel_pilot_runs
       set status='DONE',finished_at=now(),
           summary=jsonb_build_object('reason','NO_ELIGIBLE_UNITS')
     where id=v_run_id;
  end if;

  return jsonb_build_object(
    'pilot_contract','ENGINEERING_PARALLEL_BOOTSTRAP_PILOT_V1',
    'run_id',v_run_id,
    'max_lanes',2,
    'max_turns_per_lane',2,
    'max_total_runs',4,
    'lane_count',jsonb_array_length(v_lanes),
    'lanes',v_lanes
  );
end;
$$;

create or replace function programacion.fn_engineering_parallel_pilot_complete_and_refill_v1(
  p_run_id bigint,
  p_lane_no integer,
  p_turn_no integer,
  p_outcome text,
  p_bootstrap jsonb,
  p_context_admit boolean,
  p_context_reason text default null
) returns jsonb
language plpgsql
as $$
declare
  v_plan_code text;
  v_unit text;
  v_next_unit text;
  v_next_turn integer;
  v_next jsonb;
  v_active integer;
  v_run_status text;
begin
  if p_outcome not in ('SUCCESS','ERROR') then
    raise exception 'Unsupported pilot outcome: %',p_outcome;
  end if;

  perform pg_advisory_xact_lock(hashtext('ENGINEERING_PARALLEL_PILOT_RUN:'||p_run_id::text));

  select plan_code,unit_code
    into v_plan_code,v_unit
  from programacion.engineering_parallel_pilot_lane_runs
  where run_id=p_run_id
    and lane_no=p_lane_no
    and turn_no=p_turn_no
    and status='RUNNING'
  for update;

  if v_plan_code is null then
    raise exception 'Active lane turn not found: run %, lane %, turn %',
      p_run_id,p_lane_no,p_turn_no;
  end if;

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
         context_reason=p_context_reason
   where run_id=p_run_id
     and lane_no=p_lane_no
     and turn_no=p_turn_no;

  if p_turn_no < 2 and coalesce(p_context_admit,false) then
    v_next_turn:=p_turn_no+1;
    v_next_unit:=programacion.fn_engineering_parallel_pilot_pick_unit_v1(v_plan_code,p_run_id);

    if v_next_unit is not null then
      insert into programacion.engineering_parallel_pilot_lane_runs(
        run_id,lane_no,turn_no,plan_code,unit_code,status
      ) values (
        p_run_id,p_lane_no,v_next_turn,v_plan_code,v_next_unit,'RUNNING'
      );

      v_next:=jsonb_build_object(
        'lane_no',p_lane_no,
        'turn_no',v_next_turn,
        'unit_code',v_next_unit,
        'status','RUNNING'
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
             'contract_max_total_runs',4
           )
     where id=p_run_id;
  end if;

  select status into v_run_status
  from programacion.engineering_parallel_pilot_runs
  where id=p_run_id;

  return jsonb_build_object(
    'run_id',p_run_id,
    'lane_no',p_lane_no,
    'completed_turn',p_turn_no,
    'completed_unit',v_unit,
    'outcome',p_outcome,
    'context_admit',p_context_admit,
    'next',v_next,
    'active_lanes',v_active,
    'run_status',v_run_status
  );
end;
$$;

create or replace function programacion.fn_engineering_parallel_pilot_status_v1(
  p_run_id bigint
) returns jsonb
language sql
stable
as $$
select jsonb_build_object(
  'run_id',r.id,
  'plan_code',r.plan_code,
  'status',r.status,
  'max_lanes',r.max_lanes,
  'max_turns_per_lane',r.max_turns_per_lane,
  'max_total_runs',r.max_lanes*r.max_turns_per_lane,
  'started_at',r.started_at,
  'finished_at',r.finished_at,
  'summary',r.summary,
  'lanes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'lane_no',lr.lane_no,
      'turn_no',lr.turn_no,
      'unit_code',lr.unit_code,
      'status',lr.status,
      'started_at',lr.started_at,
      'finished_at',lr.finished_at,
      'bootstrap_terminal_action',lr.bootstrap_terminal_action,
      'bootstrap_engine_variant',lr.bootstrap_engine_variant,
      'bootstrap_execution_allowed',lr.bootstrap_execution_allowed,
      'context_admit',lr.context_admit,
      'context_reason',lr.context_reason,
      'result_summary',lr.result_summary
    ) order by lr.lane_no,lr.turn_no)
    from programacion.engineering_parallel_pilot_lane_runs lr
    where lr.run_id=r.id
  ),'[]'::jsonb)
)
from programacion.engineering_parallel_pilot_runs r
where r.id=p_run_id;
$$;
