create or replace function programacion.fn_engineering_closure_event_v1(
  p_plan_code text,
  p_unit_code text,
  p_event_kind text
) returns jsonb
language plpgsql
set search_path to 'programacion','public','pg_catalog'
as $$
declare
  v_work_item_id bigint;
  v_work_code text;
  v_kind text := upper(coalesce(p_event_kind,''));
  v_entity_code text;
  v_exec_id text;
  v_event_type text;
  v_entity_type text;
  v_desc text;
  v_event_id bigint;
  v_existing bigint;
  v_units jsonb := '[]'::jsonb;
  v_shas jsonb := '[]'::jsonb;
  v_handoff_id bigint;
  v_dep_count int := 0;
  v_done_count int := 0;
  v_payload jsonb;
begin
  if v_kind not in ('HANDOFF','INDEPENDENT_READBACK') then
    raise exception 'Unsupported closure event kind: %',p_event_kind;
  end if;
  select pu.work_item_id,w.work_code into v_work_item_id,v_work_code
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;
  if v_work_item_id is null then raise exception 'Canonical unit not found: %/%',p_plan_code,p_unit_code; end if;

  v_entity_code:=p_plan_code||'.'||p_unit_code||'.CLOSE.'||case when v_kind='HANDOFF' then 'HANDOFF' else 'INDEPENDENT_READBACK' end;
  v_exec_id:='ENGINEERING_CLOSURE_EVENT_V1|'||p_plan_code||'|'||p_unit_code||'|'||v_kind;
  v_event_type:=case when v_kind='HANDOFF' then 'HANDOFF_DEEP_CONTEXT' else 'READBACK_VERIFICADO' end;
  v_entity_type:=case when v_kind='HANDOFF' then 'PROGRAM_PLAN' else 'ENGINEERING_PLAN_UNIT' end;
  v_desc:=case when v_kind='HANDOFF' then 'Canonical engineering closure handoff.' else 'Independent canonical engineering closure readback.' end;

  select e.id into v_existing from public.lf_eventos e
  where e.evento_tipo=v_event_type and e.entidad_codigo=v_entity_code order by e.id desc limit 1;
  if v_existing is not null then
    return jsonb_build_object('status','REUSED','event_id',v_existing,'event_ref','event://'||v_existing,'event_kind',v_kind,'execution_id',v_exec_id);
  end if;

  select count(*),count(*) filter (where dw.status='DONE') into v_dep_count,v_done_count
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
  where d.work_item_id=v_work_item_id and d.relation_type='REQUIRES';

  select coalesce(jsonb_agg(jsonb_build_object(
      'unit',du.unit_code,'work_code',dw.work_code,'status',dw.status,
      'evidence_refs',coalesce((select jsonb_agg(c.evidence_ref order by c.sequence_no)
        from programacion.engineering_work_checkpoints c
        where c.work_item_id=dw.id and nullif(c.evidence_ref,'') is not null),'[]'::jsonb)
    ) order by du.unit_code),'[]'::jsonb)
  into v_units
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
  left join programacion.engineering_plan_units du on du.plan_code=p_plan_code and du.work_item_id=dw.id
  where d.work_item_id=v_work_item_id and d.relation_type='REQUIRES';

  select coalesce(jsonb_agg(distinct m[1]),'[]'::jsonb) into v_shas
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_checkpoints c on c.work_item_id=d.depends_on_work_item_id
  cross join lateral regexp_matches(coalesce(c.evidence_ref,''),'([0-9a-f]{40})','g') m
  where d.work_item_id=v_work_item_id and d.relation_type='REQUIRES';

  if v_kind='INDEPENDENT_READBACK' then
    select e.id into v_handoff_id from public.lf_eventos e
    where e.evento_tipo='HANDOFF_DEEP_CONTEXT'
      and e.entidad_codigo=p_plan_code||'.'||p_unit_code||'.CLOSE.HANDOFF'
    order by e.id desc limit 1;
    if v_handoff_id is null then raise exception 'Closure handoff missing for %/%',p_plan_code,p_unit_code; end if;
  end if;

  v_payload:=jsonb_build_object(
    'evidence_schema_version','operational-event/v2','execution_id',v_exec_id,
    'producer','ENGINEERING_CLOSURE_EVENT_V1',
    'purpose',case when v_kind='HANDOFF' then 'Persist canonical closure handoff from live dependency evidence.' else 'Persist independent closure readback from live dependency evidence.' end,
    'occurred_at',clock_timestamp(),'acceptance_declared',false,
    'plan_code',p_plan_code,'unit_code',p_unit_code,'work_code',v_work_code,
    'dependency_count',v_dep_count,'dependencies_done',v_done_count,
    'all_dependencies_done',(v_dep_count=v_done_count),'units',v_units,'material_shas',v_shas
  );
  if v_kind='INDEPENDENT_READBACK' then
    v_payload:=v_payload||jsonb_build_object('handoff_event_ref','event://'||v_handoff_id,'independent_identity',true);
  end if;

  insert into public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id)
  values(v_event_type,v_entity_type,v_entity_code,v_desc,'INFO',v_payload,'EXECUTION:'||v_exec_id,v_exec_id)
  returning id into v_event_id;

  perform 1 from public.lf_eventos where id=v_event_id and payload->>'execution_id'=v_exec_id;
  if not found then raise exception 'Closure event readback failed'; end if;

  return jsonb_build_object('status','RECORDED','event_id',v_event_id,'event_ref','event://'||v_event_id,'event_kind',v_kind,'execution_id',v_exec_id);
end;
$$;

create or replace function programacion.fn_engineering_checkpoint_action_spec_v3(
  p_plan_code text,p_unit_code text,p_checkpoint_code text default null::text
) returns jsonb
language sql
stable
set search_path to 'programacion','public','pg_catalog'
as $$
with s as materialized (
  select programacion.fn_engineering_checkpoint_action_spec_v2(p_plan_code,p_unit_code,p_checkpoint_code) spec
), x as materialized (
  select spec,lower(coalesce(spec->>'checkpoint_title','')) title_l,
         coalesce(spec->>'checkpoint_code','') checkpoint_code,
         coalesce((spec->>'requires_material_execution')::boolean,false) is_material,
         coalesce(jsonb_array_length(spec#>'{target,declared_artifacts}'),0) artifact_count,
         coalesce(jsonb_array_length(spec->'verification_queries'),0) verification_count
  from s
)
select case
  when spec is null then null
  when checkpoint_code='HANDOFF_EVENT' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3','precision','COMPILED_CLOSURE_EVENT',
      'action_kind','MUTATION_EXECUTION','recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
      'requires_material_execution',true,'mutation_policy','ONLY_DECLARED_TARGETS',
      'target',jsonb_build_object('checkpoint',checkpoint_code,'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,'declared_objects',jsonb_build_array('public.lf_eventos'),'declared_artifacts','[]'::jsonb),
      'verification_queries',jsonb_build_array(format('select programacion.fn_engineering_closure_event_v1(%L,%L,%L)',p_plan_code,p_unit_code,'HANDOFF')),
      'action_steps',jsonb_build_array('EMIT_CANONICAL_HANDOFF_EVENT','VERIFY_EVENT_READBACK','PERSIST_DONE','USE_RETURNED_BOOTSTRAP'))
  when checkpoint_code='INDEPENDENT_READBACK_TERMINAL' then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3','precision','COMPILED_CLOSURE_EVENT',
      'action_kind','MUTATION_EXECUTION','recipe_mode','EXECUTE_CANONICAL_CLOSURE_EVENT',
      'requires_material_execution',true,'mutation_policy','ONLY_DECLARED_TARGETS',
      'target',jsonb_build_object('checkpoint',checkpoint_code,'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb,'declared_objects',jsonb_build_array('public.lf_eventos'),'declared_artifacts','[]'::jsonb),
      'verification_queries',jsonb_build_array(format('select programacion.fn_engineering_closure_event_v1(%L,%L,%L)',p_plan_code,p_unit_code,'INDEPENDENT_READBACK')),
      'action_steps',jsonb_build_array('EMIT_CANONICAL_INDEPENDENT_READBACK','VERIFY_EVENT_READBACK','PERSIST_DONE','USE_RETURNED_BOOTSTRAP'))
  when (
    (checkpoint_code='DEPENDENCY_WIRING' and title_l like '%hallazgo%')
    or (coalesce(spec->>'recipe_mode','')='EXECUTE_DECLARED_DELIVERABLE' and title_l ~ '^(verificar|comprobar|readback|observar)' and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|registrar dependencia)')
    or (coalesce(spec->>'action_kind','')='MATERIALIZE_DECLARED_DELIVERABLE' and artifact_count=0 and verification_count>0 and title_l ~ '^(verificar|confirmar|recalcular|conteo|cobertura observada|precondici[oó]n|prerequisit|identificar|0 callers|suite .*verde|evidencia .*exist|aud-[0-9]+ cerrado|consumir .*en vez|elegibilidad le[ií]da|presupuesto .*consumido|hechos espec[ií]ficos jit)' and title_l !~ '(crear|insertar|actualizar|eliminar|materializar|implementar|construir|emitir|registrar|migraci)')
  ) then
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3','precision','COMPILED_READ_ONLY_GUARD',
      'action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT','requires_material_execution',false,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'action_steps',jsonb_build_array('READ_DECLARED_AUTHORITY_ONCE','ASSERT_EXACT_STATE','PERSIST_CHECKPOINT_ONLY','USE_RETURNED_BOOTSTRAP'),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb)||jsonb_build_array('MUTATE_DEPENDENCY_GRAPH','CREATE_UNDECLARED_SHARED_ABSTRACTION')) - 'material_contract'
  else
    spec || jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'mutation_policy',case when is_material then 'ONLY_DECLARED_TARGETS' else 'NO_DOMAIN_MUTATION' end,
      'scope_guard',jsonb_build_object('new_shared_or_transversal_abstraction','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED','dependency_graph_mutation','FORBIDDEN_UNLESS_EXPLICITLY_DECLARED','cross_checkpoint_design','FORBIDDEN'),
      'forbidden',coalesce(spec->'forbidden','[]'::jsonb)||jsonb_build_array('CREATE_UNDECLARED_SHARED_ABSTRACTION','MUTATE_UNDECLARED_TARGET'))
end from x;
$$;