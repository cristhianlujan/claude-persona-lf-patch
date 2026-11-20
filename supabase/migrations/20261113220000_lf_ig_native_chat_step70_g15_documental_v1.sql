-- B09/G12-G15 Phase 1. Governed documentary risk route, not Ed25519 or model independence.
-- SAME_LLM_SEPARATE_CHAT is only a candidate until official OIDC/nonce writer binding is installed.
-- No production authorization; G15 remains NO_GO_MOTOR for every call.
-- Baseline EKB V1.4 + docs/input-governance/b09-native-chat/03_enmienda_B09_G12_G15_firma_documental_20261113.md
BEGIN;
DO $b09_preflight$
BEGIN
 IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL
    OR to_regclass('public.lf_ig_native_chat_receipt_v1') IS NULL
    OR to_regprocedure('public.lf_record_profile_execution_step_v1(text,text,text,jsonb,text)') IS NULL
    OR md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
        IS DISTINCT FROM '78cb1b8fab6975f4539a79baa2ab11fd'
    OR md5(pg_get_functiondef('public.lf_ig_g15_motor_temporary_v1(jsonb)'::regprocedure))
        IS DISTINCT FROM 'eb1779e3d958d26d56a20f22ed717235'
 THEN RAISE EXCEPTION 'B09_DOCUMENTAL_STEP70_G15_PREIMAGE_DRIFT'; END IF;
END $b09_preflight$;

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
  v_verified_native jsonb;
  v_documental boolean:=false;
  v_writer_binding jsonb;
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

    -- Documentary same-LLM branch: no vendor signature or independent model.
    -- The official writer binding is a required separately governed dependency.
    IF p_semantic_judge_result->>'review_mode'='SAME_LLM_SEPARATE_CHAT'
       OR p_semantic_judge_result->>'verdict'='PASS_SEMANTIC_COMPENSATED_SAME_MODEL' THEN
      IF e.manifest->>'executor_mode' IS DISTINCT FROM 'GPT_NATIVE'
         OR e.manifest->>'executor_provider' IS DISTINCT FROM 'OPENAI_CHATGPT_NATIVE'
         OR p_semantic_judge_result->>'review_mode' IS DISTINCT FROM 'SAME_LLM_SEPARATE_CHAT'
         OR p_semantic_judge_result->>'verdict' IS DISTINCT FROM 'PASS_SEMANTIC_COMPENSATED_SAME_MODEL'
         OR p_semantic_judge_result->>'producer_independence_proven' IS DISTINCT FROM 'false'
         OR p_semantic_judge_result->>'reviewer_model_independence_proven' IS DISTINCT FROM 'false'
         OR p_semantic_judge_result->>'vendor_model_provenance_verified' IS DISTINCT FROM 'false'
         OR p_semantic_judge_result->>'reviewer_is_producer' IS DISTINCT FROM 'false'
         OR p_semantic_judge_result->>'effect_authority' IS DISTINCT FROM 'false'
         OR p_semantic_judge_result->>'model_call_count' IS DISTINCT FROM '1' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','LF_STEP70_SHA_DOCUMENTAL_RISK_MODE_INVALID'); END IF;
      IF to_regprocedure('public.lf_ig_verified_native_provider_receipt_v1(text)') IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','LF_STEP70_NATIVE_PROVIDER_VERIFIER_MISSING'); END IF;
      IF to_regprocedure('public.lf_ig_native_chat_official_writer_binding_receipt_v1(text)') IS NULL THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','LF_STEP70_SHA_OFFICIAL_WRITER_BINDING_MISSING'); END IF;
      v_verified_native:=public.lf_ig_verified_native_provider_receipt_v1(p_execution_id);
      EXECUTE 'SELECT public.lf_ig_native_chat_official_writer_binding_receipt_v1($1)'
        INTO v_writer_binding USING p_execution_id;
      IF jsonb_typeof(v_verified_native)<>'object'
         OR v_verified_native->>'status' IS DISTINCT FROM 'SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED'
         OR v_verified_native->>'execution_id' IS DISTINCT FROM p_execution_id
         OR v_verified_native->>'integrity_verified' IS DISTINCT FROM 'true'
         OR v_verified_native->>'effect_authority' IS DISTINCT FROM 'false'
         OR v_verified_native->>'downstream_execution_allowed' IS DISTINCT FROM 'false'
         OR v_verified_native->>'reviewer_model_independence_proven' IS DISTINCT FROM 'false'
         OR v_verified_native->>'vendor_model_provenance_verified' IS DISTINCT FROM 'false'
         OR v_verified_native->>'producer_chat_ref' IS NOT DISTINCT FROM v_verified_native->>'judge_chat_ref'
         OR jsonb_typeof(v_writer_binding)<>'object'
         OR v_writer_binding->>'status' IS DISTINCT FROM 'OFFICIAL_OIDC_WRITER_NONCE_CHAIN_BOUND'
         OR v_writer_binding->>'issuer' IS DISTINCT FROM 'lf-profiles-governance-caller-v1'
         OR v_writer_binding->>'execution_id' IS DISTINCT FROM p_execution_id
         OR v_writer_binding->>'chain_tip_sha256' IS DISTINCT FROM v_verified_native->>'chain_tip_sha256'
         OR v_writer_binding->>'candidate_sha256' IS DISTINCT FROM v_verified_native->>'candidate_sha256'
         OR v_writer_binding->>'scope_packet_sha256' IS DISTINCT FROM v_verified_native->>'scope_packet_sha256'
         OR v_writer_binding->>'nonce_binding_verified' IS DISTINCT FROM 'true'
         OR v_writer_binding->>'canonical_recorder_bound' IS DISTINCT FROM 'true'
         OR v_verified_native->>'provider_receipt_ref' IS DISTINCT FROM p_semantic_judge_result->>'provider_receipt_ref'
         OR v_verified_native->>'candidate_sha256' IS DISTINCT FROM p_semantic_judge_result->>'candidate_sha256'
         OR v_verified_native->>'scope_packet_sha256' IS DISTINCT FROM p_semantic_judge_result->>'scope_packet_sha256'
         OR v_verified_native->>'chain_tip_sha256' IS DISTINCT FROM p_semantic_judge_result->>'chain_tip_sha256'
         OR v_verified_native->>'producer_prompt_sha256' IS DISTINCT FROM p_semantic_judge_result->>'producer_prompt_sha256'
         OR v_verified_native->>'reviewer_prompt_sha256' IS DISTINCT FROM p_semantic_judge_result->>'reviewer_prompt_sha256' THEN
        RETURN jsonb_build_object('status','BLOCKED',
          'blocking_code','LF_STEP70_SHA_DOCUMENTAL_WRITER_RECEIPT_NOT_BOUND'); END IF;
      v_documental:=true;
    ELSE
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
  END IF;

  IF p_semantic_judge_result->>'status' IS DISTINCT FROM 'PASS'
     OR p_semantic_judge_result->>'validator_status' IS DISTINCT FROM 'PASS'
     OR NOT (
       (
         p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC'
         AND coalesce((p_semantic_judge_result->>'producer_independence_proven')::boolean,false) IS TRUE
         AND coalesce((p_semantic_judge_result->>'model_call_count')::integer,-1)=1
       ) OR (
         v_documental IS TRUE
         AND p_semantic_judge_result->>'verdict'='PASS_SEMANTIC_COMPENSATED_SAME_MODEL'
         AND p_semantic_judge_result->>'review_mode'='SAME_LLM_SEPARATE_CHAT'
         AND p_semantic_judge_result->>'producer_independence_proven'='false'
         AND p_semantic_judge_result->>'reviewer_model_independence_proven'='false'
         AND p_semantic_judge_result->>'model_call_count'='1'
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

  IF v_existing IS NULL OR v_existing IN ('BLOCKED_STEP_NOT_CLEAN', 'RETURN_TO_ROUTER') THEN
    -- Reuse the canonical recorder retry path, retaining attempt_history on the same RUN.
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
          when p_semantic_judge_result->>'review_mode' IN ('CURRENT_CONTEXT_REVIEW','SAME_LLM_SEPARATE_CHAT') then null
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
    'same_llm_documental_risk_accepted',v_documental,
    'model_independence_proven',case when v_documental then false else null end,
    'next_step','report_output',
    'next_action','RECORD_EXISTING_REPORT_OUTPUT'
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_ig_g15_motor_temporary_v1(p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE expected text[]:=ARRAY[
 'B02_RUN_SCOPE','B03_RUN_EFFECTS','B06_OWNER','B07_SCHEMA',
 'B08_IDENTITY','B09_E2E','B12_LEGACY'];
 v text;missing text[]:=ARRAY[]::text[];
 v_b09_run text;
 v_native jsonb;
 v_binding jsonb;
BEGIN
 IF jsonb_typeof(p_evidence)<>'object' THEN
   RETURN jsonb_build_object('status','NO_GO_MOTOR',
     'blocking_code','G15_MOTOR_EVIDENCE_MISSING'); END IF;
 FOREACH v IN ARRAY expected LOOP
   IF jsonb_typeof(p_evidence->v)<>'object'
     OR p_evidence->v->>'status'<>'VERIFIED'
     OR char_length(coalesce(p_evidence->v->>'sha256',''))<>64
     OR coalesce(p_evidence->v->>'sha256','') ~ '[^0-9a-f]'
     OR nullif(p_evidence->v->>'evidence_ref','') IS NULL
   THEN missing:=array_append(missing,v); END IF;
 END LOOP;
 IF cardinality(missing)>0 THEN
   RETURN jsonb_build_object('status','NO_GO_MOTOR',
     'blocking_code','G15_MOTOR_7_OF_7_NOT_EVIDENCED',
     'missing_or_unverified',to_jsonb(missing)); END IF;
 -- B09 documental SHA is neither provider authentication nor independent-model evidence.
 -- SHA risk acceptance NEVER grants full motor GO or production authorization.
 IF p_evidence#>>'{B09_E2E,risk_mode}'='SAME_LLM_SEPARATE_CHAT_SHA256_DOCUMENTAL' THEN
   v_b09_run:=p_evidence#>>'{B09_E2E,execution_id}';
   IF coalesce(v_b09_run,'') !~ '^EXEC-[A-Za-z0-9_-]{8,}$'
      OR to_regprocedure('public.lf_ig_native_chat_official_writer_binding_receipt_v1(text)') IS NULL THEN
     RETURN jsonb_build_object('status','NO_GO_MOTOR',
       'blocking_code','G15_B09_DOCUMENTAL_OFFICIAL_WRITER_NOT_READY',
       'b09_documental_accepted',false); END IF;
   v_native:=public.lf_ig_verified_native_provider_receipt_v1(v_b09_run);
   EXECUTE 'SELECT public.lf_ig_native_chat_official_writer_binding_receipt_v1($1)'
      INTO v_binding USING v_b09_run;
   IF v_native->>'status' IS DISTINCT FROM 'SHA256_CHAIN_VERIFIED_DOCUMENTAL_PROVENANCE_UNATTESTED'
      OR v_native->>'execution_id' IS DISTINCT FROM v_b09_run
      OR v_binding->>'status' IS DISTINCT FROM 'OFFICIAL_OIDC_WRITER_NONCE_CHAIN_BOUND'
      OR v_binding->>'nonce_binding_verified' IS DISTINCT FROM 'true'
      OR v_binding->>'canonical_recorder_bound' IS DISTINCT FROM 'true'
      OR v_binding->>'chain_tip_sha256' IS DISTINCT FROM v_native->>'chain_tip_sha256'
      OR p_evidence#>>'{B09_E2E,sha256}' IS DISTINCT FROM v_native->>'chain_tip_sha256' THEN
     RETURN jsonb_build_object('status','NO_GO_MOTOR',
       'blocking_code','G15_B09_DOCUMENTAL_RECEIPT_NOT_BOUND',
       'b09_documental_accepted',false); END IF;
   RETURN jsonb_build_object('status','NO_GO_MOTOR',
     'blocking_code','G15_DOCUMENTAL_B09_ACCEPTED_OTHER_BLOCKERS_REQUIRE_INDEPENDENT_SIGNOFF',
     'b09_documental_accepted',true,'identity_verified',false,
     'provider_signature_verified',false,'independent_model_verified',false,
     'content_production_authorized',false,'final_database_authorized',false);
 END IF;
 RETURN jsonb_build_object('status','NO_GO_MOTOR',
   'blocking_code','G15_MOTOR_CRYPTOGRAPHIC_SIGNATURES_NOT_VERIFIED',
   'evidence_shape','7_OF_7_DECLARED_NOT_AUTHENTICATED',
   'content_production_authorized',false,'final_database_authorized',false);
END $fn$;
REVOKE ALL ON FUNCTION public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_ig_g15_motor_temporary_v1(jsonb)
 FROM PUBLIC,anon,authenticated;
COMMIT;
