create or replace function programacion.fn_open_dependency_integration_blockers()
returns trigger
language plpgsql
set search_path = pg_catalog, programacion
as $function$
declare d record;
begin
  if old.definition_status='DRAFT' and new.definition_status='SEALED' then
    for d in select depends_on_task_id from programacion.task_dependencies where task_id=new.id order by depends_on_task_id loop
      insert into programacion.task_blockers(task_id,blocker_code,owner_type,owner_ref,required_action,source_ref,status)
      values(
        new.id,
        'DEPENDENCY_INTEGRATION_REQUIRED',
        'REPOSITORY_INTEGRATION',
        'agent-task://'||d.depends_on_task_id,
        'INTEGRATE_VERIFIED_PREDECESSOR_THEN_SUPERSEDE_AND_RESEAL_WITH_INTEGRATED_CHANGED_PATHS',
        'task-dependency://'||new.id||'/'||d.depends_on_task_id,
        'OPEN'
      )
      on conflict (task_id,blocker_code,source_ref) do nothing;
    end loop;
  end if;
  return new;
end;
$function$;