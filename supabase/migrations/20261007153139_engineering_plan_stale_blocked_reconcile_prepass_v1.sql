create or replace function programacion.fn_engineering_plan_stale_blocked_reconcile_prepass_v1(
  p_plan_code text
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare r record; v_result jsonb; v_count int:=0; v_changed int:=0;
begin
  for r in
    select pu.unit_code,w.id work_item_id
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.disposition='ASSIGNED'
      and w.status='BLOCKED'
      and programacion.fn_engineering_effective_open_blocker_count_v1(w.id)=0
      and not exists(
        select 1 from programacion.fn_engineering_effective_dependencies_v1(w.id) d
        where d.is_unmet
      )
    order by pu.id
  loop
    v_result:=programacion.fn_engineering_stale_blocked_state_reconcile_v1(
      p_plan_code,r.unit_code,true
    );
    v_count:=v_count+1;
    if coalesce((v_result->>'state_changed')::boolean,false) then
      v_changed:=v_changed+1;
    end if;
  end loop;

  return jsonb_build_object(
    'schema_version','ENGINEERING_PLAN_STALE_BLOCKED_RECONCILE_PREPASS_V1',
    'attempted',v_count,'changed',v_changed
  );
end; $$;