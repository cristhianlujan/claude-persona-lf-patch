-- S36 WP06 — Cards I8 pre-promotion assurance in the one canonical LF Test Matrix.
-- Phase A only. No Router registration, no OPERATION_LIFECYCLE promotion, no runtime/production/Golden activation.
-- Deterministic structure/currentness is evaluated in DB; semantic/I8/E2E evidence remains REVIEW_REQUIRED
-- until a distinct governed reviewer records strict PASS judges and finalizes the qualification receipt.

insert into public.lf_test_suites(
  suite_code,module_code,name,version,status,rule_set_code,execution_policy,metadata,
  created_by_execution_id,updated_by_execution_id
) values (
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1',
  'LF_TEST_ASSURANCE',
  'ACTUALIZACION_CARD_LF I8 pre-promotion assurance',
  'v1',
  'CANDIDATO',
  null,
  '{"deterministic_first":true,"false_pass_tolerance":0,"independent_review_required":true,"phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE","router_required":false,"owner_promotion_allowed":false}'::jsonb,
  '{"canonical_matrix":"S36_CANONICAL_LF_TEST_MATRIX","family":"CARDS","process":"CARD_UPDATE","source_owner":"CARD_OPERATIONS","assurance_owner":"S36","intake_code":"S36-INTAKE-CARD-UPDATE-I8-E2E-ASSURANCE-001","source_operation":"ACTUALIZACION_CARD_LF","source_operation_state":"OP_CANDIDATE","dimension":["FUNCIONALIDAD","CALIDAD","PROFUNDIDAD"],"no_parallel_matrix":true,"no_router_activation":true,"no_runtime_change":true,"no_production_change":true,"no_golden_change":true}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001',
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
)
on conflict (suite_code) do update set
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
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-01',10,null,'{}'::text[],
  'Operation lifecycle state is catalog-valid before assurance',
  'DETERMINISTIC','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"probe_code":"OP_REGISTRY_STATE_VALID"}'::jsonb,
  '{"passed":true}'::jsonb,
  '{"forbidden":["unknown_lifecycle_state","missing_registry_entry"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"FUNCIONALIDAD","depth":"STATEFUL_SEQUENCE","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-02',20,null,'{}'::text[],
  'Canonical required assurance binding is present',
  'DETERMINISTIC','AUTOMATED','CRITICAL','[]'::jsonb,
  '{"probe_code":"QUALIFICATION_BINDING_PRESENT"}'::jsonb,
  '{"passed":true}'::jsonb,
  '{"forbidden":["zero_required_binding","parallel_matrix_binding"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"FUNCIONALIDAD","depth":"REQUIRED_STEP_REACHABILITY","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-03',30,null,'{}'::text[],
  'I8 L4 top-tier expertise positive path',
  'SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[]'::jsonb,
  '{"probe_code":"INDEPENDENT_REVIEW","review_case":"I8_L4_TOP_TIER_POSITIVE","validator":"public.lf_validate_card_expertise_gate_v1","expected_level":"L4_TOP_TIER"}'::jsonb,
  '{"verdict":"PASS","outcome":"CARD_EXPERTISE_TOP_TIER_EXACT"}'::jsonb,
  '{"forbidden":["self_assessment","commodity_only","level_below_L4","missing_evidence"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"CALIDAD","depth":"EDGE","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE","evidence_policy":"RECONSTRUCTIBLE_INDEPENDENT"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-04',40,null,'{}'::text[],
  'I8 rejects commodity baseline that does not beat the baseline',
  'SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[]'::jsonb,
  '{"probe_code":"INDEPENDENT_REVIEW","review_case":"I8_COMMODITY_NEGATIVE","validator":"public.lf_validate_card_expertise_gate_v1"}'::jsonb,
  '{"verdict":"PASS","expected_block":"EXPERTISE_COMMODITY_BASELINE_NOT_BEATEN"}'::jsonb,
  '{"forbidden":["false_pass_commodity"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"CALIDAD","depth":"NEGATIVE","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-05',50,null,'{}'::text[],
  'I8 rejects self-assessment as independent expertise evidence',
  'SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[]'::jsonb,
  '{"probe_code":"INDEPENDENT_REVIEW","review_case":"I8_SELF_ASSESSMENT_NEGATIVE","validator":"public.lf_validate_card_expertise_gate_v1"}'::jsonb,
  '{"verdict":"PASS","expected_block":"EXPERTISE_ASSESSOR_MODE_INVALID"}'::jsonb,
  '{"forbidden":["producer_as_independent_assessor","self_review_pass"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"CALIDAD","depth":"NEGATIVE","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-06',60,null,'{}'::text[],
  'I8 rejects L1-L3 downgrade for a case requiring L4',
  'SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[]'::jsonb,
  '{"probe_code":"INDEPENDENT_REVIEW","review_case":"I8_L1_L3_DOWNGRADE_NEGATIVE","validator":"public.lf_validate_card_expertise_gate_v1"}'::jsonb,
  '{"verdict":"PASS","expected_block":"EXPERTISE_MAX_LEVEL_CASE_DOWNGRADED"}'::jsonb,
  '{"forbidden":["accept_L1","accept_L2","accept_L3"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"CALIDAD","depth":"NEGATIVE","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-07',70,null,'{}'::text[],
  'Full controlled Card update E2E passes prewrite through governed write and exact readback',
  'SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[]'::jsonb,
  '{"probe_code":"INDEPENDENT_REVIEW","review_case":"FULL_OPERATION_E2E_PREPROMOTION","required_path":["prewrite_currentness","expertise_step_85","governed_write","exact_readback","deterministic_validation","semantic_judge","regression_after"]}'::jsonb,
  '{"verdict":"PASS","write_readback":"EXACT","bypass":false}'::jsonb,
  '{"forbidden":["direct_write_bypass","skip_expertise_step_85","stale_prewrite","missing_readback","semantic_judge_omitted"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"FUNCIONALIDAD","depth":"PATH_TRAJECTORY","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE","owner_gate_note":"Recorder ceiling >85 remains owner-controlled; S36 must not open it itself."}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
),
(
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1','CARD-I8-08',80,null,'{}'::text[],
  'Independent holdout confirms Card update assurance without producer self-review',
  'SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[]'::jsonb,
  '{"probe_code":"INDEPENDENT_REVIEW","review_case":"INDEPENDENT_HOLDOUT","requires_distinct_reviewer":true,"requires_reconstructible_evidence":true,"requires_exact_revision":true}'::jsonb,
  '{"verdict":"PASS","independence":"VERIFIED","currentness":"EXACT_REVISION"}'::jsonb,
  '{"forbidden":["producer_as_reviewer","evidence_only_assertion","stale_revision","pass_with_restrictions_as_pass"]}'::jsonb,
  'CANDIDATO',
  '{"dimension":"PROFUNDIDAD","depth":"PATH_TRAJECTORY","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE","judge_type":"INDEPENDENT_HOLDOUT"}'::jsonb,
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001','EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
)
on conflict (suite_code,test_code) do update set
  test_order=excluded.test_order,
  story_code=excluded.story_code,
  rule_codes=excluded.rule_codes,
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

insert into public.lf_test_requirement_bindings(
  binding_code,subject_type,subject_code,characteristic_code,suite_code,required,min_pass_rate,
  false_pass_tolerance,independent_review_required,rollback_required,currentness_mode,
  activation_condition,effective_from,status,created_by_execution_id,updated_by_execution_id
) values (
  'BIND-OP-CARD-UPDATE-I8-PREPROMOTION-V1',
  'OPERATION',
  'ACTUALIZACION_CARD_LF',
  null,
  'TS-CARD-OP-UPDATE-I8-PREPROMOTION-V1',
  true,
  1.00000,
  0,
  true,
  false,
  'EXACT_REVISION',
  '{"type":"ALWAYS","phase":"PHASE_A_S36_PREPROMOTION_ASSURANCE","router_not_required_pre_promotion":true}'::jsonb,
  clock_timestamp(),
  'ACTIVE',
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001',
  'EXEC-S36-INTAKE-CARD-UPDATE-I8-ASSURANCE-20260914-001'
)
on conflict (binding_code) do update set
  subject_type=excluded.subject_type,
  subject_code=excluded.subject_code,
  characteristic_code=excluded.characteristic_code,
  suite_code=excluded.suite_code,
  required=excluded.required,
  min_pass_rate=excluded.min_pass_rate,
  false_pass_tolerance=excluded.false_pass_tolerance,
  independent_review_required=excluded.independent_review_required,
  rollback_required=excluded.rollback_required,
  currentness_mode=excluded.currentness_mode,
  activation_condition=excluded.activation_condition,
  effective_from=least(public.lf_test_requirement_bindings.effective_from,excluded.effective_from),
  status=excluded.status,
  updated_at=clock_timestamp(),
  updated_by_execution_id=excluded.updated_by_execution_id;
