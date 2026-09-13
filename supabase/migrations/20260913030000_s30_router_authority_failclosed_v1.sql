begin;

-- S30 closure repair: preserve the current Router implementation as an internal core,
-- then expose only a fail-closed wrapper to trusted runtime callers.
-- The public signature is intentionally unchanged for compatibility.
alter function public.lf_router_resolve_v1(text,text,text,text,text)
  rename to lf_router_resolve_core_v1;

revoke all on function public.lf_router_resolve_core_v1(text,text,text,text,text)
  from public, anon, authenticated, service_role;

create function public.lf_router_resolve_v1(
  p_request_text text,
  p_target_hint text default null::text,
  p_action_hint text default null::text,
  p_asset_type_hint text default null::text,
  p_distribution_mode text default 'ROUTER'::text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_result jsonb;
begin
  -- Canonical compact-router protocol is ROUTER-only. Any NULL, case variant,
  -- whitespace variant or unknown mode must fail closed before policy filtering.
  if p_distribution_mode is distinct from 'ROUTER' then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_UNSUPPORTED_DISTRIBUTION_MODE',
      'router','ACT-0001',
      'distribution_mode',p_distribution_mode
    );
  end if;

  -- target_hint is accepted only for backward signature compatibility and is never
  -- forwarded as authority. Discovery remains request-text driven as required by
  -- PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.
  v_result := public.lf_router_resolve_core_v1(
    p_request_text,
    null,
    p_action_hint,
    p_asset_type_hint,
    'ROUTER'
  );

  return v_result;
end;
$function$;

revoke all on function public.lf_router_resolve_v1(text,text,text,text,text)
  from public, anon, authenticated;
grant execute on function public.lf_router_resolve_v1(text,text,text,text,text)
  to postgres, service_role;

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
  'S30 fail-closed Router authority wrapper. Only exact ROUTER distribution mode is accepted; target_hint is never authoritative and is not forwarded to the internal core.';
comment on function public.lf_router_resolve_core_v1(text,text,text,text,text) is
  'Internal pre-S30 Router implementation. Direct service_role execution is revoked; callers must use public.lf_router_resolve_v1.';

-- S30 closure repair: generic execution reservation must prove Router authority
-- structurally at reservation time. Preserve the reliability/idempotency implementation
-- as a non-callable core and gate it through a Router-backed wrapper.
alter function public.fn_lf_operation_reserve_execution_v1(
  text,text,text,text,text,text,text,text,text,jsonb
) rename to fn_lf_operation_reserve_execution_core_v1;

revoke all on function public.fn_lf_operation_reserve_execution_core_v1(
  text,text,text,text,text,text,text,text,text,jsonb
) from public, anon, authenticated, service_role;

create function public.fn_lf_operation_reserve_execution_v1(
  p_execution_id text,
  p_operation_code text,
  p_target_type text,
  p_target_code text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_target_repo text default null,
  p_target_path text default null,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_router_request jsonb;
  v_request_text text;
  v_action_hint text;
  v_asset_type_hint text;
  v_route jsonb;
  v_route_asset_type text;
begin
  if p_manifest is null or jsonb_typeof(p_manifest) <> 'object' then
    raise exception 'INVALID_MANIFEST';
  end if;

  v_router_request := p_manifest->'router_request';
  if jsonb_typeof(v_router_request) <> 'object' then
    raise exception 'ROUTER_PROVENANCE_REQUIRED';
  end if;

  v_request_text := nullif(btrim(coalesce(v_router_request->>'request_text','')), '');
  v_action_hint := nullif(btrim(coalesce(v_router_request->>'action_hint','')), '');
  v_asset_type_hint := nullif(btrim(coalesce(v_router_request->>'asset_type_hint','')), '');

  if v_request_text is null or v_action_hint is null or v_asset_type_hint is null then
    raise exception 'ROUTER_PROVENANCE_REQUEST_INCOMPLETE';
  end if;

  -- Re-resolve authority inside the reservation transaction. Caller-supplied target_hint
  -- and caller-supplied Router receipts are deliberately not trusted.
  v_route := public.lf_router_resolve_v1(
    v_request_text,
    null,
    v_action_hint,
    v_asset_type_hint,
    'ROUTER'
  );

  if coalesce(v_route->>'status','') <> 'READY_TO_EXECUTE' then
    raise exception 'ROUTER_PROVENANCE_NOT_READY:%', coalesce(v_route->>'blocking_code','UNKNOWN');
  end if;

  if coalesce(v_route->>'operation_code','') is distinct from p_operation_code then
    raise exception 'ROUTER_OPERATION_MISMATCH';
  end if;

  v_route_asset_type := coalesce(v_route->>'asset_type', v_route#>>'{asset,tipo_activo}');
  if coalesce(v_route_asset_type,'') is distinct from p_target_type then
    raise exception 'ROUTER_TARGET_TYPE_MISMATCH';
  end if;

  if v_route ? 'downstream_execution_allowed'
     and coalesce((v_route->>'downstream_execution_allowed')::boolean,false) is not true then
    raise exception 'ROUTER_DOWNSTREAM_EXECUTION_NOT_ALLOWED';
  end if;

  return public.fn_lf_operation_reserve_execution_core_v1(
    p_execution_id,
    p_operation_code,
    p_target_type,
    p_target_code,
    p_idempotency_key,
    p_request_sha256,
    p_actor_execution_id,
    p_target_repo,
    p_target_path,
    p_manifest
  );
end;
$function$;

revoke all on function public.fn_lf_operation_reserve_execution_v1(
  text,text,text,text,text,text,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function public.fn_lf_operation_reserve_execution_v1(
  text,text,text,text,text,text,text,text,text,jsonb
) to postgres, service_role;

comment on function public.fn_lf_operation_reserve_execution_v1(text,text,text,text,text,text,text,text,text,jsonb) is
  'S30 Router-backed execution reservation. Requires manifest.router_request and re-runs ACT-0001 in ROUTER mode before delegating to the idempotent reservation core.';
comment on function public.fn_lf_operation_reserve_execution_core_v1(text,text,text,text,text,text,text,text,text,jsonb) is
  'Internal reliability/idempotency reservation core. Direct service_role execution is revoked; authority must pass through fn_lf_operation_reserve_execution_v1.';

commit;
