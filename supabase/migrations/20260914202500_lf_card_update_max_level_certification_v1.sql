-- LF_CARD_UPDATE_MAX_LEVEL_CERTIFICATION_V1
-- Runtime may adapt from L1..L4, but Card certification is valid only at the maximum L4/TOP_TIER level.
-- This patch tightens ACTUALIZACION_CARD_LF v0.3-candidate. No runtime, production, Router or promotion activation.

begin;

-- Fail closed unless the top-tier gate introduced by the immediately prior migration exists.
do $$
begin
  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code = 'ACTUALIZACION_CARD_LF'
      and version = 'v0.3-candidate'
      and lifecycle_state_code = 'OP_CANDIDATE'
      and status = 'CANDIDATO_READ_ONLY'
  ) then
    raise exception 'ACTUALIZACION_CARD_LF v0.3-candidate is required before max-level certification patch';
  end if;

  if not exists (
    select 1
    from public.lf_operation_step_contracts
    where operation_code = 'ACTUALIZACION_CARD_LF'
      and step_id = 'expertise_quality_gate'
      and contract_code = 'CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
      and status = 'CANDIDATO_READ_ONLY'
  ) then
    raise exception 'expertise_quality_gate v0.3 is required before max-level certification patch';
  end if;
end $$;

-- Adaptive depth is a runtime optimization only. Certification may never use L1-L3 as substitute evidence.
update public.lf_operation_contracts
set allowed = coalesce(allowed, '{}'::jsonb) || jsonb_build_object(
      'runtime_depth_policy', 'ADAPTIVE_L1_L4',
      'runtime_lower_levels_allowed', true,
      'certification_test_level', 'L4_TOP_TIER_ONLY',
      'max_level_test_required', true,
      'lower_levels_certification_eligible', false,
      'max_level_suite_minimum_cases', 5,
      'max_level_suite_required_case_families', jsonb_build_array(
        'CONFLICTING_OBJECTIVES',
        'INCOMPLETE_OR_AMBIGUOUS_EVIDENCE',
        'ADVERSARIAL_FALSIFICATION',
        'CROSS_DOMAIN_SECOND_ORDER_EFFECTS',
        'HIGH_IMPACT_DECISION'
      )
    ),
    blocked = coalesce(blocked, '[]'::jsonb) || jsonb_build_array(
      'lower_level_only_certification',
      'adaptive_runtime_result_used_as_certification_substitute',
      'max_level_suite_missing',
      'max_level_suite_incomplete',
      'max_level_case_not_l4_top_tier'
    ),
    required_before_write = coalesce(required_before_write, '[]'::jsonb) || jsonb_build_array(
      'max_level_l4_certification_pass'
    ),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-MAX-LEVEL-CERT-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and contract_code = 'CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
  and status = 'CANDIDATO_READ_ONLY';

-- The dedicated judge must reject any certification evidence produced below L4.
update public.lf_operation_judges
set pass_if = coalesce(pass_if, '[]'::jsonb) || jsonb_build_array(
      'certification_level=L4_TOP_TIER',
      'max_level_suite contains at least five cases',
      'max_level_suite covers conflicting objectives',
      'max_level_suite covers incomplete or ambiguous evidence',
      'max_level_suite covers adversarial falsification',
      'max_level_suite covers cross-domain second-order effects',
      'max_level_suite covers a high-impact decision',
      'every certification case is executed at L4_TOP_TIER',
      'all required max-level cases pass the top-tier thresholds',
      'L1-L3 evidence is informational only and not certification evidence'
    ),
    fail_if = coalesce(fail_if, '[]'::jsonb) || jsonb_build_array(
      'certification_level below L4_TOP_TIER',
      'any required certification case executed at L1 L2 or L3',
      'max-level suite has fewer than five cases',
      'required max-level case family missing',
      'adaptive routing downgrade accepted as certification',
      'one or more max-level cases fail top-tier thresholds'
    ),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-MAX-LEVEL-CERT-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and judge_code = 'JUDGE-CARD-EXPERTISE-TOP-TIER-v1'
  and status = 'CANDIDATO_READ_ONLY';

-- Evidence contract: explicitly bind the test level and the hardest-case suite.
update public.lf_operation_step_contracts
set output_payload = coalesce(output_payload, '[]'::jsonb) || jsonb_build_array(
      'certification_level',
      'max_level_suite',
      'max_level_suite_result',
      'adaptive_runtime_policy_verified'
    ),
    required_evidence_keys = coalesce(required_evidence_keys, '[]'::jsonb) || jsonb_build_array(
      'certification_level',
      'max_level_suite',
      'max_level_suite_result',
      'adaptive_runtime_policy_verified'
    ),
    pass_condition = coalesce(pass_condition, '{}'::jsonb) || jsonb_build_object(
      'certification_level', 'L4_TOP_TIER',
      'runtime_depth_policy', 'ADAPTIVE_L1_L4',
      'certification_uses_runtime_downgrade', false,
      'max_level_suite_minimum_cases', 5,
      'required_case_families', jsonb_build_array(
        'CONFLICTING_OBJECTIVES',
        'INCOMPLETE_OR_AMBIGUOUS_EVIDENCE',
        'ADVERSARIAL_FALSIFICATION',
        'CROSS_DOMAIN_SECOND_ORDER_EFFECTS',
        'HIGH_IMPACT_DECISION'
      ),
      'all_cases_must_use_level', 'L4_TOP_TIER',
      'all_cases_must_pass', true
    ),
    block_condition = coalesce(block_condition, '{}'::jsonb) || jsonb_build_object(
      'block_on_lower_certification_level', true,
      'block_on_missing_required_case_family', true,
      'block_on_any_max_level_case_failure', true,
      'block_on_runtime_downgrade_as_certification', true
    ),
    notes = concat_ws(' | ', nullif(notes,''), 'Certification is MAX-LEVEL ONLY: runtime may adapt L1-L4, but L1-L3 results can never certify a Card. All certification cases execute as L4_TOP_TIER.'),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-MAX-LEVEL-CERT-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and step_id = 'expertise_quality_gate'
  and contract_code = 'CONTRACT-ACTUALIZACION-CARD-LF-v0.3'
  and status = 'CANDIDATO_READ_ONLY';

update public.lf_operation_steps
set evidence_required = 'benchmark_version; assessor_mode; assessor_execution_id; dimension_scores; weighted_overall_score; minimum_dimension_score; commodity_baseline_comparison; falsification_cases; top_tier_verdict; evidence_refs; certification_level=L4_TOP_TIER; max_level_suite; max_level_suite_result; adaptive_runtime_policy_verified',
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-MAX-LEVEL-CERT-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and step_id = 'expertise_quality_gate'
  and step_order = 85
  and active = true;

update public.lf_operation_step_judge_bindings
set required_evidence_keys = coalesce(required_evidence_keys, '[]'::jsonb) || jsonb_build_array(
      'certification_level',
      'max_level_suite',
      'max_level_suite_result',
      'adaptive_runtime_policy_verified'
    ),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-MAX-LEVEL-CERT-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and step_id = 'expertise_quality_gate'
  and step_order = 85
  and judge_code = 'JUDGE-CARD-EXPERTISE-TOP-TIER-v1'
  and status = 'CANDIDATO_READ_ONLY';

update public.lf_operation_registry
set notes = concat_ws(' | ', nullif(notes,''), 'I8 MAX-LEVEL CERTIFICATION: runtime depth may adapt L1-L4 for efficiency, but Card qualification/certification must always execute the hardest L4_TOP_TIER suite. L1-L3 are never sufficient certification evidence.'),
    updated_at = now(),
    updated_by_execution_id = 'EXEC-CARD-UPDATE-I8-MAX-LEVEL-CERT-20260914-001'
where operation_code = 'ACTUALIZACION_CARD_LF'
  and version = 'v0.3-candidate'
  and lifecycle_state_code = 'OP_CANDIDATE'
  and status = 'CANDIDATO_READ_ONLY';

commit;
