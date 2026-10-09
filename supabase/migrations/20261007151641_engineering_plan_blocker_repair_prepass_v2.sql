create or replace function programacion.fn_engineering_plan_blocker_repair_prepass_v2(
  p_plan_code text
) returns jsonb
language plpgsql
set search_path to programacion,public,pg_catalog
as $$
declare
  r record;
  v_cp text;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
  v_attempted int:=0;
  v_changed int:=0;
begin
  for r in
    select pu.unit_code
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_items w on w.id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.disposition='ASSIGNED'
      and w.status in ('BACKLOG','READY','IN_PROGRESS','BLOCKED')
      and programacion.fn_engineering_effective_open_blocker_count_v1(w.id)>0
    order by pu.id
  loop
    select c.checkpoint_code into v_cp
    from programacion.engineering_plan_units pu
    join programacion.engineering_work_checkpoints c on c.work_item_id=pu.work_item_id
    where pu.plan_code=p_plan_code
      and pu.unit_code=r.unit_code
      and c.status not in ('DONE','NOT_APPLICABLE')
    order by c.sequence_no
    limit 1;

    if v_cp is null then
      continue;
    end if;

    v_result:=programacion.fn_engineering_blocker_family_dispatch_v1(
      p_plan_code,r.unit_code,v_cp,true
    );
    v_attempted:=v_attempted+1;
    if coalesce((v_result->>'state_changed')::boolean,false) then
      v_changed:=v_changed+1;
    end if;
    v_results:=v_results||jsonb_build_array(
      jsonb_build_object('unit_code',r.unit_code,'checkpoint_code',v_cp,'result',v_result)
    );
  end loop;

  return jsonb_build_object(
    'schema_version','ENGINEERING_PLAN_BLOCKER_REPAIR_PREPASS_V2',
    'plan_code',p_plan_code,
    'attempted',v_attempted,
    'changed',v_changed,
    'results',v_results
  );
end; $$;