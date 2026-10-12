-- IG_CURATOR_VALIDATOR_REFACTOR_V2 M9.9
-- Atomic consumer contract + governance: sandbox qualification is distinct from
-- operational activation. No production permission, no live canary receipt bypass.
-- This source explicitly supersedes the *intent* of the unapplied
-- 20261012013000_ig_m99_existing_n9_adapter_proof_boundary_v1.sql;
-- migration reconciliation is separately required by DB_WRITE_TRANSPORT.
DO $m99$
DECLARE u record; cp4 jsonb; cp5 jsonb; pass jsonb; gov jsonb;
BEGIN
 SELECT id,unit_metadata,exit_criterion INTO STRICT u
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9'
 FOR UPDATE;
 cp4:=u.unit_metadata#>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE}';
 cp5:=u.unit_metadata#>'{action_specs_v1,CANARY_READBACK}';
 IF cp4->>'status' IS DISTINCT FROM 'READY'
 OR cp5->>'status' IS DISTINCT FROM 'READY'
 OR cp4#>>'{assertion_contract,pass_when,runtime_canary_proven}' IS DISTINCT FROM 'true'
 OR cp5#>>'{readback_acceptance_v1,signed_live_receipts_required}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M99_RESCOPING_BASELINE_DRIFT'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=267 AND checkpoint_code='ROLLBACK_TRIGGER_NEGATIVE'
  AND status='PENDING')
 OR NOT EXISTS (
  SELECT 1 FROM programacion.engineering_work_checkpoints
  WHERE work_item_id=267 AND checkpoint_code='CANARY_READBACK'
  AND status='PENDING')
 THEN RAISE EXCEPTION 'M99_RESCOPING_CHECKPOINT_ALREADY_TRANSITIONED'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.lf_capability_current
   WHERE capability_code='REVERSIBLE_CANDIDATE_VERIFICATION'
   AND version='1.0.3'
 ) OR NOT EXISTS (
   SELECT 1 FROM public.lf_capability_current
   WHERE capability_code='INDEPENDENT_ASSURANCE'
   AND version='2.0.1'
 ) OR NOT EXISTS (
   SELECT 1 FROM public.lf_capability_current
   WHERE capability_code='INPUT_GOVERNANCE'
   AND version='1.0.0' AND previous_version IS NULL
 ) THEN RAISE EXCEPTION 'M99_RESCOPING_CAPABILITY_CURRENTNESS_DRIFT'; END IF;

 -- Two independent acceptance levels: scoped sandbox engineering versus
 -- production/operational release, whose original strict receipts remain.
 gov:=jsonb_build_object(
  'schema_version','IG_M99_TWO_LEVEL_QUALIFICATION_GOVERNANCE_V2',
  'decision','REPLACE_MISSCOPED_LIVE_CANARY_EXIT_WITH_SANDBOX_MEASUREMENT',
  'unit_acceptance_scope','SANDBOX_ENGINEERING_ONLY',
  'operational_gate',jsonb_build_object(
    'status','BLOCKED_UNTIL_SEPARATE_AUTHORIZATION_AND_VERIFIED_PROVENANCE',
    'production_activation',false,'runtime_activation',false,
    'signed_live_receipts_required',true,
    'independent_review_required',true,
    'origin_authority','EVIDENCE_LEDGER+EVIDENCE_VERIFIER_V1',
    'five_live_conditions_required',true,
    'may_infer_live_canary_from_sandbox_test',false),
  'sandbox_gate',jsonb_build_object(
    'requires_actual_db_pointer_test',true,
    'required_cases',jsonb_build_array('CLEAN','FALSE_PASS','DIVERGENCE',
      'TIMEOUT','EXECUTION_ERROR','MISSING_RECEIPT'),
    'require_each_expected_decision',true,
    'require_exact_baseline_version_and_manifest',true,
    'require_zero_version_and_receipt_residue',true,
    'require_source_git_ref_and_db_result',true,
    'historical_timeout_classification','POLICY_SEMANTIC_PROBE_ONLY',
    'canary_live_claim',false,
    'signed_live_receipts_required',false),
  'scope_boundary','Unit qualification cannot authorize cohort cutover or production.');
 pass:=jsonb_build_object(
  'test_passed',true,'test_exit_code',0,
  'sandbox_six_case_matrix_verified',true,'positive_control_verified',true,
  'negative_case_count',5,'rollback_exact',true,
  'zero_residue',true,'baseline_currentness_verified',true,
  'evidence_origin','SOURCE_BOUND_SANDBOX_DB_RUN',
  'operational_canary_activated',false);
 cp4:=jsonb_set(cp4,'{assertion_contract,pass_when}',pass,true);
 cp4:=jsonb_set(cp4,'{test_execution_contract}',
  cp4->'test_execution_contract'||jsonb_build_object(
   'rollback_requirement','SIX_CASE_TRANSACTIONAL_DB_REVERSIBILITY',
   'provenance_requirement','GIT_SOURCE_PLUS_SANDBOX_DB_READBACK',
   'simulated_signals_suffice',false,
   'historical_timeout_is_runtime_SLA_proof',false,
   'execution_scope','SANDBOX_ONLY_NO_SWITCH'),true);
 cp4:=cp4||jsonb_build_object(
  'expected','Bounded six-case sandbox proof of governed version-pointer reversibility; positive/negative decisions, baseline exact and zero residue. No live canary certificate or production authorization.',
  'acceptance_profile','SANDBOX_REVERSIBLE_QUALIFICATION_V2',
  'operational_assurance_deferred_to_release_gate',true,
  'requires_material_execution',true);
 cp4:=jsonb_set(cp4,'{reversible_consumer_binding_v1}',
  coalesce(cp4->'reversible_consumer_binding_v1','{}'::jsonb)||
    jsonb_build_object('execution_admission','SANDBOX_TEST_ONLY_WITH_LIVE_RELEASE_BLOCKED',
                       'flow_adapter_binding_status','SANDBOX_DB_PROBE_VERIFIED_NOT_LIVE_CANARY'),true);

 cp5:=cp5||jsonb_build_object(
  'precision','SANDBOX_BASELINE_READBACK_V2',
  'recipe_mode','ASSERT_SOURCE_BOUND_SIX_CASE_DB_RESULT_AND_BASELINE_PARITY',
  'expected','Verify 6/6 sandbox cases from the exact versioned test artifact, INPUT_GOVERNANCE 1.0.0 current, unchanged manifest and previous_version=NULL, zero registered candidate versions and zero persisted test receipts. Live receipts not required for sandbox scope; required for separate operational admission.',
  'sandbox_readback_acceptance_v2',jsonb_build_object(
    'source_bound_case_count',6,'negative_count',5,
    'baseline_manifest_must_match_frozen',true,'zero_residue_required',true,
    'valid_test_evidence_required',true,'test_evidence_not_live_authorization',true),
  'operational_readback_acceptance_v1',cp5->'readback_acceptance_v1');
 cp5:=cp5-'readback_acceptance_v1';
 cp5:=jsonb_set(cp5,'{target,declared_artifacts}',
   jsonb_build_array(jsonb_build_object(
    'role','EVIDENCE_ONLY','target_kind','REPOSITORY_SOURCE',
    'path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_9/cases/integrated_six_case_canary_v1.sql')),true);

 UPDATE programacion.engineering_plan_units
 SET exit_criterion='M9.9 sandbox-only: six-case scoped DB canary proof (clean + five negative triggers), automatic transactional rollback, frozen baseline pointer/manifest exact, zero residue. Operational live canary activation with independent signed receipts is a distinct release gate and remains BLOCKED, not a prerequisite for sandbox engineering completion.',
 unit_metadata=jsonb_set(jsonb_set(
    jsonb_set(unit_metadata,'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE}',cp4,true),
    '{action_specs_v1,CANARY_READBACK}',cp5,true),
    '{m99_two_level_qualification_governance_v2}',gov,true)
 WHERE id=u.id;

 IF programacion.fn_engineering_checkpoint_action_spec_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','ROLLBACK_TRIGGER_NEGATIVE'
 )#>>'{acceptance_profile}' IS DISTINCT FROM 'SANDBOX_REVERSIBLE_QUALIFICATION_V2'
 OR programacion.fn_engineering_checkpoint_action_spec_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','CANARY_READBACK'
 )#>>'{sandbox_readback_acceptance_v2,source_bound_case_count}' IS DISTINCT FROM '6'
 THEN RAISE EXCEPTION 'M99_RESCOPING_COMPILER_READBACK_FAILED'; END IF;
END $m99$;
