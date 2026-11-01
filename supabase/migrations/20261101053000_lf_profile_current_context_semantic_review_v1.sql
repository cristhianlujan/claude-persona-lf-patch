-- LF governed read-only current-context V3 review. Owner-approved alternative:
-- SAME-CONTEXT is not independent; avoid invented provider calls.
-- Existing independent V3 mode remains compatible. No Router/service_role change.
-- All writes exclusively through the LF Migration Merge Train.
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
           and coalesce((e.manifest->>'read_only')::boolean,false) is true
           and coalesce((e.manifest->>'no_write')::boolean,false) is true
           and coalesce((e.manifest->>'no_promotion')::boolean,false) is true
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
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_semantic_v1(p_execution_id text, p_semantic_judge_result jsonb, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_existing text;
  v_step jsonb;
  v_clean integer;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_semantic_judge_result)<>'object'
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXECUTION_INVALID'
    );
  END IF;

  IF p_semantic_judge_result->>'status' IS DISTINCT FROM 'PASS'
     OR p_semantic_judge_result->>'validator_status' IS DISTINCT FROM 'PASS'
     OR NOT (
       (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,false) IS TRUE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=1
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_REVIEWED_CURRENT_CONTEXT'
         AND p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
         AND p_semantic_judge_result->>'reviewer_is_producer'='true'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,true) IS FALSE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=0
         AND coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
         AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
         AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE
       )
     )
     OR jsonb_typeof(p_semantic_judge_result#>'{result,unsupported_claims}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,unsupported_claims}')<>0
     OR jsonb_typeof(p_semantic_judge_result#>'{result,blocking_codes}')<>'array'
     OR jsonb_array_length(p_semantic_judge_result#>'{result,blocking_codes}')<>0 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_JUDGE_NOT_PASS'
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge';

  IF v_existing IS NULL THEN
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'semantic_judge',
      p_evidence_ref,
      jsonb_build_object(
        'semantic_judge_result',p_semantic_judge_result,
        'unsupported_claims','[]'::jsonb,
        'semantic_review_receipt_ref',p_evidence_ref,
        'independent_semantic_receipt_ref',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW' then null
          else p_evidence_ref end
      ),
      v_actor
    );

    IF coalesce(v_step->>'status',v_step->>'step_status')
       IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;

  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>10 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_SEMANTIC_POST_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',10
    );
  END IF;

  RETURN jsonb_build_object(
    'status','SEMANTIC_JUDGE_RECORDED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','semantic_judge',
    'next_step','report_output',
    'next_action','RECORD_EXISTING_REPORT_OUTPUT'
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(p_execution_id text, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_semantic public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_actor text;
  v_candidate text;
  v_scope text;
  v_semantic_receipt text;
  v_step jsonb;
  v_clean integer;
  v_terminal jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_INPUT_INVALID');
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status NOT IN ('IN_PROGRESS','COMPLETED')
     OR NOT COALESCE(
       (e.manifest->>'executor_mode'='GPT_NATIVE'
        AND e.manifest->>'executor_provider'='OPENAI_CHATGPT_NATIVE')
       OR
       (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false
     )
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_INVALID');
  END IF;

  SELECT * INTO v_semantic
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_semantic.step_id IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_NOT_CLEAN');
  END IF;

  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';
  v_scope:=v_semantic.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}';
  v_semantic_receipt:=coalesce(v_semantic.evidence_payload->>'semantic_review_receipt_ref',v_semantic.evidence_payload->>'independent_semantic_receipt_ref');

  IF coalesce(v_candidate,'') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_scope,'') !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_SEMANTIC_BINDING_INVALID');
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='report_output';

  IF v_existing IS NULL THEN
    IF e.status<>'IN_PROGRESS' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXECUTION_ALREADY_CLOSED_WITHOUT_REPORT');
    END IF;
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'report_output',
      p_evidence_ref,
      jsonb_build_object(
        'result',v_semantic.evidence_payload#>>'{semantic_judge_result,verdict}',
        'execution_id',p_execution_id,
        'profile_code',e.target_code,
        'no_write_performed',true,
        'candidate_sha256',v_candidate,
        'scope_packet_sha256',v_scope,
        'semantic_review_receipt_ref',v_semantic_receipt,
        'independent_semantic_receipt_ref',case
          when v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW' then null
          else v_semantic_receipt end,
        'next_gate','RETURN_TO_ROUTER'
      ),
      v_actor
    );
    IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_RECORD_REJECTED',
        'recorder_result',v_step
      );
    END IF;
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_EXISTING_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF v_clean<>11 OR e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_COMPLETION_NOT_CLEAN',
      'clean_step_count',v_clean,
      'execution_status',e.status
    );
  END IF;

  v_terminal:=public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id);
  IF v_terminal->>'status' IS DISTINCT FROM 'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_REPORT_TERMINAL_RECEIPT_NOT_READY',
      'terminal_result',v_terminal
    );
  END IF;

  RETURN jsonb_build_object(
    'status','PROFILE_EXECUTION_COMPLETED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','report_output',
    'execution_status',e.status,
    'terminal_authority_receipt_sha256',v_terminal->>'terminal_authority_receipt_sha256',
    'next_gate','RETURN_TO_ROUTER'
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_terminal_authority_receipt_v1(p_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  j record;
  v_steps jsonb;
  v_step_count int;
  v_router jsonb;
  v_router_kind text;
  v_scope jsonb;
  v_source jsonb;
  v_context jsonb;
  v_execute jsonb;
  v_output jsonb;
  v_semantic jsonb;
  v_report jsonb;
  v_literal text;
  v_body jsonb;
  v_sha text;
  v_queue_request_id text;
  v_executor_mode text;
  v_executor_provider text;
  v_transport_kind text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTION_INVALID'
    );
  END IF;

  IF e.status<>'COMPLETED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTION_NOT_COMPLETED',
      'canonical_status',e.status
    );
  END IF;

  SELECT required_steps,required_steps_pass,fail_count,blocked_count,judge_result
    INTO j
  FROM public.v_lf_operation_execution_judge
  WHERE execution_id=p_execution_id;

  IF j IS NULL
     OR j.judge_result IS DISTINCT FROM 'PASS'
     OR j.required_steps IS DISTINCT FROM 11
     OR j.required_steps_pass IS DISTINCT FROM j.required_steps
     OR coalesce(j.fail_count,0)<>0
     OR coalesce(j.blocked_count,0)<>0
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_JUDGE_NOT_CLEAN',
      'judge_result',coalesce(j.judge_result,'MISSING'),
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count
    );
  END IF;

  SELECT count(*),
         jsonb_object_agg(
           s.step_id,
           jsonb_build_object(
             'status',s.status,
             'evidence_ref',s.evidence_ref,
             'evidence_payload',s.evidence_payload
           )
           ORDER BY os.step_order
         )
    INTO v_step_count,v_steps
  FROM public.lf_operation_execution_steps s
  JOIN public.lf_operation_steps os
    ON os.operation_code='EJECUCION_PERFIL_LF'
   AND os.step_id=s.step_id
   AND os.active
  WHERE s.execution_id=p_execution_id
    AND s.status='STEP_PASS_WITH_EVIDENCE';

  IF v_step_count<>11 OR jsonb_typeof(v_steps)<>'object' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_STEP_SET_INCOMPLETE',
      'clean_steps',v_step_count
    );
  END IF;

  v_router:=coalesce(
    v_steps#>'{router,evidence_payload,router_authorization_receipt}',
    v_steps#>'{router,evidence_payload,router_result}'
  );

  IF v_steps#>'{router,evidence_payload,router_authorization_receipt}' IS NOT NULL THEN
    v_router_kind:='CARRIED_AUTHORIZATION_RECEIPT';
  ELSE
    v_router_kind:='LEGACY_ROUTER_RESULT';
  END IF;

  v_scope:=v_steps#>'{input_validate,evidence_payload,scope_authority_packet}';
  v_source:=v_steps#>'{profile_source_read,evidence_payload}';
  v_context:=v_steps#>'{context_admission,evidence_payload}';
  v_execute:=v_steps#>'{execute_profile,evidence_payload}';
  v_output:=v_steps#>'{output_validate,evidence_payload}';
  v_semantic:=v_steps#>'{semantic_judge,evidence_payload}';
  v_report:=v_steps#>'{report_output,evidence_payload}';
  v_literal:=v_scope#>>'{authorized_requirements,0,statement}';

  IF jsonb_typeof(v_router)<>'object'
     OR (
       v_router_kind='CARRIED_AUTHORIZATION_RECEIPT'
       AND (
         v_router->>'schema_version'<>'LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1'
         OR v_router->>'router'<>'ACT-0001'
         OR v_router->>'profile_code' IS DISTINCT FROM e.target_code
         OR v_router->>'action_code'<>'PROFILE_EXECUTION'
         OR v_router->>'operation_code'<>'EJECUCION_PERFIL_LF'
         OR coalesce((v_router->>'profile_execution_allowed')::boolean,false) IS NOT TRUE
         OR coalesce((v_router->>'router_reentry_before_execution')::boolean,true) IS NOT FALSE
       )
     )
     OR (
       v_router_kind='LEGACY_ROUTER_RESULT'
       AND (
         v_router->>'status'<>'READY_TO_EXECUTE'
         OR v_router->>'operation_code'<>'EJECUCION_PERFIL_LF'
       )
     )
     OR jsonb_typeof(v_scope)<>'object'
     OR v_scope->>'packet_version'<>'LF_SCOPE_AUTHORITY_PACKET_V1'
     OR coalesce(v_scope->>'sha256','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_source)<>'object'
     OR coalesce(v_source->>'profile_source_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_context)<>'object'
     OR coalesce(v_context->>'context_receipt_digest','') !~ '^sha256:[0-9a-f]{64}$'
     OR jsonb_typeof(v_execute)<>'object'
     OR jsonb_typeof(v_execute->'profile_output')<>'object'
     OR jsonb_typeof(v_output)<>'object'
     OR jsonb_typeof(v_semantic)<>'object'
     OR v_semantic#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
     OR jsonb_typeof(v_report)<>'object'
     OR v_semantic#>>'{semantic_judge_result,verdict}' NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
     OR v_report->>'result' IS DISTINCT FROM v_semantic#>>'{semantic_judge_result,verdict}'
     OR nullif(v_literal,'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_AUTHORITY_CHAIN_INCOMPLETE',
      'router_authority_kind',v_router_kind
    );
  END IF;

  v_queue_request_id:=nullif(btrim(coalesce(e.manifest->>'queue_request_id','')),'');
  v_executor_mode:=upper(nullif(btrim(coalesce(e.manifest->>'executor_mode','')),''));
  v_executor_provider:=nullif(btrim(coalesce(e.manifest->>'executor_provider','')),'');

  IF v_executor_mode IS NULL AND v_queue_request_id IS NOT NULL THEN
    v_executor_mode:='REMOTE_API';
  END IF;

  IF v_executor_mode IS NULL
     OR v_executor_mode NOT IN ('GPT_NATIVE','CLAUDE_NATIVE','REMOTE_API') THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_EXECUTOR_MODE_INVALID',
      'executor_mode',v_executor_mode
    );
  END IF;

  IF v_executor_mode='REMOTE_API' THEN
    IF v_queue_request_id IS NULL THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','QUEUE_REQUEST_ID_REQUIRED_FOR_REMOTE_API'
      );
    END IF;
    v_transport_kind:='REMOTE_API_QUEUE';

  ELSIF v_executor_mode='GPT_NATIVE' THEN
    IF v_queue_request_id IS NOT NULL
       OR v_executor_provider IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
       OR nullif(btrim(coalesce(e.manifest->>'runtime_target','')),'') IS NOT NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','GPT_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE'
      );
    END IF;
    v_transport_kind:='NATIVE_CURRENT_CONTEXT';

  ELSIF v_executor_mode='CLAUDE_NATIVE' THEN
    IF v_queue_request_id IS NOT NULL
       OR v_executor_provider IS DISTINCT FROM 'ANTHROPIC_CLAUDE_NATIVE'
       OR nullif(btrim(coalesce(e.manifest->>'runtime_target','')),'') IS NOT NULL
    THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'code','PROFILE_TERMINAL_RECEIPT_TRANSPORT_BINDING_INVALID',
        'executor_mode',v_executor_mode,
        'reason','CLAUDE_NATIVE_REQUIRES_NATIVE_PROVIDER_AND_NO_REMOTE_QUEUE'
      );
    END IF;
    v_transport_kind:='NATIVE_CURRENT_CONTEXT';
  END IF;

  IF e.manifest->>'input_sha256' IS NULL
     OR v_scope->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'execution_id' IS DISTINCT FROM p_execution_id
     OR v_report->>'profile_code' IS DISTINCT FROM e.target_code
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'code','PROFILE_TERMINAL_RECEIPT_IDENTITY_MISMATCH'
    );
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_PROFILE_RUNTIME_TERMINAL_AUTHORITY_RECEIPT_V1',
    'queue_request_id',v_queue_request_id,
    'canonical_execution_id',e.execution_id,
    'operation_code',e.operation_code,
    'profile_code',e.target_code,
    'executor_mode',v_executor_mode,
    'execution_transport',v_transport_kind,
    'executor_provider',v_executor_provider,
    'input_literal',v_literal,
    'input_literal_sha256',e.manifest->>'input_sha256',
    'router_authority_kind',v_router_kind,
    'router_authority_receipt',v_router,
    'scope_authority_packet',v_scope,
    'scope_authority_packet_sha256',
      v_steps#>>'{input_validate,evidence_payload,scope_authority_packet_sha256}',
    'profile_source_receipt',v_source,
    'context_receipt',jsonb_build_object(
      'ref',v_context->>'context_receipt_ref',
      'digest',v_context->>'context_receipt_digest',
      'server_validated',v_context->'server_validated'
    ),
    'raw_output_receipt',jsonb_build_object(
      'profile_output_sha256','sha256:'||encode(
        extensions.digest(
          convert_to((v_execute->'profile_output')::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ),
      'execute_evidence_ref',v_steps#>>'{execute_profile,evidence_ref}'
    ),
    'validator_receipt',jsonb_build_object(
      'output_contract_result',v_output->>'output_contract_result',
      'deterministic_validation',v_output->'deterministic_validation',
      'evidence_ref',v_steps#>>'{output_validate,evidence_ref}'
    ),
    'semantic_judge_receipt',v_semantic,
    'report_output_receipt',v_report,
    'canonical_judge_readback',jsonb_build_object(
      'required_steps',j.required_steps,
      'required_steps_pass',j.required_steps_pass,
      'fail_count',j.fail_count,
      'blocked_count',j.blocked_count,
      'judge_result',j.judge_result
    ),
    'source_refs',jsonb_build_array(
      v_steps#>>'{router,evidence_ref}',
      v_steps#>>'{input_validate,evidence_ref}',
      v_steps#>>'{profile_source_read,evidence_ref}',
      v_steps#>>'{context_admission,evidence_ref}',
      v_steps#>>'{execute_profile,evidence_ref}',
      v_steps#>>'{output_validate,evidence_ref}',
      v_steps#>>'{semantic_judge,evidence_ref}',
      v_steps#>>'{report_output,evidence_ref}'
    ),
    'authority_rule','ROUTER_AND_OPERATION_EVIDENCE_ONLY_NO_SPECIALIST_EFFECT_AUTHORITY'
  );

  v_sha:='sha256:'||encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','READY',
    'terminal_authority_receipt',
      v_body||jsonb_build_object('sha256',v_sha),
    'terminal_authority_receipt_sha256',v_sha
  );
END
$function$;
