begin;

-- Step 2 only: consume the already-resolved ACT-0001 route at the canonical
-- profile execution begin boundary. This adapter MUST NOT re-route, resolve
-- context, discover source, load policies/contracts/adapters, or execute runtime.

create or replace function public.lf_profile_execution_begin_from_route_v1(
  p_route_decision jsonb,
  p_execution_id text,
  p_idempotency_key text,
  p_request_sha256 text,
  p_actor_execution_id text,
  p_target_repo text,
  p_target_path text,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
set search_path to 'pg_catalog','public','extensions'
as $function$
declare
  v_profile_code text;
  v_route_binding_ref text;
  v_route_sha256 text;
  v_result jsonb;
begin
  if p_route_decision is null or jsonb_typeof(p_route_decision) <> 'object' then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTE_DECISION_INVALID',
      'receiver','lf_profile_execution_begin_from_route_v1'
    );
  end if;

  if p_route_decision->>'schema' <> 'LF_ROUTER_ROUTE_DECISION_V1' then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTE_SCHEMA_MISMATCH',
      'receiver','lf_profile_execution_begin_from_route_v1'
    );
  end if;

  if p_route_decision->>'status' <> 'ROUTED'
     or p_route_decision->>'router' <> 'ACT-0001' then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTE_NOT_ROUTED_BY_ACT0001',
      'receiver','lf_profile_execution_begin_from_route_v1'
    );
  end if;

  if p_route_decision->>'asset_type' <> 'PERFIL'
     or p_route_decision->>'action_code' <> 'PROFILE_EXECUTION'
     or p_route_decision->>'operation_code' <> 'EJECUCION_PERFIL_LF' then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTE_OPERATION_MISMATCH',
      'receiver','lf_profile_execution_begin_from_route_v1',
      'asset_type',p_route_decision->>'asset_type',
      'action_code',p_route_decision->>'action_code',
      'operation_code',p_route_decision->>'operation_code'
    );
  end if;

  v_profile_code := nullif(btrim(coalesce(p_route_decision#>>'{target,codigo_activo}','')),'');
  if v_profile_code is null then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTE_TARGET_MISSING',
      'receiver','lf_profile_execution_begin_from_route_v1'
    );
  end if;

  v_route_binding_ref := nullif(btrim(coalesce(p_route_decision->>'route_binding_ref','')),'');
  if v_route_binding_ref is distinct from 'public.lf_router_action_registry:PERFIL:PROFILE_EXECUTION' then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_ROUTE_BINDING_REF_MISMATCH',
      'receiver','lf_profile_execution_begin_from_route_v1'
    );
  end if;

  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_idempotency_key,'')),'') is null
     or nullif(btrim(coalesce(p_request_sha256,'')),'') is null
     or nullif(btrim(coalesce(p_actor_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_target_repo,'')),'') is null
     or nullif(btrim(coalesce(p_target_path,'')),'') is null then
    return jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_BEGIN_REQUIRED_INPUT_MISSING',
      'receiver','lf_profile_execution_begin_from_route_v1'
    );
  end if;

  v_route_sha256 := 'sha256:' || encode(
    extensions.digest(convert_to(p_route_decision::text,'UTF8'),'sha256'),
    'hex'
  );

  v_result := public.lf_profile_execution_begin_v1(
    p_execution_id,
    p_idempotency_key,
    p_request_sha256,
    p_actor_execution_id,
    v_profile_code,
    p_target_repo,
    p_target_path,
    coalesce(p_manifest,'{}'::jsonb) || jsonb_build_object(
      'route_decision_schema','LF_ROUTER_ROUTE_DECISION_V1',
      'route_decision_router','ACT-0001',
      'route_decision_binding_ref',v_route_binding_ref,
      'route_decision_sha256',v_route_sha256,
      'route_decision',p_route_decision
    )
  );

  return v_result || jsonb_build_object(
    'route_consumed',true,
    'route_decision_sha256',v_route_sha256,
    'route_binding_ref',v_route_binding_ref,
    'routed_profile_code',v_profile_code
  );
end;
$function$;

revoke all on function public.lf_profile_execution_begin_from_route_v1(jsonb,text,text,text,text,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.lf_profile_execution_begin_from_route_v1(jsonb,text,text,text,text,text,text,jsonb)
  to service_role;

comment on function public.lf_profile_execution_begin_from_route_v1(jsonb,text,text,text,text,text,text,jsonb) is
  'Thin Step-2 receiver for ACT-0001 LF_ROUTER_ROUTE_DECISION_V1. Validates exact profile-execution route identity, binds it into the execution manifest, and delegates to canonical lf_profile_execution_begin_v1. It must not re-route or resolve context/source/policies/contracts/adapters/runtime.';

do $post$
declare
  d text;
  r jsonb;
  forbidden text;
begin
  select pg_get_functiondef(
    'public.lf_profile_execution_begin_from_route_v1(jsonb,text,text,text,text,text,text,jsonb)'::regprocedure
  ) into d;

  if strpos(d,'lf_profile_execution_begin_v1')=0 then
    raise exception 'LF_PROFILE_BEGIN_ROUTE_RECEIVER_CANONICAL_BEGIN_MISSING';
  end if;

  foreach forbidden in array array[
    'lf_router_resolve_v1',
    'lf_router_route_decision_v1',
    'lf_operation_contracts',
    'lf_operation_step_contracts',
    'v_lf_operation_policy_snapshot',
    'v_lf_router_adapter_bindings',
    'fn_lf_router_input_governance_resolve_v1',
    'lf_activos',
    'v_lf_fuente_operativa_busqueda',
    'runtime_request_envelope'
  ] loop
    if strpos(lower(d),lower(forbidden))>0 then
      raise exception 'LF_PROFILE_BEGIN_ROUTE_RECEIVER_FORBIDDEN_DEPENDENCY:%',forbidden;
    end if;
  end loop;

  -- Negative proof: a foreign operation must fail closed before reservation.
  r:=public.lf_profile_execution_begin_from_route_v1(
    jsonb_build_object(
      'schema','LF_ROUTER_ROUTE_DECISION_V1',
      'status','ROUTED',
      'router','ACT-0001',
      'asset_type','PERFIL',
      'action_code','PROFILE_EXECUTION',
      'operation_code','OTRA_OPERACION',
      'target',jsonb_build_object('codigo_activo','PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'),
      'route_binding_ref','public.lf_router_action_registry:PERFIL:PROFILE_EXECUTION'
    ),
    'SHOULD-NOT-RESERVE',
    'should-not-reserve',
    repeat('a',64),
    'SHOULD-NOT-RESERVE',
    'cristhianlujan/claude-persona-lf-patch',
    'profiles/systemic_root_cause_repair_lf',
    '{}'::jsonb
  );

  if r->>'status' <> 'BLOCKED'
     or r->>'blocking_code' <> 'BLOCK_ROUTE_OPERATION_MISMATCH' then
    raise exception 'LF_PROFILE_BEGIN_ROUTE_RECEIVER_NEGATIVE_FAIL:%',r;
  end if;

  if exists (
    select 1 from public.lf_operation_execution
    where execution_id='SHOULD-NOT-RESERVE'
  ) then
    raise exception 'LF_PROFILE_BEGIN_ROUTE_RECEIVER_NEGATIVE_SIDE_EFFECT';
  end if;
end
$post$;

commit;
