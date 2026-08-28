update public.lf_activos
set metadata = jsonb_set(
  coalesce(metadata,'{}'::jsonb),
  '{keywords}',
  '["pantalla","interfaz","layout","jerarquia visual","componentes","visual QA","CTA","espaciado","diseno visual"]'::jsonb,
  true
),
updated_at=now(),
updated_by_execution_id='EXEC-ROUTER-CAPABILITY-UI-CANARY-20260827-001'
where codigo_activo='PERFIL-UI-ARCHITECT';

do $$
declare
  v_def text;
  v_new text;
  v_old_type text := $oldtype$  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint,'')),''));
  if v_type_hint is null then
    if v_req ~ '(^| )(perfil|profile)( |$)' or v_req ~ '(^| )pidele (al|a|el) ' then v_type_hint := 'PERFIL';
    elsif v_req ~ '(^| )skill( |$)' then v_type_hint := 'SKILL';
    elsif v_req ~ '(^| )adapter( |$)' then v_type_hint := 'ADAPTER';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';
    elsif v_req ~ '(^| )(doc|documento)( |$)' then v_type_hint := 'DOC';
    end if;
  end if;$oldtype$;
  v_new_type text := $newtype$  v_type_hint := upper(nullif(btrim(coalesce(p_asset_type_hint,'')),''));
  if v_type_hint is null then
    if v_req ~ '(^| )(perfil|profile)( |$)' or v_req ~ '(^| )pidele (al|a|el) ' then v_type_hint := 'PERFIL';
    elsif v_req ~ '(^| )skill( |$)' then v_type_hint := 'SKILL';
    elsif v_req ~ '(^| )adapter( |$)' then v_type_hint := 'ADAPTER';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';
    elsif v_req ~ '(^| )(doc|documento)( |$)' then v_type_hint := 'DOC';
    elsif v_req ~ '(^| )(pantalla|interfaz|layout|componentes|cta|espaciado|jerarquia|visual)( |$)' then v_type_hint := 'PERFIL';
    end if;
  end if;$newtype$;
  v_old_action text := $oldaction$  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
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
  end if;$oldaction$;
  v_new_action text := $newaction$  v_action := upper(nullif(btrim(coalesce(p_action_hint,'')),''));
  if v_action is null then
    if v_type_hint='PERFIL' and (
      v_req ~ '(^| )(pidele|evalua|evaluar|analiza|analizar|revisa|revisar|usa|usar|utiliza|utilizar|haz|propon|propone|proponer|disena|disenar)( |$)'
      or (
        v_req ~ '(^| )(crea|crear|creame|nuevo|nueva|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)'
        and v_req !~ '(^| )(perfil|profile)( |$)'
        and v_req ~ '(^| )(pantalla|interfaz|layout|componentes|cta|espaciado|jerarquia|visual)( |$)'
      )
    ) then
      v_action:='PROFILE_EXECUTION';
    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
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
    else
      v_action:='ASSET_INSPECTION';
    end if;
  end if;$newaction$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into v_def;
  if position(v_old_type in v_def)=0 then raise exception 'BASELINE_TYPE_HINT_SNIPPET_NOT_FOUND'; end if;
  v_new := replace(v_def,v_old_type,v_new_type);
  if position(v_old_action in v_new)=0 then raise exception 'BASELINE_ACTION_SNIPPET_NOT_FOUND'; end if;
  v_new := replace(v_new,v_old_action,v_new_action);
  execute v_new;
end $$;