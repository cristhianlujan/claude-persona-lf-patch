-- IG M7.13: register observed Python regression as ONE script run containing 12 scenarios.
-- Source: SentinelX ephemeral host execution on 2026-10-09 (actual return code 0).
-- The result was verified against five Git blob SHA1s; no invented 12 separate test runs.
-- Code observed: PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=12 non_ig=3 ig=2 independence_gate=7 rollback_exact=4 negative_detected=9 domain_branches_in_core=0
DO $register$
DECLARE v_suite_id uuid;
DECLARE v_test_id uuid;
DECLARE v_bundle jsonb;
DECLARE v_actor text := 'CHATGPT_IG_M713_SENTINELX_PY_20261009';
BEGIN
  INSERT INTO public.lf_test_suites(
    suite_code,module_code,name,version,status,execution_policy,metadata,created_by_execution_id)
  VALUES (
    'IG_REVERSIBLE_CANDIDATE_ASSURANCE_2_0_1','INPUT_GOVERNANCE',
    'Reversible candidate verification: exact Git source Python 2.0.1 regression','v1',
    'CANDIDATO',
    '{"execution":"OBSERVED_SENTINELX_PYTHON","qualification_authority":"DENY_WITHOUT_VERIFIED_BUNDLE","production_authority":"DENY","promotion_approval":"SEPARATE"}'::jsonb,
    '{"plan_code":"IG_CURATOR_VALIDATOR_REFACTOR_V2","unit_code":"M7.13","checkpoint_code":"CRITERIA_AS_CONTROLS"}'::jsonb,v_actor)
  ON CONFLICT (suite_code) DO NOTHING;

  INSERT INTO public.lf_test_suite_cases(suite_code,test_code,test_order,title,test_type,execution_mode,status,metadata,created_by_execution_id)
  VALUES (
    'IG_REVERSIBLE_CANDIDATE_ASSURANCE_2_0_1',
    'ENG_M713_ASSURANCE_201_PY_REGRESSION',1,
    'Python 2.0.1 complete regression: positive + negative + exact rollback',
    'REGRESSION','AUTOMATED','CANDIDATO',
    '{"unit_code":"M7.13","checkpoint_code":"CRITERIA_AS_CONTROLS","scenario_count":12,"single_script_execution":true}'::jsonb,v_actor)
  ON CONFLICT (suite_code,test_code) DO NOTHING;

  SELECT suite_run_id INTO v_suite_id
  FROM public.lf_test_suite_runs
  WHERE suite_code='IG_REVERSIBLE_CANDIDATE_ASSURANCE_2_0_1'
    AND execution_id='CHATGPT_IG_M713_SENTINELX_PY_20261009'
  LIMIT 1;

  IF v_suite_id IS NULL THEN
    INSERT INTO public.lf_test_suite_runs (
      suite_code,execution_id,environment,commit_sha,executor_type,executor_name,status,
      started_at,completed_at,duration_ms,
      tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,
      metadata,manifest,created_by_execution_id)
    VALUES (
      'IG_REVERSIBLE_CANDIDATE_ASSURANCE_2_0_1',v_actor,'SCALORA_TEMP_EPHEMERAL',
      '1170883a9ff524c0176a78151778ff0fe695d647',
      'SENTINELX','SentinelX python3 isolated temporary workdir',
      'PASSED',now(),now(),80,1,1,0,0,0,
      jsonb_build_object(
        'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
        'unit_code','M7.13','checkpoint_code','CRITERIA_AS_CONTROLS',
        'scenario_count',12,
        'source_blob_sha1','b619ea4238e4a97867b29447f9f80e5ac8079151',
        'test_blob_sha1','6647b86a71c9489f276e53e013e839310e486163',
        'provider_version','2.0.1',
        'host_id','host_3d5ff6fb467d4e9e',
        'observed_source','sentinelx://scalora-vps/script_job_e685b727ae754722a355ca4c9e39faa6',
        'observation','ACTUAL_PYTHON_EXIT_0_GIT_BLOBS_VERIFIED'
      ),
      jsonb_build_object(
        'receipt_mode','LOCAL_DECLARED_TEST_EXECUTION','python_exit_code',0,
        'scenario_count',12,'test_source_commit','1170883a9ff524c0176a78151778ff0fe695d647',
        'python_version','3.10.12',
        'runner_stdout','PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=12 non_ig=3 ig=2 independence_gate=7 rollback_exact=4 negative_detected=9 domain_branches_in_core=0',
        'git_blob_sha1',jsonb_build_object(
          'source','b619ea4238e4a97867b29447f9f80e5ac8079151',
          'test','6647b86a71c9489f276e53e013e839310e486163',
          'non_ig_adapter','e87253f0037a1b80648ea4f0816b6c0435c9f55c',
          'ig_adapter','feb877298f7064f69cf8312b241daa49b60e5111',
          'ig_oracle','964eab08b75868b2fdfe4a035dd40f46e63b6575'
        ),
        'synthetic_pass',false,'actual_execution',true,'local_script_run_count',1,
        'runner_transport','SENTINELX_EPHEMERAL'
      ),v_actor
    ) RETURNING suite_run_id INTO v_suite_id;
  END IF;

  INSERT INTO public.lf_test_runs (
    suite_run_id,suite_code,test_code,execution_id,environment,commit_sha,
    executor_type,executor_name,status,input_payload,expected_output,actual_output,
    started_at,completed_at,evidence_payload,created_by_execution_id)
  SELECT v_suite_id,'IG_REVERSIBLE_CANDIDATE_ASSURANCE_2_0_1',
    'ENG_M713_ASSURANCE_201_PY_REGRESSION',v_actor,'SCALORA_TEMP_EPHEMERAL',
    '1170883a9ff524c0176a78151778ff0fe695d647',
    'SENTINELX','SentinelX Python 3.10.12','PASS',
    '{"require_exact_git_blobs":true,"script":"test_reversible_candidate_verification_v1.py"}'::jsonb,
    '{"exit_code":0,"scenario_count":12}'::jsonb,
    '{"exit_code":0,"scenario_count":12,"test_passed":true,"stderr":"","stdout":"PASS_REVERSIBLE_CANDIDATE_VERIFICATION_V1 cases=12 non_ig=3 ig=2 independence_gate=7 rollback_exact=4 negative_detected=9 domain_branches_in_core=0"}'::jsonb,
    now(),now(),
    '{"provider":"SENTINELX","audit_ref":"sentinelx://scalora-vps/script_job_e685b727ae754722a355ca4c9e39faa6","temporary_directory_cleaned":true}'::jsonb,
    v_actor
  WHERE NOT EXISTS(
    SELECT 1 FROM public.lf_test_runs WHERE suite_run_id=v_suite_id
      AND test_code='ENG_M713_ASSURANCE_201_PY_REGRESSION')
  RETURNING test_run_id INTO v_test_id;
  IF v_test_id IS NULL THEN
    SELECT test_run_id INTO STRICT v_test_id FROM public.lf_test_runs
     WHERE suite_run_id=v_suite_id AND test_code='ENG_M713_ASSURANCE_201_PY_REGRESSION';
  END IF;

  INSERT INTO public.lf_test_assertion_results (
    test_run_id,assertion_code,assertion_order,assertion_type,description,
    expected_value,actual_value,status,operator,evidence_payload,created_by_execution_id)
  SELECT v_test_id,'PYTHON_SCRIPT_EXIT_0_AND_12_CASES',1,'EQUALITY',
    'Exact Git Python suite completes all twelve internal assertions, no stderr',
    '{"exit_code":0,"scenario_count":12,"test_passed":true}'::jsonb,
    '{"exit_code":0,"scenario_count":12,"test_passed":true}'::jsonb,
    'PASS','EQUALS',
    '{"source":"SENTINELX_EPHEMERAL","stdout_confirmed":true,"git_blobs_verified":5}'::jsonb,
    v_actor
  WHERE NOT EXISTS (
    SELECT 1 FROM public.lf_test_assertion_results
    WHERE test_run_id=v_test_id AND assertion_code='PYTHON_SCRIPT_EXIT_0_AND_12_CASES');

  v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite_id);
  IF v_bundle->>'status' IS DISTINCT FROM 'VERIFIED' THEN
    RAISE EXCEPTION 'IG_M713_PYTHON_RECEIPT_BUNDLE_INCOMPLETE:%',v_bundle;
  END IF;
END
$register$;
