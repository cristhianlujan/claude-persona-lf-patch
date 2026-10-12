-- ROUTER CONTEXT COMPILER V3 — SANDBOX CANDIDATE ONLY
-- Owner: transversal Router / Context Admission
-- Authority: ACT-0001 + Supabase operational registries.
-- This source does NOT replace public.lf_router_resolve_v1 and is not production-promoted.
-- Design goal: execute full Router server-side, transport a compact capsule, hydrate details JIT.

create table if not exists private.lf_router_context_capsules_v3_candidate (
  context_id uuid primary key default gen_random_uuid(),
  execution_id text,
  request_text text not null,
  request_sha256 text not null,
  action_hint text,
  asset_type_hint text,
  distribution_mode text not null,
  asset_code text,
  operation_code text,
  router_sha256 text not null,
  contract_sha256 text,
  policy_sha256 text,
  adapter_sha256 text,
  step_sha256 text,
  input_governance_sha256 text,
  raw_router jsonb not null,
  capsule jsonb not null,
  raw_bytes bigint not null,
  capsule_bytes bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '1 hour'),
  check (raw_bytes >= 0),
  check (capsule_bytes >= 0),
  check (distribution_mode in ('ROUTER','DIRECT'))
);

comment on table private.lf_router_context_capsules_v3_candidate is
'Sandbox-only context admission cache. Stores RAW Router evidence server-side and exposes only compact capsules/authorized JIT handles.';

create or replace function private.lf_router_context_sha256_v3_candidate(p_value jsonb)
returns text
language sql
immutable
set search_path to 'pg_catalog','extensions'
as $function$
  select encode(extensions.digest(coalesce(p_value,'null'::jsonb)::text,'sha256'),'hex');
$function$;

create or replace function private.lf_router_context_compile_v3_candidate(
  p_request_text text,
  p_action_hint text default null,
  p_asset_type_hint text default null,
  p_distribution_mode text default 'ROUTER',
  p_execution_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $function$
declare
  v_raw jsonb;
  v_status text;
  v_asset_code text;
  v_asset_type text;
  v_operation_code text;
  v_router_sha text;
  v_contracts jsonb;
  v_policies jsonb;
  v_adapters jsonb;
  v_step jsonb;
  v_input_governance jsonb;
  v_contract_sha text;
  v_policy_sha text;
  v_adapter_sha text;
  v_step_sha text;
  v_ig_sha text;
  v_context_id uuid;
  v_capsule jsonb;
  v_raw_bytes bigint;
  v_capsule_bytes bigint;
  v_mode text := upper(coalesce(nullif(btrim(p_distribution_mode),''),'ROUTER'));
begin
  if v_mode not in ('ROUTER','DIRECT') then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3_DISTRIBUTION_MODE_INVALID';
  end if;

  -- target_hint is deliberately NULL. Discovery belongs to ACT-0001.
  v_raw := public.lf_router_resolve_v1(
    p_request_text,
    null,
    p_action_hint,
    p_asset_type_hint,
    v_mode
  );

  v_status := coalesce(v_raw->>'status','BLOCKED');
  v_asset_code := coalesce(v_raw#>>'{asset,codigo_activo}',v_raw->>'asset_code');
  v_asset_type := coalesce(v_raw#>>'{asset,tipo_activo}',v_raw->>'asset_type');
  v_operation_code := nullif(v_raw->>'operation_code','');
  v_router_sha := private.lf_router_context_sha256_v3_candidate(v_raw);
  v_raw_bytes := octet_length(v_raw::text);

  -- Fail-closed responses remain RAW. There is no value in compressing a small
  -- block reason and no downstream consumer should need JIT after a block.
  if v_status='BLOCKED' then
    return jsonb_build_object(
      'context_contract','LF_ROUTER_CONTEXT_V3_CANDIDATE',
      'transport_mode','RAW_FAIL_CLOSED',
      'router_sha256',v_router_sha,
      'raw_bytes',v_raw_bytes,
      'capsule_bytes',v_raw_bytes,
      'payload',v_raw
    );
  end if;

  v_contracts := coalesce(v_raw->'contract_refs','[]'::jsonb);
  v_policies := coalesce(v_raw->'policy_refs','[]'::jsonb);
  v_adapters := coalesce(v_raw->'adapters','[]'::jsonb);
  v_step := coalesce(v_raw->'next_step','null'::jsonb);
  v_input_governance := coalesce(v_raw->'input_governance','null'::jsonb);

  v_contract_sha := private.lf_router_context_sha256_v3_candidate(v_contracts);
  v_policy_sha := private.lf_router_context_sha256_v3_candidate(v_policies);
  v_adapter_sha := private.lf_router_context_sha256_v3_candidate(v_adapters);
  v_step_sha := private.lf_router_context_sha256_v3_candidate(v_step);
  v_ig_sha := case when v_input_governance='null'::jsonb then null
                   else private.lf_router_context_sha256_v3_candidate(v_input_governance) end;

  v_context_id := gen_random_uuid();

  v_capsule := jsonb_strip_nulls(jsonb_build_object(
    'context_contract','LF_ROUTER_CONTEXT_V3_CANDIDATE',
    'context_id',v_context_id,
    'status',v_status,
    'router','ACT-0001',
    'source','SUPABASE',
    'asset',jsonb_build_object('code',v_asset_code,'type',v_asset_type),
    'action',v_raw->>'action_code',
    'operation',case when v_operation_code is null then null else jsonb_build_object(
      'code',v_operation_code,
      'status',v_raw->>'operation_status'
    ) end,
    'blocking_code',nullif(v_raw->>'blocking_code',''),
    'downstream_allowed',case when v_raw ? 'downstream_execution_allowed'
                              then v_raw->'downstream_execution_allowed' else null end,
    'handles',jsonb_strip_nulls(jsonb_build_object(
      'contracts',case when jsonb_array_length(v_contracts)>0 then v_contract_sha else null end,
      'policies',case when jsonb_array_length(v_policies)>0 then v_policy_sha else null end,
      'adapters',case when jsonb_array_length(v_adapters)>0 then v_adapter_sha else null end,
      'current_step',case when v_step<>'null'::jsonb then v_step_sha else null end,
      'input_governance',v_ig_sha
    )),
    'router_sha256',v_router_sha
  ));

  v_capsule_bytes := octet_length(v_capsule::text);

  -- If compact form does not save transport, preserve RAW instead.
  if v_capsule_bytes >= v_raw_bytes then
    return jsonb_build_object(
      'context_contract','LF_ROUTER_CONTEXT_V3_CANDIDATE',
      'transport_mode','RAW_NO_SAVINGS',
      'router_sha256',v_router_sha,
      'raw_bytes',v_raw_bytes,
      'capsule_bytes',v_raw_bytes,
      'payload',v_raw
    );
  end if;

  insert into private.lf_router_context_capsules_v3_candidate(
    context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
    distribution_mode,asset_code,operation_code,router_sha256,contract_sha256,
    policy_sha256,adapter_sha256,step_sha256,input_governance_sha256,raw_router,
    capsule,raw_bytes,capsule_bytes
  ) values (
    v_context_id,p_execution_id,p_request_text,
    encode(extensions.digest(coalesce(p_request_text,''),'sha256'),'hex'),
    p_action_hint,p_asset_type_hint,v_mode,v_asset_code,v_operation_code,v_router_sha,
    v_contract_sha,v_policy_sha,v_adapter_sha,v_step_sha,v_ig_sha,v_raw,v_capsule,
    v_raw_bytes,v_capsule_bytes
  );

  return jsonb_build_object(
    'context_contract','LF_ROUTER_CONTEXT_V3_CANDIDATE',
    'transport_mode','HANDLE_V3',
    'raw_bytes',v_raw_bytes,
    'capsule_bytes',v_capsule_bytes,
    'reduction_pct',round((1-(v_capsule_bytes::numeric/nullif(v_raw_bytes,0)))*100,2),
    'capsule',v_capsule
  );
end;
$function$;

create or replace function private.lf_router_context_currentness_v3_candidate(p_context_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_ctx private.lf_router_context_capsules_v3_candidate%rowtype;
  v_contracts jsonb := '[]'::jsonb;
  v_policies jsonb := '[]'::jsonb;
  v_adapters jsonb := '[]'::jsonb;
  v_step jsonb := 'null'::jsonb;
  v_contract_sha text;
  v_policy_sha text;
  v_adapter_sha text;
  v_step_sha text;
begin
  select context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
         distribution_mode,asset_code,operation_code,router_sha256,contract_sha256,
         policy_sha256,adapter_sha256,step_sha256,input_governance_sha256,raw_router,
         capsule,raw_bytes,capsule_bytes,created_at,expires_at
    into v_ctx
  from private.lf_router_context_capsules_v3_candidate
  where context_id=p_context_id;

  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_NOT_FOUND');
  end if;
  if clock_timestamp()>=v_ctx.expires_at then
    return jsonb_build_object('status','STALE_CONTEXT_RECOMPILE','reason','CONTEXT_EXPIRED');
  end if;

  if v_ctx.operation_code is not null then
    select coalesce(jsonb_agg(jsonb_build_array(c.contract_code,c.contract_sha) order by c.contract_code),'[]'::jsonb)
      into v_contracts
    from public.lf_operation_contracts c
    where c.operation_code=v_ctx.operation_code
      and c.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');

    select coalesce(jsonb_agg(jsonb_build_array(p.policy_code,p.policy_version,p.policy_sha) order by p.policy_code),'[]'::jsonb)
      into v_policies
    from public.v_lf_operation_policy_snapshot p
    where p.operation_code=v_ctx.operation_code
      and (v_ctx.distribution_mode is null or v_ctx.distribution_mode=any(p.distribution_modes));

    select coalesce(jsonb_agg(jsonb_build_object(
             'adapter_code',x.adapter_code,
             'adapter_version',x.adapter_version,
             'adapter_document_status',x.adapter_document_status,
             'adapter_operational_status',x.adapter_operational_status,
             'target_asset_code',x.target_asset_code,
             'relacion_tipo',x.relacion_tipo,
             'fuente',x.fuente
           ) order by x.adapter_code),'[]'::jsonb)
      into v_adapters
    from public.v_lf_router_adapter_bindings x
    where x.target_asset_code=v_ctx.asset_code;

    select jsonb_build_object(
             'step_id',s.step_id,
             'execution_order',s.execution_order,
             'contract_code',s.contract_code,
             'blocking_code',s.blocking_code,
             'status',s.status,
             'resolver_ref',s.resolver_ref,
             'required_evidence_keys',s.required_evidence_keys,
             'next_if_pass',s.next_if_pass,
             'next_if_blocked',s.next_if_blocked
           )
      into v_step
    from public.lf_operation_step_contracts s
    where s.operation_code=v_ctx.operation_code
      and s.status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')
    order by coalesce(s.execution_order,s.step_order),s.step_id
    limit 1;
  end if;

  v_contract_sha := private.lf_router_context_sha256_v3_candidate(v_contracts);
  v_policy_sha := private.lf_router_context_sha256_v3_candidate(v_policies);
  v_adapter_sha := private.lf_router_context_sha256_v3_candidate(v_adapters);
  v_step_sha := private.lf_router_context_sha256_v3_candidate(coalesce(v_step,'null'::jsonb));

  if v_contract_sha is distinct from v_ctx.contract_sha256
     or v_policy_sha is distinct from v_ctx.policy_sha256
     or v_adapter_sha is distinct from v_ctx.adapter_sha256
     or v_step_sha is distinct from v_ctx.step_sha256 then
    return jsonb_build_object(
      'status','STALE_CONTEXT_RECOMPILE',
      'contract_current',v_contract_sha is not distinct from v_ctx.contract_sha256,
      'policy_current',v_policy_sha is not distinct from v_ctx.policy_sha256,
      'adapter_current',v_adapter_sha is not distinct from v_ctx.adapter_sha256,
      'step_current',v_step_sha is not distinct from v_ctx.step_sha256
    );
  end if;

  return jsonb_build_object(
    'status','CURRENT',
    'context_id',p_context_id,
    'contract_sha256',v_contract_sha,
    'policy_sha256',v_policy_sha,
    'adapter_sha256',v_adapter_sha,
    'step_sha256',v_step_sha
  );
end;
$function$;

create or replace function private.lf_router_context_resolve_handle_v3_candidate(
  p_context_id uuid,
  p_kind text,
  p_known_sha text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_ctx private.lf_router_context_capsules_v3_candidate%rowtype;
  v_kind text := upper(btrim(coalesce(p_kind,'')));
  v_currentness jsonb;
  v_payload jsonb;
  v_sha text;
  v_fresh_raw jsonb;
begin
  if v_kind not in ('CONTRACTS','POLICIES','ADAPTERS','CURRENT_STEP','INPUT_GOVERNANCE') then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3_HANDLE_KIND_NOT_AUTHORIZED';
  end if;

  select context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
         distribution_mode,asset_code,operation_code,router_sha256,contract_sha256,
         policy_sha256,adapter_sha256,step_sha256,input_governance_sha256,raw_router,
         capsule,raw_bytes,capsule_bytes,created_at,expires_at
    into v_ctx
  from private.lf_router_context_capsules_v3_candidate
  where context_id=p_context_id;

  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_NOT_FOUND');
  end if;

  v_currentness := private.lf_router_context_currentness_v3_candidate(p_context_id);
  if v_currentness->>'status'<>'CURRENT' then
    return v_currentness;
  end if;

  case v_kind
    when 'CONTRACTS' then
      v_payload := coalesce(v_ctx.raw_router->'contract_refs','[]'::jsonb);
      v_sha := v_ctx.contract_sha256;
    when 'POLICIES' then
      v_payload := coalesce(v_ctx.raw_router->'policy_refs','[]'::jsonb);
      v_sha := v_ctx.policy_sha256;
    when 'ADAPTERS' then
      v_payload := coalesce(v_ctx.raw_router->'adapters','[]'::jsonb);
      v_sha := v_ctx.adapter_sha256;
    when 'CURRENT_STEP' then
      v_payload := coalesce(v_ctx.raw_router->'next_step','null'::jsonb);
      v_sha := v_ctx.step_sha256;
    when 'INPUT_GOVERNANCE' then
      -- Input Governance is dynamic and may be absent. Re-run ACT-0001 with
      -- the same request/hints (target_hint remains NULL) before hydration.
      v_fresh_raw := public.lf_router_resolve_v1(
        v_ctx.request_text,
        null,
        v_ctx.action_hint,
        v_ctx.asset_type_hint,
        v_ctx.distribution_mode
      );
      if private.lf_router_context_sha256_v3_candidate(v_fresh_raw)
         is distinct from v_ctx.router_sha256 then
        return jsonb_build_object('status','STALE_CONTEXT_RECOMPILE','reason','ROUTER_RESULT_CHANGED');
      end if;
      v_payload := coalesce(v_fresh_raw->'input_governance','null'::jsonb);
      v_sha := case when v_payload='null'::jsonb then null
                    else private.lf_router_context_sha256_v3_candidate(v_payload) end;
  end case;

  if v_sha is null then
    return jsonb_build_object('status','NOT_AVAILABLE','context_id',p_context_id,'kind',v_kind);
  end if;

  if nullif(btrim(coalesce(p_known_sha,'')),'') is not null and p_known_sha=v_sha then
    return jsonb_build_object(
      'status','NOT_MODIFIED',
      'context_id',p_context_id,
      'kind',v_kind,
      'sha256',v_sha
    );
  end if;

  return jsonb_build_object(
    'status','RESOLVED',
    'context_id',p_context_id,
    'kind',v_kind,
    'sha256',v_sha,
    'payload',v_payload
  );
end;
$function$;

create or replace function private.lf_router_context_budget_v3_candidate(p_context_id uuid)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','private'
as $function$
  select jsonb_build_object(
    'status','OBSERVED',
    'context_id',c.context_id,
    'raw_bytes',c.raw_bytes,
    'capsule_bytes',c.capsule_bytes,
    'reduction_pct',round((1-(c.capsule_bytes::numeric/nullif(c.raw_bytes,0)))*100,2),
    'estimated_transport_tokens_4char',ceil(c.capsule_bytes::numeric/4),
    'measurement_note','Token count is an estimate only; actual model tokens require provider/runtime telemetry.',
    'expires_at',c.expires_at
  )
  from private.lf_router_context_capsules_v3_candidate c
  where c.context_id=p_context_id;
$function$;

revoke all on table private.lf_router_context_capsules_v3_candidate from public,anon,authenticated;
revoke all on function private.lf_router_context_sha256_v3_candidate(jsonb) from public,anon,authenticated;
revoke all on function private.lf_router_context_compile_v3_candidate(text,text,text,text,text) from public,anon,authenticated;
revoke all on function private.lf_router_context_currentness_v3_candidate(uuid) from public,anon,authenticated;
revoke all on function private.lf_router_context_resolve_handle_v3_candidate(uuid,text,text) from public,anon,authenticated;
revoke all on function private.lf_router_context_budget_v3_candidate(uuid) from public,anon,authenticated;
