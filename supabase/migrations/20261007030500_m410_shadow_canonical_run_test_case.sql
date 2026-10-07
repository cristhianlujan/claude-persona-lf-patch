-- M4.10 / SHADOW_BY_MODULE canonical RUN_TEST case.
-- Root cause: action_spec requires exact canonical cases, but none existed for this checkpoint.

insert into public.lf_test_suite_cases(
  suite_code,
  test_code,
  test_order,
  story_code,
  rule_codes,
  title,
  test_type,
  execution_mode,
  severity,
  preconditions,
  input_payload,
  expected_output,
  prohibited_output,
  status,
  metadata,
  created_by_execution_id,
  updated_by_execution_id
)
values(
  'INPUT_GOVERNANCE_REGRESSION',
  'ENGINEERING_T_EQUIV_SHADOW_CORPUS',
  410030,
  null,
  array[]::text[],
  'M4.10 SHADOW_BY_MODULE — T-EQUIV corpus 1,43,58',
  'QUALIFICATION',
  'AUTOMATED',
  'HIGH',
  jsonb_build_array(
    'CONTROL_EQUIVALENCE_JUDGE current exact manifest is bound with a fresh receipt',
    'Execute programacion.fn_input_governance_shadow_evaluate_v2 only on screens 1,43,58',
    'Persist real RUN_TEST evidence; synthetic PASS is forbidden'
  ),
  jsonb_build_object(
    'schema_version','ENGINEERING_T_EQUIV_SHADOW_CORPUS_V1',
    'capability_code','CONTROL_EQUIVALENCE_JUDGE',
    'screen_ids',jsonb_build_array(1,43,58),
    'comparison_only',true,
    'domain_mutation',false,
    'diff_adjudication','NEXT_CHECKPOINT'
  ),
  jsonb_build_object(
    'shadow_contract','ENGINEERING_T_EQUIV_CORPUS_V1',
    'screen_count',3,
    'domain_mutation',false,
    'diff_adjudication','NEXT_CHECKPOINT',
    'fresh_t_equiv_binding_receipt',true
  ),
  jsonb_build_object(
    'synthetic_pass',true,
    'domain_mutation',true,
    'reuse_old_binding_as_current_receipt',true,
    'fallback_case_discovery',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'plan_code','IG_CURATOR_VALIDATOR_REFACTOR_V2',
    'unit_code','M4.10',
    'work_code','PAULO-137',
    'checkpoint_code','SHADOW_BY_MODULE',
    'capability_code','CONTROL_EQUIVALENCE_JUDGE',
    'contract','DECLARED_CAPABILITY_SHADOW_V1'
  ),
  'ENGINEERING-M4.10-SHADOW-CASE-20261007',
  'ENGINEERING-M4.10-SHADOW-CASE-20261007'
)
on conflict (suite_code,test_code)
do update set
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
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

update public.lf_error_knowledge
set evidencia=concat_ws(E'\n',nullif(evidencia,''),'[M4_10_SHADOW_CASE_20261007] Canonical RUN_TEST case ENGINEERING_T_EQUIV_SHADOW_CORPUS added for M4.10/SHADOW_BY_MODULE; eliminates ENGINEERING_RUN_TEST_NO_CANONICAL_CASES.'),
    ultima_vez=now(),
    updated_at=now()
where codigo='ENGINEERING-EXECUTION-PACKET-001';
