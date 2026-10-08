-- M8.8: expose ONLY the two validator handoff RPC entrypoints used by the Edge runtime.
-- Source authorities stay in programacion. Public bridge is invoker-security,
-- EXECUTE restricted to service_role; no anon/authenticated or global schema exposure.
create or replace function public.fn_input_governance_validator_handoff_assert_v1(
  p_run_id bigint,
  p_receipt_id bigint
) returns jsonb
language sql
security invoker
set search_path to 'pg_catalog'
as $function$
  select programacion.fn_input_governance_validator_handoff_assert_v1(p_run_id,p_receipt_id);
$function$;

create or replace function public.fn_input_governance_validator_validate_handoff_v1(
  p_run_id bigint,
  p_validator_identity text,
  p_receipt_id bigint
) returns jsonb
language sql
security invoker
set search_path to 'pg_catalog'
as $function$
  select programacion.fn_input_governance_validator_validate_handoff_v1(
    p_run_id,p_validator_identity,p_receipt_id
  );
$function$;

revoke all on function public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)
  from public,anon,authenticated;
revoke all on function public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)
  from public,anon,authenticated;
grant execute on function public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)
  to service_role;
grant execute on function public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)
  to service_role;

comment on function public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)
is 'IG M8.8 service_role-only REST adapter. Delegates to programacion canonical handoff gate, invoker security.';
comment on function public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)
is 'IG M8.8 service_role-only REST adapter. Delegates to canonical governed validator, invoker security.';

do $guard$
begin
  if not has_function_privilege('service_role',
        'public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)','execute')
     or not has_function_privilege('service_role',
        'public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)','execute')
     or has_function_privilege('anon',
        'public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)','execute')
     or has_function_privilege('authenticated',
        'public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)','execute')
     or has_function_privilege('anon',
        'public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)','execute')
     or has_function_privilege('authenticated',
        'public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)','execute')
  then raise exception 'IG_M88_RPC_BRIDGE_ROLE_GUARD_FAILED'; end if;
end;
$guard$;
