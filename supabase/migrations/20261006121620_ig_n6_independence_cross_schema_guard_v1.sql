update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1,INDEPENDENT_JUDGE}',
  jsonb_build_object(
    'schema_version','ENGINEERING_ACTION_SPEC_V3',
    'status','BLOCK_TINDEP_CROSS_SCHEMA_UNSUPPORTED',
    'checkpoint_code','INDEPENDENT_JUDGE',
    'action_kind','READBACK_ONCE',
    'recipe_mode','READBACK_EXACT',
    'requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'expected','Cross-schema producer/reviewer independence must be proven by T-INDEP before this checkpoint can close',
    'required_evidence_contract',jsonb_build_object(
      'producer_root','programacion.fn_input_governance_safe_autofix_v1',
      'reviewer_root','public.lf_independent_strategy_review_record_judge_v1',
      'current_limitation','FUNCTION_NAME_MATCH_WITHIN_DECLARED_SCHEMA',
      'resolution_required','EVOLVE_EXISTING_T_INDEP_TO_CROSS_SCHEMA_TRANSITIVE_CLOSURE_AND_REQUALIFY',
      'required_overall_state','INDEPENDENT'
    ),
    'forbidden',jsonb_build_array(
      'TREAT_PUBLIC_WRAPPER_AS_FULL_PRODUCER_CLOSURE',
      'CLOSE_CHECKPOINT_WITH_UNPROVEN_OR_PARTIAL_MEASURE'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and unit_code='N-6';