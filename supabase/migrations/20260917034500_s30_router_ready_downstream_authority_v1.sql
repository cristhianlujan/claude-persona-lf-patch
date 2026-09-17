-- S30 / adapterless Profile Runtime authority repair.
-- Source-first only. This migration is not authorized for live apply by this commit.
--
-- Root cause:
-- public.lf_router_resolve_v1 emitted downstream_execution_allowed=true only when
-- v_input_governance was non-null. Adapterless profiles can legitimately reach
-- READY_TO_EXECUTE with v_input_governance=NULL, while the canonical Profile
-- Runtime enqueue requires downstream_execution_allowed=true. The result was a
-- false fail-closed at the consumer boundary even though the Router had already
-- authorized execution.
--
-- Contract after this patch:
--   READY_TO_EXECUTE => downstream_execution_allowed=true (explicit, unconditional)
--   BLOCKED          => downstream_execution_allowed=false where downstream is denied
-- Input Governance remains additive context; it no longer owns the downstream
-- authority bit for successful Router responses.
--
-- Regression matrix enforced in this migration after the source rewrite:
--   P1 adapterless READY: downstream authority lives in the base READY object.
--   P2 adapter READY:     Input Governance remains additive and authority stays true.
--   N1 profile blocked:   profile runtime-state denials still return false.
--   N2 governance block:  adapter/Input Governance denials still return false.
--   N3 consumer strict:   canonical enqueue consumers still require explicit true.

do $$
declare
  v_def text;
  v_old text := E'    ''composition_order'',jsonb_build_array(''SHELL'',''PROFILE'',''ADAPTER'',''POLICY_AND_CONTRACT_GATES'')\n  ) || case when v_input_governance is null then ''{}''::jsonb else jsonb_build_object(''input_governance'',v_input_governance,''downstream_execution_allowed'',true) end;';
  v_new text := E'    ''composition_order'',jsonb_build_array(''SHELL'',''PROFILE'',''ADAPTER'',''POLICY_AND_CONTRACT_GATES''),\n    ''downstream_execution_allowed'',true\n  ) || case when v_input_governance is null then ''{}''::jsonb else jsonb_build_object(''input_governance'',v_input_governance) end;';
  v_matches integer;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_def;

  -- Idempotent source replay: if the exact repaired tail is already present,
  -- do not touch the function again.
  if position(v_new in v_def) > 0 then
    return;
  end if;

  v_matches := (length(v_def) - length(replace(v_def,v_old,''))) / nullif(length(v_old),0);
  if coalesce(v_matches,0) <> 1 then
    raise exception 'S30_ROUTER_DOWNSTREAM_AUTHORITY_ANCHOR_NOT_UNIQUE matches=%',coalesce(v_matches,0);
  end if;

  v_def := replace(v_def,v_old,v_new);
  execute v_def;

  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_def;

  if position(v_new in v_def) = 0
     or position(v_old in v_def) > 0 then
    raise exception 'S30_ROUTER_DOWNSTREAM_AUTHORITY_POSTCONDITION_FAILED';
  end if;
end;
$$;

-- Source-bound regression guard. These assertions execute wherever the migration
-- is applied (CI disposable DB first; live only after separate authorization).
do $$
declare
  v_router text;
  v_enqueue text;
  v_noncanonical_enqueue text;
  v_false_count integer;
  v_false_token text := E'''downstream_execution_allowed'',false';
  v_strict_consumer text := E'coalesce((v_route->>''downstream_execution_allowed'')::boolean,false) is not true';
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
    into v_router;
  select pg_get_functiondef('programacion.fn_lf_profile_runtime_enqueue_text_v1(text,text,text,text)'::regprocedure)
    into v_enqueue;
  select pg_get_functiondef('programacion.fn_lf_profile_runtime_enqueue_noncanonical_artifact_set_v1(text,text,jsonb,text,text)'::regprocedure)
    into v_noncanonical_enqueue;

  -- P1/P2: successful Router authority is explicit before the optional
  -- Input Governance extension, so both adapterless and adapter-backed READY
  -- results carry the same downstream decision.
  if position(E'''downstream_execution_allowed'',true\n  ) || case when v_input_governance is null then ''{}''::jsonb else jsonb_build_object(''input_governance'',v_input_governance) end;' in v_router) = 0 then
    raise exception 'S30_ROUTER_DOWNSTREAM_AUTHORITY_POSITIVE_REGRESSION';
  end if;

  -- N1/N2: do not weaken fail-closed Router branches.
  if position('BLOCK_PROFILE_STATE_INCOMPLETE' in v_router) = 0
     or position('BLOCK_PROFILE_RUNTIME_STATE_NOT_AUTHORIZED' in v_router) = 0
     or position('BLOCK_ADAPTER_RUNTIME_NOT_AUTHORIZED' in v_router) = 0
     or position('BLOCK_INPUT_GOVERNANCE_RESOLUTION_INVALID' in v_router) = 0 then
    raise exception 'S30_ROUTER_DOWNSTREAM_AUTHORITY_NEGATIVE_BRANCH_MISSING';
  end if;

  v_false_count := (length(v_router) - length(replace(v_router,v_false_token,''))) / nullif(length(v_false_token),0);
  if coalesce(v_false_count,0) < 4 then
    raise exception 'S30_ROUTER_DOWNSTREAM_AUTHORITY_NEGATIVE_FALSE_COUNT count=%',coalesce(v_false_count,0);
  end if;

  -- N3: keep both runtime consumers strict. Missing/false authority remains a
  -- consumer-side fail-closed condition; the producer is what was repaired.
  if position(v_strict_consumer in v_enqueue) = 0
     or position('PROFILE_RUNTIME_ROUTER_NOT_READY' in v_enqueue) = 0
     or position(v_strict_consumer in v_noncanonical_enqueue) = 0
     or position('PROFILE_RUNTIME_ROUTER_NOT_READY' in v_noncanonical_enqueue) = 0 then
    raise exception 'S30_PROFILE_RUNTIME_CONSUMER_STRICTNESS_REGRESSION';
  end if;
end;
$$;

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
  'ACT-0001 canonical Router. READY_TO_EXECUTE now carries downstream_execution_allowed=true explicitly even when no adapter/Input Governance context is present; denied downstream paths remain fail-closed.';
