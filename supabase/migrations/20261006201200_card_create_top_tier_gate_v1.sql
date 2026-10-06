-- CARD_CREATE_TOP_TIER_GATE_V1
-- Extends the existing CARD_EXPERTISE_TOP_TIER_V1 validator to Card creation.
-- CREATE requires a closed INDEPENDENT_ASSURANCE receipt bound to exact subject_revision_sha256.
-- The existing pre-write step is tightened; no new workflow engine or step-order mutation.
-- No runtime or production activation.

CREATE OR REPLACE FUNCTION public.lf_validate_card_expertise_gate_v1(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_assessor public.lf_operation_execution%rowtype;
  v_assessor_exists boolean := false;
  v_dims jsonb;
  v_suite jsonb;
  v_case jsonb;
  v_falsification jsonb;
  v_refs jsonb;
  v_keys text[] := array[
    'domain_depth','critical_reasoning','exception_coverage','decision_quality',
    'noncommodity_value','adversarial_challenge','interdisciplinary_connection','operational_actionability'
  ];
  v_weights numeric[] := array[0.18,0.16,0.14,0.18,0.12,0.08,0.07,0.07];
  v_i integer;
  v_score numeric;
  v_weighted numeric := 0;
  v_min numeric := 5;
  v_family text;
  v_has_conflicting boolean := false;
  v_has_ambiguous boolean := false;
  v_has_adversarial boolean := false;
  v_has_cross_domain boolean := false;
  v_has_high_impact boolean := false;
  v_assertions jsonb := jsonb_build_array(
    'benchmark_version=CARD_EXPERTISE_TOP_TIER_V1',
    'assessor_mode is INDEPENDENT_HOLDOUT or INDEPENDENT_REVIEW or S36_ASSURANCE',
    'assessor_execution_id differs from producer execution',
    'all eight dimension scores are numeric in range 1..5',
    'weighted overall_score >= 4.25',
    'minimum_dimension_score >= 4.00',
    'commodity_baseline_comparison demonstrates materially better decision quality',
    'at least three falsification/adversarial cases evaluated',
    'certification_level=L4_TOP_TIER',
    'max_level_suite contains at least five cases',
    'max_level_suite covers conflicting objectives',
    'max_level_suite covers incomplete or ambiguous evidence',
    'max_level_suite covers adversarial falsification',
    'max_level_suite covers cross-domain second-order effects',
    'max_level_suite covers a high-impact decision',
    'every certification case is executed at L4_TOP_TIER',
    'all required max-level cases pass top-tier thresholds',
    'L1-L3 evidence is informational only and not certification evidence',
    'top_tier_verdict=TOP_TIER_PASS',
    'evidence_refs present and reconstructible'
  );
begin
  if p_step_id is distinct from 'expertise_quality_gate' then
    return jsonb_build_object(
      'valid',false,'code','EXPERTISE_GATE_STEP_ID_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible')
    );
  end if;

  select * into v_execution
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or v_execution.operation_code not in ('ACTUALIZACION_CARD_LF','CREACION_CARD_LF')
     or v_execution.target_type is distinct from 'CARD'
     or v_execution.status is distinct from 'IN_PROGRESS' then
    return jsonb_build_object(
      'valid',false,'code','EXPERTISE_GATE_EXECUTION_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible')
    );
  end if;

  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object(
      'valid',false,'code','EXPERTISE_GATE_PAYLOAD_INVALID',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible')
    );
  end if;

  if (p_evidence_payload->>'benchmark_version') is distinct from 'CARD_EXPERTISE_TOP_TIER_V1' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_BENCHMARK_VERSION_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  if coalesce(p_evidence_payload->>'assessor_mode','') not in ('INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW','S36_ASSURANCE') then
    return jsonb_build_object('valid',false,'code','EXPERTISE_ASSESSOR_MODE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('self assessment only'));
  end if;

  if nullif(btrim(p_evidence_payload->>'assessor_execution_id'),'') is null
     or (p_evidence_payload->>'assessor_execution_id') is not distinct from p_execution_id then
    return jsonb_build_object('valid',false,'code','EXPERTISE_ASSESSOR_NOT_INDEPENDENT','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('missing independent assessor identity'));
  end if;

  select * into v_assessor
  from public.lf_operation_execution
  where execution_id=p_evidence_payload->>'assessor_execution_id';

  v_assessor_exists:=found;

  if not v_assessor_exists then
    return jsonb_build_object('valid',false,'code','EXPERTISE_ASSESSOR_EXECUTION_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('missing independent assessor identity'));
  end if;

  if v_execution.operation_code='CREACION_CARD_LF' then
    if v_assessor.operation_code<>'ORQUESTACION_PIPELINE_LF'
       or v_assessor.target_type<>'CAPABILITY'
       or v_assessor.target_code<>'INDEPENDENT_ASSURANCE'
       or coalesce(v_assessor.manifest->>'capability_code','')<>'INDEPENDENT_ASSURANCE'
       or v_assessor.status not in ('COMPLETED','CONTROLLED_READ_ONLY_PASS','CLOSED_WITH_VERIFIED_EVIDENCE')
       or coalesce(v_assessor.manifest->>'subject_revision_sha256','') !~ '^[0-9a-f]{64}

  if (p_evidence_payload->>'certification_level') is distinct from 'L4_TOP_TIER' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CERTIFICATION_LEVEL_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('certification_level below L4_TOP_TIER'));
  end if;

  if p_evidence_payload->'adaptive_runtime_policy_verified' is distinct from 'true'::jsonb then
    return jsonb_build_object('valid',false,'code','EXPERTISE_RUNTIME_POLICY_NOT_VERIFIED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('adaptive routing downgrade accepted as certification'));
  end if;

  if (p_evidence_payload->>'top_tier_verdict') is distinct from 'TOP_TIER_PASS' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_VERDICT_NOT_TOP_TIER','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('top_tier_verdict not TOP_TIER_PASS'));
  end if;

  v_dims:=p_evidence_payload->'dimension_scores';
  if jsonb_typeof(v_dims) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSIONS_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  for v_i in 1..array_length(v_keys,1) loop
    if not (v_dims ? v_keys[v_i]) or jsonb_typeof(v_dims->v_keys[v_i]) is distinct from 'number' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_SCORE_MISSING_OR_NONNUMERIC','dimension',v_keys[v_i],'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    v_score:=(v_dims->>v_keys[v_i])::numeric;
    if v_score < 1 or v_score > 5 then
      return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_SCORE_OUT_OF_RANGE','dimension',v_keys[v_i],'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    v_weighted:=v_weighted+(v_score*v_weights[v_i]);
    v_min:=least(v_min,v_score);
  end loop;

  v_weighted:=round(v_weighted,4);
  v_min:=round(v_min,4);

  if v_weighted < 4.25 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_OVERALL_BELOW_TOP_TIER','recomputed_weighted_overall_score',v_weighted,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('overall_score < 4.25'));
  end if;

  if v_min < 4.00 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_BELOW_TOP_TIER','recomputed_minimum_dimension_score',v_min,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('any dimension score < 4.00'));
  end if;

  if jsonb_typeof(p_evidence_payload->'weighted_overall_score') is distinct from 'number'
     or abs((p_evidence_payload->>'weighted_overall_score')::numeric-v_weighted) > 0.0001
     or jsonb_typeof(p_evidence_payload->'minimum_dimension_score') is distinct from 'number'
     or abs((p_evidence_payload->>'minimum_dimension_score')::numeric-v_min) > 0.0001 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CALLER_SCORE_MISMATCH','recomputed_weighted_overall_score',v_weighted,'recomputed_minimum_dimension_score',v_min,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  if jsonb_typeof(p_evidence_payload->'commodity_baseline_comparison') is distinct from 'object'
     or p_evidence_payload->'commodity_baseline_comparison'->'materially_better' is distinct from 'true'::jsonb
     or (p_evidence_payload->'commodity_baseline_comparison'->>'baseline_kind') is distinct from 'COMMODITY' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_COMMODITY_BASELINE_NOT_BEATEN','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('no decision-quality improvement versus commodity baseline'));
  end if;

  v_falsification:=p_evidence_payload->'falsification_cases';
  if jsonb_typeof(v_falsification) is distinct from 'array' or jsonb_array_length(v_falsification) < 3 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_FALSIFICATION_INSUFFICIENT','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('fewer than three falsification/adversarial cases'));
  end if;

  v_refs:=p_evidence_payload->'evidence_refs';
  if jsonb_typeof(v_refs) is distinct from 'array' or jsonb_array_length(v_refs) < 1 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_REFS_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  if v_execution.operation_code='CREACION_CARD_LF'
     and not exists (
       select 1
       from jsonb_array_elements_text(v_refs) r(ref)
       where r.ref='Execution:'||(p_evidence_payload->>'assessor_execution_id')
     ) then
    return jsonb_build_object(
      'valid',false,'code','EXPERTISE_CREATE_ASSURANCE_REF_MISSING',
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible')
    );
  end if;

  v_suite:=p_evidence_payload->'max_level_suite';
  if jsonb_typeof(v_suite) is distinct from 'array' or jsonb_array_length(v_suite) < 5 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_SUITE_TOO_SMALL','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('max-level suite has fewer than five cases'));
  end if;

  for v_case in select value from jsonb_array_elements(v_suite) loop
    if jsonb_typeof(v_case) is distinct from 'object' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    if (v_case->>'level') is distinct from 'L4_TOP_TIER' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_DOWNGRADED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('any required certification case executed at L1 L2 or L3'));
    end if;
    if (v_case->>'result') is distinct from 'TOP_TIER_PASS'
       or jsonb_typeof(v_case->'weighted_overall_score') is distinct from 'number'
       or (v_case->>'weighted_overall_score')::numeric < 4.25
       or jsonb_typeof(v_case->'minimum_dimension_score') is distinct from 'number'
       or (v_case->>'minimum_dimension_score')::numeric < 4.00 then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_FAILED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('one or more max-level cases fail top-tier thresholds'));
    end if;
    v_family:=v_case->>'case_family';
    v_has_conflicting:=v_has_conflicting or v_family='CONFLICTING_OBJECTIVES';
    v_has_ambiguous:=v_has_ambiguous or v_family='INCOMPLETE_OR_AMBIGUOUS_EVIDENCE';
    v_has_adversarial:=v_has_adversarial or v_family='ADVERSARIAL_FALSIFICATION';
    v_has_cross_domain:=v_has_cross_domain or v_family='CROSS_DOMAIN_SECOND_ORDER_EFFECTS';
    v_has_high_impact:=v_has_high_impact or v_family='HIGH_IMPACT_DECISION';
  end loop;

  if not (v_has_conflicting and v_has_ambiguous and v_has_adversarial and v_has_cross_domain and v_has_high_impact) then
    return jsonb_build_object('valid',false,'code','EXPERTISE_REQUIRED_CASE_FAMILY_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('required max-level case family missing'));
  end if;

  if (p_evidence_payload->>'max_level_suite_result') is distinct from 'PASS_ALL_L4_TOP_TIER' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_SUITE_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('one or more max-level cases fail top-tier thresholds'));
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_EXPERTISE_TOP_TIER_EXACT',
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object(
      'recomputed_weighted_overall_score',v_weighted,
      'recomputed_minimum_dimension_score',v_min,
      'max_level_suite_count',jsonb_array_length(v_suite),
      'falsification_case_count',jsonb_array_length(v_falsification)
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
end;
$function$

       or coalesce(v_assessor.manifest->>'subject_revision_sha256','') <> coalesce(p_evidence_payload->>'subject_revision_sha256','') then
      return jsonb_build_object(
        'valid',false,'code','EXPERTISE_CREATE_ASSURANCE_RECEIPT_INVALID',
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('missing independent assessor identity','benchmark evidence missing or non-reconstructible')
      );
    end if;

    if coalesce(p_evidence_payload->>'subject_revision_sha256','') !~ '^[0-9a-f]{64}

  if (p_evidence_payload->>'certification_level') is distinct from 'L4_TOP_TIER' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CERTIFICATION_LEVEL_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('certification_level below L4_TOP_TIER'));
  end if;

  if p_evidence_payload->'adaptive_runtime_policy_verified' is distinct from 'true'::jsonb then
    return jsonb_build_object('valid',false,'code','EXPERTISE_RUNTIME_POLICY_NOT_VERIFIED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('adaptive routing downgrade accepted as certification'));
  end if;

  if (p_evidence_payload->>'top_tier_verdict') is distinct from 'TOP_TIER_PASS' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_VERDICT_NOT_TOP_TIER','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('top_tier_verdict not TOP_TIER_PASS'));
  end if;

  v_dims:=p_evidence_payload->'dimension_scores';
  if jsonb_typeof(v_dims) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSIONS_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  for v_i in 1..array_length(v_keys,1) loop
    if not (v_dims ? v_keys[v_i]) or jsonb_typeof(v_dims->v_keys[v_i]) is distinct from 'number' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_SCORE_MISSING_OR_NONNUMERIC','dimension',v_keys[v_i],'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    v_score:=(v_dims->>v_keys[v_i])::numeric;
    if v_score < 1 or v_score > 5 then
      return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_SCORE_OUT_OF_RANGE','dimension',v_keys[v_i],'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    v_weighted:=v_weighted+(v_score*v_weights[v_i]);
    v_min:=least(v_min,v_score);
  end loop;

  v_weighted:=round(v_weighted,4);
  v_min:=round(v_min,4);

  if v_weighted < 4.25 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_OVERALL_BELOW_TOP_TIER','recomputed_weighted_overall_score',v_weighted,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('overall_score < 4.25'));
  end if;

  if v_min < 4.00 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_BELOW_TOP_TIER','recomputed_minimum_dimension_score',v_min,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('any dimension score < 4.00'));
  end if;

  if jsonb_typeof(p_evidence_payload->'weighted_overall_score') is distinct from 'number'
     or abs((p_evidence_payload->>'weighted_overall_score')::numeric-v_weighted) > 0.0001
     or jsonb_typeof(p_evidence_payload->'minimum_dimension_score') is distinct from 'number'
     or abs((p_evidence_payload->>'minimum_dimension_score')::numeric-v_min) > 0.0001 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CALLER_SCORE_MISMATCH','recomputed_weighted_overall_score',v_weighted,'recomputed_minimum_dimension_score',v_min,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  if jsonb_typeof(p_evidence_payload->'commodity_baseline_comparison') is distinct from 'object'
     or p_evidence_payload->'commodity_baseline_comparison'->'materially_better' is distinct from 'true'::jsonb
     or (p_evidence_payload->'commodity_baseline_comparison'->>'baseline_kind') is distinct from 'COMMODITY' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_COMMODITY_BASELINE_NOT_BEATEN','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('no decision-quality improvement versus commodity baseline'));
  end if;

  v_falsification:=p_evidence_payload->'falsification_cases';
  if jsonb_typeof(v_falsification) is distinct from 'array' or jsonb_array_length(v_falsification) < 3 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_FALSIFICATION_INSUFFICIENT','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('fewer than three falsification/adversarial cases'));
  end if;

  v_refs:=p_evidence_payload->'evidence_refs';
  if jsonb_typeof(v_refs) is distinct from 'array' or jsonb_array_length(v_refs) < 1 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_REFS_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  v_suite:=p_evidence_payload->'max_level_suite';
  if jsonb_typeof(v_suite) is distinct from 'array' or jsonb_array_length(v_suite) < 5 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_SUITE_TOO_SMALL','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('max-level suite has fewer than five cases'));
  end if;

  for v_case in select value from jsonb_array_elements(v_suite) loop
    if jsonb_typeof(v_case) is distinct from 'object' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    if (v_case->>'level') is distinct from 'L4_TOP_TIER' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_DOWNGRADED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('any required certification case executed at L1 L2 or L3'));
    end if;
    if (v_case->>'result') is distinct from 'TOP_TIER_PASS'
       or jsonb_typeof(v_case->'weighted_overall_score') is distinct from 'number'
       or (v_case->>'weighted_overall_score')::numeric < 4.25
       or jsonb_typeof(v_case->'minimum_dimension_score') is distinct from 'number'
       or (v_case->>'minimum_dimension_score')::numeric < 4.00 then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_FAILED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('one or more max-level cases fail top-tier thresholds'));
    end if;
    v_family:=v_case->>'case_family';
    v_has_conflicting:=v_has_conflicting or v_family='CONFLICTING_OBJECTIVES';
    v_has_ambiguous:=v_has_ambiguous or v_family='INCOMPLETE_OR_AMBIGUOUS_EVIDENCE';
    v_has_adversarial:=v_has_adversarial or v_family='ADVERSARIAL_FALSIFICATION';
    v_has_cross_domain:=v_has_cross_domain or v_family='CROSS_DOMAIN_SECOND_ORDER_EFFECTS';
    v_has_high_impact:=v_has_high_impact or v_family='HIGH_IMPACT_DECISION';
  end loop;

  if not (v_has_conflicting and v_has_ambiguous and v_has_adversarial and v_has_cross_domain and v_has_high_impact) then
    return jsonb_build_object('valid',false,'code','EXPERTISE_REQUIRED_CASE_FAMILY_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('required max-level case family missing'));
  end if;

  if (p_evidence_payload->>'max_level_suite_result') is distinct from 'PASS_ALL_L4_TOP_TIER' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_SUITE_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('one or more max-level cases fail top-tier thresholds'));
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_EXPERTISE_TOP_TIER_EXACT',
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object(
      'recomputed_weighted_overall_score',v_weighted,
      'recomputed_minimum_dimension_score',v_min,
      'max_level_suite_count',jsonb_array_length(v_suite),
      'falsification_case_count',jsonb_array_length(v_falsification)
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
end;
$function$
 then
      return jsonb_build_object(
        'valid',false,'code','EXPERTISE_CREATE_SUBJECT_REVISION_INVALID',
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible')
      );
    end if;
  end if;

  if (p_evidence_payload->>'certification_level') is distinct from 'L4_TOP_TIER' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CERTIFICATION_LEVEL_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('certification_level below L4_TOP_TIER'));
  end if;

  if p_evidence_payload->'adaptive_runtime_policy_verified' is distinct from 'true'::jsonb then
    return jsonb_build_object('valid',false,'code','EXPERTISE_RUNTIME_POLICY_NOT_VERIFIED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('adaptive routing downgrade accepted as certification'));
  end if;

  if (p_evidence_payload->>'top_tier_verdict') is distinct from 'TOP_TIER_PASS' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_VERDICT_NOT_TOP_TIER','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('top_tier_verdict not TOP_TIER_PASS'));
  end if;

  v_dims:=p_evidence_payload->'dimension_scores';
  if jsonb_typeof(v_dims) is distinct from 'object' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSIONS_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  for v_i in 1..array_length(v_keys,1) loop
    if not (v_dims ? v_keys[v_i]) or jsonb_typeof(v_dims->v_keys[v_i]) is distinct from 'number' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_SCORE_MISSING_OR_NONNUMERIC','dimension',v_keys[v_i],'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    v_score:=(v_dims->>v_keys[v_i])::numeric;
    if v_score < 1 or v_score > 5 then
      return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_SCORE_OUT_OF_RANGE','dimension',v_keys[v_i],'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    v_weighted:=v_weighted+(v_score*v_weights[v_i]);
    v_min:=least(v_min,v_score);
  end loop;

  v_weighted:=round(v_weighted,4);
  v_min:=round(v_min,4);

  if v_weighted < 4.25 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_OVERALL_BELOW_TOP_TIER','recomputed_weighted_overall_score',v_weighted,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('overall_score < 4.25'));
  end if;

  if v_min < 4.00 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_DIMENSION_BELOW_TOP_TIER','recomputed_minimum_dimension_score',v_min,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('any dimension score < 4.00'));
  end if;

  if jsonb_typeof(p_evidence_payload->'weighted_overall_score') is distinct from 'number'
     or abs((p_evidence_payload->>'weighted_overall_score')::numeric-v_weighted) > 0.0001
     or jsonb_typeof(p_evidence_payload->'minimum_dimension_score') is distinct from 'number'
     or abs((p_evidence_payload->>'minimum_dimension_score')::numeric-v_min) > 0.0001 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CALLER_SCORE_MISMATCH','recomputed_weighted_overall_score',v_weighted,'recomputed_minimum_dimension_score',v_min,'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  if jsonb_typeof(p_evidence_payload->'commodity_baseline_comparison') is distinct from 'object'
     or p_evidence_payload->'commodity_baseline_comparison'->'materially_better' is distinct from 'true'::jsonb
     or (p_evidence_payload->'commodity_baseline_comparison'->>'baseline_kind') is distinct from 'COMMODITY' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_COMMODITY_BASELINE_NOT_BEATEN','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('no decision-quality improvement versus commodity baseline'));
  end if;

  v_falsification:=p_evidence_payload->'falsification_cases';
  if jsonb_typeof(v_falsification) is distinct from 'array' or jsonb_array_length(v_falsification) < 3 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_FALSIFICATION_INSUFFICIENT','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('fewer than three falsification/adversarial cases'));
  end if;

  v_refs:=p_evidence_payload->'evidence_refs';
  if jsonb_typeof(v_refs) is distinct from 'array' or jsonb_array_length(v_refs) < 1 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_REFS_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
  end if;

  v_suite:=p_evidence_payload->'max_level_suite';
  if jsonb_typeof(v_suite) is distinct from 'array' or jsonb_array_length(v_suite) < 5 then
    return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_SUITE_TOO_SMALL','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('max-level suite has fewer than five cases'));
  end if;

  for v_case in select value from jsonb_array_elements(v_suite) loop
    if jsonb_typeof(v_case) is distinct from 'object' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;
    if (v_case->>'level') is distinct from 'L4_TOP_TIER' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_DOWNGRADED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('any required certification case executed at L1 L2 or L3'));
    end if;
    if (v_case->>'result') is distinct from 'TOP_TIER_PASS'
       or jsonb_typeof(v_case->'weighted_overall_score') is distinct from 'number'
       or (v_case->>'weighted_overall_score')::numeric < 4.25
       or jsonb_typeof(v_case->'minimum_dimension_score') is distinct from 'number'
       or (v_case->>'minimum_dimension_score')::numeric < 4.00 then
      return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_CASE_FAILED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('one or more max-level cases fail top-tier thresholds'));
    end if;
    v_family:=v_case->>'case_family';
    v_has_conflicting:=v_has_conflicting or v_family='CONFLICTING_OBJECTIVES';
    v_has_ambiguous:=v_has_ambiguous or v_family='INCOMPLETE_OR_AMBIGUOUS_EVIDENCE';
    v_has_adversarial:=v_has_adversarial or v_family='ADVERSARIAL_FALSIFICATION';
    v_has_cross_domain:=v_has_cross_domain or v_family='CROSS_DOMAIN_SECOND_ORDER_EFFECTS';
    v_has_high_impact:=v_has_high_impact or v_family='HIGH_IMPACT_DECISION';
  end loop;

  if not (v_has_conflicting and v_has_ambiguous and v_has_adversarial and v_has_cross_domain and v_has_high_impact) then
    return jsonb_build_object('valid',false,'code','EXPERTISE_REQUIRED_CASE_FAMILY_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('required max-level case family missing'));
  end if;

  if (p_evidence_payload->>'max_level_suite_result') is distinct from 'PASS_ALL_L4_TOP_TIER' then
    return jsonb_build_object('valid',false,'code','EXPERTISE_MAX_LEVEL_SUITE_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('one or more max-level cases fail top-tier thresholds'));
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CARD_EXPERTISE_TOP_TIER_EXACT',
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb,
    'details',jsonb_build_object(
      'recomputed_weighted_overall_score',v_weighted,
      'recomputed_minimum_dimension_score',v_min,
      'max_level_suite_count',jsonb_array_length(v_suite),
      'falsification_case_count',jsonb_array_length(v_falsification)
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
end;
$function$


CREATE OR REPLACE FUNCTION public.lf_creation_factory_trust_validation_v1(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  e public.lf_operation_execution%rowtype;
  s public.lf_operation_steps%rowtype;
  c public.lf_operation_step_contracts%rowtype;
  b public.lf_operation_step_judge_bindings%rowtype;
  j public.lf_operation_judges%rowtype;
  v_parity jsonb;
  v_missing text[] := array[]::text[];
  v_key text;
  v_assertions jsonb := '[]'::jsonb;
  v_hard jsonb := '[]'::jsonb;
  v_prior_missing integer := 0;
  v_prior_bad integer := 0;
  v_pred_bad integer := 0;
  v_contract_sha text;
  v_prewrite public.lf_operation_execution_steps%rowtype;
  v_prewrite_binding public.lf_operation_step_judge_bindings%rowtype;
  v_write public.lf_operation_execution_steps%rowtype;
  v_write_binding public.lf_operation_step_judge_bindings%rowtype;
  v_write_plan jsonb;
  v_written jsonb;
  v_readback jsonb;
  v_expected_plan_hash text;
  v_bad_count integer := 0;
  v_expertise jsonb := '{}'::jsonb;
begin
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or nullif(btrim(coalesce(p_step_id,'')),'') is null
     or p_evidence_payload is null
     or jsonb_typeof(p_evidence_payload)<>'object' then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_TRUST_INPUT_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  select * into e from public.lf_operation_execution where execution_id=p_execution_id;
  if not found
     or e.operation_code not in ('CREACION_CARD_LF','CREACION_SKILL_LF')
     or e.status<>'IN_PROGRESS'
     or (e.operation_code='CREACION_CARD_LF' and e.target_type<>'CARD')
     or (e.operation_code='CREACION_SKILL_LF' and e.target_type<>'SKILL') then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_EXECUTION_BINDING_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  v_parity:=public.lf_creation_factory_parity_guard_v1(e.operation_code);
  if coalesce((v_parity->>'valid')::boolean,false) is not true then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_PARITY_NOT_CLEAN',
      'details',v_parity,'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('factory_parity_failed'));
  end if;

  select * into s from public.lf_operation_steps
  where operation_code=e.operation_code and step_id=p_step_id and active is true;
  if not found or p_step_id='init_execution' then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_STEP_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  select * into c from public.lf_operation_step_contracts
  where operation_code=e.operation_code and step_id=p_step_id
    and step_order=s.step_order and status='ACTIVE';
  select * into b from public.lf_operation_step_judge_bindings
  where operation_code=e.operation_code and step_id=p_step_id
    and step_order=s.step_order and status='ACTIVE_ENFORCEMENT';
  select * into j from public.lf_operation_judges
  where operation_code=e.operation_code and judge_code=b.judge_code
    and status='ACTIVE_ENFORCEMENT';

  if c.step_id is null or b.step_id is null or j.judge_code is null then
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_AUTHORITY_CHAIN_INCOMPLETE',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  for v_key in select jsonb_array_elements_text(b.required_evidence_keys) loop
    if not (p_evidence_payload ? v_key)
       or p_evidence_payload->v_key is null
       or p_evidence_payload->v_key='null'::jsonb
       or (jsonb_typeof(p_evidence_payload->v_key)='string' and btrim(p_evidence_payload->>v_key)='') then
      v_missing:=array_append(v_missing,v_key);
    end if;
  end loop;
  if cardinality(v_missing)>0 then
    v_hard:=v_hard||jsonb_build_array('required_evidence_missing');
  end if;

  if jsonb_typeof(p_evidence_payload->'blocking_codes')<>'array'
     or jsonb_array_length(coalesce(p_evidence_payload->'blocking_codes','["__invalid__"]'::jsonb))<>0 then
    v_hard:=v_hard||jsonb_build_array('blocking_codes_not_clean');
  end if;

  if e.operation_code='CREACION_CARD_LF' and p_step_id='pre_write_execution_binding_gate' then
    if coalesce((p_evidence_payload->>'execution_bound_to_target_before_change')::boolean,false) is not true
       or coalesce(p_evidence_payload->>'proposed_card_sha256','') !~ '^[0-9a-f]{64}
    if coalesce((p_evidence_payload->>'execution_binding_verified')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'write_plan')<>'array'
       or jsonb_array_length(p_evidence_payload->'write_plan')=0
       or coalesce(p_evidence_payload->>'write_plan_hash','') !~ '^[0-9a-f]{64}$' then
      v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_invalid');
    else
      v_write_plan:=p_evidence_payload->'write_plan';
      v_expected_plan_hash:=encode(
        extensions.digest(convert_to(v_write_plan::text,'UTF8'),'sha256'),'hex'
      );
      if p_evidence_payload->>'write_plan_hash' is distinct from v_expected_plan_hash then
        v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_hash_mismatch');
      end if;

      select count(*) into v_bad_count
      from jsonb_array_elements(v_write_plan) x
      where jsonb_typeof(x)<>'object'
         or nullif(btrim(coalesce(x->>'path','')),'') is null
         or coalesce(x->>'sha256','') !~ '^[0-9a-f]{64}$';
      if v_bad_count<>0 then
        v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_item_invalid');
      end if;

      select count(*) into v_bad_count
      from (
        select x->>'path' as path,count(*) n
        from jsonb_array_elements(v_write_plan) x
        group by x->>'path'
        having count(*)<>1
      ) d;
      if v_bad_count<>0 then
        v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_duplicate_path');
      end if;
    end if;
  end if;

  if p_step_id in ('github_write','github_readback') then
    select * into v_prewrite_binding
    from public.lf_operation_step_judge_bindings
    where operation_code=e.operation_code and step_id='pre_write_execution_binding_gate'
      and status='ACTIVE_ENFORCEMENT';
    select * into v_prewrite
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate';

    if v_prewrite.step_id is null
       or v_prewrite_binding.clean_result_value is null
       or v_prewrite.status<>v_prewrite_binding.clean_result_value then
      v_hard:=v_hard||jsonb_build_array('write_chain_predecessor_not_clean');
    end if;

    if e.operation_code='CREACION_CARD_LF' and p_step_id='github_write'
       and coalesce(p_evidence_payload->>'file_commit_sha','') !~ '^[0-9a-f]{40}$' then
      v_hard:=v_hard||jsonb_build_array('card_file_commit_sha_invalid');
    elsif e.operation_code='CREACION_CARD_LF' and p_step_id='github_readback'
       and coalesce(p_evidence_payload->>'file_readback_sha','') !~ '^[0-9a-f]{40}$' then
      v_hard:=v_hard||jsonb_build_array('card_file_readback_sha_invalid');
    elsif e.operation_code='CREACION_SKILL_LF' and p_step_id='github_write' then
      v_write_plan:=v_prewrite.evidence_payload->'write_plan';
      v_expected_plan_hash:=v_prewrite.evidence_payload->>'write_plan_hash';
      v_written:=p_evidence_payload->'written_files';

      if jsonb_typeof(v_write_plan)<>'array'
         or jsonb_array_length(v_write_plan)=0
         or coalesce(v_expected_plan_hash,'') !~ '^[0-9a-f]{64}$'
         or p_evidence_payload->>'write_plan_hash' is distinct from v_expected_plan_hash
         or p_evidence_payload->>'repo' is distinct from e.target_repo
         or nullif(btrim(coalesce(p_evidence_payload->>'branch','')),'') is null
         or coalesce(p_evidence_payload->>'commit_sha','') !~ '^[0-9a-f]{40}$'
         or jsonb_typeof(v_written)<>'array'
         or jsonb_array_length(v_written)<>jsonb_array_length(v_write_plan)
         or coalesce((p_evidence_payload->>'partial_write_detected')::boolean,true) is not false then
        v_hard:=v_hard||jsonb_build_array('skill_github_write_evidence_invalid');
      else
        select count(*) into v_bad_count
        from jsonb_array_elements(v_written) wf
        where jsonb_typeof(wf)<>'object'
           or nullif(btrim(coalesce(wf->>'path','')),'') is null
           or coalesce(wf->>'file_sha','') !~ '^[0-9a-f]{40}$'
           or not exists (
             select 1 from jsonb_array_elements(v_write_plan) wp
             where wp->>'path'=wf->>'path'
               and (
                 not (wf ? 'content_sha256')
                 or wf->>'content_sha256'=wp->>'sha256'
               )
           );
        if v_bad_count<>0 then
          v_hard:=v_hard||jsonb_build_array('skill_written_file_not_bound_to_plan');
        end if;

        select count(*) into v_bad_count
        from jsonb_array_elements(v_write_plan) wp
        where not exists (
          select 1 from jsonb_array_elements(v_written) wf
          where wf->>'path'=wp->>'path'
        );
        if v_bad_count<>0 then
          v_hard:=v_hard||jsonb_build_array('skill_write_plan_not_fully_materialized');
        end if;
      end if;

    elsif e.operation_code='CREACION_SKILL_LF' and p_step_id='github_readback' then
      select * into v_write_binding
      from public.lf_operation_step_judge_bindings
      where operation_code=e.operation_code and step_id='github_write'
        and status='ACTIVE_ENFORCEMENT';
      select * into v_write
      from public.lf_operation_execution_steps
      where execution_id=p_execution_id and step_id='github_write';

      v_written:=v_write.evidence_payload->'written_files';
      v_readback:=p_evidence_payload->'readback_files';

      if v_write.step_id is null
         or v_write_binding.clean_result_value is null
         or v_write.status<>v_write_binding.clean_result_value
         or p_evidence_payload->>'repo' is distinct from v_write.evidence_payload->>'repo'
         or p_evidence_payload->>'branch' is distinct from v_write.evidence_payload->>'branch'
         or p_evidence_payload->>'commit_sha' is distinct from v_write.evidence_payload->>'commit_sha'
         or p_evidence_payload->>'write_plan_hash' is distinct from v_write.evidence_payload->>'write_plan_hash'
         or p_evidence_payload->>'sha_match_status'<>'PASS'
         or jsonb_typeof(v_readback)<>'array'
         or jsonb_typeof(v_written)<>'array'
         or jsonb_array_length(v_readback)<>jsonb_array_length(v_written)
         or coalesce((p_evidence_payload->>'files_count')::integer,-1)<>jsonb_array_length(v_written) then
        v_hard:=v_hard||jsonb_build_array('skill_github_readback_evidence_invalid');
      else
        select count(*) into v_bad_count
        from jsonb_array_elements(v_readback) rb
        where jsonb_typeof(rb)<>'object'
           or nullif(btrim(coalesce(rb->>'path','')),'') is null
           or coalesce(rb->>'file_sha','') !~ '^[0-9a-f]{40}$'
           or not exists (
             select 1 from jsonb_array_elements(v_written) wf
             where wf->>'path'=rb->>'path'
               and wf->>'file_sha'=rb->>'file_sha'
               and (
                 not (wf ? 'content_sha256')
                 or not (rb ? 'content_sha256')
                 or wf->>'content_sha256'=rb->>'content_sha256'
               )
           );
        if v_bad_count<>0 then
          v_hard:=v_hard||jsonb_build_array('skill_readback_not_exact_write');
        end if;
      end if;
    end if;
  end if;

  if p_step_id in ('card_examples_depth_judge','contract_judge','close') then
    select count(*) into v_prior_missing
    from public.lf_operation_steps ps
    where ps.operation_code=e.operation_code and ps.required is true and ps.active is true
      and coalesce(ps.execution_order,ps.step_order)<coalesce(s.execution_order,s.step_order)
      and not exists (
        select 1 from public.lf_operation_execution_steps pe
        where pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
      );

    select count(*) into v_prior_bad
    from public.lf_operation_steps ps
    left join public.lf_operation_step_judge_bindings pb
      on pb.operation_code=ps.operation_code and pb.step_id=ps.step_id and pb.step_order=ps.step_order
      and pb.status='ACTIVE_ENFORCEMENT'
    join public.lf_operation_execution_steps pe
      on pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
    where ps.operation_code=e.operation_code and ps.required is true and ps.active is true
      and coalesce(ps.execution_order,ps.step_order)<coalesce(s.execution_order,s.step_order)
      and (pb.clean_result_value is null or pe.status<>pb.clean_result_value);

    if v_prior_missing>0 or v_prior_bad>0 then
      v_hard:=v_hard||jsonb_build_array('required_predecessor_not_clean');
    end if;
  end if;

  if p_step_id='card_examples_depth_judge'
     and coalesce((p_evidence_payload->>'card_examples_depth_judge_pass')::boolean,false) is not true then
    v_hard:=v_hard||jsonb_build_array('card_examples_depth_not_proven');
  end if;

  if p_step_id='contract_judge' then
    select contract_sha into v_contract_sha
    from public.lf_operation_contracts
    where operation_code=e.operation_code
      and contract_code=case when e.operation_code='CREACION_CARD_LF' then 'CONTRATO_CARD_LF' else 'CONTRATO_SKILL_LF' end
    limit 1;

    if (e.manifest->>'automatic_impact') is distinct from 'BLOQUEADO'
       or coalesce((e.manifest->>'runtime_enabled')::boolean,true) is not false
       or coalesce((e.manifest->>'production_impact')::boolean,true) is not false
       or p_evidence_payload->>'source_sha' is distinct from s.source_sha
       or p_evidence_payload->>'contract_sha' is distinct from v_contract_sha
       or p_evidence_payload->>'judge_sha' is distinct from j.judge_sha
       or (e.operation_code='CREACION_CARD_LF'
           and coalesce((p_evidence_payload->>'judge_pass_and_scope_confirmed')::boolean,false) is not true)
       or (e.operation_code='CREACION_SKILL_LF'
           and coalesce((p_evidence_payload->>'contract_judged')::boolean,false) is not true) then
      v_hard:=v_hard||jsonb_build_array('contract_judge_server_binding_invalid');
    end if;
  end if;

  if p_step_id='close' then
    if (e.manifest->>'automatic_impact') is distinct from 'BLOQUEADO'
       or coalesce((e.manifest->>'runtime_enabled')::boolean,true) is not false
       or coalesce((e.manifest->>'production_impact')::boolean,true) is not false
       or coalesce((e.manifest->>'security_hold_active')::boolean,false) is true
       or (e.operation_code='CREACION_CARD_LF'
           and coalesce((p_evidence_payload->>'no_blocking_observations_and_scope_confirmed')::boolean,false) is not true)
       or (e.operation_code='CREACION_SKILL_LF'
           and coalesce((p_evidence_payload->>'close_verified')::boolean,false) is not true) then
      v_hard:=v_hard||jsonb_build_array('close_server_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(v_hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','CREATION_FACTORY_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'missing_keys',to_jsonb(v_missing),'hard_fails',v_hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if jsonb_typeof(j.pass_if)='array' then
    v_assertions:=j.pass_if;
  elsif jsonb_typeof(j.pass_if)='object' and jsonb_typeof(j.pass_if->'pass_if')='array' then
    v_assertions:=j.pass_if->'pass_if';
  elsif jsonb_typeof(j.pass_if)='object' then
    select coalesce(jsonb_agg(key order by key),'[]'::jsonb)
    into v_assertions
    from jsonb_each(j.pass_if)
    where value='true'::jsonb;
  else
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_JUDGE_PASS_SHAPE_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  if e.operation_code='CREACION_CARD_LF'
     and p_step_id='pre_write_execution_binding_gate'
     and coalesce((v_expertise->>'valid')::boolean,false) is true then
    v_assertions:=v_assertions||coalesce(v_expertise->'server_assertions','[]'::jsonb);
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CREATION_FACTORY_SERVER_VALIDATED',
    'details',jsonb_build_object(
      'step_id',p_step_id,
      'execution_id',p_execution_id,
      'expertise_validation',case when v_expertise='{}'::jsonb then null else v_expertise end
    ),
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb
  );
end
$function$

       or jsonb_typeof(p_evidence_payload->'expertise_quality_gate')<>'object'
       or p_evidence_payload->'expertise_quality_gate'->>'subject_revision_sha256'
            is distinct from p_evidence_payload->>'proposed_card_sha256' then
      v_hard:=v_hard||jsonb_build_array('card_prewrite_top_tier_binding_invalid');
    else
      v_expertise:=public.lf_validate_card_expertise_gate_v1(
        p_execution_id,
        'expertise_quality_gate',
        p_evidence_payload->'expertise_quality_gate'
      );
      if coalesce((v_expertise->>'valid')::boolean,false) is not true then
        v_hard:=v_hard||jsonb_build_array(
          'card_expertise_top_tier_not_proven:'||coalesce(v_expertise->>'code','UNKNOWN')
        );
      end if;
    end if;
  end if;

  if e.operation_code='CREACION_SKILL_LF' and p_step_id='pre_write_execution_binding_gate' then
    if coalesce((p_evidence_payload->>'execution_binding_verified')::boolean,false) is not true
       or jsonb_typeof(p_evidence_payload->'write_plan')<>'array'
       or jsonb_array_length(p_evidence_payload->'write_plan')=0
       or coalesce(p_evidence_payload->>'write_plan_hash','') !~ '^[0-9a-f]{64}$' then
      v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_invalid');
    else
      v_write_plan:=p_evidence_payload->'write_plan';
      v_expected_plan_hash:=encode(
        extensions.digest(convert_to(v_write_plan::text,'UTF8'),'sha256'),'hex'
      );
      if p_evidence_payload->>'write_plan_hash' is distinct from v_expected_plan_hash then
        v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_hash_mismatch');
      end if;

      select count(*) into v_bad_count
      from jsonb_array_elements(v_write_plan) x
      where jsonb_typeof(x)<>'object'
         or nullif(btrim(coalesce(x->>'path','')),'') is null
         or coalesce(x->>'sha256','') !~ '^[0-9a-f]{64}$';
      if v_bad_count<>0 then
        v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_item_invalid');
      end if;

      select count(*) into v_bad_count
      from (
        select x->>'path' as path,count(*) n
        from jsonb_array_elements(v_write_plan) x
        group by x->>'path'
        having count(*)<>1
      ) d;
      if v_bad_count<>0 then
        v_hard:=v_hard||jsonb_build_array('skill_prewrite_plan_duplicate_path');
      end if;
    end if;
  end if;

  if p_step_id in ('github_write','github_readback') then
    select * into v_prewrite_binding
    from public.lf_operation_step_judge_bindings
    where operation_code=e.operation_code and step_id='pre_write_execution_binding_gate'
      and status='ACTIVE_ENFORCEMENT';
    select * into v_prewrite
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='pre_write_execution_binding_gate';

    if v_prewrite.step_id is null
       or v_prewrite_binding.clean_result_value is null
       or v_prewrite.status<>v_prewrite_binding.clean_result_value then
      v_hard:=v_hard||jsonb_build_array('write_chain_predecessor_not_clean');
    end if;

    if e.operation_code='CREACION_CARD_LF' and p_step_id='github_write'
       and coalesce(p_evidence_payload->>'file_commit_sha','') !~ '^[0-9a-f]{40}$' then
      v_hard:=v_hard||jsonb_build_array('card_file_commit_sha_invalid');
    elsif e.operation_code='CREACION_CARD_LF' and p_step_id='github_readback'
       and coalesce(p_evidence_payload->>'file_readback_sha','') !~ '^[0-9a-f]{40}$' then
      v_hard:=v_hard||jsonb_build_array('card_file_readback_sha_invalid');
    elsif e.operation_code='CREACION_SKILL_LF' and p_step_id='github_write' then
      v_write_plan:=v_prewrite.evidence_payload->'write_plan';
      v_expected_plan_hash:=v_prewrite.evidence_payload->>'write_plan_hash';
      v_written:=p_evidence_payload->'written_files';

      if jsonb_typeof(v_write_plan)<>'array'
         or jsonb_array_length(v_write_plan)=0
         or coalesce(v_expected_plan_hash,'') !~ '^[0-9a-f]{64}$'
         or p_evidence_payload->>'write_plan_hash' is distinct from v_expected_plan_hash
         or p_evidence_payload->>'repo' is distinct from e.target_repo
         or nullif(btrim(coalesce(p_evidence_payload->>'branch','')),'') is null
         or coalesce(p_evidence_payload->>'commit_sha','') !~ '^[0-9a-f]{40}$'
         or jsonb_typeof(v_written)<>'array'
         or jsonb_array_length(v_written)<>jsonb_array_length(v_write_plan)
         or coalesce((p_evidence_payload->>'partial_write_detected')::boolean,true) is not false then
        v_hard:=v_hard||jsonb_build_array('skill_github_write_evidence_invalid');
      else
        select count(*) into v_bad_count
        from jsonb_array_elements(v_written) wf
        where jsonb_typeof(wf)<>'object'
           or nullif(btrim(coalesce(wf->>'path','')),'') is null
           or coalesce(wf->>'file_sha','') !~ '^[0-9a-f]{40}$'
           or not exists (
             select 1 from jsonb_array_elements(v_write_plan) wp
             where wp->>'path'=wf->>'path'
               and (
                 not (wf ? 'content_sha256')
                 or wf->>'content_sha256'=wp->>'sha256'
               )
           );
        if v_bad_count<>0 then
          v_hard:=v_hard||jsonb_build_array('skill_written_file_not_bound_to_plan');
        end if;

        select count(*) into v_bad_count
        from jsonb_array_elements(v_write_plan) wp
        where not exists (
          select 1 from jsonb_array_elements(v_written) wf
          where wf->>'path'=wp->>'path'
        );
        if v_bad_count<>0 then
          v_hard:=v_hard||jsonb_build_array('skill_write_plan_not_fully_materialized');
        end if;
      end if;

    elsif e.operation_code='CREACION_SKILL_LF' and p_step_id='github_readback' then
      select * into v_write_binding
      from public.lf_operation_step_judge_bindings
      where operation_code=e.operation_code and step_id='github_write'
        and status='ACTIVE_ENFORCEMENT';
      select * into v_write
      from public.lf_operation_execution_steps
      where execution_id=p_execution_id and step_id='github_write';

      v_written:=v_write.evidence_payload->'written_files';
      v_readback:=p_evidence_payload->'readback_files';

      if v_write.step_id is null
         or v_write_binding.clean_result_value is null
         or v_write.status<>v_write_binding.clean_result_value
         or p_evidence_payload->>'repo' is distinct from v_write.evidence_payload->>'repo'
         or p_evidence_payload->>'branch' is distinct from v_write.evidence_payload->>'branch'
         or p_evidence_payload->>'commit_sha' is distinct from v_write.evidence_payload->>'commit_sha'
         or p_evidence_payload->>'write_plan_hash' is distinct from v_write.evidence_payload->>'write_plan_hash'
         or p_evidence_payload->>'sha_match_status'<>'PASS'
         or jsonb_typeof(v_readback)<>'array'
         or jsonb_typeof(v_written)<>'array'
         or jsonb_array_length(v_readback)<>jsonb_array_length(v_written)
         or coalesce((p_evidence_payload->>'files_count')::integer,-1)<>jsonb_array_length(v_written) then
        v_hard:=v_hard||jsonb_build_array('skill_github_readback_evidence_invalid');
      else
        select count(*) into v_bad_count
        from jsonb_array_elements(v_readback) rb
        where jsonb_typeof(rb)<>'object'
           or nullif(btrim(coalesce(rb->>'path','')),'') is null
           or coalesce(rb->>'file_sha','') !~ '^[0-9a-f]{40}$'
           or not exists (
             select 1 from jsonb_array_elements(v_written) wf
             where wf->>'path'=rb->>'path'
               and wf->>'file_sha'=rb->>'file_sha'
               and (
                 not (wf ? 'content_sha256')
                 or not (rb ? 'content_sha256')
                 or wf->>'content_sha256'=rb->>'content_sha256'
               )
           );
        if v_bad_count<>0 then
          v_hard:=v_hard||jsonb_build_array('skill_readback_not_exact_write');
        end if;
      end if;
    end if;
  end if;

  if p_step_id in ('card_examples_depth_judge','contract_judge','close') then
    select count(*) into v_prior_missing
    from public.lf_operation_steps ps
    where ps.operation_code=e.operation_code and ps.required is true and ps.active is true
      and coalesce(ps.execution_order,ps.step_order)<coalesce(s.execution_order,s.step_order)
      and not exists (
        select 1 from public.lf_operation_execution_steps pe
        where pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
      );

    select count(*) into v_prior_bad
    from public.lf_operation_steps ps
    left join public.lf_operation_step_judge_bindings pb
      on pb.operation_code=ps.operation_code and pb.step_id=ps.step_id and pb.step_order=ps.step_order
      and pb.status='ACTIVE_ENFORCEMENT'
    join public.lf_operation_execution_steps pe
      on pe.execution_id=p_execution_id and pe.step_id=ps.step_id and pe.step_order=ps.step_order
    where ps.operation_code=e.operation_code and ps.required is true and ps.active is true
      and coalesce(ps.execution_order,ps.step_order)<coalesce(s.execution_order,s.step_order)
      and (pb.clean_result_value is null or pe.status<>pb.clean_result_value);

    if v_prior_missing>0 or v_prior_bad>0 then
      v_hard:=v_hard||jsonb_build_array('required_predecessor_not_clean');
    end if;
  end if;

  if p_step_id='card_examples_depth_judge'
     and coalesce((p_evidence_payload->>'card_examples_depth_judge_pass')::boolean,false) is not true then
    v_hard:=v_hard||jsonb_build_array('card_examples_depth_not_proven');
  end if;

  if p_step_id='contract_judge' then
    select contract_sha into v_contract_sha
    from public.lf_operation_contracts
    where operation_code=e.operation_code
      and contract_code=case when e.operation_code='CREACION_CARD_LF' then 'CONTRATO_CARD_LF' else 'CONTRATO_SKILL_LF' end
    limit 1;

    if (e.manifest->>'automatic_impact') is distinct from 'BLOQUEADO'
       or coalesce((e.manifest->>'runtime_enabled')::boolean,true) is not false
       or coalesce((e.manifest->>'production_impact')::boolean,true) is not false
       or p_evidence_payload->>'source_sha' is distinct from s.source_sha
       or p_evidence_payload->>'contract_sha' is distinct from v_contract_sha
       or p_evidence_payload->>'judge_sha' is distinct from j.judge_sha
       or (e.operation_code='CREACION_CARD_LF'
           and coalesce((p_evidence_payload->>'judge_pass_and_scope_confirmed')::boolean,false) is not true)
       or (e.operation_code='CREACION_SKILL_LF'
           and coalesce((p_evidence_payload->>'contract_judged')::boolean,false) is not true) then
      v_hard:=v_hard||jsonb_build_array('contract_judge_server_binding_invalid');
    end if;
  end if;

  if p_step_id='close' then
    if (e.manifest->>'automatic_impact') is distinct from 'BLOQUEADO'
       or coalesce((e.manifest->>'runtime_enabled')::boolean,true) is not false
       or coalesce((e.manifest->>'production_impact')::boolean,true) is not false
       or coalesce((e.manifest->>'security_hold_active')::boolean,false) is true
       or (e.operation_code='CREACION_CARD_LF'
           and coalesce((p_evidence_payload->>'no_blocking_observations_and_scope_confirmed')::boolean,false) is not true)
       or (e.operation_code='CREACION_SKILL_LF'
           and coalesce((p_evidence_payload->>'close_verified')::boolean,false) is not true) then
      v_hard:=v_hard||jsonb_build_array('close_server_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(v_hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','CREATION_FACTORY_SERVER_VALIDATION_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'missing_keys',to_jsonb(v_missing),'hard_fails',v_hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if jsonb_typeof(j.pass_if)='array' then
    v_assertions:=j.pass_if;
  elsif jsonb_typeof(j.pass_if)='object' and jsonb_typeof(j.pass_if->'pass_if')='array' then
    v_assertions:=j.pass_if->'pass_if';
  elsif jsonb_typeof(j.pass_if)='object' then
    select coalesce(jsonb_agg(key order by key),'[]'::jsonb)
    into v_assertions
    from jsonb_each(j.pass_if)
    where value='true'::jsonb;
  else
    return jsonb_build_object('valid',false,'code','CREATION_FACTORY_JUDGE_PASS_SHAPE_INVALID',
      'server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('server_validation_failed'));
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','CREATION_FACTORY_SERVER_VALIDATED',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',v_assertions,
    'server_hard_fails','[]'::jsonb
  );
end
$function$



create or replace function public.lf_card_create_top_tier_reconcile_v1(p_execution_id text)
returns jsonb
language plpgsql
set search_path to 'pg_catalog','public'
as $$
declare
  e public.lf_operation_execution%rowtype;
  v_parity jsonb;
begin
  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id
  for update;

  if not found
     or e.operation_code<>'CREACION_CARD_LF'
     or e.target_type<>'CARD'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object('valid',false,'code','CARD_CREATE_TOP_TIER_RECONCILE_EXECUTION_INVALID');
  end if;

  update public.lf_operation_contracts
  set required_before_write=
        coalesce(required_before_write,'[]'::jsonb)
        || case when coalesce(required_before_write,'[]'::jsonb) @> '["expertise_quality_gate_pass"]'::jsonb
                then '[]'::jsonb else '["expertise_quality_gate_pass"]'::jsonb end
        || case when coalesce(required_before_write,'[]'::jsonb) @> '["max_level_l4_certification_pass"]'::jsonb
                then '[]'::jsonb else '["max_level_l4_certification_pass"]'::jsonb end,
      allowed=coalesce(allowed,'{}'::jsonb)||jsonb_build_object(
        'professional_quality_benchmark','CARD_EXPERTISE_TOP_TIER_V1',
        'certification_test_level','L4_TOP_TIER_ONLY',
        'independent_assurance_required',true,
        'subject_revision_binding_required',true
      ),
      blocked=
        coalesce(blocked,'[]'::jsonb)
        || case when coalesce(blocked,'[]'::jsonb) @> '["expertise_quality_below_threshold"]'::jsonb
                then '[]'::jsonb else jsonb_build_array('expertise_quality_below_threshold') end
        || case when coalesce(blocked,'[]'::jsonb) @> '["self_assessment_only"]'::jsonb
                then '[]'::jsonb else jsonb_build_array('self_assessment_only') end
        || case when coalesce(blocked,'[]'::jsonb) @> '["lower_level_only_certification"]'::jsonb
                then '[]'::jsonb else jsonb_build_array('lower_level_only_certification') end
        || case when coalesce(blocked,'[]'::jsonb) @> '["max_level_suite_incomplete"]'::jsonb
                then '[]'::jsonb else jsonb_build_array('max_level_suite_incomplete') end
        || case when coalesce(blocked,'[]'::jsonb) @> '["assurance_receipt_missing_or_replayed"]'::jsonb
                then '[]'::jsonb else jsonb_build_array('assurance_receipt_missing_or_replayed') end,
      contract_sha='a7642e65b53a9ae52f38b558ddb18c2d0fbc093e',
      updated_at=now(),
      updated_by_execution_id=p_execution_id
  where operation_code='CREACION_CARD_LF'
    and contract_code='CONTRATO_CARD_LF';

  update public.lf_operation_step_contracts
  set required_evidence_keys=jsonb_build_array(
        'execution_bound_to_target_before_change',
        'proposed_card_sha256',
        'expertise_quality_gate',
        'step_result',
        'blocking_codes'
      ),
      pass_condition=coalesce(pass_condition,'{}'::jsonb)||jsonb_build_object(
        'expertise_benchmark_code','CARD_EXPERTISE_TOP_TIER_V1',
        'certification_level','L4_TOP_TIER',
        'independent_assurance_required',true,
        'subject_revision_binding_required',true
      ),
      block_condition=coalesce(block_condition,'{}'::jsonb)||jsonb_build_object(
        'expertise_missing',true,
        'expertise_not_top_tier',true,
        'assurance_receipt_missing_or_replayed',true
      ),
      notes=case
        when coalesce(notes,'') like '%CARD_CREATE_TOP_TIER_GATE_V1%' then notes
        else concat_ws(' | ',nullif(notes,''),'CARD_CREATE_TOP_TIER_GATE_V1: pre-write requires exact CARD_EXPERTISE_TOP_TIER_V1 plus closed INDEPENDENT_ASSURANCE receipt bound to proposed_card_sha256.')
      end,
      updated_at=now(),
      updated_by_execution_id=p_execution_id
  where operation_code='CREACION_CARD_LF'
    and step_id='pre_write_execution_binding_gate'
    and status='ACTIVE';

  update public.lf_operation_step_judge_bindings
  set required_evidence_keys=jsonb_build_array(
        'execution_bound_to_target_before_change',
        'proposed_card_sha256',
        'expertise_quality_gate',
        'step_result',
        'blocking_codes'
      ),
      updated_at=now(),
      updated_by_execution_id=p_execution_id
  where operation_code='CREACION_CARD_LF'
    and step_id='pre_write_execution_binding_gate'
    and status='ACTIVE_ENFORCEMENT';

  update public.lf_operation_steps
  set source_path='gobernanza/procedimientos/creacion_card_lf_steps_validation.yaml',
      source_sha='dc836d0e8a2534e5c957cb668606bd91ca1a76ae',
      evidence_required='execution_bound_to_target_before_change_and_card_expertise_top_tier_v1_pass',
      updated_at=now(),
      updated_by_execution_id=p_execution_id
  where operation_code='CREACION_CARD_LF'
    and step_id='pre_write_execution_binding_gate'
    and active is true;

  update public.lf_operation_registry
  set version='v0.5',
      notes=case
        when coalesce(notes,'') like '%CARD_CREATE_TOP_TIER_GATE_V1%' then notes
        else concat_ws(' | ',nullif(notes,''),'CARD_CREATE_TOP_TIER_GATE_V1: creation pre-write requires exact L4 TOP_TIER certification, independent assurance receipt and subject revision anti-replay binding.')
      end,
      updated_at=now(),
      updated_by_execution_id=p_execution_id
  where operation_code='CREACION_CARD_LF';

  v_parity:=public.lf_creation_factory_parity_guard_v1('CREACION_CARD_LF');

  return jsonb_build_object(
    'valid',
      coalesce((v_parity->>'valid')::boolean,false)
      and exists(
        select 1
        from public.lf_operation_step_contracts c
        join public.lf_operation_step_judge_bindings b
          on b.operation_code=c.operation_code and b.step_id=c.step_id and b.step_order=c.step_order
        where c.operation_code='CREACION_CARD_LF'
          and c.step_id='pre_write_execution_binding_gate'
          and c.required_evidence_keys @> '["proposed_card_sha256","expertise_quality_gate"]'::jsonb
          and b.required_evidence_keys @> '["proposed_card_sha256","expertise_quality_gate"]'::jsonb
      ),
    'code','CARD_CREATE_TOP_TIER_RECONCILED',
    'parity',v_parity,
    'reconciled_by_execution_id',p_execution_id
  );
end
$$;

