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

comment on function public.lf_router_resolve_v1(text,text,text,text,text) is
  'ACT-0001 canonical Router. READY_TO_EXECUTE now carries downstream_execution_allowed=true explicitly even when no adapter/Input Governance context is present; denied downstream paths remain fail-closed.';
