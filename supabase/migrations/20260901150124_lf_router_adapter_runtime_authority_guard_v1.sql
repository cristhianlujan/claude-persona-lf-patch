do $guard$
declare
  d text;
  a text := E'  if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),''[]''::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;\n\n  if jsonb_array_length(v_adapters)>0 then';
  r text := E'  if v_asset_found then select coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),''[]''::jsonb) into v_adapters from public.v_lf_router_adapter_bindings x where x.target_asset_code=v_asset.codigo_activo; end if;\n\n  if exists (select 1 from jsonb_array_elements(v_adapters) e(value) left join public.v_lf_fuente_operativa f on f.codigo_activo=e.value->>''adapter_code'' where lower(coalesce(e.value#>>''{adapter_metadata,router_discoverable}'',''false''))=''true'' and (lower(coalesce(e.value#>>''{adapter_metadata,runtime_enabled}'',''false''))<>''true'' or f.codigo_activo is null or upper(coalesce(f.runtime_estado,''''))=''NO_HABILITADO'')) then\n    return jsonb_build_object(''status'',''BLOCKED'',''blocking_code'',''BLOCK_ADAPTER_RUNTIME_NOT_AUTHORIZED'',''router'',''ACT-0001'',''source'',''SUPABASE'',''asset_type'',v_type_hint,''action_code'',v_action,''operation_code'',v_operation.operation_code,''adapters'',v_adapters,''adapter_runtime_authority_source'',''public.v_lf_fuente_operativa'',''downstream_execution_allowed'',false);\n  end if;\n\n  if jsonb_array_length(v_adapters)>0 then';
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) into d;
  if d is null then raise exception 'ROUTER_FUNCTION_MISSING'; end if;
  if position('BLOCK_ADAPTER_RUNTIME_NOT_AUTHORIZED' in d)>0 then raise exception 'ROUTER_ADAPTER_RUNTIME_GUARD_ALREADY_PRESENT'; end if;
  if position(a in d)=0 then raise exception 'ROUTER_ADAPTER_RUNTIME_GUARD_ANCHOR_DRIFT'; end if;
  execute replace(d,a,r);
end;
$guard$;
