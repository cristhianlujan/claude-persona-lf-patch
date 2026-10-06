-- CARD_EXPERTISE_INDEPENDENT_ASSURANCE_ADAPTER_V1
-- Thin Card consumer adapter for the current INDEPENDENT_ASSURANCE capability.
-- No second semantic judge, no parallel review operation, no capability activation.
-- It prepares the exact CARD_CANDIDATE subject and consumes only an exact VERIFIED
-- EVIDENCE_LEDGER AUDIT_VERDICT. The existing CARD_EXPERTISE_TOP_TIER_V1 judge
-- remains the single semantic/top-tier validator.


create or replace function public.lf_card_expertise_prepare_independent_review_v1(
  p_execution_id text,
  p_subject_sha256 text
) returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public'
as $function$
declare
  e public.lf_operation_execution%rowtype;
  v_cap_status text;
  v_cap_version text;
  v_cap_manifest_sha text;
  v_subject_ref text;
  v_authority_ref text := 'supabase://public.lf_operation_step_contracts/CREACION_CARD_LF/pre_write_execution_binding_gate';
begin
  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;

  if not found
     or e.operation_code<>'CREACION_CARD_LF'
     or e.target_type<>'CARD'
     or e.status<>'IN_PROGRESS' then
    return jsonb_build_object('result','BLOCKED','code','CARD_INDEPENDENT_REVIEW_SUBJECT_INVALID');
  end if;

  if coalesce(p_subject_sha256,'') !~ '^[0-9a-f]{64}$'
     or coalesce(e.manifest->>'candidate_sha256','') is distinct from p_subject_sha256 then
    return jsonb_build_object('result','BLOCKED','code','CARD_INDEPENDENT_REVIEW_REVISION_INVALID');
  end if;

  select r.status,c.version,c.manifest_sha256
    into v_cap_status,v_cap_version,v_cap_manifest_sha
  from public.lf_capability_registry r
  join public.lf_capability_current c using(capability_code)
  where r.capability_code='INDEPENDENT_ASSURANCE';

  if v_cap_status is distinct from 'ACTIVE'
     or nullif(btrim(coalesce(v_cap_version,'')),'') is null
     or coalesce(v_cap_manifest_sha,'') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_ASSURANCE_NOT_CURRENT');
  end if;

  v_subject_ref:='CREACION_CARD_LF/CARD/'||e.target_code||'/'||p_subject_sha256;

  return jsonb_build_object(
    'result','REVIEW_REQUIRED',
    'adapter_schema_version','CARD_EXPERTISE_INDEPENDENT_ASSURANCE_ADAPTER_V1',
    'consumer','CREACION_CARD_LF/pre_write_execution_binding_gate',
    'benchmark_version','CARD_EXPERTISE_TOP_TIER_V1',
    'capability_code','INDEPENDENT_ASSURANCE',
    'capability_version',v_cap_version,
    'capability_manifest_sha256',v_cap_manifest_sha,
    'subject_type','CARD_CANDIDATE',
    'subject_ref',v_subject_ref,
    'subject_sha256',p_subject_sha256,
    'authority_ref',v_authority_ref,
    'producer_execution_id',p_execution_id,
    'required_dimensions',jsonb_build_array(
      'domain_depth','critical_reasoning','exception_coverage','decision_quality',
      'noncommodity_value','adversarial_challenge','interdisciplinary_connection','operational_actionability'
    ),
    'required_receipt',jsonb_build_object(
      'ledger','private.lf_evidence_ledger_v1',
      'receipt_kind','AUDIT_VERDICT',
      'verification_state','VERIFIED',
      'independent',true,
      'independence_measure_state','INDEPENDENT',
      'independence_dimensions',jsonb_build_array('DEPENDENCIES','DATA','AUTHOR'),
      'self_review','FORBIDDEN'
    )
  );
end
$function$;

create or replace function public.lf_card_expertise_consume_independent_review_v1(
  p_execution_id text,
  p_subject_sha256 text,
  p_receipt_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_prepare jsonb;
  v_receipt private.lf_evidence_ledger_v1%rowtype;
  v_payload jsonb;
  v_measure jsonb;
  v_reviewer_execution_id text;
begin
  v_prepare:=public.lf_card_expertise_prepare_independent_review_v1(p_execution_id,p_subject_sha256);
  if v_prepare->>'result'<>'REVIEW_REQUIRED' then
    return v_prepare;
  end if;

  if p_receipt_id is null then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_REQUIRED');
  end if;

  select * into v_receipt
  from private.lf_evidence_ledger_v1
  where receipt_id=p_receipt_id;

  if not found then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_NOT_FOUND');
  end if;

  if v_receipt.capability_code is distinct from 'INDEPENDENT_ASSURANCE'
     or v_receipt.receipt_kind is distinct from 'AUDIT_VERDICT'
     or v_receipt.subject_type is distinct from v_prepare->>'subject_type'
     or v_receipt.subject_ref is distinct from v_prepare->>'subject_ref'
     or v_receipt.subject_sha256 is distinct from v_prepare->>'subject_sha256'
     or v_receipt.authority_ref is distinct from v_prepare->>'authority_ref'
     or v_receipt.verification_state is distinct from 'VERIFIED' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_BINDING_INVALID');
  end if;

  v_payload:=v_receipt.receipt_payload;
  if jsonb_typeof(v_payload)<>'object' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_RECEIPT_PAYLOAD_INVALID');
  end if;

  if v_payload->>'capability_version' is distinct from v_prepare->>'capability_version'
     or v_payload->>'capability_manifest_sha256' is distinct from v_prepare->>'capability_manifest_sha256'
     or v_payload->>'benchmark_version' is distinct from 'CARD_EXPERTISE_TOP_TIER_V1'
     or v_payload->>'subject_revision_sha256' is distinct from p_subject_sha256
     or v_payload->>'producer_execution_id' is distinct from p_execution_id
     or v_payload->>'verdict' is distinct from 'PASS'
     or v_payload->'independent' is distinct from 'true'::jsonb then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_CONTENT_INVALID');
  end if;

  v_reviewer_execution_id:=nullif(btrim(coalesce(v_payload->>'reviewer_execution_id','')),'');
  if v_reviewer_execution_id is null
     or v_reviewer_execution_id=p_execution_id
     or v_receipt.created_by_execution_id is distinct from v_reviewer_execution_id then
    return jsonb_build_object('result','BLOCKED','code','SELF_REVIEW_REJECTED');
  end if;

  v_measure:=v_payload->'independence_measure';
  if jsonb_typeof(v_measure)<>'object'
     or v_measure->>'state' is distinct from 'INDEPENDENT'
     or v_measure#>>'{dimensions,DEPENDENCIES}' is distinct from 'INDEPENDENT'
     or v_measure#>>'{dimensions,DATA}' is distinct from 'INDEPENDENT'
     or v_measure#>>'{dimensions,AUTHOR}' is distinct from 'INDEPENDENT' then
    return jsonb_build_object('result','BLOCKED','code','INDEPENDENT_REVIEW_INDEPENDENCE_INVALID');
  end if;

  return jsonb_build_object(
    'result','PASS',
    'adapter_schema_version','CARD_EXPERTISE_INDEPENDENT_ASSURANCE_ADAPTER_V1',
    'capability_code',v_receipt.capability_code,
    'capability_version',v_prepare->>'capability_version',
    'capability_manifest_sha256',v_prepare->>'capability_manifest_sha256',
    'subject_type',v_receipt.subject_type,
    'subject_ref',v_receipt.subject_ref,
    'subject_sha256',v_receipt.subject_sha256,
    'reviewer_execution_id',v_reviewer_execution_id,
    'receipt_id',v_receipt.receipt_id,
    'receipt_sha256',v_receipt.receipt_sha256,
    'verification_state',v_receipt.verification_state
  );
end
$function$;

revoke all on function public.lf_card_expertise_consume_independent_review_v1(text,text,uuid) from public,anon,authenticated;
grant execute on function public.lf_card_expertise_consume_independent_review_v1(text,text,uuid) to service_role;


CREATE OR REPLACE FUNCTION public.lf_validate_card_expertise_gate_v1(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_execution public.lf_operation_execution%rowtype;
  v_assessor public.lf_operation_execution%rowtype;
  v_assessor_exists boolean := false;
  v_receipt_id uuid;
  v_receipt_check jsonb;
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

  if v_execution.operation_code='CREACION_CARD_LF' then
    begin
      v_receipt_id:=(p_evidence_payload->>'independent_assurance_receipt_id')::uuid;
    exception when invalid_text_representation then
      return jsonb_build_object('valid',false,'code','EXPERTISE_CREATE_RECEIPT_ID_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('independent assurance receipt missing or invalid'));
    end;

    if v_receipt_id is null then
      return jsonb_build_object('valid',false,'code','EXPERTISE_CREATE_RECEIPT_REQUIRED','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('independent assurance receipt missing or invalid'));
    end if;

    if coalesce(p_evidence_payload->>'subject_revision_sha256','') !~ '^[0-9a-f]{64}$' then
      return jsonb_build_object('valid',false,'code','EXPERTISE_CREATE_SUBJECT_REVISION_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
    end if;

    v_receipt_check:=public.lf_card_expertise_consume_independent_review_v1(
      p_execution_id,
      p_evidence_payload->>'subject_revision_sha256',
      v_receipt_id
    );

    if v_receipt_check->>'result'<>'PASS' then
      return jsonb_build_object(
        'valid',false,
        'code','EXPERTISE_CREATE_INDEPENDENT_ASSURANCE_INVALID',
        'receipt_result',v_receipt_check,
        'server_assertions','[]'::jsonb,
        'server_hard_fails',jsonb_build_array('independent assurance receipt missing or invalid')
      );
    end if;

    if nullif(btrim(coalesce(p_evidence_payload->>'assessor_execution_id','')),'') is null
       or (p_evidence_payload->>'assessor_execution_id') is distinct from (v_receipt_check->>'reviewer_execution_id') then
      return jsonb_build_object('valid',false,'code','EXPERTISE_CREATE_REVIEWER_BINDING_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('missing independent assessor identity'));
    end if;

    if coalesce(p_evidence_payload->>'assessor_mode','') not in ('INDEPENDENT_HOLDOUT','INDEPENDENT_REVIEW') then
      return jsonb_build_object('valid',false,'code','EXPERTISE_CREATE_REVIEW_MODE_INVALID','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('self assessment only'));
    end if;
  else
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

  if v_execution.operation_code='CREACION_CARD_LF'
     and not exists (
       select 1
       from jsonb_array_elements_text(v_refs) r(ref)
       where r.ref='Receipt:'||(p_evidence_payload->>'independent_assurance_receipt_id')
     ) then
    return jsonb_build_object('valid',false,'code','EXPERTISE_CREATE_ASSURANCE_REF_MISSING','server_assertions','[]'::jsonb,'server_hard_fails',jsonb_build_array('benchmark evidence missing or non-reconstructible'));
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
;
