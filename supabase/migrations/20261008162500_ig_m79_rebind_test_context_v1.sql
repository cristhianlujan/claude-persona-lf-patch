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