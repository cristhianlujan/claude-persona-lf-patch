-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261008075955
-- source_name=ig_validator_rpc_bridge_rollback_v1
-- Roll back M8.8-only REST adapters after unmet verified handoff receipt precondition.
-- Both Edge functions have already been restored from predeploy backups.
-- Preserve authoritative programacion functions and all unrelated schemas.
drop function if exists public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint);
drop function if exists public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint);

do $guard$
begin
  if to_regprocedure('public.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)') is not null
     or to_regprocedure('public.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)') is not null
     or to_regprocedure('programacion.fn_input_governance_validator_handoff_assert_v1(bigint,bigint)') is null
     or to_regprocedure('programacion.fn_input_governance_validator_validate_handoff_v1(bigint,text,bigint)') is null
  then raise exception 'IG_M88_RPC_BRIDGE_ROLLBACK_READBACK_FAILED'; end if;
end;
$guard$;