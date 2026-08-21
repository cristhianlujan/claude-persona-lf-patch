create or replace function programacion.fn_open_dependency_integration_blockers()
returns trigger
language plpgsql
set search_path to 'pg_catalog','programacion'
as $$
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
        'INTEGRATE_VERIFIED_PREDECESSOR_AND_REBIND_REPOSITORY_HEAD',
        'task-dependency://'||new.id||'/'||d.depends_on_task_id,
        'OPEN'
      )
      on conflict (task_id,blocker_code,source_ref) do nothing;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_agent_tasks_dependency_integration on programacion.agent_tasks;
create trigger trg_agent_tasks_dependency_integration
after update of definition_status on programacion.agent_tasks
for each row execute function programacion.fn_open_dependency_integration_blockers();

-- Backfill already-sealed dependencies introduced by the pilot before this trigger existed.
insert into programacion.task_blockers(task_id,blocker_code,owner_type,owner_ref,required_action,source_ref,status)
select d.task_id,'DEPENDENCY_INTEGRATION_REQUIRED','REPOSITORY_INTEGRATION',
       'agent-task://'||d.depends_on_task_id,
       'INTEGRATE_VERIFIED_PREDECESSOR_AND_REBIND_REPOSITORY_HEAD',
       'task-dependency://'||d.task_id||'/'||d.depends_on_task_id,'OPEN'
from programacion.task_dependencies d
join programacion.agent_tasks t on t.id=d.task_id and t.definition_status='SEALED'
where not exists(
  select 1 from programacion.task_blockers b
  where b.task_id=d.task_id
    and b.blocker_code='DEPENDENCY_INTEGRATION_REQUIRED'
    and b.source_ref='task-dependency://'||d.task_id||'/'||d.depends_on_task_id
)
on conflict (task_id,blocker_code,source_ref) do nothing;

create or replace function programacion.fn_resolve_dependency_integration(
  p_task_id bigint,
  p_depends_on_task_id bigint,
  p_binding_decision_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','programacion'
as $$
declare
  v_dep_exec programacion.ejecuciones%rowtype;
  v_binding public.lf_decisiones_gov%rowtype;
  v_blocker_id bigint;
  v_repo text;
  v_head text;
  v_story text;
  v_module text;
begin
  if not exists(select 1 from programacion.task_dependencies d where d.task_id=p_task_id and d.depends_on_task_id=p_depends_on_task_id) then
    raise exception 'dependency edge not found';
  end if;

  select ex.* into v_dep_exec
  from programacion.v_ejecucion_autoridad ea
  join programacion.ejecuciones ex on ex.id=ea.execution_id
  where ex.request_ref='agent-task://'||p_depends_on_task_id
    and ea.effective_verdict='PASS'
  order by ex.completed_at desc nulls last,ex.id desc
  limit 1;
  if v_dep_exec.id is null then raise exception 'dependency integration requires predecessor effective PASS'; end if;

  select f.story_code,s.module_code into v_story,v_module
  from programacion.agent_tasks t
  join public.lf_functional_versions f on f.id=t.functional_version_id
  join public.lf_user_stories s on s.story_code=f.story_code
  where t.id=p_task_id;

  select * into v_binding from public.lf_decisiones_gov where id_decision=p_binding_decision_id;
  if v_binding.id_decision is null
     or v_binding.estado_normalizado<>'APROBADO_READ_ONLY'
     or v_binding.raw_payload->>'decision_type'<>'TECHNICAL_REPOSITORY_BINDING'
     or coalesce((v_binding.raw_payload->>'read_only_preparation')::boolean,false) is not true
  then raise exception 'dependency integration requires approved read-only repository binding'; end if;

  if not (
    v_binding.raw_payload->>'story_code'=v_story
    or (v_binding.raw_payload->>'story_code' is null and v_binding.raw_payload->>'module_code'=v_module)
  ) then raise exception 'repository binding does not apply to dependent task'; end if;

  v_repo:=v_binding.raw_payload->>'repo_full_name';
  v_head:=v_binding.raw_payload->>'pinned_head_sha';
  if v_repo is distinct from v_dep_exec.repo_full_name then raise exception 'repository binding/predecessor repo mismatch'; end if;
  if v_head is null or v_head!~'^[0-9a-f]{40}$' then raise exception 'repository binding requires pinned 40-hex head'; end if;
  if v_head=v_dep_exec.head_sha then raise exception 'dependency integration head must differ from predecessor base head'; end if;
  if v_dep_exec.completed_at is null or v_binding.updated_at<v_dep_exec.completed_at then
    raise exception 'repository binding must be observed after predecessor PASS completion';
  end if;

  select id into v_blocker_id from programacion.task_blockers
  where task_id=p_task_id
    and blocker_code='DEPENDENCY_INTEGRATION_REQUIRED'
    and owner_ref='agent-task://'||p_depends_on_task_id
    and status='OPEN'
  order by id desc limit 1;
  if v_blocker_id is null then raise exception 'open dependency integration blocker not found'; end if;

  update programacion.task_blockers
  set status='RESOLVED',
      resolved_by=current_user,
      resolution_ref='repo-binding://'||p_binding_decision_id||'#'||v_head
  where id=v_blocker_id;

  return jsonb_build_object(
    'task_id',p_task_id,
    'depends_on_task_id',p_depends_on_task_id,
    'blocker_id',v_blocker_id,
    'status','RESOLVED',
    'repo_full_name',v_repo,
    'integrated_head_sha',v_head,
    'binding_decision_id',p_binding_decision_id,
    'predecessor_execution_id',v_dep_exec.id
  );
end;
$$;

revoke all on function programacion.fn_resolve_dependency_integration(bigint,bigint,text) from public;
grant execute on function programacion.fn_resolve_dependency_integration(bigint,bigint,text)
  to programacion_builder,programacion_human_authority;