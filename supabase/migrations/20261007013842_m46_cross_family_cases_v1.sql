-- M4.6 CROSS_FAMILY_CASES V1
-- Materialize exactly ten Q4 cases in the existing Input Governance regression suite.
-- Five positive controls + five negatives; execution is performed by the versioned
-- rollback harness against the existing semantic-coherence trigger.

do $pre$
begin
  if exists (
    select 1 from public.lf_test_suite_cases
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and (
        test_code in ('M46_POS_REDUCED_MOTION','M46_NEG_REDUCED_MOTION','M46_POS_FORCED_COLORS_CONTRAST','M46_NEG_FORCED_COLORS_CONTRAST','M46_POS_THEME_LIGHT_DARK_SYSTEM','M46_NEG_THEME_LIGHT_DARK_SYSTEM','M46_POS_ACCESSIBILITY','M46_NEG_ACCESSIBILITY','M46_POS_MFA_OTP_SSO','M46_NEG_MFA_OTP_SSO')
        or test_order between 460001 and 460010
      )
  ) then
    raise exception 'M46_CROSS_FAMILY_CASE_RANGE_ALREADY_OCCUPIED';
  end if;

  if not exists (
    select 1 from public.lf_test_suites
    where suite_code='INPUT_GOVERNANCE_REGRESSION'
      and status='CANDIDATO'
  ) then
    raise exception 'M46_INPUT_GOVERNANCE_REGRESSION_SUITE_NOT_AVAILABLE';
  end if;
end;
$pre$;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
)
values
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_POS_REDUCED_MOTION',
  460001,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 positive cross-family detector: REDUCED_MOTION',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','REDUCED_MOTION',
    'polarity','POSITIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','PASS_ACCEPTED_BY_DETECTOR',
    'expected_error_any_of','[]'::jsonb
  ),
  jsonb_build_object(
    'false_pass',false,
    'false_reject',true,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_NEG_REDUCED_MOTION',
  460002,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 negative cross-family detector: REDUCED_MOTION',
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','REDUCED_MOTION',
    'polarity','NEGATIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','DETECTED',
    'expected_error_any_of',to_jsonb(array['V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH']::text[])
  ),
  jsonb_build_object(
    'false_pass',true,
    'false_reject',false,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_POS_FORCED_COLORS_CONTRAST',
  460003,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 positive cross-family detector: FORCED_COLORS_CONTRAST',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','FORCED_COLORS_CONTRAST',
    'polarity','POSITIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','PASS_ACCEPTED_BY_DETECTOR',
    'expected_error_any_of','[]'::jsonb
  ),
  jsonb_build_object(
    'false_pass',false,
    'false_reject',true,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_NEG_FORCED_COLORS_CONTRAST',
  460004,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 negative cross-family detector: FORCED_COLORS_CONTRAST',
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','FORCED_COLORS_CONTRAST',
    'polarity','NEGATIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','DETECTED',
    'expected_error_any_of',to_jsonb(array['V512_VALIDATOR_SOURCE_CANDIDATE_REQUIREMENT_SEMANTICS_MISMATCH']::text[])
  ),
  jsonb_build_object(
    'false_pass',true,
    'false_reject',false,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_POS_THEME_LIGHT_DARK_SYSTEM',
  460005,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 positive cross-family detector: THEME_LIGHT_DARK_SYSTEM',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','THEME_LIGHT_DARK_SYSTEM',
    'polarity','POSITIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','PASS_ACCEPTED_BY_DETECTOR',
    'expected_error_any_of','[]'::jsonb
  ),
  jsonb_build_object(
    'false_pass',false,
    'false_reject',true,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_NEG_THEME_LIGHT_DARK_SYSTEM',
  460006,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 negative cross-family detector: THEME_LIGHT_DARK_SYSTEM',
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','THEME_LIGHT_DARK_SYSTEM',
    'polarity','NEGATIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','DETECTED',
    'expected_error_any_of',to_jsonb(array['V512_VALIDATOR_THEME_SEMANTICS_MISMATCH']::text[])
  ),
  jsonb_build_object(
    'false_pass',true,
    'false_reject',false,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_POS_ACCESSIBILITY',
  460007,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 positive cross-family detector: ACCESSIBILITY',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','ACCESSIBILITY',
    'polarity','POSITIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','PASS_ACCEPTED_BY_DETECTOR',
    'expected_error_any_of','[]'::jsonb
  ),
  jsonb_build_object(
    'false_pass',false,
    'false_reject',true,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_NEG_ACCESSIBILITY',
  460008,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 negative cross-family detector: ACCESSIBILITY',
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','ACCESSIBILITY',
    'polarity','NEGATIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','DETECTED',
    'expected_error_any_of',to_jsonb(array['V512_VALIDATOR_ACCESSIBILITY_CORE_PRESENT_BUT_CANDIDATE_INCOMPLETE']::text[])
  ),
  jsonb_build_object(
    'false_pass',true,
    'false_reject',false,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_POS_MFA_OTP_SSO',
  460009,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 positive cross-family detector: MFA_OTP_SSO',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','MFA_OTP_SSO',
    'polarity','POSITIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','PASS_ACCEPTED_BY_DETECTOR',
    'expected_error_any_of','[]'::jsonb
  ),
  jsonb_build_object(
    'false_pass',false,
    'false_reject',true,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
),
(
  'INPUT_GOVERNANCE_REGRESSION',
  'M46_NEG_MFA_OTP_SSO',
  460010,
  array['M4.6','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT']::text[],
  'M4.6 negative cross-family detector: MFA_OTP_SSO',
  'NEGATIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'Use a transaction-local fixture cloned from a fresh current successor for pantalla_id=54',
    'Build fresh Validator assertions for the target family',
    'Attach only programacion.fn_guard_input_validator_semantic_coherence_v512 to the temporary fixture table',
    'Rollback every fixture and assertion-set write'
  ),
  jsonb_build_object(
    'schema_version','M46_CROSS_FAMILY_FIXTURE_V1',
    'family_code','MFA_OTP_SSO',
    'polarity','NEGATIVE',
    'base_screen_id',54,
    'fixture_kind','TRANSACTION_LOCAL_TRIGGER_UNIT_CASE',
    'fresh_assertions',true,
    'rollback_required',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','DETECTED',
    'expected_error_any_of',to_jsonb(array['V512_VALIDATOR_OTP_PRESENT_BUT_FAMILY_NOT_APPLICABLE','V512_VALIDATOR_NA_WITHOUT_POSITIVE_EXCLUSION']::text[])
  ),
  jsonb_build_object(
    'false_pass',true,
    'false_reject',false,
    'persistent_fixture_mutation',true,
    'assurance_activation',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.6',
    'work_code','PAULO-060',
    'checkpoint_code','CROSS_FAMILY_CASES',
    'q_class','Q4',
    'detector_ref','programacion.fn_guard_input_validator_semantic_coherence_v512',
    'harness_path','sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
    'defeater_obligation','IG-C5_13-SEMANTIC_COHERENCE_CONTRACT',
    'assurance_evaluator_activation','NOT_REQUIRED_FOR_THIS_DETECTOR_UNIT_TEST',
    'change_impact_l3c_gold_ref','sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql'
  ),
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007',
  'CHATGPT-IG-M46-CROSS-FAMILY-CASES-20261007'
);

update programacion.engineering_plan_units
set unit_metadata=jsonb_set(
  coalesce(unit_metadata,'{}'::jsonb),
  '{action_specs_v1}',
  coalesce(unit_metadata->'action_specs_v1','{}'::jsonb)
  || jsonb_build_object(
    'CROSS_FAMILY_CASES',
    jsonb_build_object(
      'schema_version','ENGINEERING_ACTION_SPEC_V3',
      'status','READY',
      'checkpoint_code','CROSS_FAMILY_CASES',
      'checkpoint_title','Casos cross-family (incl. change_impact_l3c gold) ejecutados contra el detector',
      'action_kind','DECLARED_TEST_EXECUTION',
      'recipe_mode','RUN_EXACT_TEST_SET',
      'precision','EXPLICIT_M46_CROSS_FAMILY_CASES_V1',
      'contract_source','EXPLICIT_ACTION_SPEC',
      'requires_material_execution',true,
      'mutation_policy','NO_DOMAIN_MUTATION',
      'expected','Execute exactly ten M4.6 Q4 cases using the versioned transaction-rollback harness: five coherent positive controls must be accepted and five contradiction negatives must be detected by the existing semantic-coherence trigger; persist the canonical suite receipt and assertion receipt.',
      'target',jsonb_build_object(
        'declared_objects',jsonb_build_array(
          'public.lf_test_suite_cases',
          'programacion.fn_guard_input_validator_semantic_coherence_v512',
          'programacion.fn_engineering_run_test_persist_v1'
        ),
        'declared_artifacts',jsonb_build_array(
          jsonb_build_object(
            'path','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql',
            'role','TEST_HARNESS_EVIDENCE'
          ),
          jsonb_build_object(
            'path','github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_incremental/change_impact_l3c_gold_50.sql',
            'role','REFERENCE_GOLD_EVIDENCE'
          )
        ),
        'declared_assets','[]'::jsonb,
        'declared_events','[]'::jsonb,
        'mutation_artifacts','[]'::jsonb
      ),
      'test_case_codes',jsonb_build_array('M46_POS_REDUCED_MOTION','M46_NEG_REDUCED_MOTION','M46_POS_FORCED_COLORS_CONTRAST','M46_NEG_FORCED_COLORS_CONTRAST','M46_POS_THEME_LIGHT_DARK_SYSTEM','M46_NEG_THEME_LIGHT_DARK_SYSTEM','M46_POS_ACCESSIBILITY','M46_NEG_ACCESSIBILITY','M46_POS_MFA_OTP_SSO','M46_NEG_MFA_OTP_SSO'),
      'test_case_set_sha256',programacion.fn_v09_sha256_jsonb(jsonb_build_array('M46_POS_REDUCED_MOTION','M46_NEG_REDUCED_MOTION','M46_POS_FORCED_COLORS_CONTRAST','M46_NEG_FORCED_COLORS_CONTRAST','M46_POS_THEME_LIGHT_DARK_SYSTEM','M46_NEG_THEME_LIGHT_DARK_SYSTEM','M46_POS_ACCESSIBILITY','M46_NEG_ACCESSIBILITY','M46_POS_MFA_OTP_SSO','M46_NEG_MFA_OTP_SSO')),
      'assertion_contract',jsonb_build_object(
        'mode','EXPLICIT_PASS_WHEN_SUBSET',
        'pass_when',jsonb_build_object(
          'tests_total',10,
          'tests_passed',10,
          'tests_failed',0,
          'tests_blocked',0,
          'tests_review_required',0,
          'receipt_bundle_status','VERIFIED'
        )
      ),
      'verification_queries',jsonb_build_array(
$q$
with c as (
  select *
  from public.lf_test_suite_cases
  where suite_code='INPUT_GOVERNANCE_REGRESSION'
    and metadata->>'unit_code'='M4.6'
    and metadata->>'checkpoint_code'='CROSS_FAMILY_CASES'
)
select
  count(*)=10 as case_count_exact,
  count(*) filter(where test_type='POSITIVE')=5 as positive_count_exact,
  count(*) filter(where test_type='NEGATIVE')=5 as negative_count_exact,
  count(distinct metadata->>'q_class')=1
    and min(metadata->>'q_class')='Q4' as q4_exact,
  bool_and(metadata->>'detector_ref'='programacion.fn_guard_input_validator_semantic_coherence_v512') as detector_exact,
  bool_and(input_payload->>'rollback_required'='true') as rollback_required,
  count(distinct input_payload->>'family_code')=5 as five_families_exact
from c
$q$
      ),
      'persist',jsonb_build_object(
        'on_pass','DONE',
        'entrypoint','programacion.fn_engineering_checkpoint_transition_v1',
        'next_state','RETURNED_BOOTSTRAP_ONLY'
      ),
      'forbidden',jsonb_build_array(
        'ACTIVATE_ASSURANCE_EVALUATOR',
        'CREATE_PARALLEL_TEST_ENGINE',
        'EXECUTE_FOREIGN_UNIT_TEST_CASES',
        'PERSIST_FIXTURE_MUTATIONS',
        'SYNTHETIC_PASS'
      )
    )
  ),
  true
)
where plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  and unit_code='M4.6'
  and disposition='ASSIGNED';

insert into public.lf_error_knowledge(
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref
) values (
  'IG-M46-CROSS-FAMILY-DETECTOR-TESTSET-001',
  'INPUT_GOVERNANCE',
  'Cross-family detector uses exact owned Q4 cases with rollback fixtures',
  'M4.6 owns ten exact test cases: one positive and one negative for each of REDUCED_MOTION, FORCED_COLORS_CONTRAST, THEME_LIGHT_DARK_SYSTEM, ACCESSIBILITY and MFA_OTP_SSO. The harness builds fresh assertions on a current successor, attaches only the existing semantic-coherence trigger to a transaction-local fixture, executes each case, and rolls back all fixture data.',
  'The previous checkpoint referenced cross-family cases and change_impact_l3c gold but did not own an exact executable case set.',
  'CROSS_FAMILY_DETECTOR_WITHOUT_OWNED_EXECUTABLE_CASE_SET',
  'Keep the ten cases owned by M4.6, resolve them by explicit test codes, execute only the existing detector, use fresh assertions, and persist only test receipts—not fixture mutations.',
  'PASS when canonical case count is 10 (5 positive, 5 negative), all are Q4 and owned by M4.6/CROSS_FAMILY_CASES, harness execution returns 10/10 PASS with 5 negative detections, canonical RUN_TEST receipt bundle is VERIFIED, and material assertion receipt is recorded before DONE.',
  'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/sandbox/lf_contract_gate_test/input_governance_cross_family/m46_cross_family_detector_cases_v1.sql; supabase://public.lf_test_suite_cases',
  'EXECUTION',
  array['INPUT_VALIDATOR','ENGINEERING_SCHEDULER']::text[],
  'R2_NO_VE','LOUD_EARLY',
  'M4.6 CROSS_FAMILY_CASES',
  'supabase://public.lf_test_suite_cases'
)
on conflict (codigo) do update set
  descripcion=excluded.descripcion,
  causa_raiz=excluded.causa_raiz,
  patron=excluded.patron,
  prevencion=excluded.prevencion,
  validacion=excluded.validacion,
  evidencia=excluded.evidencia,
  ultima_vez=now(),
  updated_at=now();
