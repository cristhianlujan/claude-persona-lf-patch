BEGIN;
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure)) <> '6e42b9cd2738b8c25049f7235b2fa188'
 THEN RAISE EXCEPTION 'LF_STEP70_CLEAN_EVAL_BRIDGE_PREIMAGE_DRIFT'; END IF;
 IF to_regprocedure('public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb)') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_STEP70_CLEAN_EVAL_VERIFIER_PREEXISTS_DRIFT'; END IF;
 IF to_regclass('public.lf_ig_native_chat_receipt_v1') IS NULL
 THEN RAISE EXCEPTION 'LF_STEP70_CLEAN_EVAL_CONTEXT_SOURCE_MISSING_DRIFT'; END IF;
END
$pre$;

-- Internal verification over EXISTING immutable B09 event table.
-- This function does NOT issue receipts, create LLM calls or grant effect authority.
CREATE FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1(
 p_execution_id text,p_semantic_judge_result jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $clean$
DECLARE
 e public.lf_operation_execution%ROWTYPE;
 r record;
 j jsonb;
 v50 public.lf_operation_execution_steps%ROWTYPE;
 v40 public.lf_operation_execution_steps%ROWTYPE;
 v60 public.lf_operation_execution_steps%ROWTYPE;
 n int:=0; tip text:=repeat('0',64); link_hash text;
 candidate text; scope_hash text; nonce_value text;
 expected_bundle text; bundle_hash text; producer_ctx text;
 producer_schema text; producer_eval text; producer_profile text;
 reviewer_ctx text; reviewer_schema text; reviewer_eval text;
 reviewer_profile text; receipt_ref text;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR e.manifest->>'governed_repair_write'<>'true'
    OR e.manifest->>'no_promotion'<>'true'
    OR p_semantic_judge_result->>'review_mode'<>'INDEPENDENT_EVAL_CONTEXT'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_SCOPE_INVALID'); END IF;
 SELECT * INTO v40 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT * INTO v50 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT * INTO v60 FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 IF v40.step_id IS NULL OR v50.step_id IS NULL OR v60.step_id IS NULL
   OR v60.evidence_payload#>>'{deterministic_validation,status}'<>'PASS'
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_UPSTREAM_NOT_CLEAN'); END IF;
 candidate:=v50.evidence_payload->>'raw_output_sha256';
 scope_hash:=replace(v40.evidence_payload->>'scope_authority_packet_sha256','sha256:','');
 IF coalesce(candidate,'') !~ '^[0-9a-f]{64}$' OR coalesce(scope_hash,'') !~ '^[0-9a-f]{64}$'
  OR p_semantic_judge_result->>'candidate_sha256' IS DISTINCT FROM candidate
  OR p_semantic_judge_result->>'scope_packet_sha256' IS DISTINCT FROM scope_hash
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_SOURCE_SHA_DRIFT'); END IF;
 expected_bundle:=encode(extensions.digest(convert_to(
    'LF_STEP70_FROZEN_BUNDLE_V1|'||candidate||'|'||scope_hash||'|'||v50.evidence_ref,
    'UTF8'),'sha256'),'hex');
 FOR r IN SELECT * FROM public.lf_ig_native_chat_receipt_v1
    WHERE execution_id=p_execution_id ORDER BY seq LOOP
   n:=n+1;
   IF n>3 OR r.seq<>n OR r.kind<>(CASE n WHEN 1 THEN 'REQUEST' WHEN 2 THEN 'EXECUTOR' WHEN 3 THEN 'JUDGE' END)
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_SEQUENCE_DRIFT'); END IF;
   IF encode(extensions.digest(convert_to(r.raw_text,'UTF8'),'sha256'),'hex')<>r.raw_sha256
      OR r.prev_sha256<>tip
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_RAW_SHA_DRIFT'); END IF;
   link_hash:=encode(extensions.digest(convert_to(
     'LF_NATIVE_CHAT_EVENT_V1|'||r.execution_id||'|'||r.seq::text||'|'||
     r.kind||'|'||r.raw_sha256||'|'||r.prev_sha256||'|'||
     r.writer_receipt_sha256,'UTF8'),'sha256'),'hex');
   IF link_hash<>r.chain_sha256 OR r.recorded_at<e.created_at
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_CHAIN_DRIFT'); END IF;
   j:=r.raw_text::jsonb;
   IF jsonb_typeof(j)<>'object' OR j->>'stage' IS DISTINCT FROM r.kind
      OR j->>'execution_id' IS DISTINCT FROM p_execution_id
      OR j->>'candidate_sha256' IS DISTINCT FROM candidate
      OR j->>'scope_packet_sha256' IS DISTINCT FROM scope_hash
      OR j->>'frozen_bundle_sha256' IS DISTINCT FROM expected_bundle
      OR coalesce(j->>'nonce','')=''
      OR (nonce_value IS NOT NULL AND j->>'nonce' IS DISTINCT FROM nonce_value)
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_BINDING_DRIFT'); END IF;
   IF n=1 THEN
     nonce_value:=j->>'nonce';bundle_hash:=j->>'frozen_bundle_sha256';
   ELSIF n=2 THEN
     producer_ctx:=nullif(j->>'executor_context_ref','');
     producer_schema:=nullif(j->>'producer_schema_id','');
     producer_eval:=nullif(j->>'producer_eval_id','');
     producer_profile:=nullif(j->>'producer_profile_id','');
     IF producer_ctx IS NULL OR producer_schema IS NULL OR producer_eval IS NULL
        OR producer_profile IS NULL OR r.recorded_at<v50.created_at
     THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_PRODUCER_CONFIG_MISSING'); END IF;
   ELSIF n=3 THEN
     reviewer_ctx:=nullif(j->>'reviewer_context_ref','');
     reviewer_schema:=nullif(j->>'reviewer_schema_id','');
     reviewer_eval:=nullif(j->>'reviewer_eval_id','');
     reviewer_profile:=nullif(j->>'reviewer_profile_id','');
     receipt_ref:=r.writer_receipt_ref;
     IF reviewer_ctx IS NULL OR reviewer_ctx=producer_ctx OR reviewer_schema IS NULL
        OR reviewer_schema<>'LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1'
        OR reviewer_schema=producer_schema
        OR reviewer_eval<>'LF_STEP70_SAME_LLM_SEMANTIC_EVAL_V1'
        OR reviewer_eval=producer_eval
        OR reviewer_profile IS NULL OR reviewer_profile=producer_profile
        OR j->>'review_mode' IS DISTINCT FROM 'INDEPENDENT_EVAL_CONTEXT'
        OR j->>'eval_status' IS DISTINCT FROM 'PASS'
        OR j->>'reviewer_context_cleared' IS DISTINCT FROM 'true'
        OR j->'review_payload' IS DISTINCT FROM p_semantic_judge_result->'judge_v3_evidence'
        OR r.recorded_at<=v50.created_at
     THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_JUDGE_NOT_ISOLATED'); END IF;
   END IF;
   tip:=r.chain_sha256;
 END LOOP;
 IF n<>3 THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','LF_STEP70_CLEAN_CONTEXT_RECEIPT_NOT_VERIFIED'); END IF;
 RETURN jsonb_build_object('status','CLEAN_CONTEXT_EVAL_VERIFIED',
   'execution_id',p_execution_id,'candidate_sha256',candidate,
   'scope_packet_sha256',scope_hash,'bundle_sha256',bundle_hash,
   'context_receipt_ref',receipt_ref,'reviewer_context_ref',reviewer_ctx,
   'producer_context_ref',producer_ctx,'judge_schema_id',reviewer_schema,
   'judge_eval_id',reviewer_eval,'chain_tip_sha256',tip,
   'provider_attestation_required',false,'effect_authority',false);
EXCEPTION WHEN invalid_text_representation THEN RETURN jsonb_build_object(
 'status','BLOCKED','blocking_code','LF_STEP70_CLEAN_CONTEXT_RAW_JSON_INVALID');
END
$clean$;
REVOKE ALL ON FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_step70_clean_eval_context_verify_v1(text,jsonb) TO service_role;

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
  v_family_judge jsonb;
  v_step jsonb;
  v_clean integer;
  v_verified_native jsonb;
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

  -- Governed SRCR clean-eval mode: independent CONTEXT and EVAL, same LLM.
  -- Server recomputes immutable event SHA chain and Step40/50/60 bindings.
  -- Model-authored flags alone cannot satisfy this verifier.
  IF p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT' THEN
    v_verified_native:=public.lf_profile_step70_clean_eval_context_verify_v1(
       p_execution_id,p_semantic_judge_result);
    IF v_verified_native->>'status' IS DISTINCT FROM 'CLEAN_CONTEXT_EVAL_VERIFIED' THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code',coalesce(v_verified_native->>'blocking_code',
          'LF_STEP70_CLEAN_CONTEXT_RECEIPT_NOT_VERIFIED'));
    END IF;
  END IF;

  -- Effects-bearing LF Product Director Step70 requires a genuinely
  -- verified independent native provider receipt. Read-only profiles retain
  -- their pre-existing current-context path. No HMAC / asserted-JSON bypass.
  IF e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND NOT (
      coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
      AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE
    )
  THEN
    IF p_semantic_judge_result->>'review_mode'
       IN ('CURRENT_CONTEXT_REVIEW','HMAC_TEST','MOCK')
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_SELF_REVIEW_FORBIDDEN'); END IF;
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING'); END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF jsonb_typeof(v_verified_native)<>'object'
      OR v_verified_native->>'status' IS DISTINCT FROM 'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'provider_receipt_ref'
           IS DISTINCT FROM p_semantic_judge_result->>'provider_receipt_ref'
      OR v_verified_native->>'candidate_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
           IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR coalesce(p_semantic_judge_result->>'provider_receipt_ref','')=''
      OR p_semantic_judge_result->>'producer_independence_proven'
           IS DISTINCT FROM 'true'
      OR p_semantic_judge_result->>'model_call_count'
           IS DISTINCT FROM '1'
    THEN RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','LF_STEP70_NATIVE_RECEIPT_NOT_VERIFIED'); END IF;
  END IF;

  -- An asserted independent review is not proof of another model/reviewer.
  -- No cryptographically verified provider attestation => refuse the authority
  -- claim; callers can continue read-only through CURRENT_CONTEXT_REVIEW.
  IF p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
    AND p_semantic_judge_result->>'review_mode' IS DISTINCT FROM 'INDEPENDENT_EVAL_CONTEXT' THEN
    IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','JUDGE_INDEPENDENCE_PROVIDER_VERIFIER_UNAVAILABLE');
    END IF;
    EXECUTE 'SELECT public.lf_ig_verified_native_provider_receipt_v1($1)'
      INTO v_verified_native USING p_execution_id;
    IF v_verified_native->>'status'<>'CRYPTOGRAPHICALLY_VERIFIED'
      OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
      OR v_verified_native->>'candidate_sha256'
            IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
      OR v_verified_native->>'scope_packet_sha256'
            IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
      OR p_semantic_judge_result->>'provider_receipt_ref'
            IS DISTINCT FROM v_verified_native->>'provider_receipt_ref'
      OR v_verified_native->>'reviewer_model_independence_proven'<>'true'
    THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','JUDGE_INDEPENDENCE_UNVERIFIED_AUTHORITY_CLAIM');
    END IF;
  END IF;

  IF p_semantic_judge_result->>'status' IS DISTINCT FROM 'PASS'
     OR p_semantic_judge_result->>'validator_status' IS DISTINCT FROM 'PASS'
     OR NOT (
       (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,false) IS TRUE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=1
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT'
         AND p_semantic_judge_result->>'reviewer_is_producer'='false'
         AND p_semantic_judge_result->>'producer_independence_proven'='true'
         AND p_semantic_judge_result->>'model_call_count' IS NULL
         AND v_verified_native->>'status'='CLEAN_CONTEXT_EVAL_VERIFIED'
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


  -- Independent V3 remains the authority for provenance; this specialist
  -- validates each claimed family/source equivalence and transferability.
  v_family_judge:=public.lf_input_family_semantic_transfer_eval_for_run_v1(
    p_execution_id,p_semantic_judge_result#>'{result,family_reuse_evaluation}');
  IF v_family_judge->>'status'='RETURN_TO_WORKER' THEN
    RETURN jsonb_build_object('status','RETURN_TO_WORKER',
      'code','FAMILY_REUSE_SEMANTIC_REVIEW_REQUIRED',
      'continuation_allowed',true,'family_reuse_evaluation',v_family_judge,
      'next_action','REVIEW_TRANSFERABILITY_AND_RESUME_SAME_RUN');
  END IF;
  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='semantic_judge';

  IF v_existing IS NULL OR v_existing IN ('BLOCKED_STEP_NOT_CLEAN', 'RETURN_TO_ROUTER') THEN
    -- Reuse the canonical recorder retry path, retaining attempt_history on the same RUN.
    v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'semantic_judge',
      p_evidence_ref,
      jsonb_build_object(
        'semantic_judge_result',p_semantic_judge_result,
        'family_reuse_evaluation',v_family_judge,
        'unsupported_claims','[]'::jsonb,
        'semantic_review_receipt_ref',p_evidence_ref,
        'independent_semantic_receipt_ref',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW' then null
          when p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT' then v_verified_native->>'context_receipt_ref'
          else v_verified_native->>'provider_receipt_ref' end,
        'judge_independence_status',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then 'NOT_PROVEN'
          when p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT'
            then 'CONTEXT_EVAL_VERIFIED'
          else 'PROVIDER_VERIFIED' end,
        'content_findings',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then jsonb_build_array(jsonb_build_object(
               'finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN',
               'continuation_allowed',true,'effect_authority',false,
               'reviewer_is_producer',true,'producer_independence_proven',false,
               'model_call_count',0))
          else '[]'::jsonb end
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
COMMIT;
