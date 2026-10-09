-- IG M9.3: repair contract/executor mismatch, not a waiver of acceptance.
-- PRECONDITION: FULL_PIPELINE_CANDIDATE is still a bounded authored test.
-- Explicitly declare the missing bounded evidence-acquisition runner as a
-- separate test artifact. Neither a source file alone nor the shadow AS-IS
-- may satisfy terminal acceptance or the existing blocker #88.
DO $m93$
DECLARE
  v_metadata jsonb;
  v_spec jsonb;
  v_runner jsonb := jsonb_build_object(
    'path','cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_3/full_pipeline_shadow_runner.py',
    'role','MUTATION_TARGET','purpose','CHECKPOINT_EVIDENCE_ACQUISITION_RUNNER',
    'target_kind','EXACT_NEW_OR_UPDATE_FILE'
  );
  v_next jsonb;
BEGIN
  SELECT unit_metadata INTO STRICT v_metadata
  FROM programacion.engineering_plan_units
  WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3'
  FOR UPDATE;
  v_spec := v_metadata#>'{action_specs_v1,FULL_PIPELINE_CANDIDATE}';
  IF v_spec->>'action_kind' <> 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
     OR v_spec#>>'{test_execution_contract,test_code}' <> 'ENG_M9_3_FULL_PIPELINE_CANDIDATE'
     OR (v_spec->'target'->'declared_artifacts') @> jsonb_build_array(v_runner) THEN
    RAISE EXCEPTION 'M9_3_RUNNER_SCOPE_SOURCE_DRIFT';
  END IF;

  v_next := v_spec || jsonb_build_object(
    'status','READY',
    'precision','BOUNDED_SHADOW_RUNNER_AND_TEST_V1',
    'expected','Author and execute a governed read-only full vNext pipeline runner plus the independent test. T-EQUIV compares live results with 5.13 on all 7 M9.4 cohorts. Zero authoritative candidate writes and real positive+negative machine receipts required; no fake PASS.',
    'target',(v_spec->'target')||jsonb_build_object(
      'declared_artifacts',coalesce(v_spec#>'{target,declared_artifacts}','[]'::jsonb)||jsonb_build_array(v_runner),
      'mutation_artifacts',coalesce(v_spec#>'{target,mutation_artifacts}','[]'::jsonb)||jsonb_build_array(v_runner)
    ),
    'evidence_acquisition_contract',jsonb_build_object(
      'schema_version','IG_M9_3_FULL_PIPELINE_ACQUISITION_V1',
      'runner_path',v_runner->>'path',
      'runner_target_role','CHECKPOINT_TEST_ARTIFACT',
      'runtime_mode','READ_ONLY_TRANSACTIONS',
      'source','LIVE_SANDBOX_AND_EXACT_MERGED_GIT',
      'cohort_authority','programacion.v_input_governance_representative_cohort_v1',
      'required_cohort_count',7,
      'required_stages',jsonb_build_array('CORE','SEMANTICS','CURATOR','VALIDATOR'),
      'equivalence_capability','CONTROL_EQUIVALENCE_JUDGE',
      'baseline','5.13',
      'candidate','VNEXT',
      'require_zero_authoritative_writes',true,
      'on_missing_stage','BLOCK_WITH_TYPED_EVIDENCE',
      'on_timeout','BLOCK_WITH_TYPED_EVIDENCE',
      'synthetic_receipts','FORBIDDEN'
    ),
    'test_execution_contract',(v_spec->'test_execution_contract') || jsonb_build_object(
      'runner_path',v_runner->>'path',
      'real_run_receipts_required',true,
      'negative_required',true,
      'synthetic_pass','FORBIDDEN',
      'source_contract','EXACT_MERGED_SHA'
    )
  );

  UPDATE programacion.engineering_plan_units
     SET unit_metadata=jsonb_set(v_metadata,'{action_specs_v1,FULL_PIPELINE_CANDIDATE}',v_next,true)
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3';
  IF NOT FOUND THEN RAISE EXCEPTION 'M9_3_SCOPE_UPDATE_MISSING'; END IF;
END $m93$;
