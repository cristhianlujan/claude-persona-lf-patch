-- Strategy 26 / backlog #55
-- Fail closed PROFILE_EXECUTION before READY_TO_EXECUTE when the resolved
-- profile runtime state is not currently authorized. This is a narrow Router
-- enforcement fix only; it does not enable any profile, alter impact policy,
-- or create a runtime-state promotion path.

do $$
declare
  v_def text;
  v_anchor text := E'  if v_operation.applies_to_asset_type is not null and v_operation.applies_to_asset_type<>v_type_hint then return jsonb_build_object(''status'',''BLOCKED'',''blocking_code'',''BLOCK_OPERATION_ASSET_TYPE_MISMATCH'',''router'',''ACT-0001'',''asset_type'',v_type_hint,''operation_code'',v_operation.operation_code,''applies_to_asset_type'',v_operation.applies_to_asset_type); end if;\n';
  v_guard text := E'\n  -- Strategy26 G-A: the profile asset itself must be runtime-authorized before\n  -- EJECUCION_PERFIL_LF can proceed. Runtime capability is not authority.\n  if v_operation.operation_code = ''EJECUCION_PERFIL_LF'' and v_asset_found then\n    if nullif(btrim(coalesce(v_asset.runtime_estado, '''')), '''') is null\n       or nullif(btrim(coalesce(v_asset.estado_operativo, '''')), '''') is null\n       or nullif(btrim(coalesce(v_asset.estado_documental, '''')), '''') is null then\n      return jsonb_build_object(\n        ''status'',''BLOCKED'',\n        ''blocking_code'',''BLOCK_PROFILE_STATE_INCOMPLETE'',\n        ''router'',''ACT-0001'',\n        ''source'',''SUPABASE'',\n        ''asset_type'',v_type_hint,\n        ''action_code'',v_action,\n        ''operation_code'',v_operation.operation_code,\n        ''asset_code'',v_asset.codigo_activo,\n        ''downstream_execution_allowed'',false\n      );\n    end if;\n\n    if upper(v_asset.runtime_estado) in (''NO_HABILITADO'',''NO_APLICA'')\n       or upper(v_asset.estado_operativo) in (''BLOQUEADO'',''ELIMINADO'')\n       or upper(v_asset.estado_documental) = ''ELIMINADO'' then\n      return jsonb_build_object(\n        ''status'',''BLOCKED'',\n        ''blocking_code'',''BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED'',\n        ''router'',''ACT-0001'',\n        ''source'',''SUPABASE'',\n        ''asset_type'',v_type_hint,\n        ''action_code'',v_action,\n        ''operation_code'',v_operation.operation_code,\n        ''asset_code'',v_asset.codigo_activo,\n        ''profile_state'',jsonb_build_object(\n          ''estado_documental'',v_asset.estado_documental,\n          ''estado_operativo'',v_asset.estado_operativo,\n          ''runtime_estado'',v_asset.runtime_estado,\n          ''impacto_automatico'',v_asset.impacto_automatico\n        ),\n        ''downstream_execution_allowed'',false\n      );\n    end if;\n  end if;\n';
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_def;

  if position('BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED' in v_def) > 0 then
    return;
  end if;

  if position(v_anchor in v_def) = 0 then
    raise exception 'S26_ROUTER_PROFILE_RUNTIME_GATE_ANCHOR_NOT_FOUND';
  end if;

  v_def := replace(v_def, v_anchor, v_anchor || v_guard);
  execute v_def;
end;
$$;

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
  'ACT-0001 canonical Router. Strategy26 G-A hardening: EJECUCION_PERFIL_LF fails closed when the resolved profile runtime state is NO_HABILITADO/NO_APLICA, incomplete, or the profile is operationally blocked/deleted. This gate does not enable runtime or promotion.';
