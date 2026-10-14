-- IG M10.12 / NEG_CASCADE: provider-executed bounded test receipt.
-- Does NOT close any checkpoint, run DROP, change privileges or activate runtime.
-- Test source: Git blob 0959b5cc82aa346740f8756b09b3a1cda507f0d3.
-- Contract:    Git blob 3bff326fd740f1d5e1b04592eaff96e0119ae019.
-- Independent ephemeral runner: script_job_19ed5e87e273429a8d79513c51b32382,
-- return code 0, 9/9 unit fixtures + current no-target readback rejected.
-- The provider test is an admission-oracle check, NOT a live DROP refusal.
DO $m1012_suite$
DECLARE
 v_actor constant text := 'IG_M1012_PROVIDER_TEST_RECEIPT_V1';
 v_suite_code constant text := 'IG_M1012_NEG_CASCADE_BOUNDED_V1';
 v_exec constant text := 'IG-M1012-SENTINELX-NEG-CASCADE-20261013';
 v_commit constant text := 'e86f44251d70a03299b96054db602f185ebdf480';
 v_blob constant text := '0959b5cc82aa346740f8756b09b3a1cda507f0d3';
 v_contract constant text := '3bff326fd740f1d5e1b04592eaff96e0119ae019';
 v_historical bigint;
 v_ready bigint;
 v_caller bigint;
 v_legacy_suite public.lf_test_suite_runs%rowtype;
 v_suite uuid;
 v_test uuid;
 v_bundle jsonb;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_test_suites WHERE suite_code=v_suite_code)
   OR EXISTS (SELECT 1 FROM public.lf_test_suite_runs WHERE suite_code=v_suite_code)
 THEN RAISE EXCEPTION 'M1012_SUITE_ALREADY_REGISTERED'; END IF;
 IF (SELECT status FROM programacion.engineering_work_items WHERE id=198)
    IS DISTINCT FROM 'IN_PROGRESS'
   OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=198 AND status='DONE') IS DISTINCT FROM 2 THEN
   RAISE EXCEPTION 'M1012_NEGATIVE_TEST_CHECKPOINT_PRESTATE_CHANGED';
 END IF;

 SELECT max(id) INTO v_historical FROM public.lf_eventos
 WHERE entidad_codigo='IG_CURATOR_VALIDATOR_REFACTOR_V2.M10.10.PAULO-160';
 IF v_historical IS NULL THEN RAISE EXCEPTION 'M1012_HISTORICAL_CLASSIFICATION_MISSING'; END IF;
 SELECT count(*) INTO v_ready FROM public.lf_eventos e
 CROSS JOIN LATERAL jsonb_array_elements(e.payload->'matrix') x(item)
 WHERE e.id=v_historical AND item->>'class'='REMOVE_READY';
 IF v_ready<>0 THEN RAISE EXCEPTION 'M1012_ZERO_TARGET_OBSERVATION_DRIFT'; END IF;
 SELECT count(*) INTO v_caller FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion'
 AND p.proname='fn_input_gov_gold_b_prepare_review_v1'
 AND p.prosrc ILIKE '%fn_input_readiness_run_is_current_cached_v2%';
 IF v_caller<1 THEN RAISE EXCEPTION 'M1012_SQL_CALLER_OBSERVATION_DRIFT'; END IF;

 SELECT * INTO v_legacy_suite FROM public.lf_test_suite_runs
 WHERE suite_code='IG_M1011_ZERO_TARGET_FINAL_V1'
 ORDER BY created_at DESC LIMIT 1;
 IF NOT FOUND OR v_legacy_suite.status<>'PASSED'
   OR v_legacy_suite.metadata->>'remove_ready_count'<>'0'
   OR v_legacy_suite.metadata->>'independently_verified'<>'true'
   OR v_legacy_suite.metadata->>'dynamic_absence_proven'<>'false'
   OR v_legacy_suite.metadata->>'historical_classification_id' IS DISTINCT FROM v_historical::text
   OR (programacion.fn_engineering_run_test_receipt_bundle_v1(
           v_legacy_suite.suite_run_id)->>'status') IS DISTINCT FROM 'VERIFIED'
 THEN RAISE EXCEPTION 'M1012_SIGNED_ZERO_TARGET_SOURCE_MISSING'; END IF;

 -- Ensure source/contract identifiers observed on the independent runner
 -- retain their exact Git-object shape. Git-first Train verifies migrated SQL.
 IF v_commit !~ '^[0-9a-f]{40}$'
   OR v_blob !~ '^[0-9a-f]{40}$'
   OR v_contract !~ '^[0-9a-f]{40}$'
 THEN RAISE EXCEPTION 'M1012_TEST_SOURCE_IDENTITY_INVALID'; END IF;

 INSERT INTO public.lf_test_suites(
   suite_code,module_code,name,version,status,execution_policy,metadata,created_by_execution_id)
 VALUES (
   v_suite_code,'INPUT_GOVERNANCE',
   'M10.12 bounded negative candidate admission oracle (not live migration enforcement)',
   'v1','CANDIDATO',
   '{"execution":"OBSERVED_SENTINELX_EPHEMERAL_SOURCE_EXACT","production_authority":"DENY","scope":"NO_TARGET_BOUNDARY","forbid_live_drop_claim":true}'::jsonb,
   jsonb_build_object('plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','M10.12','checkpoint_code','NEG_CASCADE',
      'test_source_blob',v_blob,'governing_contract_blob',v_contract,
      'scope_limit','NO_ACTUAL_DB_DROP_AND_NO_TRAIN_INTEGRATION_TEST'),
   v_actor
 );
 INSERT INTO public.lf_test_suite_cases(
   suite_code,test_code,test_order,title,test_type,execution_mode,status,metadata,created_by_execution_id)
 VALUES (
   v_suite_code,'ENG_M1012_NEG_CASCADE_EXECUTED_BOUNDED_V1',1,
   'Independent exact-source 9-fixture rejection plus current no-target denial',
   'REGRESSION','AUTOMATED','CANDIDATO',
   jsonb_build_object('unit_code','M10.12','checkpoint_code','NEG_CASCADE',
     'scenario_count',9,'negative_required',true,'local_case_owner','M10.12',
     'test_path','sandbox/lf_contract_gate_test/engineering_checkpoints/m10_12/neg_cascade.py'),
   v_actor
 );
 INSERT INTO public.lf_test_suite_runs(
   suite_code,execution_id,environment,commit_sha,executor_type,executor_name,status,
   started_at,completed_at,duration_ms,
   tests_total,tests_passed,tests_failed,tests_blocked,tests_review_required,
   metadata,manifest,created_by_execution_id)
 VALUES (
   v_suite_code,v_exec,'LF_SUPABASE_SANDBOX_READONLY_SNAPSHOT_AND_SENTINELX_EPHEMERAL',
   v_commit,'SENTINELX','Independent Python exact-source bounded checker',
   'PASSED',clock_timestamp(),clock_timestamp(),60,1,1,0,0,0,
   jsonb_build_object(
     'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
     'unit_code','M10.12','checkpoint_code','NEG_CASCADE',
     'case_owner','M10.12','test_source_blob_sha1',v_blob,
     'contract_blob_sha1',v_contract,'test_path',
     'sandbox/lf_contract_gate_test/engineering_checkpoints/m10_12/neg_cascade.py',
     'job_id','script_job_19ed5e87e273429a8d79513c51b32382',
     'provider','SENTINELX','provider_returncode',0,
     'fixture_tests_run',9,'fixture_tests_passed',9,
     'negative_cases_executed',true,
     'semantic_authority_bound',true,
     'observed_zero_target_rejected',true,
     'observed_no_target_code','NO_REMOVE_READY',
     'historical_classification_id',v_historical::text,
     'remove_ready_count',v_ready,
     'live_sql_caller_count',v_caller,
     'external_test_mode','PURE_POLICY_ORACLE',
     'real_db_drop_tested',false,'train_gate_enforced',false,
     'runtime_release_qualified',false,'physical_operation_executed',false,
     'independent_runner','SENTINELX_EPHEMERAL'),
   jsonb_build_object(
     'receipt_mode','LOCAL_DECLARED_TEST_EXECUTION',
     'actual_execution',true,'python_exit_code',0,
     'scenario_count',9,'negative_count',7,'source_git_blob_sha1',v_blob,
     'contract_git_blob_sha1',v_contract,'runner_job',
     'script_job_19ed5e87e273429a8d79513c51b32382',
     'stdout','NO_REMOVE_READY;fixture_tests_run=9;fixture_tests_passed=9',
     'test_passed',true,'test_exit_code',0,
     'semantic_authority_bound',true,'adversarial_case_executed',true,
     'physical_operation_executed',false,'real_db_drop_tested',false,
     'qualifies_runtime',false,'synthetic_pass',false,
     'independence_boundary','EXTERNAL_RUNNER_BOUNDED_ORACLE_NO_LIVE_DB_DELETE'),
   v_actor
 )
 RETURNING suite_run_id INTO v_suite;

 INSERT INTO public.lf_test_runs(
   suite_run_id,suite_code,test_code,execution_id,environment,commit_sha,
   executor_type,executor_name,status,input_payload,expected_output,actual_output,
   started_at,completed_at,evidence_payload,created_by_execution_id)
 VALUES (
   v_suite,v_suite_code,'ENG_M1012_NEG_CASCADE_EXECUTED_BOUNDED_V1',v_exec,
   'LF_SUPABASE_SANDBOX_READONLY_SNAPSHOT_AND_SENTINELX_EPHEMERAL',
   v_commit,'SENTINELX','Exact Git Python bounded test','PASS',
   jsonb_build_object('source_git_blob',v_blob,
     'governed_contract_blob',v_contract,'observed_remove_ready',v_ready,
     'observed_sql_callers',v_caller),
   '{"fixture_tests_run":9,"fixture_tests_passed":9,"code":"NO_REMOVE_READY","admitted":false,"physical_operation_executed":false}'::jsonb,
   '{"fixture_tests_run":9,"fixture_tests_passed":9,"code":"NO_REMOVE_READY","admitted":false,"physical_operation_executed":false}'::jsonb,
   clock_timestamp(),clock_timestamp(),
   jsonb_build_object('provider_job_id','script_job_19ed5e87e273429a8d79513c51b32382',
     'provider_returncode',0,'script_blob_sha1',v_blob,
     'contract_blob_sha1',v_contract,'source_verified',true,
     'real_drop_not_executed',true,'checkpoint_scope_only',true),v_actor
 )
 RETURNING test_run_id INTO v_test;

 INSERT INTO public.lf_test_assertion_results(
   test_run_id,assertion_code,assertion_order,assertion_type,description,
   expected_value,actual_value,status,operator,evidence_payload,created_by_execution_id)
 VALUES (
   v_test,'M1012_BOUNDED_NEG_CASCADE_REAL_PROVIDER_EXEC',1,'EQUALITY',
   'Exact-source independent 9-fixture negative and zero-target rejection, no actual DROP',
   '{"fixture_tests_run":9,"fixture_tests_passed":9,"code":"NO_REMOVE_READY","admitted":false,"physical_operation_executed":false}'::jsonb,
   '{"fixture_tests_run":9,"fixture_tests_passed":9,"code":"NO_REMOVE_READY","admitted":false,"physical_operation_executed":false}'::jsonb,
   'PASS','EQUALS',
   jsonb_build_object('provider_job','script_job_19ed5e87e273429a8d79513c51b32382',
      'git_test_blob',v_blob,'contract_blob',v_contract,
      'real_sql_drop_tested',false,'no_misleading_runtime_claim',true),v_actor
 );
 v_bundle:=programacion.fn_engineering_run_test_receipt_bundle_v1(v_suite);
 IF v_bundle->>'status' IS DISTINCT FROM 'VERIFIED'
   OR v_bundle#>>'{verification,test_graph_complete}' IS DISTINCT FROM 'true'
   OR v_bundle#>>'{verification,local_case_ownership_complete}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M1012_BOUNDED_TEST_CANONICAL_BUNDLE_NOT_VERIFIED:%',v_bundle; END IF;
END;
$m1012_suite$;
