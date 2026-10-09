update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{transversal_execution_v1,INDEPENDENT_JUDGE,capabilities,0,execution_input}',
  jsonb_build_object(
    'dependency_schema','programacion',
    'producer_root','programacion.fn_input_governance_safe_autofix_v1',
    'reviewer_root','public.lf_independent_strategy_review_record_judge_v1',
    'max_depth',8,
    'context','{}'::jsonb
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='N-6';

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  unit_metadata,
  '{source_pack_v1,checkpoint_inputs,INDEPENDENT_JUDGE,missing_typed}',
  coalesce((
    select jsonb_agg(x)
    from jsonb_array_elements(coalesce(unit_metadata#>'{source_pack_v1,checkpoint_inputs,INDEPENDENT_JUDGE,missing_typed}','[]'::jsonb)) x
    where x->>'kind'<>'TRANSVERSAL_CAPABILITY_LIMITATION'
  ),'[]'::jsonb),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='N-6';