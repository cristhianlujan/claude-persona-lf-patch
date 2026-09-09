-- S30 candidate-only ACT-0001 inference patch.
-- Scope: recognize explicit policy/politica language for REGLA without changing generic REGLA behavior.
-- No durable apply or production authorization is implied by this source.

do $s30_router_policy_inference_patch$
declare
  v_def text;
  v_old_create text := $old_create$    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; else v_action:='CREATE'; end if;$old_create$;
  v_new_create text := $new_create$    elsif v_req ~ '(^| )(crea|crear|creame|nuevo|nueva)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_CREATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_CREATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_CREATE'; elsif v_type_hint='REGLA' and v_req ~ '(^| )(policy|politica)( |$)' then v_action:='POLICY_CREATE'; else v_action:='CREATE'; end if;$new_create$;
  v_old_update text := $old_update$    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE'; else v_action:='UPDATE'; end if;$old_update$;
  v_new_update text := $new_update$    elsif v_req ~ '(^| )(corrige|corregir|mejora|mejorar|actualiza|actualizar|remedia|remediar|repara|reparar|modifica|modificar)( |$)' then
      if v_type_hint='PERFIL' then v_action:='PROFILE_UPDATE'; elsif v_type_hint='SKILL' then v_action:='SKILL_UPDATE'; elsif v_type_hint='ADAPTER' then v_action:='ADAPTER_UPDATE'; elsif v_type_hint='REGLA' and v_req ~ '(^| )(policy|politica)( |$)' then v_action:='POLICY_UPDATE'; elsif v_type_hint='REGLA' then v_action:='RULE_UPDATE'; else v_action:='UPDATE'; end if;$new_update$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into v_def;
  if length(v_def)-length(replace(v_def,v_old_create,'')) <> length(v_old_create) then
    raise exception 'S30_ROUTER_POLICY_CREATE_ANCHOR_NOT_EXACTLY_ONCE';
  end if;
  if length(v_def)-length(replace(v_def,v_old_update,'')) <> length(v_old_update) then
    raise exception 'S30_ROUTER_POLICY_UPDATE_ANCHOR_NOT_EXACTLY_ONCE';
  end if;
  v_def := replace(v_def,v_old_create,v_new_create);
  v_def := replace(v_def,v_old_update,v_new_update);
  execute v_def;
end;
$s30_router_policy_inference_patch$;
