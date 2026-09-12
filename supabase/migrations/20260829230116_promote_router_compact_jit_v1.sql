create or replace function public.lf_router_resolve_v1(
  p_request_text text,
  p_target_hint text default null::text,
  p_action_hint text default null::text,
  p_asset_type_hint text default null::text,
  p_distribution_mode text default 'ROUTER'::text
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $function$
declare
  v_req text;
  v_target_norm text;
  v_action text;
  v_type_hint text;
  v_candidate_code text;
  v_asset public.lf_activos%rowtype;
  v_asset_found boolean := false;
  v_rule public.lf_router_action_registry%rowtype;
  v_operation public.lf_operation_registry%rowtype;
  v_contract_refs jsonb := '[]'::jsonb;
  v_next_step jsonb := null;
  v_policy_refs jsonb := '[]'::jsonb;
  v_adapters jsonb := '[]'::jsonb;
  v_required_policy_count integer := 0;
  v_resolved_policy_count integer := 0;
  v_contract_count integer := 0;
  v_step_count integer := 0;
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

  if v_target_norm<>'' then
    select b.codigo_activo into v_candidate_code
    from public.v_lf_fuente_operativa_busqueda b
    where (v_type_hint is null or b.tipo_activo=v_type_hint)
      and (
        regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        or regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        or exists (
          select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
          where regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
        )
      )
    order by b.codigo_activo limit 1;
    v_asset_found := found;
  else
    select b.codigo_activo into v_candidate_code
    from public.v_lf_fuente_operativa_busqueda b
    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by
      case when position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0 then 1200 else 0 end +
      case when position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0 then 900 else 0 end +
      coalesce((select max(800) from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
                where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0),0) +
      coalesce((select max(300) from jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw
                where position(regexp_replace(translate(lower(kw),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0),0) +
      coalesce((select count(*)*25 from regexp_split_to_table(lower(concat_ws(' ',b.nombre_canonico,b.subtipo_activo)), '[^a-z0-9]+') tok
                where length(tok)>=2 and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                  and v_req ~ ('(^|[^a-z0-9])'||tok)),0) +
      coalesce((select count(*)*10 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al,
                                        regexp_split_to_table(lower(al),'[^a-z0-9]+') tok
                where length(tok)>=2 and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                  and v_req ~ ('(^|[^a-z0-9])'||tok)),0) +
      coalesce((select count(*)*2 from jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw,
                                       regexp_split_to_table(lower(kw),'[^a-z0-9]+') tok
                where length(tok)>=3 and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                  and v_req ~ ('(^|[^a-z0-9])'||tok)),0) desc,
      case when b.tipo_activo in ('PERFIL','SKILL') then 1 else 0 end desc,
      b.codigo_activo limit 1;

    if found then
      select exists (
        select 1 from public.v_lf_fuente_operativa_busqueda b
        where b.codigo_activo=v_candidate_code
          and (
            position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
            or position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
            or exists (select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
                       where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0)
            or exists (
              select 1 from regexp_split_to_table(lower(concat_ws(' ',b.nombre_canonico,b.subtipo_activo)), '[^a-z0-9]+') tok
              where length(tok)>=2 and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                and v_req ~ ('(^|[^a-z0-9])'||tok)
            )
            or exists (
              select 1 from jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw,
                   regexp_split_to_table(lower(kw),'[^a-z0-9]+') tok
              where length(tok)>=3 and tok not in ('perfil','profile','skill','adapter','regla','policy','doc','documento','lf','candidato')
                and v_req ~ ('(^|[^a-z0-9])'||tok)
            )
          )
      ) into v_asset_found;
    end if;
  end if;

  if v_asset_found then
    select a.* into v_asset from public.lf_activos a
    where a.codigo_activo=v_candidate_code and a.archived_at is null limit 1;
    if not found then
      return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_MASTER_ASSET_HYDRATION_FAILED','router','ACT-0001','asset_code',v_candidate_code);
    end if;
    v_type_hint := v_asset.tipo_activo;
  end if;

  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
  if v_action is null then
    if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then v_action:='ASSET_INSPECTION';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_CREATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then v_action:='PROFILE_UPDATE';
    elsif v_type_hint='PERFIL' and v_asset_found then v_action:='PROFILE_EXECUTION';
    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; else v_action:='CREATE'; end if;
    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE'; else v_action:='UPDATE'; end if;
    else v_action:='ASSET_INSPECTION'; end if;
  end if;

  if v_action in ('PROFILE_CREATE','SKILL_CREATE','ADAPTER_CREATE') and v_asset_found and v_target_norm='' then
    if not exists (
      select 1 from public.v_lf_fuente_operativa_busqueda b
      where b.codigo_activo=v_asset.codigo_activo
        and (
          position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
          or position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
          or exists (select 1 from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0)
        )
    ) then v_asset_found := false; end if;
  end if;

  if v_type_hint is null then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED','router','ACT-0001','action_code',v_action);
  end if;

  select * into v_rule from public.lf_router_action_registry where asset_type=v_type_hint and action_code=v_action and status='ACTIVE';
  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_NOT_REGISTERED','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset_code',case when v_asset_found then v_asset.codigo_activo else null end);
  end if;
  if v_rule.requires_existing_target and not v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ASSET_NOT_FOUND','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action); end if;
  if v_rule.requires_missing_target and v_asset_found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_TARGET_ALREADY_EXISTS','router','ACT-0001','asset_type',v_type_hint,'action_code',v_action,'asset_code',v_asset.codigo_activo); end if;

  if v_rule.operation_resolution='NONE' then
    if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;
    return jsonb_build_object('status','READY_INSPECTION','router','ACT-0001','source','SUPABASE','discovery_source','public.v_lf_fuente_operativa_busqueda','asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,'asset_type',v_type_hint,'action_code',v_action,'operation_code',null,'adapters',v_adapters,'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'));
  end if;

  select * into v_operation from public.lf_operation_registry where operation_code=v_rule.operation_code;
  if not found then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_REGISTRY_MISSING','router','ACT-0001','operation_code',v_rule.operation_code); end if;
  if v_operation.applies_to_asset_type is not null and v_operation.applies_to_asset_type<>v_type_hint then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_OPERATION_ASSET_TYPE_MISMATCH','router','ACT-0001','asset_type',v_type_hint,'operation_code',v_operation.operation_code,'applies_to_asset_type',v_operation.applies_to_asset_type); end if;

  select count(*), coalesce(jsonb_agg(jsonb_build_array(c.contract_code,c.contract_sha) order by c.contract_code),'[]'::jsonb)
    into v_contract_count,v_contract_refs
  from public.lf_operation_contracts c
  where c.operation_code=v_operation.operation_code and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_contract_count=0 then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_CONTRACT_MISSING','router','ACT-0001','operation_code',v_operation.operation_code); end if;

  select count(*) into v_step_count from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_step_count=0 then return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_ACTIVE_STEPS_MISSING','router','ACT-0001','operation_code',v_operation.operation_code); end if;

  select jsonb_build_object(
      'step_id',s.step_id,'execution_order',s.execution_order,'contract_code',s.contract_code,
      'blocking_code',s.blocking_code,'status',s.status,'resolver_ref',s.resolver_ref,
      'required_evidence_keys',s.required_evidence_keys,'next_if_pass',s.next_if_pass,'next_if_blocked',s.next_if_blocked
    ) into v_next_step
  from public.lf_operation_step_contracts s
  where s.operation_code=v_operation.operation_code and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
  order by coalesce(s.execution_order,s.step_order),s.step_id limit 1;

  select count(*) filter (where b.required) into v_required_policy_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=v_operation.operation_code and b.binding_status='ACTIVE'
    and (p_distribution_mode is null or p_distribution_mode=any(b.distribution_modes));

  select count(*) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and p.required
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));
  if v_required_policy_count>v_resolved_policy_count then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_REQUIRED_POLICY_MISSING','router','ACT-0001','operation_code',v_operation.operation_code,'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count);
  end if;

  select coalesce(jsonb_agg(jsonb_build_array(p.policy_code,p.policy_version,p.policy_sha) order by p.policy_role,p.policy_code),'[]'::jsonb) into v_policy_refs
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));

  if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;

  return jsonb_build_object(
    'status','READY_TO_EXECUTE','router','ACT-0001','source','SUPABASE','discovery_source','public.v_lf_fuente_operativa_busqueda',
    'asset',case when v_asset_found then jsonb_build_object('codigo_activo',v_asset.codigo_activo,'nombre_canonico',v_asset.nombre_canonico,'tipo_activo',v_asset.tipo_activo,'subtipo_activo',v_asset.subtipo_activo,'estado_documental',v_asset.estado_documental,'estado_operativo',v_asset.estado_operativo,'version',v_asset.version) else null end,
    'asset_type',v_type_hint,'action_code',v_action,'operation_code',v_operation.operation_code,
    'operation_status',v_operation.status,'operation_applies_to_asset_type',v_operation.applies_to_asset_type,
    'contract_count',v_contract_count,'contract_refs',v_contract_refs,
    'step_count',v_step_count,'next_step',v_next_step,'next_step_ref',v_operation.operation_code||'/'||(v_next_step->>'step_id'),
    'required_policy_count',v_required_policy_count,'resolved_policy_count',v_resolved_policy_count,'policy_refs',v_policy_refs,
    'policy_stale_guard','public.lf_operation_policy_snapshot_guard_v1','adapters',v_adapters,
    'precedence',jsonb_build_array('OPERATION_CONTRACT','POLICY','ADAPTER','PROFILE','SHELL'),
    'composition_order',jsonb_build_array('SHELL','PROFILE','ADAPTER','POLICY_AND_CONTRACT_GATES')
  );
end;
$function$;