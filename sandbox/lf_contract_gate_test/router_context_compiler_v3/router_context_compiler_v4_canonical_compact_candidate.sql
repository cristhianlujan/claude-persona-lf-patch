-- ROUTER CONTEXT COMPILER V4 — CANONICAL COMPACT + JIT SANDBOX CANDIDATE
-- Preferred candidate for PR #653. Supersedes V3A/V3B/V3C as consumer contract.
-- Reuses PROMOVIDO v1.0 docs/operations/PROTOCOLO_CONSUMO_COMPACTO_ROUTER_LF.md.
-- Top-level compact output is EXACTLY the promoted eight fields.
-- Handles are additive only inside operation_payload / adapter_payload.
-- Scope: distribution_mode=ROUTER only. target_hint is intentionally absent.

create table if not exists private.lf_router_context_capsules_v4_candidate (
  context_id uuid primary key default gen_random_uuid(),
  execution_id text not null,
  request_text text not null,
  request_sha256 text not null,
  action_hint text not null,
  asset_type_hint text,
  distribution_mode text not null default 'ROUTER',
  router_sha256 text not null,
  raw_router jsonb not null,
  compact_payload jsonb not null,
  handles jsonb not null,
  raw_bytes bigint not null,
  compact_bytes bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '1 hour'),
  check (btrim(execution_id)<>''),
  check (btrim(action_hint)<>''),
  check (distribution_mode='ROUTER'),
  check (raw_bytes>=0 and compact_bytes>=0)
);

create table if not exists private.lf_router_context_hydration_events_v4_candidate (
  id bigint generated always as identity primary key,
  context_id uuid not null,
  execution_id text not null,
  requested_kinds text[] not null,
  result_status text not null,
  router_rechecks integer not null,
  returned_bytes bigint not null,
  measured_ms numeric not null,
  observed_at timestamptz not null default clock_timestamp(),
  check (router_rechecks between 0 and 1),
  check (returned_bytes>=0),
  check (measured_ms>=0)
);

create or replace function private.lf_router_context_sha256_v4_candidate(p_value jsonb)
returns text
language sql
immutable
set search_path to 'pg_catalog','extensions'
as $function$
  select encode(extensions.digest(coalesce(p_value,'null'::jsonb)::text,'sha256'),'hex');
$function$;

create or replace function private.lf_router_context_compile_v4_candidate(
  p_request_text text,
  p_action_hint text,
  p_asset_type_hint text,
  p_execution_id text
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
  v_raw_bytes bigint;
  v_context_id uuid := gen_random_uuid();
  v_contracts jsonb;
  v_policies jsonb;
  v_adapters jsonb;
  v_step jsonb;
  v_ig jsonb;
  v_handles jsonb;
  v_operation_payload jsonb := '{}'::jsonb;
  v_adapter_payload jsonb := '{}'::jsonb;
  v_compact jsonb;
  v_compact_bytes bigint;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V4_EXECUTION_ID_REQUIRED';
  end if;
  if nullif(btrim(coalesce(p_action_hint,'')),'') is null then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V4_ACTION_HINT_REQUIRED';
  end if;

  -- Canonical invocation: action_hint explicit, target_hint omitted, ROUTER only.
  v_raw := public.lf_router_resolve_v1(
    p_request_text => p_request_text,
    p_action_hint => p_action_hint,
    p_asset_type_hint => p_asset_type_hint,
    p_distribution_mode => 'ROUTER'
  );

  v_status := coalesce(v_raw->>'status','BLOCKED');
  v_router_sha := private.lf_router_context_sha256_v4_candidate(v_raw);
  v_raw_bytes := octet_length(v_raw::text);

  -- Promoted protocol exception: consume RAW for blocks.
  if v_status='BLOCKED' then
    return v_raw;
  end if;

  v_asset_code := coalesce(v_raw->>'asset_code',v_raw#>>'{asset,codigo_activo}');
  v_asset_type := coalesce(v_raw->>'asset_type',v_raw#>>'{asset,tipo_activo}');
  v_operation_code := nullif(v_raw->>'operation_code','');
  v_contracts := coalesce(v_raw->'contract_refs','[]'::jsonb);
  v_policies := coalesce(v_raw->'policy_refs','[]'::jsonb);
  v_adapters := coalesce(v_raw->'adapters','[]'::jsonb);
  v_step := coalesce(v_raw->'next_step','null'::jsonb);
  v_ig := coalesce(v_raw->'input_governance','null'::jsonb);

  v_handles := jsonb_strip_nulls(jsonb_build_object(
    'contracts',case when jsonb_typeof(v_contracts)='array' and jsonb_array_length(v_contracts)>0
      then private.lf_router_context_sha256_v4_candidate(v_contracts) end,
    'policies',case when jsonb_typeof(v_policies)='array' and jsonb_array_length(v_policies)>0
      then private.lf_router_context_sha256_v4_candidate(v_policies) end,
    'adapters',case when jsonb_typeof(v_adapters)='array' and jsonb_array_length(v_adapters)>0
      then private.lf_router_context_sha256_v4_candidate(v_adapters) end,
    'current_step',case when v_step<>'null'::jsonb
      then private.lf_router_context_sha256_v4_candidate(v_step) end,
    'input_governance',case when v_ig<>'null'::jsonb
      then private.lf_router_context_sha256_v4_candidate(v_ig) end
  ));

  if v_operation_code is not null then
    v_operation_payload := jsonb_build_object(
      v_operation_code,
      jsonb_strip_nulls(jsonb_build_object(
        'operation_status',v_raw->>'operation_status',
        'step_count',v_raw->'step_count',
        'distribution_mode','ROUTER',
        -- Server-side context store is populated before this payload is emitted,
        -- therefore heavy blocks are cache-resident and omitted from transport.
        'cache_hit',true,
        'context_id',v_context_id,
        'router_sha256',v_router_sha,
        'retrieval_handles',jsonb_strip_nulls(jsonb_build_object(
          'steps',v_handles->'current_step',
          'contracts',v_handles->'contracts',
          'policies',v_handles->'policies',
          'input_governance',v_handles->'input_governance'
        )),
        'downstream_execution_allowed',case when v_raw ? 'downstream_execution_allowed'
          then v_raw->'downstream_execution_allowed' end
      ))
    );
  end if;

  if v_asset_code is not null then
    v_adapter_payload := jsonb_build_object(
      v_asset_code,
      jsonb_strip_nulls(jsonb_build_object(
        'cache_hit',true,
        'context_id',v_context_id,
        'retrieval_handles',jsonb_strip_nulls(jsonb_build_object(
          'adapters',v_handles->'adapters'
        ))
      ))
    );
  end if;

  -- EXACT eight promoted top-level fields; do not add metadata here.
  v_compact := jsonb_build_object(
    'status',v_status,
    'blocking_code',nullif(v_raw->>'blocking_code',''),
    'asset_code',v_asset_code,
    'asset_type',v_asset_type,
    'action_code',v_raw->>'action_code',
    'operation_code',v_operation_code,
    'operation_payload',v_operation_payload,
    'adapter_payload',v_adapter_payload
  );
  v_compact_bytes := octet_length(v_compact::text);

  -- Promoted protocol exception: compact only when it actually saves bytes.
  if v_compact_bytes>=v_raw_bytes then
    return v_raw;
  end if;

  insert into private.lf_router_context_capsules_v4_candidate(
    context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
    distribution_mode,router_sha256,raw_router,compact_payload,handles,raw_bytes,compact_bytes
  ) values (
    v_context_id,p_execution_id,p_request_text,
    encode(extensions.digest(coalesce(p_request_text,''),'sha256'),'hex'),
    upper(btrim(p_action_hint)),upper(nullif(btrim(coalesce(p_asset_type_hint,'')),'')),
    'ROUTER',v_router_sha,v_raw,v_compact,v_handles,v_raw_bytes,v_compact_bytes
  );

  return v_compact;
end;
$function$;

create or replace function private.lf_router_context_hydrate_v4_candidate(
  p_context_id uuid,
  p_execution_id text,
  p_kinds text[],
  p_known_shas jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_started timestamptz := clock_timestamp();
  v_ctx private.lf_router_context_capsules_v4_candidate%rowtype;
  v_fresh jsonb;
  v_fresh_sha text;
  v_kind text;
  v_payload jsonb;
  v_sha text;
  v_known text;
  v_items jsonb := '{}'::jsonb;
  v_response jsonb;
  v_status text := 'RESOLVED';
  v_rechecks integer := 0;
  v_ms numeric;
  v_bytes bigint;
begin
  if coalesce(array_length(p_kinds,1),0)=0 or array_length(p_kinds,1)>5 then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V4_HANDLE_BATCH_SIZE_INVALID';
  end if;
  if exists (
    select 1 from unnest(p_kinds) as k
    where upper(btrim(k)) not in ('CONTRACTS','POLICIES','ADAPTERS','CURRENT_STEP','INPUT_GOVERNANCE')
  ) then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V4_HANDLE_KIND_NOT_AUTHORIZED';
  end if;
  if (select count(*) from unnest(p_kinds)) <>
     (select count(distinct upper(btrim(k))) from unnest(p_kinds) as k) then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V4_DUPLICATE_HANDLE_KIND';
  end if;

  select context_id,execution_id,request_text,request_sha256,action_hint,asset_type_hint,
         distribution_mode,router_sha256,raw_router,compact_payload,handles,raw_bytes,
         compact_bytes,created_at,expires_at
    into v_ctx
  from private.lf_router_context_capsules_v4_candidate
  where context_id=p_context_id;

  if not found then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_NOT_FOUND');
  end if;
  if v_ctx.execution_id is distinct from p_execution_id then
    return jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_CONTEXT_EXECUTION_MISMATCH');
  end if;
  if clock_timestamp()>=v_ctx.expires_at then
    v_status := 'STALE_CONTEXT_RECOMPILE';
    v_response := jsonb_build_object('status',v_status,'reason','CONTEXT_EXPIRED');
  else
    -- One full Router currentness oracle for the entire requested batch.
    v_fresh := public.lf_router_resolve_v1(
      p_request_text => v_ctx.request_text,
      p_action_hint => v_ctx.action_hint,
      p_asset_type_hint => v_ctx.asset_type_hint,
      p_distribution_mode => 'ROUTER'
    );
    v_rechecks := 1;
    v_fresh_sha := private.lf_router_context_sha256_v4_candidate(v_fresh);

    if v_fresh_sha is distinct from v_ctx.router_sha256 then
      v_status := 'STALE_CONTEXT_RECOMPILE';
      v_response := jsonb_build_object(
        'status',v_status,
        'reason','ROUTER_RESULT_CHANGED',
        'stored_router_sha256',v_ctx.router_sha256,
        'fresh_router_sha256',v_fresh_sha
      );
    else
      foreach v_kind in array p_kinds loop
        v_kind := upper(btrim(v_kind));
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
          v_items := v_items || jsonb_build_object(lower(v_kind),jsonb_build_object('status','NOT_AVAILABLE'));
        elsif private.lf_router_context_sha256_v4_candidate(v_payload) is distinct from v_sha then
          v_status := 'BLOCKED';
          v_response := jsonb_build_object(
            'status','BLOCKED','blocking_code','BLOCK_CONTEXT_HANDLE_DIGEST_MISMATCH','kind',v_kind
          );
          exit;
        else
          v_known := nullif(btrim(coalesce(p_known_shas->>lower(v_kind),'')), '');
          if v_known=v_sha then
            v_items := v_items || jsonb_build_object(lower(v_kind),jsonb_build_object(
              'status','NOT_MODIFIED','sha256',v_sha
            ));
          else
            v_items := v_items || jsonb_build_object(lower(v_kind),jsonb_build_object(
              'status','RESOLVED','sha256',v_sha,'payload',v_payload
            ));
          end if;
        end if;
      end loop;

      if v_response is null then
        v_response := jsonb_build_object(
          'status','RESOLVED',
          'context_id',p_context_id,
          'router_sha256',v_fresh_sha,
          'router_rechecks',v_rechecks,
          'items',v_items
        );
      end if;
    end if;
  end if;

  v_ms := greatest(0,extract(epoch from (clock_timestamp()-v_started))*1000);
  v_bytes := octet_length(v_response::text);
  insert into private.lf_router_context_hydration_events_v4_candidate(
    context_id,execution_id,requested_kinds,result_status,router_rechecks,returned_bytes,measured_ms
  ) values (
    p_context_id,p_execution_id,
    array(select upper(btrim(k)) from unnest(p_kinds) as k),
    v_status,v_rechecks,v_bytes,v_ms
  );

  return v_response;
end;
$function$;

create or replace function private.lf_router_context_observability_v4_candidate(
  p_context_id uuid,
  p_execution_id text
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','private'
as $function$
  with c as (
    select context_id,execution_id,raw_bytes,compact_bytes,expires_at
    from private.lf_router_context_capsules_v4_candidate
    where context_id=p_context_id and execution_id=p_execution_id
  ), h as (
    select count(*)::bigint as hydration_calls,
           coalesce(sum(router_rechecks),0)::bigint as router_rechecks,
           coalesce(sum(returned_bytes),0)::bigint as hydration_returned_bytes,
           coalesce(sum(measured_ms),0)::numeric as hydration_total_ms,
           coalesce(max(measured_ms),0)::numeric as hydration_max_ms
    from private.lf_router_context_hydration_events_v4_candidate
    where context_id=p_context_id and execution_id=p_execution_id
  )
  select jsonb_build_object(
    'status','OBSERVED',
    'context_id',c.context_id,
    'raw_bytes',c.raw_bytes,
    'effective_bytes',c.compact_bytes,
    'ahorro_real_pct',round(((c.raw_bytes-c.compact_bytes)::numeric/nullif(c.raw_bytes,0))*100,2),
    'hydration_calls',h.hydration_calls,
    'router_rechecks',h.router_rechecks,
    'hydration_returned_bytes',h.hydration_returned_bytes,
    'hydration_total_ms',round(h.hydration_total_ms,3),
    'hydration_max_ms',round(h.hydration_max_ms,3),
    'actual_model_tokens','NOT_OBSERVED',
    'client_network_latency','NOT_OBSERVED',
    'expires_at',c.expires_at
  )
  from c cross join h;
$function$;

revoke all on table private.lf_router_context_capsules_v4_candidate from public,anon,authenticated;
revoke all on table private.lf_router_context_hydration_events_v4_candidate from public,anon,authenticated;
revoke all on function private.lf_router_context_sha256_v4_candidate(jsonb) from public,anon,authenticated;
revoke all on function private.lf_router_context_compile_v4_candidate(text,text,text,text) from public,anon,authenticated;
revoke all on function private.lf_router_context_hydrate_v4_candidate(uuid,text,text[],jsonb) from public,anon,authenticated;
revoke all on function private.lf_router_context_observability_v4_candidate(uuid,text) from public,anon,authenticated;
