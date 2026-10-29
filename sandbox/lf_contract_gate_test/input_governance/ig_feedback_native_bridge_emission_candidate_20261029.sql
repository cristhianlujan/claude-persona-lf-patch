-- LF profile native output envelope feedback: SOURCE-ONLY SANDBOX CANDIDATE.
-- Does not change profile schema, CI, ACL, model output, Router selection, IG.
-- The native caller still must independently attest raw model evidence.
BEGIN;
DO $precheck$ BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)'::regprocedure))<>'e16131b4a542c71867e59730ca14b253' THEN
  RAISE EXCEPTION 'IG_FB_NATIVE_BRIDGE_SOURCE_DRIFT';
 END IF;
END $precheck$;

CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_output_v1(p_execution_id text, p_profile_output jsonb, p_validation jsonb, p_raw_evidence_ref text, p_validator_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_actor text;
  v_context public.lf_operation_execution_steps%rowtype;
  v_baseline public.lf_operation_execution_steps%rowtype;
  v_source public.lf_operation_execution_steps%rowtype;
  v_existing text;
  v_candidate_digest text;
  v_raw_sha text;
  v_step jsonb;
  v_clean integer;
  v_source_refs jsonb;
  v_model_feedback jsonb;
  v_model_response_envelope jsonb;
  v_model_envelope_sha text;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR jsonb_typeof(p_profile_output)<>'object'
     OR jsonb_typeof(p_validation)<>'object'
     OR coalesce((p_validation->>'valid')::boolean,false) IS NOT TRUE
     OR (
       jsonb_typeof(p_validation->'blocking_codes')='array'
       AND jsonb_array_length(p_validation->'blocking_codes')<>0
     )
     OR nullif(btrim(coalesce(p_raw_evidence_ref,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_validator_evidence_ref,'')),'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_INPUT_INVALID'
    );
  END IF;

  SELECT * INTO e
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR e.operation_code<>'EJECUCION_PERFIL_LF'
     OR e.target_type<>'PERFIL'
     OR e.status<>'IN_PROGRESS'
     OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
     OR e.manifest->>'executor_provider'<>'OPENAI_CHATGPT_NATIVE'
     OR e.manifest ? 'queue_request_id'
     OR nullif(e.manifest->>'runtime_target','') IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_EXECUTION_INVALID'
    );
  END IF;

  SELECT * INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  SELECT * INTO v_source
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='profile_source_read'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context.step_id IS NULL
     OR v_baseline.step_id IS NULL
     OR v_source.step_id IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_PREDECESSOR_NOT_CLEAN'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_candidate_digest:='sha256:'||encode(
    extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
    'hex'
  );
  v_raw_sha=substr(v_candidate_digest,8);
  v_source_refs:=jsonb_build_array(
    v_source.evidence_payload->>'profile_source_ref',
    v_context.evidence_payload->>'context_receipt_ref'
  );

  -- An optional profile-neutral feedback is sourced from the SAME native
  -- response envelope as the specialist output. The model's deliverable
  -- remains schema-clean; only its execution evidence carries the sidecar.
  IF p_validation ? 'ig_profile_feedback_candidate' THEN
    v_model_feedback:=p_validation->'ig_profile_feedback_candidate';
    v_model_response_envelope:=p_validation->'native_model_response_envelope';
    IF jsonb_typeof(v_model_feedback) IS DISTINCT FROM 'object'
      OR jsonb_typeof(v_model_response_envelope) IS DISTINCT FROM 'object'
      OR (SELECT count(*) FROM jsonb_object_keys(v_model_response_envelope) z(k))<>2
      OR NOT (v_model_response_envelope ? 'profile_output')
      OR NOT (v_model_response_envelope ? 'ig_profile_feedback')
      OR v_model_response_envelope->'profile_output' IS DISTINCT FROM p_profile_output
      OR v_model_response_envelope->'ig_profile_feedback' IS DISTINCT FROM v_model_feedback
      OR v_model_feedback->>'source_execution_id' IS DISTINCT FROM p_execution_id
      OR v_model_feedback->>'source_profile_code' IS DISTINCT FROM e.target_code
      OR v_model_feedback->>'source_profile_output_sha256' IS DISTINCT FROM v_candidate_digest
      OR p_validation->>'native_model_evidence_ref' IS DISTINCT FROM p_raw_evidence_ref
      OR p_validation->>'native_response_admission' IS DISTINCT FROM 'VALIDATED_NATIVE_ENVELOPE'
    THEN RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_FEEDBACK_ORIGIN_ENVELOPE_INVALID'); END IF;

    v_model_envelope_sha:='sha256:'||encode(extensions.digest(
      convert_to(v_model_response_envelope::text,'UTF8'),'sha256'),'hex');
    IF p_validation->>'native_model_response_sha256' IS DISTINCT FROM v_model_envelope_sha THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_FEEDBACK_ENVELOPE_SHA_MISMATCH');
    END IF;
    -- This is a source-envelope binding, not independent authenticity proof.
    -- The trusted native executor must still verify raw evidence bytes.
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'execute_profile',
      p_raw_evidence_ref,
      jsonb_build_object(
        'context_receipt_digest',v_context.evidence_payload->>'context_receipt_digest',
        'context_receipt_ref',v_context.evidence_payload->>'context_receipt_ref',
        'context_transport',jsonb_build_object(
          'profile_source_mode','JIT_BY_REF',
          'jit_resolver_ref','supabase://public.v_lf_fuente_operativa/EVIDENCE_RESOLVER_REGISTRY',
          'jit_only',true,
          'policy_payloads',false,
          'full_ekb_entries',false,
          'full_readmes',false,
          'full_prefetch_count',0,
          'hydrated_refs','[]'::jsonb
        ),
        'profile_output',p_profile_output,
        'candidate_digest',v_candidate_digest,
        'raw_output_sha256',v_raw_sha,
        'research_baseline_digest',
          v_baseline.evidence_payload#>>'{research_baseline_binding,baseline_digest}',
        'research_baseline_ref',v_baseline.evidence_payload->>'baseline_receipt_ref',
        'source_refs',v_source_refs
      ) || CASE WHEN v_model_feedback IS NOT NULL
           THEN jsonb_build_object(
             'ig_profile_feedback_candidate',v_model_feedback,
             'ig_feedback_native_response_sha256',v_model_envelope_sha,
             'ig_feedback_native_evidence_ref',p_raw_evidence_ref,
             'ig_feedback_origin_verification','BOUND_TO_SUBMITTED_NATIVE_ENVELOPE_NOT_INDEPENDENTLY_ATTESTED'
           )
           ELSE '{}'::jsonb END,
      
      v_actor
    );
  ELSIF v_model_feedback IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution_steps prev
    WHERE prev.execution_id=p_execution_id AND prev.step_id='execute_profile'
      AND prev.status='STEP_PASS_WITH_EVIDENCE'
      AND prev.evidence_payload->'ig_profile_feedback_candidate' IS NOT DISTINCT FROM v_model_feedback
      AND prev.evidence_payload->>'ig_feedback_native_response_sha256'=v_model_envelope_sha
  ) THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_FEEDBACK_REPLAY_CONFLICT');
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTE_PROFILE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'output_validate',
      p_validator_evidence_ref,
      jsonb_build_object(
        'output_contract_result','PASS',
        'deterministic_validation',
          (p_validation-'native_model_response_envelope'-'ig_profile_feedback_candidate')
          ||jsonb_build_object(
            'status','PASS',
            'candidate_digest',v_candidate_digest
          ),
        'raw_output_sha256',v_raw_sha
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_OUTPUT_VALIDATE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>9 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_POST_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',9
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_PRODUCER_VALIDATED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'candidate_digest',v_candidate_digest,
    'raw_output_sha256',v_raw_sha,
    'clean_step_count',v_clean,
    'next_step','semantic_judge',
    'next_action','RUN_INDEPENDENT_SEMANTIC_JUDGE',
    'independent_semantic_judge_required',true,
    'producer_may_self_authorize',false,
    'terminal_authority_ready',false,
    'router_reentry_required',false
  );
END
$function$;

-- No live fixture or runtime calls are performed in a production database.
ROLLBACK;
