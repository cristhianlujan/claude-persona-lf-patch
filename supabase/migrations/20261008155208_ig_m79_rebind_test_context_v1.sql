-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261008155208
-- source_name=ig_m79_rebind_test_context_v1
-- M7.9: complete removal of inherited LINEAGE_DAG test metadata.
-- Preserve all test assertions, DB targets, authored case data and evidence.
do $fix$
declare old_ctx text;expected text;
begin
 select unit_metadata#>>'{action_specs_v1,REBIND_CASES,test_execution_contract,checkpoint_title_context}',
 unit_metadata#>>'{action_specs_v1,REBIND_CASES,checkpoint_title}'
 into old_ctx,expected
 from programacion.engineering_plan_units where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M7.9';
 if old_ctx is null or old_ctx=expected or old_ctx not ilike '%lineage/DAG%' then
   raise exception 'M79_TITLE_INHERITANCE_BASELINE_DRIFT';
 end if;
 update programacion.engineering_plan_units
 set unit_metadata=jsonb_set(unit_metadata,
 '{action_specs_v1,REBIND_CASES,test_execution_contract,checkpoint_title_context}',to_jsonb(expected),true)
 where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='M7.9';
 if (select programacion.fn_engineering_checkpoint_action_spec_v3(
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.9','REBIND_CASES')#>>'{test_execution_contract,checkpoint_title_context}') is distinct from expected
 then raise exception 'M79_INHERITED_TEST_CONTEXT_NOT_REMOVED';end if;
end;
$fix$;