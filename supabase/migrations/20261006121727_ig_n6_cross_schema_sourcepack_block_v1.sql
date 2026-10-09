update programacion.engineering_plan_units
set unit_metadata =
  jsonb_set(
    unit_metadata #- '{action_specs_v1,INDEPENDENT_JUDGE}',
    '{source_pack_v1,checkpoint_inputs,INDEPENDENT_JUDGE,missing}',
    coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,INDEPENDENT_JUDGE,missing}','[]'::jsonb)
      || jsonb_build_array('T-INDEP v1 no prueba closures cross-schema para producer programacion.fn_input_governance_safe_autofix_v1 vs reviewer public.lf_independent_strategy_review_record_judge_v1'),
    true
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='N-6';

update programacion.engineering_plan_units
set unit_metadata =
  jsonb_set(
    unit_metadata,
    '{source_pack_v1,checkpoint_inputs,INDEPENDENT_JUDGE,missing_typed}',
    coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,INDEPENDENT_JUDGE,missing_typed}','[]'::jsonb)
      || jsonb_build_array(jsonb_build_object(
        'kind','TRANSVERSAL_CAPABILITY_LIMITATION',
        'text','INDEPENDENT_ASSURANCE v1 usa FUNCTION_NAME_MATCH_WITHIN_DECLARED_SCHEMA y no puede demostrar la independencia material cross-schema de N-6',
        'blocking',true,
        'resolver','Evolucionar la capability existente T-INDEP a closure transitivo qualified cross-schema, requalificar la revisión exacta y luego proveer dependency/data/author evidence'
      )),
    true
  )
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='N-6';