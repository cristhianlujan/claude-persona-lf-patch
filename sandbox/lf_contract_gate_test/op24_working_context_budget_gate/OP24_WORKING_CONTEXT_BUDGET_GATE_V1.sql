-- OP24 Working Context Budget Gate V1 — sandbox candidate only.
-- No runtime activation. No production authorization. No model call.

create or replace function private.sbx_fn_lf_working_context_budget_gate_v1(
  p_execution_id text,
  p_budget_limit bigint,
  p_max_age interval default interval '1 hour'
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private'
as $function$
declare
  v_event private.lf_context_budget_events_v2%rowtype;
  v_now timestamptz := clock_timestamp();
  v_reason text;
  v_authorized boolean := false;
begin
  if p_execution_id is null or btrim(p_execution_id) = '' then
    return jsonb_build_object(
      'authorized', false,
      'reason', 'EXECUTION_ID_REQUIRED',
      'model_call_authorized', false
    );
  end if;

  if p_budget_limit is null or p_budget_limit < 0 then
    return jsonb_build_object(
      'authorized', false,
      'reason', 'VALID_BUDGET_LIMIT_REQUIRED',
      'model_call_authorized', false
    );
  end if;

  if p_max_age is null or p_max_age <= interval '0 seconds' then
    return jsonb_build_object(
      'authorized', false,
      'reason', 'VALID_MAX_AGE_REQUIRED',
      'model_call_authorized', false
    );
  end if;

  select e.*
    into v_event
  from private.lf_context_budget_events_v2 e
  where e.execution_id = p_execution_id
  order by e.recorded_at desc, e.id desc
  limit 1;

  if not found then
    v_reason := 'BUDGET_NOT_OBSERVED';
  elsif v_event.recorded_at > v_now + interval '5 minutes' then
    v_reason := 'BUDGET_EVENT_FROM_FUTURE';
  elsif v_now - v_event.recorded_at > p_max_age then
    v_reason := 'BUDGET_STALE';
  elsif v_event.context_status <> 'GREEN' then
    v_reason := 'BUDGET_STATUS_' || v_event.context_status;
  elsif v_event.estimated_tokens > p_budget_limit then
    v_reason := 'BUDGET_OVER_LIMIT';
  else
    v_authorized := true;
    v_reason := 'BUDGET_GREEN_WITHIN_LIMIT';
  end if;

  return jsonb_build_object(
    'authorized', v_authorized,
    'reason', v_reason,
    'model_call_authorized', v_authorized,
    'execution_id', p_execution_id,
    'budget_event_id', v_event.id,
    'estimated_tokens', v_event.estimated_tokens,
    'budget_limit', p_budget_limit,
    'context_status', v_event.context_status,
    'recorded_at', v_event.recorded_at,
    'evaluated_at', v_now
  );
end
$function$;

revoke all on function private.sbx_fn_lf_working_context_budget_gate_v1(text,bigint,interval)
  from public, anon, authenticated, service_role;

comment on function private.sbx_fn_lf_working_context_budget_gate_v1(text,bigint,interval) is
  'OP24 sandbox-only fail-closed budget gate. GREEN+fresh+within-limit is necessary but not sufficient for Working Context model consumption.';
