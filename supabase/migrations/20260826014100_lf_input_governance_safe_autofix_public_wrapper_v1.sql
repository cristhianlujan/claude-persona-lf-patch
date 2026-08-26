-- INPUT_GOVERNANCE_AGENT 5.12
-- Expose the already-governed safe-autofix delegate through PostgREST for the Edge orchestrator.
-- This does not widen autofix authority: the internal function remains the only implementation,
-- and execute is granted only to service_role, matching Curator/Validator/Dispatcher wrappers.

create or replace function public.fn_input_governance_safe_autofix_v1(p_run_id bigint)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_input_governance_safe_autofix_v1(p_run_id);
$function$;

revoke all on function public.fn_input_governance_safe_autofix_v1(bigint) from public;
revoke all on function public.fn_input_governance_safe_autofix_v1(bigint) from anon;
revoke all on function public.fn_input_governance_safe_autofix_v1(bigint) from authenticated;
grant execute on function public.fn_input_governance_safe_autofix_v1(bigint) to service_role;

do $selftest$
begin
  if to_regprocedure('public.fn_input_governance_safe_autofix_v1(bigint)') is null then
    raise exception 'SELFTEST_SAFE_AUTOFIX_PUBLIC_WRAPPER_MISSING';
  end if;
  if not has_function_privilege('service_role','public.fn_input_governance_safe_autofix_v1(bigint)','EXECUTE') then
    raise exception 'SELFTEST_SAFE_AUTOFIX_SERVICE_ROLE_EXECUTE_MISSING';
  end if;
  if has_function_privilege('anon','public.fn_input_governance_safe_autofix_v1(bigint)','EXECUTE') then
    raise exception 'SELFTEST_SAFE_AUTOFIX_ANON_EXECUTE_FORBIDDEN';
  end if;
  if has_function_privilege('authenticated','public.fn_input_governance_safe_autofix_v1(bigint)','EXECUTE') then
    raise exception 'SELFTEST_SAFE_AUTOFIX_AUTHENTICATED_EXECUTE_FORBIDDEN';
  end if;
end;
$selftest$;

comment on function public.fn_input_governance_safe_autofix_v1(bigint)
is 'PostgREST entrypoint for INPUT_GOV_SAFE_AUTOFIX_V1. service_role only; delegates to governed programacion implementation without widening write authority.';
