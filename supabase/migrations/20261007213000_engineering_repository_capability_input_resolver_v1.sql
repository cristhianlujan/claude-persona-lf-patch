-- Generic resolver for ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1.
-- Root fix: a repository capability packet may be READY only when its resolution
-- code is backed by an executable resolver contract. External facts remain explicit
-- and are never synthesized.

create or replace function programacion.fn_engineering_repository_capability_input_resolve_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text,
  p_ref jsonb,
  p_previous_output jsonb default null,
  p_external_facts jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_resolution text;
  v_source_checkpoint text;
  v_work_item_id bigint;
  v_work_status text;
  v_source_evidence text;
  v_dependencies jsonb := '[]'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_external_ok boolean := false;
  v_input jsonb;
begin
  if jsonb_typeof(p_ref) is distinct from 'object'
     or p_ref->>'schema_version' is distinct from 'ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',false,'ready',false,'status','INVALID_INPUT_REF'
    );
  end if;

  if coalesce(p_ref->>'literal_payload','') is distinct from 'FORBIDDEN' then
    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',false,'ready',false,'status','LITERAL_PAYLOAD_POLICY_INVALID'
    );
  end if;

  v_resolution:=nullif(btrim(coalesce(p_ref->>'resolution','')),'');
  v_source_checkpoint:=nullif(btrim(coalesce(p_ref->>'source_checkpoint','')),'');

  if v_resolution not in (
    'CURRENT_UNIT_STATE_PLUS_CURRENTNESS_AUTHORITY',
    'EXACT_IMMUTABLE_PLAN_FROM_POST_PASE_ROUTER',
    'CURRENT_UNIT_DEPENDENCY_EVIDENCE_AND_CURRENTNESS',
    'CURRENT_MAIN_EDGE_CONTRACT_AND_RELEASE_BINDING'
  ) then
    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',false,'ready',false,'status','UNSUPPORTED_RESOLUTION',
      'resolution',v_resolution
    );
  end if;

  select pu.work_item_id,w.status
    into v_work_item_id,v_work_status
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_items w on w.id=pu.work_item_id
  where pu.plan_code=p_plan_code and pu.unit_code=p_unit_code;

  if v_work_item_id is null then
    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',true,'ready',false,'status','UNIT_NOT_FOUND',
      'resolution',v_resolution
    );
  end if;

  if v_source_checkpoint is not null then
    select c.evidence_ref into v_source_evidence
    from programacion.engineering_work_checkpoints c
    where c.work_item_id=v_work_item_id
      and c.checkpoint_code=v_source_checkpoint;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'unit_code',du.unit_code,
      'work_code',dw.work_code,
      'status',dw.status,
      'evidence_refs',coalesce((
        select jsonb_agg(c.evidence_ref order by c.sequence_no)
        from programacion.engineering_work_checkpoints c
        where c.work_item_id=dw.id
          and nullif(btrim(coalesce(c.evidence_ref,'')),'') is not null
      ),'[]'::jsonb)
    ) order by du.unit_code),'[]'::jsonb)
    into v_dependencies
  from programacion.engineering_work_dependencies d
  join programacion.engineering_work_items dw on dw.id=d.depends_on_work_item_id
  left join programacion.engineering_plan_units du
    on du.plan_code=p_plan_code and du.work_item_id=dw.id
  where d.work_item_id=v_work_item_id
    and d.relation_type='REQUIRES';

  if v_resolution='EXACT_IMMUTABLE_PLAN_FROM_POST_PASE_ROUTER' then
    if jsonb_typeof(p_previous_output)='object'
       and p_previous_output->>'schema_version'='LF_POST_PASE_PLAN_V1'
       and coalesce((p_previous_output->>'immutable')::boolean,false)
       and coalesce(p_previous_output->>'plan_digest','') ~ '^[0-9a-f]{64}$' then
      return jsonb_build_object(
        'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
        'supported',true,'ready',true,'status','RESOLVED',
        'resolution',v_resolution,
        'resolution_class','PREVIOUS_TRANSVERSAL_OUTPUT',
        'capability_input',p_previous_output,
        'external_fact_requirements','[]'::jsonb
      );
    end if;
    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',true,'ready',false,'status','WAITING_PREVIOUS_TRANSVERSAL_OUTPUT',
      'resolution',v_resolution,
      'resolution_class','PREVIOUS_TRANSVERSAL_OUTPUT',
      'external_fact_requirements',jsonb_build_array('previous_transversal_step_output')
    );
  end if;

  if v_resolution='CURRENT_UNIT_STATE_PLUS_CURRENTNESS_AUTHORITY' then
    v_required:=jsonb_build_array(
      'repository','target_branch','merge_sha','currentness_receipt','orchestrator_entry',
      'post_pase_execution_id','pase_orchestrator_execution_id','source_pase_execution_id',
      'declared_paths'
    );

    select not exists(
      select 1 from jsonb_array_elements_text(v_required) k
      where not (coalesce(p_external_facts,'{}'::jsonb) ? k)
    ) into v_external_ok;

    if not v_external_ok then
      return jsonb_build_object(
        'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
        'supported',true,'ready',false,'status','NEEDS_EXTERNAL_FACTS',
        'resolution',v_resolution,
        'resolution_class','POST_PASE_ROUTER_CURRENT_UNIT',
        'internal_context',jsonb_build_object(
          'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,
          'work_status',v_work_status,'source_checkpoint',v_source_checkpoint,
          'source_evidence_ref',v_source_evidence,'dependencies',v_dependencies
        ),
        'external_fact_requirements',v_required
      );
    end if;

    if coalesce(p_external_facts->>'merge_sha','') !~ '^[0-9a-f]{40}$'
       or jsonb_typeof(p_external_facts->'currentness_receipt') is distinct from 'object'
       or p_external_facts#>>'{currentness_receipt,schema_version}' is distinct from 'LF_CURRENTNESS_AUTHORITY_RECEIPT_V1'
       or coalesce((p_external_facts#>>'{currentness_receipt,ready}')::boolean,false) is not true
       or p_external_facts#>>'{currentness_receipt,current_revision}' is distinct from p_external_facts->>'merge_sha'
       or jsonb_typeof(p_external_facts->'orchestrator_entry') is distinct from 'object'
       or p_external_facts#>>'{orchestrator_entry,decision}' is distinct from 'ORCHESTRATOR_ENTRY_ACCEPTED'
       or p_external_facts#>>'{orchestrator_entry,capability_code}' is distinct from 'POST_PASE_ROUTER'
       or jsonb_typeof(p_external_facts->'declared_paths') is distinct from 'array'
       or jsonb_array_length(p_external_facts->'declared_paths')=0 then
      return jsonb_build_object(
        'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
        'supported',true,'ready',false,'status','EXTERNAL_FACTS_INVALID',
        'resolution',v_resolution,'external_fact_requirements',v_required
      );
    end if;

    v_input:=jsonb_strip_nulls(jsonb_build_object(
      'post_pase_execution_id',p_external_facts->>'post_pase_execution_id',
      'pase_orchestrator_execution_id',p_external_facts->>'pase_orchestrator_execution_id',
      'source_pase_execution_id',p_external_facts->>'source_pase_execution_id',
      'repository',p_external_facts->>'repository',
      'target_branch',p_external_facts->>'target_branch',
      'merge_sha',p_external_facts->>'merge_sha',
      'target_set_event_id',19549,
      'currentness_receipt',p_external_facts->'currentness_receipt',
      'orchestrator_entry',p_external_facts->'orchestrator_entry',
      'declared_paths',p_external_facts->'declared_paths',
      'repository_invariants',coalesce(p_external_facts->'repository_invariants','[]'::jsonb),
      'authority_scopes',coalesce(p_external_facts->'authority_scopes','[]'::jsonb),
      'runtime_deploy_scope',p_external_facts->'runtime_deploy_scope'
    ));

    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',true,'ready',true,'status','RESOLVED',
      'resolution',v_resolution,
      'resolution_class','POST_PASE_ROUTER_CURRENT_UNIT',
      'internal_context',jsonb_build_object(
        'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,
        'work_status',v_work_status,'source_checkpoint',v_source_checkpoint,
        'source_evidence_ref',v_source_evidence,'dependencies',v_dependencies
      ),
      'external_fact_requirements',v_required,
      'capability_input',v_input
    );
  end if;

  if v_resolution='CURRENT_UNIT_DEPENDENCY_EVIDENCE_AND_CURRENTNESS' then
    v_required:=jsonb_build_array('capability_input');
    v_external_ok:=jsonb_typeof(p_external_facts->'capability_input')='object'
      and p_external_facts->'capability_input'<>'{}'::jsonb;
    return jsonb_build_object(
      'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
      'supported',true,'ready',v_external_ok,
      'status',case when v_external_ok then 'RESOLVED' else 'NEEDS_EXTERNAL_FACTS' end,
      'resolution',v_resolution,
      'resolution_class','CURRENT_UNIT_DEPENDENCY_EVIDENCE',
      'internal_context',jsonb_build_object(
        'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,
        'work_status',v_work_status,'source_checkpoint',v_source_checkpoint,
        'source_evidence_ref',v_source_evidence,'dependencies',v_dependencies
      ),
      'external_fact_requirements',v_required,
      'capability_input',case when v_external_ok then p_external_facts->'capability_input' else null end
    );
  end if;

  v_required:=jsonb_build_array('capability_input');
  v_external_ok:=jsonb_typeof(p_external_facts->'capability_input')='object'
    and p_external_facts->'capability_input'<>'{}'::jsonb;
  return jsonb_build_object(
    'schema_version','ENGINEERING_REPOSITORY_CAPABILITY_INPUT_RESOLUTION_V1',
    'supported',true,'ready',v_external_ok,
    'status',case when v_external_ok then 'RESOLVED' else 'NEEDS_EXTERNAL_FACTS' end,
    'resolution',v_resolution,
    'resolution_class','CURRENT_MAIN_EDGE_RELEASE',
    'internal_context',jsonb_build_object(
      'plan_code',p_plan_code,'unit_code',p_unit_code,'checkpoint_code',p_checkpoint_code,
      'work_status',v_work_status,'source_checkpoint',v_source_checkpoint,
      'source_evidence_ref',v_source_evidence,'dependencies',v_dependencies
    ),
    'external_fact_requirements',v_required,
    'capability_input',case when v_external_ok then p_external_facts->'capability_input' else null end
  );
end;
$function$;

comment on function programacion.fn_engineering_repository_capability_input_resolve_v1(text,text,text,jsonb,jsonb,jsonb)
is 'Canonical generic resolver for repository capability input references. Resolves internal unit/dependency context, declares exact external-fact requirements, consumes previous transversal output when required, and never synthesizes external authority facts.';

create or replace function pg_temp.rep(src text,o text,n text)
returns text language plpgsql as $r$
begin
  if position(o in src)=0 then raise exception 'PATCH_ANCHOR_MISSING:%',left(o,180); end if;
  if position(o in substr(src,position(o in src)+length(o)))>0 then raise exception 'PATCH_ANCHOR_NON_UNIQUE:%',left(o,180); end if;
  return replace(src,o,n);
end
$r$;

do $patch_action$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_transversal_capability_action_spec_v2';

  d:=pg_temp.rep(d,
    $o$  v_query text;
begin$o$,
    $n$  v_query text;
  v_input_resolution jsonb;
begin$n$
  );

  d:=pg_temp.rep(d,
    $o$  if v_handler in ('REPOSITORY_CAPABILITY_EXECUTOR','REPOSITORY_COMPARATOR_EXECUTOR') then
    if v_impl is null then$o$,
    $n$  if v_handler in ('REPOSITORY_CAPABILITY_EXECUTOR','REPOSITORY_COMPARATOR_EXECUTOR') then
    v_input_resolution:=programacion.fn_engineering_repository_capability_input_resolve_v1(
      p_plan_code,p_unit_code,p_checkpoint_code,
      coalesce(v_input->'capability_input','{}'::jsonb),
      null,
      '{}'::jsonb
    );
    if coalesce((v_input_resolution->>'supported')::boolean,false) is not true then
      return v_base || jsonb_build_object(
        'status','BLOCK_TRANSVERSAL_INPUT_RESOLVER_MISSING',
        'precision','STRUCTURAL_TRANSVERSAL_ADAPTER_V3',
        'transversal_capability_code',v_code,
        'transversal_handler',v_handler,
        'handler_requirement',v_req,
        'input_resolution',v_input_resolution
      );
    end if;
    if v_impl is null then$n$
  );

  d:=pg_temp.rep(d,
    $o$        'execution_input',v_input,
        'source_policy','CURRENT_EXACT_MANIFEST',$o$,
    $n$        'execution_input',v_input,
        'input_resolver_entrypoint','programacion.fn_engineering_repository_capability_input_resolve_v1',
        'input_resolution',v_input_resolution,
        'source_policy','CURRENT_EXACT_MANIFEST',$n$
  );

  execute d;
end
$patch_action$;

do $patch_packet$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='programacion' and p.proname='fn_engineering_execution_packet_apply_transversal_adapter_v1';

  d:=pg_temp.rep(d,
    $o$          'execution_input',coalesce(v_exec->'execution_input','{}'::jsonb),
          'fetch_exact_repository_source',true,$o$,
    $n$          'execution_input',coalesce(v_exec->'execution_input','{}'::jsonb),
          'input_resolver_entrypoint',coalesce(v_exec->>'input_resolver_entrypoint','programacion.fn_engineering_repository_capability_input_resolve_v1'),
          'input_resolution',coalesce(v_exec->'input_resolution','{}'::jsonb),
          'fetch_exact_repository_source',true,$n$
  );

  execute d;
end
$patch_packet$;

-- Terminal ordering root fix: INDEPENDENT_READBACK requires the HANDOFF event.
do $order$
declare r record;
begin
  for r in
    select pu.work_item_id,pu.unit_code
    from programacion.engineering_plan_units pu
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      and pu.unit_code in ('M5.10','M6.13')
  loop
    update programacion.engineering_work_checkpoints
       set sequence_no=sequence_no+100
     where work_item_id=r.work_item_id
       and checkpoint_code in ('HANDOFF_EVENT','NEGATIVE_OPEN_UNIT','INDEPENDENT_READBACK');

    update programacion.engineering_work_checkpoints
       set sequence_no=case checkpoint_code
         when 'HANDOFF_EVENT' then 3
         when 'NEGATIVE_OPEN_UNIT' then 4
         when 'INDEPENDENT_READBACK' then 5
       end
     where work_item_id=r.work_item_id
       and checkpoint_code in ('HANDOFF_EVENT','NEGATIVE_OPEN_UNIT','INDEPENDENT_READBACK');
  end loop;
end
$order$;

do $selftest$
declare
  v_refs int;
  v_supported int;
  v_bad_order int;
  v_spec jsonb;
  v_packet jsonb;
begin
  with refs as (
    select distinct x as ref
    from programacion.engineering_plan_units pu
    cross join lateral jsonb_path_query(
      pu.unit_metadata,
      '$.** ? (@.schema_version == "ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1")'
    ) x
    where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  )
  select count(*),
         count(*) filter(where coalesce((
           programacion.fn_engineering_repository_capability_input_resolve_v1(
             'IG_CURATOR_VALIDATOR_REFACTOR_V2','M5.10','FINAL_EVIDENCE_SADM',ref,null,'{}'::jsonb
           )->>'supported'
         )::boolean,false))
    into v_refs,v_supported
  from refs;

  if v_refs<>4 or v_supported<>4 then
    raise exception 'ENGINEERING_REPOSITORY_INPUT_RESOLUTION_COVERAGE refs=% supported=%',v_refs,v_supported;
  end if;

  select count(*) into v_bad_order
  from programacion.engineering_plan_units pu
  join programacion.engineering_work_checkpoints h
    on h.work_item_id=pu.work_item_id and h.checkpoint_code='HANDOFF_EVENT'
  join programacion.engineering_work_checkpoints i
    on i.work_item_id=pu.work_item_id and i.checkpoint_code='INDEPENDENT_READBACK'
  where pu.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    and pu.unit_code in ('M5.10','M6.13')
    and h.sequence_no>=i.sequence_no;

  if v_bad_order<>0 then
    raise exception 'ENGINEERING_HANDOFF_ORDER_INVALID:%',v_bad_order;
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M5.10','FINAL_EVIDENCE_SADM'
  );
  if v_spec->>'status' is distinct from 'READY'
     or v_spec#>>'{capability_execution,input_resolver_entrypoint}'
        is distinct from 'programacion.fn_engineering_repository_capability_input_resolve_v1'
     or coalesce((v_spec#>>'{capability_execution,input_resolution,supported}')::boolean,false) is not true then
    raise exception 'ENGINEERING_M5_10_RESOLVER_NOT_COMPILED:%',v_spec;
  end if;

  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M5.10','FINAL_EVIDENCE_SADM',v_spec,'{}'::jsonb
  );
  if v_packet->>'status' is distinct from 'READY'
     or v_packet#>>'{connector_plan,0,executor_contract,input_resolver_entrypoint}'
        is distinct from 'programacion.fn_engineering_repository_capability_input_resolve_v1' then
    raise exception 'ENGINEERING_M5_10_RESOLVER_PACKET_NOT_READY:%',v_packet;
  end if;
end
$selftest$;

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'ENGINEERING-REPOSITORY-CAPABILITY-INPUT-RESOLVER-001',
  'ENGINEERING_ORCHESTRATION',
  'Repository capability input references require an executable resolver before READY',
  'The transversal adapter treated the presence of ENGINEERING_REPOSITORY_CAPABILITY_INPUT_REF_V1 as a complete runtime input even when its resolution code had no executable producer.',
  'REFERENCE_INPUT_DECLARED_BUT_NOT_RESOLVABLE',
  'TRANSVERSAL_REPOSITORY_CAPABILITY_PACKET_READY_WITHOUT_EXECUTABLE_INPUT_RESOLUTION',
  'Every repository capability input reference must resolve through fn_engineering_repository_capability_input_resolve_v1. Unknown resolution codes fail closed; external authority facts are explicit requirements and are never synthesized.',
  'PASS when all four live IG repository-input resolution codes are supported, M5.10 packet exposes the canonical resolver entrypoint, unknown resolution codes block, and HANDOFF precedes INDEPENDENT_READBACK in M5.10/M6.13.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'supabase://programacion.fn_engineering_repository_capability_input_resolve_v1',
  'EXECUTION',
  array['ENGINEERING_EXECUTOR','ENGINEERING_SCHEDULER','PROGRAMMING_AGENT']::text[],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'Generic repository capability execution inputs',
  'supabase://programacion.fn_engineering_repository_capability_input_resolve_v1'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  estado=excluded.estado,
  ultima_vez=now(),
  updated_at=now();
