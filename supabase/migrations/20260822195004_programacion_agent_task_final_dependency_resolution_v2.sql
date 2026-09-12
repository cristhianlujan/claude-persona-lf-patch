create or replace function programacion.fn_guard_agent_task_final_dependency_resolution()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $function$
begin
  if new.status='SEALED' and old.status='DRAFT'
     and exists(
       select 1
       from jsonb_array_elements(new.dependency_resolution) d
       where d->>'resolution_type' in ('BLOCKER','UNRESOLVED')
     ) then
    raise exception 'FINAL_DEPENDENCY_RESOLUTION_REQUIRED: SEALED contract cannot retain BLOCKER or UNRESOLVED dependency mappings';
  end if;
  return new;
end;
$function$;

create trigger trg_agent_task_delivery_contract_final_dependency_resolution
before update on programacion.agent_task_delivery_contracts
for each row execute function programacion.fn_guard_agent_task_final_dependency_resolution();