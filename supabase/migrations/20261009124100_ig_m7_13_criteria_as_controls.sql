-- M7.13 / PAULO-085. Scope correction only; does not activate a release gate.
UPDATE programacion.engineering_plan_units
SET unit_metadata =
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          unit_metadata,
          '{action_specs_v1,CRITERIA_AS_CONTROLS,target,declared_objects}',
          '["public.lf_test_requirement_bindings","programacion.fn_ig_release_criteria_controls_v1"]'::jsonb
        ),
        '{action_specs_v1,CRITERIA_AS_CONTROLS,authoring_contract,db_targets_exact}',
        '["public.lf_test_requirement_bindings","programacion.fn_ig_release_criteria_controls_v1"]'::jsonb
      ),
      '{source_pack_v1,checkpoint_inputs,CRITERIA_AS_CONTROLS,inputs,db_objects}',
      '["programacion.input_family_assessments","public.lf_capability_registry","public.lf_test_requirement_bindings","public.lf_test_suite_runs","public.lf_qualification_receipts"]'::jsonb
    ),
    '{action_specs_v1,CRITERIA_AS_CONTROLS,qualification_controls_contract_v1}',
    '{"false_pass_known":{"required":0,"evidence":"M7.7 mutation receipts","unknown":"BLOCKED"},"unexplained_divergence":{"required":0,"evidence":"typed divergence receipts","unknown":"BLOCKED"},"family_coverage":{"required":47,"evidence":"input_family_assessments + current family catalog","unknown":"BLOCKED"},"reuse":"QUALIFICATION_FRAMEWORK/CLOSURE_GATE","own_gate":false,"positive_and_negative_tests":true,"bundle_binding":"M9.0","release_authorized":false}'::jsonb
  )
WHERE plan_code = 'IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND unit_code = 'M7.13'
  AND unit_metadata #> '{action_specs_v1,CRITERIA_AS_CONTROLS,authoring_contract,db_targets_exact}'
      = '["public.lf_capability_registry","programacion.input_family_assessments"]'::jsonb;
