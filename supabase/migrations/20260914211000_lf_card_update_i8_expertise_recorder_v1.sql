-- LF_CARD_UPDATE_I8_EXPERTISE_RECORDER_V1
-- Purpose: allow the non-writing expertise_quality_gate at step 85 while preserving the write ceiling above 85.
-- Scope: ACTUALIZACION_CARD_LF candidate only. No Card content write, runtime, production, Router or promotion activation.

begin;

create or replace function public.lf_validate_card_expertise_gate_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_execution public.lf_operation_execution%rowtype;
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
    'assessor_mode is INDEPENDENT_HOLDOUT or S36_ASSURANCE',
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
     or v_execution.operation_code is distinct from 'ACTUALIZACION_CARD_LF'
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

  if coalesce(p_evidence_payload->>'assessor_mode','') not in ('INDEPENDENT_HOLDOUT','S36_ASSURANCE') then
    return jsonb_build_object('valid',false,'code','EXPERTISE_ASSESSOR_MODE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('self assessment only'));
  end if;

  if nullif(btrim(p_evidence_payload->>'assessor_execution_id'),'') is null
     or (p_evidence_payload->>'assessor_execution_id') is not distinct from p_execution_id then
    return jsonb_build_object('valid',false,'code','EXPERTISE_ASSESSOR_NOT_INDEPENDENT','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('missing independent assessor identity'));
  end if;

  select exists(
    select 1 from public.lf_operation_execution
    where execution_id=p_evidence_payload->>'assessor_execution_id'
  ) into v_assessor_exists;

  if not v_assessor_exists then
    return jsonb_build_object('valid',false,'code','EXPERTISE_ASSESSOR_EXECUTION_NOT_FOUND','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('missing independent assessor identity'));
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
  when invalid_text_representation or numeric_value_out_of_range then
    return jsonb_build_object('valid',false,'code','EXPERTISE_EVIDENCE_TYPE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_step_order integer;
  v_server_validation jsonb;
begin
  select step_order into v_step_order
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF'
    and step_id=p_step_id
    and active is true;

  if v_step_order is null then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false);
  end if;

  if v_step_order>85 then
    v_server_validation:=jsonb_build_object(
      'valid',false,
      'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I8',
      'details',jsonb_build_object('step_order',v_step_order,'ceiling_step_order',85),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')
    );
  elsif p_step_id='expertise_quality_gate' then
    v_server_validation:=public.lf_validate_card_expertise_gate_v1(
      p_execution_id,
      p_step_id,
      p_evidence_payload
    );
  else
    v_server_validation:=public.lf_validate_card_update_step_evidence_v5(
      p_execution_id,
      p_step_id,
      p_evidence_payload
    );
  end if;

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD',
    'CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',
    v_server_validation,true,'lf_record_card_operation_step_v1'
  );
end;
$function$;

revoke all on function public.lf_validate_card_expertise_gate_v1(text,text,jsonb) from public;
grant execute on function public.lf_validate_card_expertise_gate_v1(text,text,jsonb) to service_role;

-- The recorder already exists; CREATE OR REPLACE preserves its existing ACL. Reassert service-role execution explicitly.
grant execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) to service_role;

-- Fail closed if the wrapper does not expose exactly step 85 and keep step 90+ blocked.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.lf_record_card_operation_step_v1(text,text,text,jsonb,text)'::regprocedure)
  into v_def;

  if position('v_step_order>85' in v_def)=0
     or position('expertise_quality_gate' in v_def)=0
     or position('lf_validate_card_expertise_gate_v1' in v_def)=0
     or position('CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I8' in v_def)=0 then
    raise exception 'CARD_UPDATE_I8_EXPERTISE_RECORDER_STRUCTURAL_ASSERTION_FAILED';
  end if;
end $$;

commit;
