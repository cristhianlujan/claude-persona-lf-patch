-- S36 WP06 — enroll the S26 PR merge-base regression into the one canonical LF Test Matrix.
-- Source-first catalog migration. This does not create a parallel matrix, does not alter runtime,
-- and deliberately does not create lf_test_requirement_bindings because the current DB qualification
-- runner only executes lf_eval_strategy_matrix_probe_v1 probes and would not execute this GitHub/CI regression faithfully.

insert into public.lf_test_suites(
  suite_code,module_code,name,version,status,rule_set_code,execution_policy,metadata,
  created_by_execution_id,updated_by_execution_id
) values (
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1',
  'LF_TEST_ASSURANCE',
  'S26 PR merge-base and candidate-parent regression',
  'v1',
  'CANDIDATO',
  null,
  '{"deterministic_first":true,"false_pass_tolerance":0,"execution_authority":"GITHUB_ACTIONS_REAL_GOVERNED","db_matrix_runner_applicable":false,"normalized_ci_evidence_required":true}'::jsonb,
  '{"matrix_family":"TRANSVERSAL_REGRESSION","canonical_matrix":"S36_CANONICAL_LF_TEST_MATRIX","family":"RUNTIME_GOVERNANCE","process":"S26_PR_COMMIT_READBACK_BINDING","source_owner":"S26","assurance_owner":"S36","intake_code":"S36-INTAKE-S26-PR-MERGE-BASE-DRIFT-001","source_test":"sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/test_s26_commit_readback_pr_merge_base_drift.py","source_guard":"sandbox/lf_contract_gate_test/profile_runtime_structural_context_v3/test_s26_commit_readback_binding.py","dimension":"PROFUNDIDAD","assurance_depth":"PATH_TRAJECTORY","promotion_state":"AUTOMATION_VERIFIED_PENDING_NORMALIZED_CI_EVIDENCE","no_runtime_change":true,"no_production_change":true,"no_golden_change":true}'::jsonb,
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001',
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001'
) on conflict (suite_code) do update set
  module_code=excluded.module_code,
  name=excluded.name,
  version=excluded.version,
  status=excluded.status,
  rule_set_code=excluded.rule_set_code,
  execution_policy=excluded.execution_policy,
  metadata=excluded.metadata,
  updated_at=clock_timestamp(),
  updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_test_suite_cases(
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,execution_mode,severity,
  preconditions,input_payload,expected_output,prohibited_output,status,metadata,
  created_by_execution_id,updated_by_execution_id
) values
(
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26-MB-01',10,null,'{}',
  'Forward-only event-base drift preserves exact candidate parent',
  'DETERMINISTIC','REAL_GOVERNED','CRITICAL','{}',
  '{"case":"historical_forward_main_drift","executor":"GITHUB_ACTIONS","source_test":"test_s26_commit_readback_pr_merge_base_drift.py"}',
  '{"result":"PASS","policy":"ALLOW_FORWARD_ONLY_BASE_DRIFT_WITH_EXACT_CANDIDATE_PARENT"}',
  '{"forbidden":["accept_divergent_base","accept_candidate_parent_mismatch"]}',
  'CANDIDATO',
  '{"dimension":"PROFUNDIDAD","primary_depth":"PATH_TRAJECTORY","polarity":"POSITIVE","source_owner":"S26","assurance_owner":"S36"}',
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001','EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001'
),
(
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26-MB-02',20,null,'{}',
  'Exact event base remains a positive path',
  'DETERMINISTIC','REAL_GOVERNED','CRITICAL','{}',
  '{"case":"exact_event_base","executor":"GITHUB_ACTIONS","source_test":"test_s26_commit_readback_pr_merge_base_drift.py"}',
  '{"result":"PASS","resolved_base":"EVENT_BASE"}',
  '{"forbidden":["false_block_exact_base"]}',
  'CANDIDATO',
  '{"dimension":"PROFUNDIDAD","primary_depth":"PATH_TRAJECTORY","polarity":"POSITIVE","source_owner":"S26","assurance_owner":"S36"}',
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001','EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001'
),
(
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26-MB-03',30,null,'{}',
  'Candidate parent mismatch fails closed',
  'NEGATIVE_CANARY','REAL_GOVERNED','CRITICAL','{}',
  '{"case":"candidate_parent_mismatch","executor":"GITHUB_ACTIONS","source_test":"test_s26_commit_readback_pr_merge_base_drift.py"}',
  '{"blocking_code":"S26_SHA_BINDING_PR_EVENT_CANDIDATE_PARENT_MISMATCH"}',
  '{"forbidden":["PASS","silent_accept"]}',
  'CANDIDATO',
  '{"dimension":"PROFUNDIDAD","primary_depth":"NEGATIVE","secondary_depths":["PATH_TRAJECTORY"],"polarity":"NEGATIVE","source_owner":"S26","assurance_owner":"S36"}',
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001','EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001'
),
(
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26-MB-04',40,null,'{}',
  'Divergent PR base fails closed',
  'NEGATIVE_CANARY','REAL_GOVERNED','CRITICAL','{}',
  '{"case":"divergent_base","executor":"GITHUB_ACTIONS","source_test":"test_s26_commit_readback_pr_merge_base_drift.py"}',
  '{"blocking_code":"S26_SHA_BINDING_PR_EVENT_BASE_NOT_ANCESTOR_OF_CHECKOUT_BASE"}',
  '{"forbidden":["PASS","silent_accept"]}',
  'CANDIDATO',
  '{"dimension":"PROFUNDIDAD","primary_depth":"NEGATIVE","secondary_depths":["PATH_TRAJECTORY"],"polarity":"NEGATIVE","source_owner":"S26","assurance_owner":"S36"}',
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001','EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001'
),
(
  'TS-S36-S26-PR-MERGE-BASE-DRIFT-V1','S26-MB-05',50,null,'{}',
  'Invalid candidate parent count fails closed',
  'NEGATIVE_CANARY','REAL_GOVERNED','CRITICAL','{}',
  '{"case":"parent_count","executor":"GITHUB_ACTIONS","source_test":"test_s26_commit_readback_pr_merge_base_drift.py"}',
  '{"blocking_code":"S26_SHA_BINDING_PR_MERGE_PARENT_COUNT_INVALID"}',
  '{"forbidden":["PASS","silent_accept"]}',
  'CANDIDATO',
  '{"dimension":"PROFUNDIDAD","primary_depth":"NEGATIVE","secondary_depths":["PATH_TRAJECTORY"],"polarity":"NEGATIVE","source_owner":"S26","assurance_owner":"S36"}',
  'EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001','EXEC-S36-WP06-S26-CANONICAL-CATALOG-20260914-001'
)
on conflict (suite_code,test_code) do update set
  test_order=excluded.test_order,
  title=excluded.title,
  test_type=excluded.test_type,
  execution_mode=excluded.execution_mode,
  severity=excluded.severity,
  preconditions=excluded.preconditions,
  input_payload=excluded.input_payload,
  expected_output=excluded.expected_output,
  prohibited_output=excluded.prohibited_output,
  status=excluded.status,
  metadata=excluded.metadata,
  updated_at=clock_timestamp(),
  updated_by_execution_id=excluded.updated_by_execution_id;
