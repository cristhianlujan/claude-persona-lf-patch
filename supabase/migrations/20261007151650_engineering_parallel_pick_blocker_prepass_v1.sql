create or replace function programacion.fn_engineering_parallel_pilot_pick_unit_v1(
  p_plan_code text,
  p_run_id bigint
) returns text
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  v_unit text;
begin
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
end; $$;