\set ON_ERROR_STOP on

-- T01 disposable integration fire-test.
-- Requires, in this order: live-schema-only disposable DB -> baseline seed ->
-- PR #877 exact migration -> PR #879 evaluator migration -> exact #877 source tests PASS.
-- This file never targets Supabase live.

DO $seed$
DECLARE
  v_suite_run uuid;
  v_exec constant text := 'EXEC-T01-CURRENTNESS-FIRETEST-20260917-001';
  v_revision constant text := 'c56b20d7d34b3dc7e4cdf44af69d17253f3efc52';
BEGIN
  INSERT INTO public.lf_operation_execution(
    execution_id,operation_code,target_type,target_code,status,completed_at,manifest,created_by_execution_id
  ) VALUES (
    v_exec,'OPERATION_ENFORCEMENT_REGRESSION_SUITE_LF','CAPABILITY','CURRENTNESS_AUTHORITY',
    'COMPLETED',clock_timestamp(),
    jsonb_build_object('firetest',true,'consumer_pr',877,'consumer_head',v_revision,'evaluator_pr',879),
    v_exec
  ) ON CONFLICT (execution_id) DO NOTHING;

  INSERT INTO public.lf_test_suite_runs(
    suite_code,execution_id,environment,application_version,commit_sha,executor_type,executor_name,
    status,started_at,completed_at,tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,
    manifest,metadata,created_by_execution_id
  ) VALUES (
    'TS-CURRENTNESS-AUTHORITY-V1',v_exec,'T01_DISPOSABLE_FIRETEST','candidate',v_revision,
    'DETERMINISTIC_DB','T01_CURRENTNESS_CLAIM_FIRETEST','PASSED',clock_timestamp(),clock_timestamp(),
    7,7,0,0,0,
    jsonb_build_object('source_tests_executed',true,'source_revision',v_revision),
    jsonb_build_object('fixture_scope','DISPOSABLE_ONLY','synthetic_matrix_rows',true),v_exec
  ) RETURNING suite_run_id INTO v_suite_run;

  INSERT INTO public.lf_test_runs(
    suite_run_id,suite_code,test_code,execution_id,operation_code,environment,application_version,commit_sha,
    executor_type,executor_name,status,input_payload,expected_output,actual_output,severity,
    started_at,completed_at,duration_ms,evidence_payload,metadata,created_by_execution_id
  )
  SELECT
    v_suite_run,tc.suite_code,tc.test_code,v_exec,'OPERATION_ENFORCEMENT_REGRESSION_SUITE_LF',
    'T01_DISPOSABLE_FIRETEST','candidate',v_revision,
    'DETERMINISTIC_PYTEST_FIRETEST','CURRENTNESS_EXACT_SOURCE_REGRESSION','PASS',tc.input_payload,tc.expected_output,
    tc.expected_output || CASE WHEN tc.test_code='CUR-NEG-004'
      THEN jsonb_build_object('zero_effect_on_failure',true)
      ELSE '{}'::jsonb END,
    tc.severity,clock_timestamp(),clock_timestamp(),1,
    jsonb_build_object(
      'source_regression','PASS',
      'source_revision',v_revision,
      'consumer_pr',877,
      'fixture_scope','DISPOSABLE_ONLY',
      'counterevidence',CASE WHEN tc.test_code='CUR-NEG-004'
        THEN jsonb_build_array('breaking_change_negative','missing_assessment_negative')
        ELSE '[]'::jsonb END,
      'zero_effect_on_failure',CASE WHEN tc.test_code='CUR-NEG-004' THEN true ELSE false END
    ),
    jsonb_build_object('firetest_fixture',true,'source_test_metadata',tc.metadata),v_exec
  FROM public.lf_test_suite_cases tc
  WHERE tc.suite_code='TS-CURRENTNESS-AUTHORITY-V1'
    AND tc.test_code IN (
      'CUR-DET-001','CUR-DET-002','CUR-DET-003','CUR-NEG-004',
      'CUR-REPLAY-005','CUR-EVID-006','CUR-INT-007'
    );
END
$seed$;

DO $assert$
DECLARE
  v_revision constant text := 'c56b20d7d34b3dc7e4cdf44af69d17253f3efc52';
  v_exec constant text := 'EXEC-T01-CURRENTNESS-FIRETEST-20260917-001';
  v_root jsonb;
  v_material jsonb;
  v_evidence jsonb;
  v_selective jsonb;
  v_replay jsonb;
  v_bypass jsonb;
  v_runner jsonb;
  v_semantic jsonb;
  v_id1 uuid;
  v_id2 uuid;
  v_count integer;
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.lf_test_runs
    WHERE suite_code='TS-CURRENTNESS-AUTHORITY-V1'
      AND test_code IN ('CUR-E2E-008','CUR-E2E-009','CUR-E2E-010','CUR-SEM-011','CUR-SEM-012')
      AND commit_sha=v_revision
  ) THEN
    RAISE EXCEPTION 'T01_FIRETEST_FORBIDDEN_GAP_EVIDENCE_PRESENT';
  END IF;

  v_material := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_MATERIAL_VALID_V1',1);
  v_evidence := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_EVIDENCE_BOUND_EXACT_V1',1);
  v_selective := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_SELECTIVE_INVALIDATION_V1',1);
  v_replay := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_RECEIPT_ANTI_REPLAY_V1',1);
  v_bypass := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_NO_BYPASS_BEFORE_EFFECT_V1',1);
  v_runner := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_REQUIRED_REAL_RUNNER_V1',1);
  v_semantic := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CUR_SEMANTIC_COMPATIBILITY_JUSTIFIED_V1',1);
  v_root := public.lf_assurance_claim_evaluate_v1('CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CURRENTNESS_AUTHORITY_ASSURED_V1',1);

  IF v_material->>'result' <> 'PASS' THEN
    RAISE EXCEPTION 'T01_FIRETEST_MATERIAL_EXPECTED_PASS:%',v_material;
  END IF;
  IF v_evidence->>'result' <> 'PASS' THEN
    RAISE EXCEPTION 'T01_FIRETEST_EVIDENCE_EXPECTED_PASS:%',v_evidence;
  END IF;
  IF v_selective->>'result' <> 'PASS' THEN
    RAISE EXCEPTION 'T01_FIRETEST_SELECTIVE_EXPECTED_PASS:%',v_selective;
  END IF;
  IF v_replay->>'result' <> 'UNPROVEN' THEN
    RAISE EXCEPTION 'T01_FIRETEST_REPLAY_EXPECTED_UNPROVEN:%',v_replay;
  END IF;
  IF v_bypass->>'result' <> 'UNPROVEN' THEN
    RAISE EXCEPTION 'T01_FIRETEST_BYPASS_EXPECTED_UNPROVEN:%',v_bypass;
  END IF;
  IF v_runner->>'result' <> 'UNPROVEN' THEN
    RAISE EXCEPTION 'T01_FIRETEST_RUNNER_EXPECTED_UNPROVEN:%',v_runner;
  END IF;
  IF v_semantic->>'result' <> 'UNPROVEN' THEN
    RAISE EXCEPTION 'T01_FIRETEST_SEMANTIC_EXPECTED_UNPROVEN:%',v_semantic;
  END IF;
  IF v_root->>'result' <> 'UNPROVEN' THEN
    RAISE EXCEPTION 'T01_FIRETEST_FALSE_PASS_ROOT_RESULT:%',v_root;
  END IF;

  v_id1 := public.lf_assurance_claim_evaluate_and_record_v1(
    'CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,v_exec,v_exec
  );
  v_id2 := public.lf_assurance_claim_evaluate_and_record_v1(
    'CAPABILITY','CURRENTNESS_AUTHORITY',v_revision,'CURRENTNESS_AUTHORITY_ASSURED_V1',1,v_exec,v_exec
  );

  IF v_id1 IS DISTINCT FROM v_id2 THEN
    RAISE EXCEPTION 'T01_FIRETEST_RECORDER_NOT_IDEMPOTENT first=% second=%',v_id1,v_id2;
  END IF;

  SELECT count(*) INTO v_count
  FROM public.lf_assurance_evaluations
  WHERE subject_type='CAPABILITY'
    AND subject_code='CURRENTNESS_AUTHORITY'
    AND subject_revision=v_revision
    AND claim_code='CURRENTNESS_AUTHORITY_ASSURED_V1'
    AND claim_version=1
    AND execution_id=v_exec;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'T01_FIRETEST_APPEND_ONLY_COUNT expected=1 actual=%',v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_assurance_evaluations
    WHERE evaluation_id=v_id1 AND result='UNPROVEN'
  ) THEN
    RAISE EXCEPTION 'T01_FIRETEST_RECORDED_RESULT_NOT_UNPROVEN';
  END IF;

  RAISE NOTICE 'T01_CURRENTNESS_CLAIM_FIRETEST=PASS root=UNPROVEN deterministic_subclaims=3 missing_surfaces=4 evaluation_id=%',v_id1;
END
$assert$;

SELECT jsonb_build_object(
  'firetest','PASS',
  'consumer','CURRENTNESS_AUTHORITY',
  'consumer_pr',877,
  'consumer_head','c56b20d7d34b3dc7e4cdf44af69d17253f3efc52',
  'evaluator_pr',879,
  'expected_root_result','UNPROVEN',
  'deterministic_subclaims_expected_pass',jsonb_build_array(
    'CUR_MATERIAL_VALID_V1','CUR_EVIDENCE_BOUND_EXACT_V1','CUR_SELECTIVE_INVALIDATION_V1'
  ),
  'expected_unproven_subclaims',jsonb_build_array(
    'CUR_RECEIPT_ANTI_REPLAY_V1','CUR_NO_BYPASS_BEFORE_EFFECT_V1',
    'CUR_REQUIRED_REAL_RUNNER_V1','CUR_SEMANTIC_COMPATIBILITY_JUSTIFIED_V1'
  )
) AS t01_firetest_summary;
