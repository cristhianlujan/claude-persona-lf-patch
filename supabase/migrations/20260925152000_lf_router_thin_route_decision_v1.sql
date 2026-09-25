begin;

-- Thin ACT-0001 routing boundary.
-- This function performs only request classification + target/action/operation routing.
-- It intentionally does NOT resolve contracts, steps, policies, adapters, Input Governance,
-- execution readiness, lifecycle qualification, runtime eligibility, context, or next-step state.

create or replace function public.lf_router_route_decision_v1(
  p_request_text text,
  p_target_hint text default null::text,
  p_action_hint text default null::text,
  p_asset_type_hint text default null::text
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
  v_target_found boolean := false;
  v_target_name text;
  v_target_subtype text;
  v_rule public.lf_router_action_registry%rowtype;
  v_operation_exists boolean := false;
begin
  if btrim(coalesce(p_request_text,''))='' then
    return jsonb_build_object(
      'schema','LF_ROUTER_ROUTE_DECISION_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_EMPTY_REQUEST',
      'router','ACT-0001'
    );
  end if;

  v_req := regexp_replace(
    translate(lower(coalesce(p_request_text,'')),'áéíóúüñ','aeiouun'),
    '[^a-z0-9_\- ]+',' ','g'
  );
  v_req := regexp_replace(v_req,'\s+',' ','g');
  v_target_norm := regexp_replace(
    translate(lower(coalesce(p_target_hint,'')),'áéíóúüñ','aeiouun'),
    '[^a-z0-9_\- ]+',' ','g'
  );

  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint,'')),''));
  if v_type_hint is null then
    if v_req ~ '(^| )(perfil|profile)( |$)' or v_req ~ '(^| )pidele (al|a|el) ' then
      v_type_hint := 'PERFIL';
    elsif v_req ~ '(^| )skill( |$)' then
      v_type_hint := 'SKILL';
    elsif v_req ~ '(^| )adapter( |$)' then
      v_type_hint := 'ADAPTER';
    elsif v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)'
       and v_req ~ '(^| )(regla|policy)( |$)'
       and v_req ~ '(^| )(pantalla|screen)( |$)' then
      v_type_hint := 'REGLA_PANTALLA_RELATION';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then
      v_type_hint := 'REGLA';
    elsif v_req ~ '(^| )(estrategia|strategy)( |$)' then
      v_type_hint := 'STRATEGY';
    elsif v_req ~ '(^| )(doc|documento)( |$)' then
      v_type_hint := 'DOC';
    end if;
  end if;

  if v_target_norm<>'' then
    if v_type_hint='OPERATION_CODE' then
      select r.operation_code,r.operation_code,r.operation_type
        into v_candidate_code,v_target_name,v_target_subtype
      from public.lf_operation_registry r
      where lower(r.operation_code)=lower(btrim(coalesce(p_target_hint,'')))
      order by r.operation_code
      limit 1;
      v_target_found := found;
    else
      select b.codigo_activo,b.nombre_canonico,b.subtipo_activo
        into v_candidate_code,v_target_name,v_target_subtype
      from public.v_lf_fuente_operativa_busqueda b
      where (v_type_hint is null or b.tipo_activo=v_type_hint)
        and (
          regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
          or regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
          or exists (
            select 1
            from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
            where regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g')=v_target_norm
          )
        )
      order by b.codigo_activo
      limit 1;
      v_target_found := found;
    end if;
  else
    select b.codigo_activo,b.nombre_canonico,b.subtipo_activo
      into v_candidate_code,v_target_name,v_target_subtype
    from public.v_lf_fuente_operativa_busqueda b
    where (v_type_hint is null or b.tipo_activo=v_type_hint)
    order by
      case when position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0 then 1200 else 0 end +
      case when position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0 then 900 else 0 end +
      coalesce((select max(800) from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0),0) +
      coalesce((select max(300) from jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw where position(regexp_replace(translate(lower(kw),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0),0) desc,
      b.codigo_activo
    limit 1;

    if found then
      select exists (
        select 1
        from public.v_lf_fuente_operativa_busqueda b
        where b.codigo_activo=v_candidate_code
          and (
            position(regexp_replace(translate(lower(b.codigo_activo),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
            or position(regexp_replace(translate(lower(b.nombre_canonico),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
            or exists (
              select 1
              from jsonb_array_elements_text(coalesce(b.aliases,'[]'::jsonb)) al
              where position(regexp_replace(translate(lower(al),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
            )
            or exists (
              select 1
              from jsonb_array_elements_text(coalesce(b.keywords,'[]'::jsonb)) kw
              where position(regexp_replace(translate(lower(kw),'áéíóúüñ','aeiouun'),'[^a-z0-9_\- ]+',' ','g') in v_req)>0
            )
          )
      ) into v_target_found;
    end if;
  end if;

  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
  if v_action is null then
    if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then
      v_action := 'ASSET_INSPECTION';
    elsif v_type_hint='REGLA_PANTALLA_RELATION'
       and v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' then
      v_action := 'REGLA_PANTALLA_LINK';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(ejecuta|ejecutar|corre|correr|continua|continuar|retoma|retomar)( |$)' then
      v_action := 'STRATEGY_EXECUTION';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(cierra|cerrar|cierre|finaliza|finalizar)( |$)' then
      v_action := 'STRATEGY_CLOSE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      v_action := 'STRATEGY_CREATE';
    elsif v_type_hint='STRATEGY' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      v_action := 'STRATEGY_UPDATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then
      v_action := 'PROFILE_CREATE';
    elsif v_type_hint='PERFIL' and v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' and v_req ~ '(^| )(perfil|profile)( |$)' then
      v_action := 'PROFILE_UPDATE';
    elsif v_type_hint='PERFIL' and v_target_found then
      v_action := 'PROFILE_EXECUTION';
    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE';
      elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE';
      elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE';
      elsif v_type_hint='REGLA' then v_action:='REGLA_CREATE';
      else v_action:='CREATE';
      end if;
    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE';
      elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE';
      elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE';
      elsif v_type_hint='REGLA' then v_action:='REGLA_UPDATE';
      else v_action:='UPDATE';
      end if;
    else
      v_action := 'ASSET_INSPECTION';
    end if;
  end if;

  if v_type_hint is null then
    return jsonb_build_object(
      'schema','LF_ROUTER_ROUTE_DECISION_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_ASSET_TYPE_UNRESOLVED',
      'router','ACT-0001',
      'action_code',v_action
    );
  end if;

  select * into v_rule
  from public.lf_router_action_registry
  where asset_type=v_type_hint
    and action_code=v_action
    and status='ACTIVE';

  if not found then
    return jsonb_build_object(
      'schema','LF_ROUTER_ROUTE_DECISION_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_OPERATION_NOT_REGISTERED',
      'router','ACT-0001',
      'asset_type',v_type_hint,
      'action_code',v_action,
      'target_code',case when v_target_found then v_candidate_code else null end
    );
  end if;

  if v_rule.requires_existing_target and not v_target_found then
    return jsonb_build_object(
      'schema','LF_ROUTER_ROUTE_DECISION_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_ASSET_NOT_FOUND',
      'router','ACT-0001',
      'asset_type',v_type_hint,
      'action_code',v_action
    );
  end if;

  if v_rule.requires_missing_target and v_target_found then
    return jsonb_build_object(
      'schema','LF_ROUTER_ROUTE_DECISION_V1',
      'status','BLOCKED',
      'blocking_code','BLOCK_TARGET_ALREADY_EXISTS',
      'router','ACT-0001',
      'asset_type',v_type_hint,
      'action_code',v_action,
      'target_code',v_candidate_code
    );
  end if;

  if v_rule.operation_resolution <> 'NONE' then
    select exists(
      select 1
      from public.lf_operation_registry r
      where r.operation_code=v_rule.operation_code
    ) into v_operation_exists;

    if not v_operation_exists then
      return jsonb_build_object(
        'schema','LF_ROUTER_ROUTE_DECISION_V1',
        'status','BLOCKED',
        'blocking_code','BLOCK_OPERATION_REGISTRY_MISSING',
        'router','ACT-0001',
        'asset_type',v_type_hint,
        'action_code',v_action,
        'operation_code',v_rule.operation_code
      );
    end if;
  end if;

  return jsonb_build_object(
    'schema','LF_ROUTER_ROUTE_DECISION_V1',
    'status','ROUTED',
    'router','ACT-0001',
    'asset_type',v_type_hint,
    'action_code',v_action,
    'operation_code',case when v_rule.operation_resolution='NONE' then null else v_rule.operation_code end,
    'target',case when v_target_found then jsonb_build_object(
      'codigo_activo',v_candidate_code,
      'nombre_canonico',coalesce(v_target_name,v_candidate_code),
      'tipo_activo',v_type_hint,
      'subtipo_activo',v_target_subtype
    ) else null end,
    'route_binding_ref','public.lf_router_action_registry:'||v_type_hint||':'||v_action
  );
end;
$function$;

revoke all on function public.lf_router_route_decision_v1(text,text,text,text) from public,anon,authenticated;
grant execute on function public.lf_router_route_decision_v1(text,text,text,text) to service_role;

comment on function public.lf_router_route_decision_v1(text,text,text,text) is
  'Thin ACT-0001 router. Classifies request and resolves target/action/operation route only. It must not resolve contracts, steps, policies, adapters, Input Governance, lifecycle/runtime eligibility, context, execution state, or next-step decisions.';

do $post$
declare
  d text;
  r jsonb;
  forbidden text;
begin
  select pg_get_functiondef('public.lf_router_route_decision_v1(text,text,text,text)'::regprocedure)
    into d;

  foreach forbidden in array array[
    'lf_operation_contracts',
    'lf_operation_step_contracts',
    'v_lf_operation_policy_snapshot',
    'v_lf_router_adapter_bindings',
    'fn_lf_router_input_governance_resolve_v1',
    'lf_test_requirement_bindings',
    'lf_qualification_current_v1',
    'downstream_execution_allowed',
    'next_step',
    'contract_refs',
    'policy_refs',
    'input_governance'
  ] loop
    if strpos(lower(d),lower(forbidden))>0 then
      raise exception 'LF_ROUTER_THIN_BOUNDARY_FORBIDDEN_DEPENDENCY:%',forbidden;
    end if;
  end loop;

  r:=public.lf_router_route_decision_v1(
    'Ejecuta el perfil Systemic Root Cause Repair',
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',
    'PROFILE_EXECUTION',
    'PERFIL'
  );

  if r->>'schema'<>'LF_ROUTER_ROUTE_DECISION_V1'
     or r->>'status'<>'ROUTED'
     or r->>'router'<>'ACT-0001'
     or r->>'action_code'<>'PROFILE_EXECUTION'
     or r->>'operation_code'<>'EJECUCION_PERFIL_LF'
     or r#>>'{target,codigo_activo}'<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF' then
    raise exception 'LF_ROUTER_THIN_ROUTE_READBACK_FAILED:%',r;
  end if;

  if r ?| array['contract_refs','next_step','policy_refs','adapters','input_governance','downstream_execution_allowed'] then
    raise exception 'LF_ROUTER_THIN_ROUTE_OUTPUT_OVERLOADED:%',r;
  end if;
end
$post$;

commit;
