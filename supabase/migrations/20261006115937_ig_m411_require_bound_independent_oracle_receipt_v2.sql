update programacion.engineering_plan_units
set unit_metadata = jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1,PREREQ_GATES_PASS}',
  jsonb_build_object(
    'schema_version','ENGINEERING_ACTION_SPEC_V3',
    'status','BLOCK_INDEPENDENCE_RECEIPT_REQUIRED',
    'precision','EXPLICIT_FAIL_CLOSED_PREREQUISITE',
    'checkpoint_code','PREREQ_GATES_PASS',
    'checkpoint_title','Verificar prerequisitos: M4.10 adjudicado, M9.8 Shadow Gate PASS y M9.12 CUTOVER_READY (por work_items y receipts)',
    'recipe_mode','READBACK_EXACT',
    'action_kind','READBACK_ONCE',
    'requires_material_execution',false,
    'mutation_policy','NO_DOMAIN_MUTATION',
    'expected','M4.10 adjudicado + M9.8 PASS + M9.12 CUTOVER_READY del mismo bundle + receipt T-INDEP del candidato exacto con overall=INDEPENDENT y DEPENDENCIES/DATA/AUTHOR=INDEPENDENT',
    'required_evidence_contract',jsonb_build_object(
      'capability_code','INDEPENDENT_ASSURANCE',
      'measure_entrypoint','public.lf_independent_assurance_measure_v1',
      'producer_root','fn_input_governance_bootstrap_classify_v2',
      'reviewer_root','fn_input_governance_shadow_priority_oracle_v2',
      'required_overall_state','INDEPENDENT',
      'required_dimensions',jsonb_build_object(
        'DEPENDENCIES','INDEPENDENT',
        'DATA','INDEPENDENT',
        'AUTHOR','INDEPENDENT'
      ),
      'binding_rule','EXACT_CANDIDATE_REVISION_AND_SAME_M9_12_CUTOVER_READY_BUNDLE_SHA',
      'receipt_required',true,
      'current_observation',jsonb_build_object(
        'state','NOT_INDEPENDENT',
        'shared_dependency_count',7,
        'unresolved_shared_dependency_count',7,
        'data_state','UNPROVEN',
        'author_state','UNPROVEN',
        'observed_at','2026-10-06',
        'source_unit','M4.4'
      )
    ),
    'forbidden',jsonb_build_array(
      'TREAT_M4_4_DONE_AS_INDEPENDENCE_PROOF',
      'TREAT_CAPABILITY_PIN_AS_INDEPENDENCE_PROOF',
      'TREAT_ZERO_TEXTUAL_CLASSIFIER_REFS_AS_TRANSITIVE_INDEPENDENCE_PROOF',
      'ACTIVATE_DECISIONAL_ORACLE_WITH_NOT_INDEPENDENT_OR_UNPROVEN_RECEIPT'
    ),
    'persist',jsonb_build_object(
      'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
      'on_pass','DONE',
      'next_state','RETURNED_BOOTSTRAP_ONLY'
    ),
    'fallback_only_on',jsonb_build_array(
      'MISSING_CANONICAL_OBJECT','CONTRADICTION','STALE_CURRENTNESS',
      'DEMONSTRATED_DRIFT','MATERIAL_FINGERPRINT_CHANGE'
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.11';