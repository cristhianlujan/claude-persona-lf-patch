-- IG M8.2 PER_FAMILY_RESOLVER: reconcile exact execution owner.
-- Actual per-family deterministic+semantic invocation lives in the BEFORE INSERT
-- function. No modifications to checkpoint status, dependencies or other units.
do $scope$
declare v_count integer;
begin
 update programacion.engineering_plan_units u
 set unit_metadata=jsonb_set(
   jsonb_set(u.unit_metadata,
     '{action_specs_v1,PER_FAMILY_RESOLVER,target,declared_objects}',
     u.unit_metadata#>'{action_specs_v1,PER_FAMILY_RESOLVER,target,declared_objects}'||
       jsonb_build_array('programacion.fn_input_curator_compose_before_insert_v1'),false),
   '{action_specs_v1,PER_FAMILY_RESOLVER,authoring_contract,db_targets_exact}',
   u.unit_metadata#>'{action_specs_v1,PER_FAMILY_RESOLVER,authoring_contract,db_targets_exact}'||
       jsonb_build_array('programacion.fn_input_curator_compose_before_insert_v1'),false)
 where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.unit_code='M8.2'
   and u.unit_metadata#>'{action_specs_v1,PER_FAMILY_RESOLVER,target,declared_objects}'=
       '["programacion.fn_input_governance_curator_materialize_v1"]'::jsonb
   and u.unit_metadata#>'{action_specs_v1,PER_FAMILY_RESOLVER,authoring_contract,db_targets_exact}'=
       '["programacion.fn_input_governance_curator_materialize_v1"]'::jsonb;
 get diagnostics v_count=row_count;
 if v_count<>1 then raise exception 'IG_M82_TARGET_RECONCILE_DRIFT:%',v_count; end if;
end;
$scope$;
