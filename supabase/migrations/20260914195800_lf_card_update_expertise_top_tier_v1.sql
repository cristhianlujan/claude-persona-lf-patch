-- LF_CARD_UPDATE_EXPERTISE_TOP_TIER_V1
-- Purpose: prevent technically valid but professionally shallow/commodity Card updates from being written.
-- Internal benchmark naming is neutral: TOP_TIER, not institution-specific.
-- Scope: ACTUALIZACION_CARD_LF candidate only. No runtime, production or automatic promotion.

begin;

-- Guard: this patch is only valid on the existing Card update candidate.
do $$
begin
  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code = 'ACTUALIZACION_CARD_LF'
      and lifecycle_state_code = 'OP_CANDIDATE'
      and status = 'CANDIDATO_READ_ONLY'
  ) then
    raise exception 'ACTUALIZACION_CARD_LF must remain OP_CANDIDATE/CANDIDATO_READ_ONLY before expertise gate patch';
  end if;
end $$;

-- Version the candidate contract without changing lifecycle state.
update public.lf_operation_contracts
set status = 'SUPERSEDED',
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and contract_code = 'CONTRACT-ACTUALIZACION-CARD-LF-v0.2'
  and status = 'CANDIDATO_READ_ONLY';

insert into public.lf_operation_contracts (
  operation_code,
  contract_code,
  contract_path,
  contract_sha,
  required_before_write,
  allowed,
  blocked,
  required_after_write,
  status,
  created_at,
  updated_at,
  created_by_execution_id,
  updated_by_execution_id
)
select
  c.operation_code,
  'CONTRACT-ACTUALIZACION-CARD-LF-v0.3',
  'public.lf_operation_contracts/ACTUALIZACION_CARD_LF/CONTRACT-ACTUALIZACION-CARD-LF-v0.3',
  null,
  c.required_before_write || jsonb_build_array('expertise_quality_gate_pass'),
  coalesce(c.allowed, '{}'::jsonb) || jsonb_build_object(
    'professional_quality_benchmark', true,
    'expertise_benchmark_code', 'CARD_EXPERTISE_TOP_TIER_V1',
    'expertise_gate_before_write', true,
    'expertise_assessment_mode', 'INDEPENDENT_HOLDOUT_OR_S36_ASSURANCE'
  ),
  coalesce(c.blocked, '[]'::jsonb) || jsonb_build_array(
    'expertise_quality_below_threshold',
    'commodity_quality_only',
    'self_assessment_only',
    'expertise_evidence_missing'
  ),
  c.required_after_write,
  'CANDIDATO_READ_ONLY',
  now(),
  now(),
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001',
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
from public.lf_operation_contracts c
where c.operation_code = 'ACTUALIZACION_CARD_LF'
  and c.contract_code = 'CONTRACT-ACTUALIZACION-CARD-LF-v0.2'
on conflict (operation_code, contract_code) do update
set required_before_write = excluded.required_before_write,
    allowed = excluded.allowed,
    blocked = excluded.blocked,
    required_after_write = excluded.required_after_write,
    status = excluded.status,
    updated_at = now(),
    updated_by_execution_id = excluded.updated_by_execution_id;

-- New independent professional-depth judge.
insert into public.lf_operation_judges (
  operation_code,
  judge_code,
  judge_path,
  judge_sha,
  pass_if,
  fail_if,
  result_values,
  status,
  created_at,
  updated_at,
  created_by_execution_id,
  updated_by_execution_id
) values (
  'ACTUALIZACION_CARD_LF',
  'JUDGE-CARD-EXPERTISE-TOP-TIER-v1',
  'supabase://public/lf_operation_judges/ACTUALIZACION_CARD_LF/JUDGE-CARD-EXPERTISE-TOP-TIER-v1',
  null,
  jsonb_build_array(
    'benchmark_version=CARD_EXPERTISE_TOP_TIER_V1',
    'assessor_mode is INDEPENDENT_HOLDOUT or S36_ASSURANCE',
    'assessor_execution_id differs from producer execution',
    'all eight dimension scores are numeric in range 1..5',
    'weighted overall_score >= 4.25',
    'minimum_dimension_score >= 4.00',
    'commodity_baseline_comparison demonstrates materially better decision quality',
    'at least three falsification/adversarial cases evaluated',
    'top_tier_verdict=TOP_TIER_PASS',
    'evidence_refs present and reconstructible'
  ),
  jsonb_build_array(
    'self assessment only',
    'missing independent assessor identity',
    'overall_score < 4.25',
    'any dimension score < 4.00',
    'generic or commodity reasoning',
    'no exception/risk coverage',
    'no decision-quality improvement versus commodity baseline',
    'fewer than three falsification/adversarial cases',
    'benchmark evidence missing or non-reconstructible',
    'top_tier_verdict not TOP_TIER_PASS'
  ),
  jsonb_build_object(
    'pass','TOP_TIER_PASS',
    'blocked','BLOCKED_EXPERTISE_BELOW_TOP_TIER',
    'return','RETURN_TO_WORKER_FOR_EXPERTISE_REFINEMENT'
  ),
  'CANDIDATO_READ_ONLY',
  now(),
  now(),
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001',
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
)
on conflict (operation_code, judge_code) do update
set pass_if = excluded.pass_if,
    fail_if = excluded.fail_if,
    result_values = excluded.result_values,
    status = excluded.status,
    updated_at = now(),
    updated_by_execution_id = excluded.updated_by_execution_id;

-- Insert required expertise gate between pre-write binding (80) and write dispatch (90).
insert into public.lf_operation_steps (
  operation_code,
  step_order,
  step_id,
  required,
  evidence_required,
  source_path,
  source_sha,
  active,
  created_at,
  updated_at,
  execution_order,
  created_by_execution_id,
  updated_by_execution_id
) values (
  'ACTUALIZACION_CARD_LF',
  85,
  'expertise_quality_gate',
  true,
  'benchmark_version; assessor_mode; assessor_execution_id; dimension_scores; weighted_overall_score; minimum_dimension_score; commodity_baseline_comparison; falsification_cases; top_tier_verdict; evidence_refs',
  'public.lf_operation_step_contracts/ACTUALIZACION_CARD_LF/expertise_quality_gate',
  null,
  true,
  now(),
  now(),
  85,
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001',
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
)
on conflict (operation_code, step_order) do update
set step_id = excluded.step_id,
    required = excluded.required,
    evidence_required = excluded.evidence_required,
    source_path = excluded.source_path,
    active = excluded.active,
    execution_order = excluded.execution_order,
    updated_at = now(),
    updated_by_execution_id = excluded.updated_by_execution_id;

-- Re-point all candidate step contracts to v0.3 and insert the new step contract.
update public.lf_operation_step_contracts
set contract_code = 'CONTRACT-ACTUALIZACION-CARD-LF-v0.3',
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and status = 'CANDIDATO_READ_ONLY';

-- Existing step 80 must now pass through expertise before any write.
update public.lf_operation_step_contracts
set next_if_pass = 'expertise_quality_gate',
    notes = concat_ws(' | ', nullif(notes,''), 'I8: write is forbidden until CARD_EXPERTISE_TOP_TIER_V1 returns TOP_TIER_PASS.'),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and step_id = 'pre_write_execution_binding_gate'
  and status = 'CANDIDATO_READ_ONLY';

insert into public.lf_operation_step_contracts (
  operation_code,
  step_id,
  step_order,
  execution_order,
  contract_code,
  purpose,
  input_required,
  resolver_ref,
  output_payload,
  pass_condition,
  block_condition,
  blocking_code,
  mini_judge_code,
  required_evidence_keys,
  next_if_pass,
  next_if_blocked,
  status,
  notes,
  created_at,
  updated_at,
  execution_sql,
  fail_condition,
  created_by_execution_id,
  updated_by_execution_id
) values (
  'ACTUALIZACION_CARD_LF',
  'expertise_quality_gate',
  85,
  85,
  'CONTRACT-ACTUALIZACION-CARD-LF-v0.3',
  'Evaluate proposed Card content against a top-tier professional benchmark before any write.',
  jsonb_build_array('proposed_card_content','change_scope','regression_plan','pre_write_execution_binding_gate'),
  'GPT_RUNTIME_WITH_SUPABASE_CONTEXT',
  jsonb_build_array(
    'benchmark_version',
    'assessor_mode',
    'assessor_execution_id',
    'dimension_scores',
    'weighted_overall_score',
    'minimum_dimension_score',
    'commodity_baseline_comparison',
    'falsification_cases',
    'top_tier_verdict',
    'evidence_refs'
  ),
  jsonb_build_object(
    'benchmark_code','CARD_EXPERTISE_TOP_TIER_V1',
    'required_level','TOP_TIER',
    'scale_min',1,
    'scale_max',5,
    'weighted_overall_min',4.25,
    'minimum_dimension_min',4.00,
    'required_dimensions',jsonb_build_array(
      'domain_depth',
      'critical_reasoning',
      'exception_coverage',
      'decision_quality',
      'noncommodity_value',
      'adversarial_challenge',
      'interdisciplinary_connection',
      'operational_actionability'
    ),
    'weights',jsonb_build_object(
      'domain_depth',0.18,
      'critical_reasoning',0.16,
      'exception_coverage',0.14,
      'decision_quality',0.18,
      'noncommodity_value',0.12,
      'adversarial_challenge',0.08,
      'interdisciplinary_connection',0.07,
      'operational_actionability',0.07
    ),
    'minimum_falsification_cases',3,
    'independent_assessment_required',true
  ),
  jsonb_build_object(
    'block_on_any',jsonb_build_array(
      'SELF_ASSESSMENT_ONLY',
      'OVERALL_BELOW_4_25',
      'ANY_DIMENSION_BELOW_4_00',
      'COMMODITY_ONLY',
      'MISSING_FALSIFICATION',
      'MISSING_RECONSTRUCTIBLE_EVIDENCE'
    )
  ),
  'BLOCKED_ACTUALIZACION_CARD_LF_EXPERTISE_NOT_TOP_TIER',
  'JUDGE-CARD-EXPERTISE-TOP-TIER-v1',
  jsonb_build_array(
    'benchmark_version',
    'assessor_mode',
    'assessor_execution_id',
    'dimension_scores',
    'weighted_overall_score',
    'minimum_dimension_score',
    'commodity_baseline_comparison',
    'falsification_cases',
    'top_tier_verdict',
    'evidence_refs'
  ),
  'carrier_write_dispatch',
  'RETURN_TO_WORKER_FOR_EXPERTISE_REFINEMENT',
  'CANDIDATO_READ_ONLY',
  'User-facing analogy may compare university/professional levels, but canonical governance uses neutral TOP_TIER benchmark naming. This gate evaluates professional depth, not institutional prestige.',
  now(),
  now(),
  null,
  jsonb_build_object(
    'fail_if',jsonb_build_array(
      'overall_score < 4.25',
      'minimum_dimension_score < 4.00',
      'self assessment only',
      'commodity baseline not materially exceeded',
      'fewer than three falsification cases',
      'evidence not reconstructible'
    )
  ),
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001',
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
)
on conflict (operation_code, step_id) do update
set step_order = excluded.step_order,
    execution_order = excluded.execution_order,
    contract_code = excluded.contract_code,
    purpose = excluded.purpose,
    input_required = excluded.input_required,
    resolver_ref = excluded.resolver_ref,
    output_payload = excluded.output_payload,
    pass_condition = excluded.pass_condition,
    block_condition = excluded.block_condition,
    blocking_code = excluded.blocking_code,
    mini_judge_code = excluded.mini_judge_code,
    required_evidence_keys = excluded.required_evidence_keys,
    next_if_pass = excluded.next_if_pass,
    next_if_blocked = excluded.next_if_blocked,
    status = excluded.status,
    notes = excluded.notes,
    fail_condition = excluded.fail_condition,
    updated_at = now(),
    updated_by_execution_id = excluded.updated_by_execution_id;

insert into public.lf_operation_step_judge_bindings (
  operation_code,
  step_order,
  step_id,
  judge_code,
  clean_result_value,
  blocked_result_value,
  return_result_value,
  required_evidence_keys,
  status,
  created_at,
  updated_at,
  created_by_execution_id,
  updated_by_execution_id
) values (
  'ACTUALIZACION_CARD_LF',
  85,
  'expertise_quality_gate',
  'JUDGE-CARD-EXPERTISE-TOP-TIER-v1',
  'TOP_TIER_PASS',
  'BLOCKED_EXPERTISE_BELOW_TOP_TIER',
  'RETURN_TO_WORKER_FOR_EXPERTISE_REFINEMENT',
  jsonb_build_array(
    'benchmark_version',
    'assessor_mode',
    'assessor_execution_id',
    'dimension_scores',
    'weighted_overall_score',
    'minimum_dimension_score',
    'commodity_baseline_comparison',
    'falsification_cases',
    'top_tier_verdict',
    'evidence_refs'
  ),
  'CANDIDATO_READ_ONLY',
  now(),
  now(),
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001',
  'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
)
on conflict (operation_code, step_order, step_id) do update
set judge_code = excluded.judge_code,
    clean_result_value = excluded.clean_result_value,
    blocked_result_value = excluded.blocked_result_value,
    return_result_value = excluded.return_result_value,
    required_evidence_keys = excluded.required_evidence_keys,
    status = excluded.status,
    updated_at = now(),
    updated_by_execution_id = excluded.updated_by_execution_id;

-- Keep the operation candidate/read-only, only advance its contract version.
update public.lf_operation_registry
set version = 'v0.3-candidate',
    notes = concat_ws(' | ', nullif(notes,''), 'I8: adds mandatory pre-write CARD_EXPERTISE_TOP_TIER_V1 independent benchmark; top-tier requires weighted overall >=4.25, every dimension >=4.00, commodity-baseline superiority and falsification evidence. No runtime/production/promotion authorization.'),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-EXPERTISE-GATE-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and lifecycle_state_code = 'OP_CANDIDATE'
  and status = 'CANDIDATO_READ_ONLY';

-- Structural assertions. Fail closed if the gate is not truly inserted before write.
do $$
declare
  v_required boolean;
  v_next text;
  v_contract text;
  v_judge text;
begin
  select required into v_required
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF' and step_order=85 and step_id='expertise_quality_gate' and active=true;

  select next_if_pass into v_next
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_CARD_LF' and step_id='pre_write_execution_binding_gate';

  select contract_code into v_contract
  from public.lf_operation_contracts
  where operation_code='ACTUALIZACION_CARD_LF' and status='CANDIDATO_READ_ONLY';

  select judge_code into v_judge
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_CARD_LF' and step_order=85 and step_id='expertise_quality_gate';

  if v_required is distinct from true
     or v_next is distinct from 'expertise_quality_gate'
     or v_contract is distinct from 'CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
     or v_judge is distinct from 'JUDGE-CARD-EXPERTISE-TOP-TIER-v1' then
    raise exception 'Card expertise gate structural assertion failed';
  end if;
end $$;

commit;
