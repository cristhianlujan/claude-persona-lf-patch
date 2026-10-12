-- ROUTER CONTEXT COMPILER V3B — SANDBOX CANDIDATE ONLY
-- Supersedes V3A in this PR for currentness semantics.
-- Owner: TRANSVERSAL_ROUTER_CONTEXT_ADMISSION.
-- No production promotion. The canonical Router remains public.lf_router_resolve_v1.
-- Core invariant: never reconstruct Router semantics locally for currentness.

create table if not exists private.lf_router_context_capsules_v3b_candidate (
  context_id uuid primary key default gen_random_uuid(),
  execution_id text not null,
  request_text text not null,
  request_sha256 text not null,
  action_hint text,
  asset_type_hint text,
  distribution_mode text not null,
  router_sha256 text not null,
  raw_router jsonb not null,
  capsule jsonb not null,
  handles jsonb not null,
  raw_bytes bigint not null,
  capsule_bytes bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '1 hour'),
  check (btrim(execution_id)<>''),
  check (distribution_mode in ('ROUTER','DIRECT')),
  check (raw_bytes>=0 and capsule_bytes>=0)
);

comment on table private.lf_router_context_capsules_v3b_candidate is
'Sandbox candidate: full Router result stays server-side; LLM transport is a compact capsule plus execution-bound JIT handles.';

create or replace function private.lf_router_context_sha256_v3b_candidate(p_value jsonb)
returns text
language sql
immutable
set search_path to 'pg_catalog','extensions'
as $function$
  select encode(extensions.digest(coalesce(p_value,'null'::jsonb)::text,'sha256'),'hex');
$function$;

create or replace function private.lf_router_context_compile_v3b_candidate(
  p_request_text text,
  p_action_hint text,
  p_asset_type_hint text,
  p_distribution_mode text,
  p_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $function$
declare
  v_mode text := upper(coalesce(nullif(btrim(p_distribution_mode),''),'ROUTER'));
  v_raw jsonb;
  v_status text;
  v_router_sha text;
  v_raw_bytes bigint;
  v_context_id uuid := gen_random_uuid();
  v_contracts jsonb;
  v_policies jsonb;
  v_adapters jsonb;
  v_step jsonb;
  v_ig jsonb;
  v_handles jsonb;
  v_capsule jsonb;
  v_capsule_bytes bigint;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3B_EXECUTION_ID_REQUIRED';
  end if;
  if v_mode not in ('ROUTER','DIRECT') then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3B_DISTRIBUTION_MODE_INVALID';
  end if;

  -- Router-first remains intact. target_hint is intentionally NULL so ACT-0001
  -- performs discovery; compiler callers cannot bypass that with a target pin.
  v_raw := public.lf_router_resolve_v1(
    p_request_text,
    null,
    p_action_hint,
    p_asset_type_hint,
    v_mode
  );

  v_status := coalesce(v_raw->>'status','BLOCKED');
  v_router_sha := private.lf_router_context_sha256_v3b_candidate(v_raw);
  v_raw_bytes := octet_length(v_raw::text);

  if v_status='BLOCKED' then
    return jsonb_build_object(
      'context_contract','LF_ROUTER_CONTEXT_V3B_CANDIDATE',
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
  v_ig := coalesce(v_raw->'input_governance','null'::jsonb);

  v_handles := jsonb_strip_nulls(jsonb_build_object(
    'contracts',case when jsonb_typeof(v_contracts)='array' and jsonb_array_length(v_contracts)>0
      then private.lf_router_context_sha256_v3b_candidate(v_contracts) end,
    'policies',case when jsonb_typeof(v_policies)='array' and jsonb_array_length(v_policies)>0
      then private.lf_router_context_sha256_v3b_candidate(v_policies) end,
    'adapters',case when jsonb_typeof(v_adapters)='array' and jsonb_array_length(v_adapters)>0
      then private.lf_router_context_sha256_v3b_candidate(v_adapters) end,
    'current_step',case when v_step<>'null'::jsonb
      then private.lf_router_context_sha256_v3b_candidate(v_step) end,
    'input_governance',case when v_ig<>'null'::jsonb
      then private.lf_router_context_sha256_v3b_candidate(v_ig) end
  ));

  v_capsule := jsonb_strip_nulls(jsonb_build_object(
    'context_contract','LF_ROUTER_CONTEXT_V3B_CANDIDATE',
    'context_id',v_context_id,
    'status',v_status,
    'router',v_raw->>'router',
    'source',v_raw->>'source',
    'asset',jsonb_build_object(
      'code',coalesce(v_raw#>>'{asset,codigo_activo}',v_raw->>'asset_code'),
      'type',coalesce(v_raw#>>'{asset,tipo_activo}',v_raw->>'asset_type')
    ),
    'action',v_raw->>'action_code',
    'operation',case when nullif(v_raw->>'operation_code','') is null then null
      else jsonb_build_object('code',v_raw->>'operation_code','status',v_raw->>'operation_status') end,
    'blocking_code',nullif(v_raw->>'blocking_code',''),
    'downstream_allowed',case when v_raw ? 'downstream_execution_allowed'
      then v_raw->'downstream_execution_allowed' end,
    'handles',v_handles,
    'router_sha256',v_router_sha
  ));
  v_capsule_bytes := octet_length(v_capsule::text);

  if v_capsule_bytes>=v_raw_bytes then
    return jsonb_build_object(
      'context_contract','LF_ROUTER_CONTEXT_V3B_CANDIDATE',
      'transport_mode','RAW_NO_SAVINGS',
      'router_sha256',v_router_sha,
      'raw_bytes',v_raw_bytes,
      'capsule_bytes',v_raw_bytes,
      'payload',v_raw
    );
  end if;

  insert into private.lf_router_context_capsules_v3b_candidate(
    context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
    distribution_mode,router_sha256,raw_router,capsule,handles,raw_bytes,capsule_bytes
  ) values (
    v_context_id,p_execution_id,p_request_text,
    encode(extensions.digest(coalesce(p_request_text,''),'sha256'),'hex'),
    p_action_hint,p_asset_type_hint,v_mode,v_router_sha,v_raw,v_capsule,v_handles,
    v_raw_bytes,v_capsule_bytes
  );

  return jsonb_build_object(
    'context_contract','LF_ROUTER_CONTEXT_V3B_CANDIDATE',
    'transport_mode','HANDLE_V3',
    'raw_bytes',v_raw_bytes,
    'capsule_bytes',v_capsule_bytes,
    'reduction_pct',round((1-(v_capsule_bytes::numeric/nullif(v_raw_bytes,0)))*100,2),
    'capsule',v_capsule
  );
end;
$function$;

create or replace function private.lf_router_context_currentness_v3b_candidate(
  p_context_id uuid,
  p_execution_id text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_ctx private.lf_router_context_capsules_v3b_candidate%rowtype;
  v_fresh jsonb;
  v_fresh_sha text;
begin
  select context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
         distribution_mode,router_sha256,raw_router,capsule,handles,raw_bytes,capsule_bytes,
         created_at,expires_at
    into v_ctx
  from private.lf_router_context_capsules_v3b_candidate
  where context_id=p_context_id;

  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_NOT_FOUND');
  end if;
  if v_ctx.execution_id is distinct from p_execution_id then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_EXECUTION_MISMATCH');
  end if;
  if clock_timestamp()>=v_ctx.expires_at then
    return jsonb_build_object('status','STALE_CONTEXT_RECOMPILE','reason','CONTEXT_EXPIRED');
  end if;

  -- Do not duplicate/reconstruct policy, adapter, contract or step rules here.
  -- Reuse the canonical Router as the single currentness oracle.
  v_fresh := public.lf_router_resolve_v1(
    v_ctx.request_text,
    null,
    v_ctx.action_hint,
    v_ctx.asset_type_hint,
    v_ctx.distribution_mode
  );
  v_fresh_sha := private.lf_router_context_sha256_v3b_candidate(v_fresh);

  if v_fresh_sha is distinct from v_ctx.router_sha256 then
    return jsonb_build_object(
      'status','STALE_CONTEXT_RECOMPILE',
      'reason','ROUTER_RESULT_CHANGED',
      'stored_router_sha256',v_ctx.router_sha256,
      'fresh_router_sha256',v_fresh_sha
    );
  end if;

  return jsonb_build_object(
    'status','CURRENT',
    'context_id',p_context_id,
    'execution_id',p_execution_id,
    'router_sha256',v_fresh_sha
  );
end;
$function$;

create or replace function private.lf_router_context_resolve_handle_v3b_candidate(
  p_context_id uuid,
  p_execution_id text,
  p_kind text,
  p_known_sha text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_ctx private.lf_router_context_capsules_v3b_candidate%rowtype;
  v_kind text := upper(btrim(coalesce(p_kind,'')));
  v_current jsonb;
  v_payload jsonb;
  v_sha text;
begin
  if v_kind not in ('CONTRACTS','POLICIES','ADAPTERS','CURRENT_STEP','INPUT_GOVERNANCE') then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3B_HANDLE_KIND_NOT_AUTHORIZED';
  end if;

  select context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
         distribution_mode,router_sha256,raw_router,capsule,handles,raw_bytes,capsule_bytes,
         created_at,expires_at
    into v_ctx
  from private.lf_router_context_capsules_v3b_candidate
  where context_id=p_context_id;

  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_NOT_FOUND');
  end if;
  if v_ctx.execution_id is distinct from p_execution_id then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_EXECUTION_MISMATCH');
  end if;

  v_current := private.lf_router_context_currentness_v3b_candidate(p_context_id,p_execution_id);
  if v_current->>'status'<>'CURRENT' then
    return v_current;
  end if;

  case v_kind
    when 'CONTRACTS' then
      v_payload := coalesce(v_ctx.raw_router->'contract_refs','[]'::jsonb);
      v_sha := v_ctx.handles->>'contracts';
    when 'POLICIES' then
      v_payload := coalesce(v_ctx.raw_router->'policy_refs','[]'::jsonb);
      v_sha := v_ctx.handles->>'policies';
    when 'ADAPTERS' then
      v_payload := coalesce(v_ctx.raw_router->'adapters','[]'::jsonb);
      v_sha := v_ctx.handles->>'adapters';
    when 'CURRENT_STEP' then
      v_payload := coalesce(v_ctx.raw_router->'next_step','null'::jsonb);
      v_sha := v_ctx.handles->>'current_step';
    when 'INPUT_GOVERNANCE' then
      v_payload := coalesce(v_ctx.raw_router->'input_governance','null'::jsonb);
      v_sha := v_ctx.handles->>'input_governance';
  end case;

  if nullif(v_sha,'') is null then
    return jsonb_build_object('status','NOT_AVAILABLE','context_id',p_context_id,'kind',v_kind);
  end if;

  if private.lf_router_context_sha256_v3b_candidate(v_payload) is distinct from v_sha then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_HANDLE_DIGEST_MISMATCH','kind',v_kind);
  end if;

  if nullif(btrim(coalesce(p_known_sha,'')),'') is not null and p_known_sha=v_sha then
    return jsonb_build_object('status','NOT_MODIFIED','context_id',p_context_id,'kind',v_kind,'sha256',v_sha);
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

create or replace function private.lf_router_context_budget_v3b_candidate(
  p_context_id uuid,
  p_execution_id text
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','private'
as $function$
  select case
    when c.execution_id is distinct from p_execution_id then
      jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_EXECUTION_MISMATCH')
    else jsonb_build_object(
      'status','OBSERVED',
      'context_id',c.context_id,
      'raw_bytes',c.raw_bytes,
      'capsule_bytes',c.capsule_bytes,
      'reduction_pct',round((1-(c.capsule_bytes::numeric/nullif(c.raw_bytes,0)))*100,2),
      'estimated_transport_tokens_4char',ceil(c.capsule_bytes::numeric/4),
      'actual_model_tokens','NOT_OBSERVED',
      'client_network_latency','NOT_OBSERVED',
      'measurement_note','4-char token value is an estimate only; actual provider telemetry is required for token claims.',
      'expires_at',c.expires_at
    ) end
  from private.lf_router_context_capsules_v3b_candidate c
  where c.context_id=p_context_id;
$function$;

revoke all on table private.lf_router_context_capsules_v3b_candidate from public,anon,authenticated;
revoke all on function private.lf_router_context_sha256_v3b_candidate(jsonb) from public,anon,authenticated;
revoke all on function private.lf_router_context_compile_v3b_candidate(text,text,text,text,text) from public,anon,authenticated;
revoke all on function private.lf_router_context_currentness_v3b_candidate(uuid,text) from public,anon,authenticated;
revoke all on function private.lf_router_context_resolve_handle_v3b_candidate(uuid,text,text,text) from public,anon,authenticated;
revoke all on function private.lf_router_context_budget_v3b_candidate(uuid,text) from public,anon,authenticated;
