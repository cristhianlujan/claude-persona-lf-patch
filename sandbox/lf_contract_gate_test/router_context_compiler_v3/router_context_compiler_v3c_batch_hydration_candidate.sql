-- ROUTER CONTEXT COMPILER V3C — BATCH HYDRATION CANDIDATE
-- Depends on router_context_compiler_v3b_candidate.sql.
-- V3C is the preferred sandbox consumer path: one canonical Router currentness
-- recheck per hydration batch, never one recheck per handle.

create table if not exists private.lf_router_context_hydration_events_v3c_candidate (
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

create or replace function private.lf_router_context_hydrate_v3c_candidate(
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
  v_ctx private.lf_router_context_capsules_v3b_candidate%rowtype;
  v_fresh jsonb;
  v_fresh_sha text;
  v_kind text;
  v_payload jsonb;
  v_sha text;
  v_known text;
  v_items jsonb := '{}'::jsonb;
  v_response jsonb;
  v_status text := 'RESOLVED';
  v_ms numeric;
  v_bytes bigint;
begin
  if coalesce(array_length(p_kinds,1),0)=0 or array_length(p_kinds,1)>5 then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3C_HANDLE_BATCH_SIZE_INVALID';
  end if;
  if exists (
    select 1 from unnest(p_kinds) as k
    where upper(btrim(k)) not in ('CONTRACTS','POLICIES','ADAPTERS','CURRENT_STEP','INPUT_GOVERNANCE')
  ) then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3C_HANDLE_KIND_NOT_AUTHORIZED';
  end if;
  if (select count(*) from unnest(p_kinds)) <>
     (select count(distinct upper(btrim(k))) from unnest(p_kinds) as k) then
    raise exception using errcode='22023', message='ROUTER_CONTEXT_V3C_DUPLICATE_HANDLE_KIND';
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
  if clock_timestamp()>=v_ctx.expires_at then
    v_status := 'STALE_CONTEXT_RECOMPILE';
    v_response := jsonb_build_object('status',v_status,'reason','CONTEXT_EXPIRED');
  else
    -- Exactly one Router call validates all requested handles in this batch.
    v_fresh := public.lf_router_resolve_v1(
      v_ctx.request_text,
      null,
      v_ctx.action_hint,
      v_ctx.asset_type_hint,
      v_ctx.distribution_mode
    );
    v_fresh_sha := private.lf_router_context_sha256_v3b_candidate(v_fresh);

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
        else
          if private.lf_router_context_sha256_v3b_candidate(v_payload) is distinct from v_sha then
            v_status := 'BLOCKED';
            v_response := jsonb_build_object(
              'status','BLOCKED',
              'blocking_code','BLOCK_CONTEXT_HANDLE_DIGEST_MISMATCH',
              'kind',v_kind
            );
            exit;
          end if;

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
          'execution_id',p_execution_id,
          'router_sha256',v_fresh_sha,
          'router_rechecks',1,
          'items',v_items
        );
      end if;
    end if;
  end if;

  v_ms := greatest(0,extract(epoch from (clock_timestamp()-v_started))*1000);
  v_bytes := octet_length(v_response::text);
  insert into private.lf_router_context_hydration_events_v3c_candidate(
    context_id,execution_id,requested_kinds,result_status,router_rechecks,returned_bytes,measured_ms
  ) values (
    p_context_id,p_execution_id,
    array(select upper(btrim(k)) from unnest(p_kinds) as k),
    v_status,
    case when v_status='STALE_CONTEXT_RECOMPILE' and v_response->>'reason'='CONTEXT_EXPIRED' then 0 else 1 end,
    v_bytes,v_ms
  );

  return v_response;
end;
$function$;

create or replace function private.lf_router_context_observability_v3c_candidate(
  p_context_id uuid,
  p_execution_id text
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','private'
as $function$
  with c as (
    select context_id,execution_id,raw_bytes,capsule_bytes,expires_at
    from private.lf_router_context_capsules_v3b_candidate
    where context_id=p_context_id and execution_id=p_execution_id
  ), h as (
    select count(*)::bigint as hydration_calls,
           coalesce(sum(router_rechecks),0)::bigint as router_rechecks,
           coalesce(sum(returned_bytes),0)::bigint as hydration_returned_bytes,
           coalesce(sum(measured_ms),0)::numeric as hydration_total_ms,
           coalesce(max(measured_ms),0)::numeric as hydration_max_ms
    from private.lf_router_context_hydration_events_v3c_candidate
    where context_id=p_context_id and execution_id=p_execution_id
  )
  select jsonb_build_object(
    'status','OBSERVED',
    'context_id',c.context_id,
    'compile_raw_bytes',c.raw_bytes,
    'compile_capsule_bytes',c.capsule_bytes,
    'compile_reduction_pct',round((1-(c.capsule_bytes::numeric/nullif(c.raw_bytes,0)))*100,2),
    'hydration_calls',h.hydration_calls,
    'router_rechecks',h.router_rechecks,
    'hydration_returned_bytes',h.hydration_returned_bytes,
    'hydration_total_ms',round(h.hydration_total_ms,3),
    'hydration_max_ms',round(h.hydration_max_ms,3),
    'n_plus_one_currentness',case when h.hydration_calls>0 and h.router_rechecks>h.hydration_calls then true else false end,
    'actual_model_tokens','NOT_OBSERVED',
    'client_network_latency','NOT_OBSERVED',
    'expires_at',c.expires_at
  )
  from c cross join h;
$function$;

revoke all on table private.lf_router_context_hydration_events_v3c_candidate from public,anon,authenticated;
revoke all on function private.lf_router_context_hydrate_v3c_candidate(uuid,text,text[],jsonb) from public,anon,authenticated;
revoke all on function private.lf_router_context_observability_v3c_candidate(uuid,text) from public,anon,authenticated;
