-- PROGRAMMING_SIMPLE_EXECUTOR_V1
-- Fill every free lane after dependency release, not only the lane that just completed.

create or replace function programacion.fn_programming_simple_executor_fill_free_lanes_v1(
  p_run_id bigint,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_run programacion.programming_simple_runs%rowtype;
  v_lane_no integer;
  v_turn integer;
  u record;
  v_refills jsonb:='[]'::jsonb;
  v_filled integer:=0;
begin
  select * into v_run
  from programacion.programming_simple_runs
  where id=p_run_id
  for update;

  if not found or v_run.status<>'RUNNING' then
    raise exception 'PROGRAMMING_SIMPLE_RUNNING_RUN_REQUIRED';
  end if;

  for v_lane_no in 1..v_run.max_lanes loop
    if exists (
      select 1
      from programacion.programming_simple_run_units ru
      where ru.run_id=p_run_id
        and ru.lane_no=v_lane_no
        and ru.status='RUNNING'
    ) then
      continue;
    end if;

    select pu.unit_code,w.id as work_item_id,w.priority
      into u
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code=v_run.plan_code
      and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS')
      and not exists (
        select 1
        from programacion.engineering_work_dependencies d
        join programacion.engineering_plan_units dep
          on dep.plan_code=pu.plan_code
         and dep.work_item_id=d.depends_on_work_item_id
        join programacion.engineering_work_items dw
          on dw.id=dep.work_item_id
        where d.work_item_id=w.id
          and d.relation_type='REQUIRES'
          and dw.status<>'DONE'
      )
      and not exists (
        select 1
        from programacion.programming_simple_run_units ru
        where ru.plan_code=v_run.plan_code
          and ru.unit_code=pu.unit_code
          and ru.status='RUNNING'
      )
      and not exists (
        select 1
        from programacion.programming_simple_run_units ru
        where ru.run_id=p_run_id
          and ru.unit_code=pu.unit_code
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
    limit 1
    for update of w skip locked;

    if not found then
      exit;
    end if;

    select coalesce(max(turn_no),0)+1
      into v_turn
    from programacion.programming_simple_run_units
    where run_id=p_run_id
      and lane_no=v_lane_no;

    insert into programacion.programming_simple_run_units(
      run_id,lane_no,turn_no,plan_code,unit_code,status
    ) values (
      p_run_id,v_lane_no,v_turn,v_run.plan_code,u.unit_code,'RUNNING'
    );

    update programacion.engineering_work_items
       set status='IN_PROGRESS',
           started_at=coalesce(started_at,now()),
           updated_at=now(),
           updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
     where id=u.work_item_id
       and status not in ('DONE','CANCELLED');

    v_filled:=v_filled+1;
    v_refills:=v_refills||jsonb_build_array(
      jsonb_build_object(
        'lane_no',v_lane_no,
        'turn_no',v_turn,
        'unit_code',u.unit_code,
        'bootstrap',programacion.fn_programming_simple_unit_bootstrap_v1(
          p_run_id,v_run.plan_code,u.unit_code
        )
      )
    );
  end loop;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_FILL_FREE_LANES_V1',
    'run_id',p_run_id,
    'plan_code',v_run.plan_code,
    'max_lanes',v_run.max_lanes,
    'filled_lanes',v_filled,
    'refills',v_refills
  );
end;
$function$;

create or replace function programacion.fn_programming_simple_executor_complete_and_refill_v1(
  p_run_id bigint,
  p_unit_code text,
  p_outcome text,
  p_result jsonb default '{}'::jsonb,
  p_actor text default 'PROGRAMMING_SIMPLE_EXECUTOR_V1'
)
returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_run programacion.programming_simple_runs%rowtype;
  v_lane programacion.programming_simple_run_units%rowtype;
  v_work_status text;
  v_fill jsonb;
  v_refills jsonb;
  v_first_refill jsonb;
  v_running integer;
begin
  if p_outcome not in ('DONE','YIELDED','FAILED') then
    raise exception 'PROGRAMMING_SIMPLE_OUTCOME_UNSUPPORTED:%',p_outcome;
  end if;

  select * into v_run
  from programacion.programming_simple_runs
  where id=p_run_id
  for update;

  if not found or v_run.status<>'RUNNING' then
    raise exception 'PROGRAMMING_SIMPLE_RUNNING_RUN_REQUIRED';
  end if;

  select * into v_lane
  from programacion.programming_simple_run_units
  where run_id=p_run_id
    and unit_code=p_unit_code
    and status='RUNNING'
  for update;

  if not found then
    raise exception 'PROGRAMMING_SIMPLE_RUNNING_UNIT_REQUIRED';
  end if;

  select w.status into v_work_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=v_run.plan_code
    and pu.unit_code=p_unit_code;

  if p_outcome='DONE' and v_work_status<>'DONE' then
    raise exception 'PROGRAMMING_SIMPLE_UNIT_NOT_DONE:% status=%',
      p_unit_code,coalesce(v_work_status,'(missing)');
  end if;

  update programacion.programming_simple_run_units
     set status=p_outcome,
         finished_at=now(),
         result=coalesce(p_result,'{}'::jsonb)
   where id=v_lane.id;

  if p_outcome in ('YIELDED','FAILED') then
    update programacion.engineering_work_items w
       set status='BLOCKED',
           updated_at=now(),
           updated_by_execution_id=coalesce(nullif(p_actor,''),'PROGRAMMING_SIMPLE_EXECUTOR_V1')
      from programacion.engineering_plan_units pu
     where pu.plan_code=v_run.plan_code
       and pu.unit_code=p_unit_code
       and pu.work_item_id=w.id
       and w.status not in ('DONE','CANCELLED');
  end if;

  v_fill:=programacion.fn_programming_simple_executor_fill_free_lanes_v1(
    p_run_id,p_actor
  );
  v_refills:=coalesce(v_fill->'refills','[]'::jsonb);
  if jsonb_array_length(v_refills)>0 then
    v_first_refill:=v_refills->0;
  end if;

  select count(*) into v_running
  from programacion.programming_simple_run_units
  where run_id=p_run_id
    and status='RUNNING';

  if v_running=0 then
    update programacion.programming_simple_runs
       set status='COMPLETE',
           finished_at=now(),
           summary=summary||jsonb_build_object(
             'reason','NO_MORE_READY_UNITS',
             'completed_at',now()
           )
     where id=p_run_id;
  end if;

  return jsonb_build_object(
    'schema_version','PROGRAMMING_SIMPLE_EXECUTOR_REFILL_V2',
    'run_id',p_run_id,
    'completed_unit',p_unit_code,
    'outcome',p_outcome,
    'refill',v_first_refill,
    'refills',v_refills,
    'filled_lanes',coalesce((v_fill->>'filled_lanes')::integer,0),
    'run_status',case when v_running=0 then 'COMPLETE' else 'RUNNING' end
  );
end;
$function$;

comment on function programacion.fn_programming_simple_executor_fill_free_lanes_v1(bigint,text) is
'Fills every currently free lane with dependency-clear units up to run.max_lanes. Used after dependency release; never invents dependencies or reruns a unit already seen in the run.';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,estado,source_ref,updated_at
)
values (
  'PROGRAMMING-SIMPLE-REFILL-ALL-FREE-LANES-001',
  'PROGRAMMING_EXECUTOR',
  'Dependency release must refill all free lanes, not only the completing lane',
  'A cold-start run can begin with one READY root unit and several blocked dependents. When the root finishes, multiple units can become READY simultaneously. Refilling only the completed lane serializes work despite configured parallel capacity.',
  'Initial refill logic was lane-local and did not reconsider unused lane numbers after a dependency release.',
  'UNIT DONE -> recompute dependency-clear READY set -> fill every free lane up to max_lanes.',
  'Use fn_programming_simple_executor_fill_free_lanes_v1 after every unit terminal outcome. Preserve one-unit-per-lane ownership and never rerun a unit already present in the run.',
  'Pilot B2B_SHELL_ATOMIC_PILOT_V1: S01.1 starts alone; after DONE, S02.1/S03.1/S04.1 must occupy separate available lanes in the same run.',
  'HIGH','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261007233500_programming_simple_fill_free_lanes_v1.sql',
  now()
)
on conflict (codigo) do update
set titulo=excluded.titulo,descripcion=excluded.descripcion,causa_raiz=excluded.causa_raiz,
    patron=excluded.patron,prevencion=excluded.prevencion,validacion=excluded.validacion,
    severidad=excluded.severidad,estado=excluded.estado,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
