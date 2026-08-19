create or replace function programacion.fn_resolve_dependency_integration(p_task_id bigint, p_depends_on_task_id bigint, p_binding_decision_id text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, programacion
as $function$
declare
  v_dep_exec programacion.ejecuciones%rowtype;
  v_binding public.lf_decisiones_gov%rowtype;
  v_blocker_id bigint;
  v_repo text;
  v_head text;
  v_story text;
  v_module text;
  v_task_sealed_at timestamptz;
  v_context_paths text[];
  v_changed_paths text[];
  v_missing_context_paths text[];
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

  if not programacion.fn_agent_task_worker_context_receipt_ok(v_dep_exec.id) then
    raise exception 'dependency integration requires predecessor PASS receipt bound to Context Pack v2';
  end if;

  select f.story_code,s.module_code,t.sealed_at,t.context_path_patterns
    into v_story,v_module,v_task_sealed_at,v_context_paths
  from programacion.agent_tasks t
  join public.lf_functional_versions f on f.id=t.functional_version_id
  join public.lf_user_stories s on s.story_code=f.story_code
  where t.id=p_task_id;
  if v_task_sealed_at is null then raise exception 'dependency integration requires sealed dependent task'; end if;

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

  if v_task_sealed_at<=v_binding.updated_at then
    raise exception 'DEPENDENCY_CONTEXT_REBIND_REQUIRED: supersede dependent task and seal it after integrated HEAD binding %',p_binding_decision_id;
  end if;

  select coalesce(array_agg(distinct cp order by cp),'{}'::text[])
    into v_changed_paths
  from programacion.evidencias ev
  join programacion.evaluaciones eva on eva.id=ev.evaluacion_id and eva.resultado='PASS'
  join programacion.objetivos_ejecucion obj on obj.id=eva.objetivo_id and obj.execution_id=v_dep_exec.id
  cross join lateral jsonb_array_elements_text(coalesce(ev.metadata#>'{worker_receipt,changed_paths}','[]'::jsonb)) as x(cp)
  where ev.tipo='VERIFIED_WORKER_RECEIPT'
    and ev.source_system='PROGRAMMING_AGENT_WORKER'
    and ev.metadata#>>'{worker_receipt,status}'='PASS'
    and exists(
      select 1 from programacion.evidence_verifications vv
      where vv.evidence_id=ev.id
        and vv.verification_status='VERIFIED'
        and vv.evidence_sha256=ev.sha256
        and vv.source_system=ev.source_system
        and vv.source_ref=ev.source_ref
    );

  if cardinality(v_changed_paths)=0 then
    raise exception 'DEPENDENCY_CONTEXT_REBIND_REQUIRED: predecessor PASS receipt has no changed_paths';
  end if;

  select coalesce(array_agg(p order by p),'{}'::text[])
    into v_missing_context_paths
  from unnest(v_changed_paths) p
  where not (p=any(v_context_paths));

  if cardinality(v_missing_context_paths)>0 then
    raise exception 'DEPENDENCY_CONTEXT_PATH_MISSING: dependent Task context must explicitly include predecessor changed paths %',v_missing_context_paths;
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
    'predecessor_execution_id',v_dep_exec.id,
    'context_rebound_after_integration',true,
    'predecessor_changed_paths',to_jsonb(v_changed_paths)
  );
end;
$function$;

revoke all on function programacion.fn_resolve_dependency_integration(bigint,bigint,text) from public,anon,authenticated;