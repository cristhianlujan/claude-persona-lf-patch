-- LF sandbox: surgical V2 trust validator compatibility for owner-approved
-- same-chat CURRENT_CONTEXT_REVIEW, ONLY guarded SRCR candidate artifacts.
-- Does not bypass V3 checks, scope/candidate SHA, existing read-only checks,
-- Step70 source evidence, promotion authority, Product Director, or production.
-- Must apply ONLY through LF Migration Merge Train.
BEGIN;
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_execution_trust_validation_v2(text,text,jsonb)'::regprocedure))
    <> '4a14fef959203b9b41212862877585f0'
 THEN RAISE EXCEPTION 'LF_SRCR_STEP70_V2_TRUST_PREIMAGE_DRIFT'; END IF;
 IF to_regprocedure('public.lf_profile_srcr_same_context_candidate_scope_v1(text)') IS NULL
 THEN RAISE EXCEPTION 'LF_SRCR_STEP70_V2_SCOPE_GUARD_MISSING'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION public.lf_profile_execution_trust_validation_v2(p_execution_id text, p_step_id text, p_evidence_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
declare
  base jsonb;
  e public.lf_operation_execution%rowtype;
  input_step public.lf_operation_execution_steps%rowtype;
  execute_step public.lf_operation_execution_steps%rowtype;
  semantic_step public.lf_operation_execution_steps%rowtype;
  input_binding public.lf_operation_step_judge_bindings%rowtype;
  execute_binding public.lf_operation_step_judge_bindings%rowtype;
  semantic_binding public.lf_operation_step_judge_bindings%rowtype;
  packet jsonb;
  packet_body jsonb;
  expected_digest text;
  scope_digest text;
  candidate_digest text;
  semantic_result jsonb;
  canonical_read_judge jsonb;
  hard jsonb := '[]'::jsonb;
begin
  base:=public.lf_profile_execution_trust_validation_v1(
    p_execution_id,p_step_id,p_evidence_payload
  );
  if coalesce((base->>'valid')::boolean,false) is not true then
    return base;
  end if;

  select * into e
  from public.lf_operation_execution
  where execution_id=p_execution_id;
  if not found then
    return jsonb_build_object(
      'valid',false,'code','PROFILE_EXECUTION_V2_BINDING_INVALID',
      'details',jsonb_build_object('execution_id',p_execution_id),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  if p_step_id='input_validate' then
    packet:=p_evidence_payload->'scope_authority_packet';
    scope_digest:=p_evidence_payload->>'scope_authority_packet_sha256';
    if jsonb_typeof(packet)<>'object'
       or coalesce(packet->>'packet_version','')<>'LF_SCOPE_AUTHORITY_PACKET_V1'
       or packet->>'execution_id' is distinct from p_execution_id
       or packet->>'subject_ref' is distinct from
          'supabase://public.lf_operation_execution/'||p_execution_id||'#manifest'
       or packet->>'canonicalization_rule' is distinct from
          'POSTGRES_JSONB_TEXT_UTF8_SHA256_V1'
       or jsonb_typeof(packet->'authorized_requirements')<>'array'
       or jsonb_array_length(packet->'authorized_requirements')=0
       or jsonb_typeof(packet->'constraints')<>'array'
       or jsonb_typeof(packet->'forbidden_changes')<>'array'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
    then
      hard:=hard||jsonb_build_array('scope_authority_packet_shape_invalid');
    else
      packet_body:=packet-'sha256';
      expected_digest:='sha256:'||
        encode(extensions.digest(convert_to(packet_body::text,'UTF8'),'sha256'),'hex');
      if scope_digest is distinct from expected_digest
         or packet->>'sha256' is distinct from expected_digest then
        hard:=hard||jsonb_build_array('scope_authority_packet_digest_mismatch');
      end if;
    end if;

  elsif p_step_id='semantic_judge' then
    select * into input_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='input_validate'
      and status='ACTIVE_ENFORCEMENT';
    select * into input_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='input_validate';

    select * into execute_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='execute_profile'
      and status='ACTIVE_ENFORCEMENT';
    select * into execute_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='execute_profile';

    if input_step.step_id is null
       or input_step.status<>input_binding.clean_result_value then
      hard:=hard||jsonb_build_array('input_validate_predecessor_not_clean');
    end if;
    if execute_step.step_id is null
       or execute_step.status<>execute_binding.clean_result_value then
      hard:=hard||jsonb_build_array('execute_profile_predecessor_not_clean');
    end if;

    scope_digest:=input_step.evidence_payload->>'scope_authority_packet_sha256';
    candidate_digest:=execute_step.evidence_payload->>'candidate_digest';
    semantic_result:=p_evidence_payload->'semantic_judge_result';
    canonical_read_judge:=public.lf_profile_execution_canonical_read_judge_v1(p_execution_id);

    if jsonb_typeof(semantic_result)<>'object'
       or semantic_result->>'status' is distinct from 'PASS'
       or semantic_result->>'validator_status' is distinct from 'PASS'
       or not (
         (
           semantic_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
           and coalesce((semantic_result->>'producer_independence_proven')::boolean,false) is true
           and (
             coalesce((semantic_result->>'model_call_count')::integer,-1)=1
             or (
               coalesce((semantic_result->>'model_call_count')::integer,-1)=0
               and semantic_result->>'judge_mode'='DETERMINISTIC_CANONICAL_READ_V1'
               and canonical_read_judge->>'status'='PASS'
               and semantic_result is not distinct from canonical_read_judge
             )
           )
         )
         or (
           semantic_result->>'verdict'='PASS_REVIEWED_CURRENT_CONTEXT'
           and semantic_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
           and semantic_result->>'reviewer_is_producer'='true'
           and coalesce((semantic_result->>'producer_independence_proven')::boolean,true) is false
           and coalesce((semantic_result->>'model_call_count')::integer,-1)=0
           and (
             (
               coalesce((e.manifest->>'read_only')::boolean,false) is true
               and coalesce((e.manifest->>'no_write')::boolean,false) is true
               and coalesce((e.manifest->>'no_promotion')::boolean,false) is true
             )
             or (
               e.target_code='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
               and public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
             )
           )
           and semantic_result#>>'{judge_v3_evidence,verdict}'='PASS_REVIEWED_CURRENT_CONTEXT'
           and semantic_result#>>'{judge_v3_evidence,review_mode}'='CURRENT_CONTEXT_REVIEW'
           and semantic_result#>>'{judge_v3_evidence,reviewer_is_producer}'='true'
           and semantic_result#>>'{judge_v3_evidence,producer_independence_proven}'='false'
           and semantic_result#>>'{judge_v3_evidence,model_call_count}'='0'
           and semantic_result#>>'{judge_v3_evidence,router_direct_consistency}'='NOT_TESTED'
           and semantic_result#>>'{judge_v3_evidence,decision_checks,router_direct_consistency,result}'='not_applicable'
           and semantic_result#>>'{judge_v3_evidence,decision_checks,router_direct_consistency,applicability}'='ROUTER_ONLY'
           and semantic_result#>>'{judge_v3_evidence,counterfactual_result}'='PASS'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,context_resolution_valid,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,evidence_supported,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,decision_resolves_objective,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,authority_resolution_valid,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,constraints_preserved,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,claims_authorized,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,materiality_handled_correctly,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,tradeoff_defensible,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,acceptance_detects_wrong_implementation,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,handoff_implementation_ready,result}'='true'
             and semantic_result#>>'{judge_v3_evidence,decision_checks,counterfactual_trajectory,result}'='true'
         )
       )
       or coalesce(candidate_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or coalesce(scope_digest,'') !~ '^sha256:[0-9a-f]{64}$'
       or 'sha256:'||coalesce(semantic_result->>'candidate_sha256','')
          is distinct from candidate_digest
       or 'sha256:'||coalesce(semantic_result->>'scope_packet_sha256','')
          is distinct from scope_digest
       or jsonb_typeof(semantic_result->'result')<>'object'
       or semantic_result#>>'{result,verdict}'
          is distinct from semantic_result->>'verdict'
       or semantic_result#>>'{result,candidate_sha256}'
          is distinct from semantic_result->>'candidate_sha256'
       or semantic_result#>>'{result,scope_packet_sha256}'
          is distinct from semantic_result->>'scope_packet_sha256'
       or jsonb_typeof(p_evidence_payload->'unsupported_claims')<>'array'
       or jsonb_array_length(p_evidence_payload->'unsupported_claims')<>0
       or jsonb_typeof(semantic_result#>'{result,unsupported_claims}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,unsupported_claims}')<>0
       or jsonb_typeof(semantic_result#>'{result,blocking_codes}')<>'array'
       or jsonb_array_length(semantic_result#>'{result,blocking_codes}')<>0
    then
      hard:=hard||jsonb_build_array('semantic_judge_v2_not_pass');
    end if;

  elsif p_step_id='report_output' then
    select * into semantic_binding
    from public.lf_operation_step_judge_bindings
    where operation_code='EJECUCION_PERFIL_LF'
      and step_id='semantic_judge'
      and status='ACTIVE_ENFORCEMENT';
    select * into semantic_step
    from public.lf_operation_execution_steps
    where execution_id=p_execution_id and step_id='semantic_judge';

    if semantic_step.step_id is null
       or semantic_step.status<>semantic_binding.clean_result_value then
      hard:=hard||jsonb_build_array('semantic_judge_predecessor_not_clean');
    end if;

    if p_evidence_payload->>'result' is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,verdict}'
       or p_evidence_payload->>'profile_code' is distinct from e.target_code
       or p_evidence_payload->>'execution_id' is distinct from p_execution_id
       or coalesce((p_evidence_payload->>'no_write_performed')::boolean,false) is not true
       or p_evidence_payload->>'candidate_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,candidate_sha256}'
       or p_evidence_payload->>'scope_packet_sha256'
          is distinct from semantic_step.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}'
    then
      hard:=hard||jsonb_build_array('report_output_semantic_binding_invalid');
    end if;
  end if;

  if jsonb_array_length(hard)>0 then
    return jsonb_build_object(
      'valid',false,
      'code','PROFILE_EXECUTION_SERVER_VALIDATION_V2_FAILED',
      'details',jsonb_build_object('step_id',p_step_id,'hard_fails',hard),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('server_validation_failed')
    );
  end if;

  return jsonb_build_object(
    'valid',true,
    'code','PROFILE_EXECUTION_SERVER_VALIDATED_V2',
    'details',jsonb_build_object('step_id',p_step_id,'execution_id',p_execution_id),
    'server_assertions',jsonb_build_array('server_validated'),
    'server_hard_fails','[]'::jsonb
  );
end
$function$
;
COMMIT;
