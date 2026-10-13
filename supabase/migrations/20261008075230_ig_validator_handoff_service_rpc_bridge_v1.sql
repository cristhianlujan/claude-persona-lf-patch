-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261008075230
-- source_name=ig_validator_handoff_service_rpc_bridge_v1
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
