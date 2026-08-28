begin;

create table if not exists public.lf_router_action_registry (
  asset_type text not null,
  action_code text not null,
  operation_code text null,
  operation_resolution text not null default 'STATIC',
  requires_existing_target boolean not null default true,
  requires_missing_target boolean not null default false,
  write_allowed boolean not null default false,
  status text not null default 'ACTIVE',
  notes text null,
  created_by_execution_id text not null default 'EXEC-GOV-ROUTER-ACT0001-20260827-001',
  updated_by_execution_id text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (asset_type, action_code),
  check (operation_resolution in ('STATIC','NONE')),
  check (not (requires_existing_target and requires_missing_target))
);

alter table public.lf_router_action_registry enable row level security;
revoke all on table public.lf_router_action_registry from anon, authenticated;

insert into public.lf_router_action_registry
(asset_type, action_code, operation_code, operation_resolution, requires_existing_target, requires_missing_target, write_allowed, status, notes)
values
('PERFIL','ASSET_INSPECTION',null,'NONE',true,false,false,'ACTIVE','Read metadata/state/version/source of an existing profile; no operation execution required.'),
('PERFIL','PROFILE_EXECUTION','EJECUCION_PERFIL_LF','STATIC',true,false,false,'ACTIVE','Use an existing profile on an external subject/artifact.'),
('PERFIL','PROFILE_UPDATE','ACTUALIZACION_PERFIL_LF','STATIC',true,false,true,'ACTIVE','Modify/remediate an existing profile package.'),
('PERFIL','PROFILE_CREATE','CREACION_PERFIL_LF','STATIC',false,true,true,'ACTIVE','Create a new profile only when no existing target resolves.'),
('SKILL','ASSET_INSPECTION',null,'NONE',true,false,false,'ACTIVE','Inspect an existing skill without executing or modifying it.'),
('SKILL','SKILL_UPDATE','ACTUALIZACION_SKILL_LF','STATIC',true,false,true,'ACTIVE','Modify/remediate an existing skill.'),
('SKILL','SKILL_CREATE','CREACION_SKILL_LF','STATIC',false,true,true,'ACTIVE','Create a new skill only when no existing target resolves.'),
('ADAPTER','ASSET_INSPECTION',null,'NONE',true,false,false,'ACTIVE','Inspect an existing adapter; applicability is resolved through lf_activo_relaciones.'),
('ADAPTER','ADAPTER_CREATE','CREACION_ADAPTER_LF','STATIC',false,true,true,'ACTIVE','Create a new adapter only when no existing target resolves.'),
('REGLA','ASSET_INSPECTION',null,'NONE',true,false,false,'ACTIVE','Inspect a rule/policy asset. Policies remain tipo_activo=REGLA with specialized subtype/version store.'),
('DOC','ASSET_INSPECTION',null,'NONE',true,false,false,'ACTIVE','Inspect an existing document asset; no generic document mutation operation is inferred.')
on conflict (asset_type, action_code) do update set
  operation_code=excluded.operation_code,
  operation_resolution=excluded.operation_resolution,
  requires_existing_target=excluded.requires_existing_target,
  requires_missing_target=excluded.requires_missing_target,
  write_allowed=excluded.write_allowed,
  status=excluded.status,
  notes=excluded.notes,
  updated_by_execution_id='EXEC-GOV-ROUTER-ACT0001-20260827-001',
  updated_at=now();

create or replace view public.v_lf_router_adapter_bindings
with (security_invoker = true)
as
select
  r.codigo_activo as adapter_code,
  a.nombre_canonico as adapter_name,
  a.subtipo_activo as adapter_subtype,
  a.estado_documental as adapter_document_status,
  a.estado_operativo as adapter_operational_status,
  a.version as adapter_version,
  a.metadata as adapter_metadata,
  r.relacionado_codigo as target_asset_code,
  t.nombre_canonico as target_asset_name,
  t.tipo_activo as target_asset_type,
  r.relacion_tipo,
  r.valor_original,
  r.fuente,
  r.created_at,
  r.updated_at
from public.lf_activo_relaciones r
join public.lf_activos a on a.codigo_activo=r.codigo_activo and a.tipo_activo='ADAPTER' and a.archived_at is null
join public.lf_activos t on t.codigo_activo=r.relacionado_codigo and t.archived_at is null
where r.relacion_tipo='ADAPTER_APLICA_A';

revoke all on table public.v_lf_router_adapter_bindings from anon, authenticated;

insert into public.lf_activo_relaciones
(codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id,updated_at)
select 'ADAPTER-LF-SHELL-PROFILE-20260827',
       x.target_code,
       'ADAPTER_APLICA_A',
       'Canonical adapter binding materialized from adapter metadata applies_to_profiles',
       'SUPABASE_CANONICAL_ROUTER_BINDING',
       '44444444-4444-4444-8444-202608270001'::uuid,
       'EXEC-GOV-ROUTER-ACT0001-20260827-001',
       'EXEC-GOV-ROUTER-ACT0001-20260827-001',
       now()
from (values
  ('PERFIL-UI-ARCHITECT'),
  ('ACT-0051'),
  ('PERFIL-PRODUCT-DIRECTOR-LF'),
  ('PERFIL-GAMIFICATION-SYSTEM-ARCHITECT')
) as x(target_code)
where exists (select 1 from public.lf_activos t where t.codigo_activo=x.target_code and t.archived_at is null)
  and not exists (
    select 1 from public.lf_activo_relaciones r
    where r.codigo_activo='ADAPTER-LF-SHELL-PROFILE-20260827'
      and r.relacionado_codigo=x.target_code
      and r.relacion_tipo='ADAPTER_APLICA_A'
  );

create or replace function public.lf_router_resolve_v1(
  p_request_text text,
  p_target_hint text default null,
  p_action_hint text default null,
  p_asset_type_hint text default null,
  p_distribution_mode text default 'ROUTER'
) returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog','public'
as $$
declare
  v_req text;
  v_target_norm text;
  v_action text;
  v_type_hint text;
  v_asset public.lf_activos%rowtype;
  v_asset_found boolean := false;
  v_rule public.lf_router_action_registry%rowtype;
  v_operation public.lf_operation_registry%rowtype;
  v_contracts jsonb := '[]'::jsonb;
  v_steps jsonb := '[]'::jsonb;
  v_policies jsonb := '[]'::jsonb;
  v_adapters jsonb := '[]'::jsonb;
  v_required_policy_count integer := 0;
  v_resolved_policy_count integer := 0;
  v_contract_count integer := 0;
  v_step_count integer := 0;
  v_result_status text;
begin
  if btrim(coalesce(p_request_text,''))='' then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_EMPTY_REQUEST','router','ACT-0001');
  end if;

  v_req := regexp_replace(translate(lower(coalesce(p_request_text,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');
  v_req := regexp_replace(v_req,'\s+',' ','g');
  v_target_norm := regexp_replace(translate(lower(coalesce(p_target_hint,'')),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g');

  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint,'')),''));
  if v_type_hint is null then
    if v_req ~ '(^| )(perfil|profile)( |$)' or v_req ~ '(^| )pidele (al|a|el) ' then v_type_hint := 'PERFIL';
    elsif v_req ~ '(^| )skill( |$)' then v_type_hint := 'SKILL';
    elsif v_req ~ '(^| )adapter( |$)' then v_type_hint := 'ADAPTER';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';
    elsif v_req ~ '(^| )(doc|documento)( |$)' then v_type_hint := 'DOC';
    end if;
  end if;

  select a.* into v_asset
  from public.lf_activos a
  where a.archived_at is null
    and (v_type_hint is null or a.tipo_activo=v_type_hint)
  order by
    case when v_target_norm<>'' and regexp_replace(translate(lower(a.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm then 2000 else 0 end +
    case when v_target_norm<>'' and regexp_replace(translate(lower(a.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm then 1800 else 0 end +
    case when position(regexp_replace(translate(lower(a.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0 then 1200 else 0 end +
    case when position(regexp_replace(translate(lower(a.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0 then 900 else 0 end +
    coalesce((select max(800) from jsonb_array_elements_text(coalesce(a.metadata->'aliases','[]'::jsonb)) al
              where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0),0) +
    coalesce((select count(*)*25 from regexp_split_to_table(lower(concat_ws(' ',a.nombre_canonico,a.subtipo_activo)), '[^a-z0-9]+') tok
              where length(tok)>=2 and position(tok in v_req)>0),0) +
    coalesce((select count(*)*10 from jsonb_array_elements_text(coalesce(a.metadata->'aliases','[]'::jsonb)) al,
                                      regexp_split_to_table(lower(al),'[^a-z0-9]+') tok
              where length(tok)>=2 and position(tok in v_req)>0),0) +
    coalesce((select count(*)*2 from jsonb_array_elements_text(coalesce(a.metadata->'keywords','[]'::jsonb)) kw,
                                     regexp_split_to_table(lower(kw),'[^a-z0-9]+') tok
              where length(tok)>=3 and position(tok in v_req)>0),0) desc,
    a.codigo_activo
  limit 1;

  if found then
    if (v_target_norm<>'' and (
          regexp_replace(translate(lower(v_asset.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm or
          regexp_replace(translate(lower(v_asset.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
       )) or position(regexp_replace(translate(lower(v_asset.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
       or position(regexp_replace(translate(lower(v_asset.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
       or exists (select 1 from jsonb_array_elements_text(coalesce(v_asset.metadata->'aliases','[]'::jsonb)) al
                  where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0)
       or exists (select 1 from regexp_split_to_table(lower(concat_ws(' ',v_asset.nombre_canonico,v_asset.subtipo_activo)), '[^a-z0-9]+') tok
                  where length(tok)>=2 and position(tok in v_req)>0)
    then v_asset_found := true;
    end if;
  end if;

  if v_asset_found then
    v_type_hint := v_asset.tipo_activo;
  end if;

  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
  if v_action is null then
    if v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE';
      elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE';
      elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE';
      else v_action:='CREATE'; end if;
    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE';
      elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE';
      elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE';
      elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE';
      else v_action:='UPDATE'; end if;
    elsif v_req ~ '(^| )(consulta|consultar|muestra|mostrar|version|estado|metadata|existe)( |$)' then
      v_action:='ASSET_INSPECTION';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(pidele|evalua|evaluar|analiza|analizar|usa|usar|utiliza|utilizar)( |$)' then
      v_action:='PROFILE_EXECUTION';
    else
      v_action:='ASSET_INSPECTION';
    end if;
  end if;

  if v_type_hint is null then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action);
  end if;

  select * into v_rule from public.lf_router_action_registry
  where asset_type=v_type_hint and action_code=v_action and status='ACTIVE';
  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_REGISTERED','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset',case when v_asset_found then v_asset.codigo_activo else null end);
  end if;

  if v_rule.requires_existing_target and not v_asset_found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_NOT_FOUND','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action);
  end if;
  if v_rule.requires_missing_target and v_asset_found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_TARGET_ALREADY_EXISTS','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset',v_asset.codigo_activo);
  end if;

  if v_rule.operation_resolution='NONE' then
    if v_asset_found then
      select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters
      from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo;
    end if;
    return jsonb_build_object(
      'status','READY_INSPECTION','router','ACT-0001','source','SUPABASE',
      'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
      'action_code',v_action,'operation_code',null,'adapters',v_adapters,
      'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL')
    );
  end if;

  select * into v_operation from public.lf_operation_registry where operation_code=v_rule.operation_code;
  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_REGISTRY_MISSING','router','ACT-0001','operation_code',v_rule.operation_code);
  end if;
  if v_operation.applies_to_asset_type is not null and v_operation.applies_to_asset_type<>v_type_hint then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_ASSET_TYPE_MISMATCH','router','ACT-0001','asset_type',v_type_hint,'operation_code',v_operation.operation_code,'applies_to_asset_type',v_operation.applies_to_asset_type);
  end if;

  select count(*), coalesce(jsonb_agg(to_jsonb(c) order by c.contract_code),'[]'::jsonb)
  into v_contract_count,v_contracts
  from public.lf_operation_contracts c
  where c.operation_code=v_operation.operation_code and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_contract_count=0 then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_CONTRACT_MISSING','router','ACT-0001','operation_code',v_operation.operation_code);
  end if;

  select count(*), coalesce(jsonb_agg(jsonb_build_object('step_id',s.step_id,'step_order',s.step_order,'execution_order',s.execution_order,'contract_code',s.contract_code,'purpose',s.purpose,'blocking_code',s.blocking_code,'status',s.status) order by coalesce(s.execution_order,s.step_order),s.step_id),'[]'::jsonb)
  into v_step_count,v_steps
  from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_step_count=0 then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_STEPS_MISSING','router','ACT-0001','operation_code',v_operation.operation_code);
  end if;

  select count(*) filter (where b.required),
         count(*) filter (where b.required and pv.policy_code is not null)
  into v_required_policy_count,v_resolved_policy_count
  from public.lf_operation_policy_bindings b
  left join public.lf_policy_versions pv on pv.policy_code=b.policy_code and pv.status='ACTIVE'
  where b.operation_code=v_operation.operation_code and b.binding_status='ACTIVE';
  if v_required_policy_count>v_resolved_policy_count then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_REQUIRED_POLICY_MISSING','router','ACT-0001','operation_code',v_operation.operation_code,'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count);
  end if;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.policy_role,p.policy_code),'[]'::jsonb) into v_policies
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));

  if v_asset_found then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters
    from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo;
  end if;

  v_result_status := 'READY_TO_EXECUTE';
  return jsonb_build_object(
    'status',v_result_status,
    'router','ACT-0001',
    'source','SUPABASE',
    'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
    'asset_type',v_type_hint,
    'action_code',v_action,
    'operation_code',v_operation.operation_code,
    'operation_status',v_operation.status,
    'operation_applies_to_asset_type',v_operation.applies_to_asset_type,
    'contract_count',v_contract_count,
    'contracts',v_contracts,
    'step_count',v_step_count,
    'steps',v_steps,
    'required_policy_count',v_required_policy_count,
    'resolved_policy_count',v_resolved_policy_count,
    'policies',v_policies,
    'policy_stale_guard','public.lf_operation_policy_snapshot_guard_v1',
    'adapters',v_adapters,
    'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
    'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES')
  );
end;
$$;

revoke all on function public.lf_router_resolve_v1(text,text,text,text,text) from public, anon, authenticated;

update public.lf_activos
set version='v0.3',
    metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'router_architecture_version','v1.0',
      'master_asset_registry','public.lf_activos',
      'operational_asset_view','public.v_lf_fuente_operativa',
      'operational_search_view','public.v_lf_fuente_operativa_busqueda',
      'router_action_registry','public.lf_router_action_registry',
      'router_runtime_function','public.lf_router_resolve_v1',
      'adapter_binding_model','public.lf_activo_relaciones.relacion_tipo=ADAPTER_APLICA_A',
      'adapter_binding_view','public.v_lf_router_adapter_bindings',
      'policy_type_model','tipo_activo=REGLA + subtipo_activo=POLICY_*',
      'policy_version_store','public.lf_policy_versions',
      'policy_binding_store','public.lf_operation_policy_bindings',
      'policy_snapshot_view','public.v_lf_operation_policy_snapshot',
      'conflict_precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
      'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES'),
      'deterministic_blocking',jsonb_build_array('BLOCK_ASSET_TYPE_UNRESOLVED','BLOCK_ASSET_NOT_FOUND','BLOCK_TARGET_ALREADY_EXISTS','BLOCK_OPERATION_NOT_REGISTERED','BLOCK_OPERATION_REGISTRY_MISSING','BLOCK_OPERATION_ASSET_TYPE_MISMATCH','BLOCK_ACTIVE_CONTRACT_MISSING','BLOCK_ACTIVE_STEPS_MISSING','BLOCK_REQUIRED_POLICY_MISSING')
    ),
    updated_by_execution_id='EXEC-GOV-ROUTER-ACT0001-20260827-001',
    updated_at=now()
where codigo_activo='ACT-0001';

commit;
