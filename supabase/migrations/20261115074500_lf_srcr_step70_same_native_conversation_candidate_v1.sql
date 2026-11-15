-- Owner-directed sandbox-only Step70 current-context review; NO independence claim.
-- Only candidate artifacts under sandbox/lf_contract_gate_test; no product mutation or promotion.
-- PR goes through LF Migration Merge Train. Never edit an existing RUN manifest.
BEGIN;
DO $pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
    <> '958ac3c85314950db49ecff2f74f095e'
 THEN RAISE EXCEPTION 'LF_SRCR_SAME_CHAT_SEMANTIC_PREIMAGE_DRIFT'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure))
    <> 'f9178d495753ee159f476222a3ba009d'
 THEN RAISE EXCEPTION 'LF_SRCR_SAME_CHAT_REPORT_PREIMAGE_DRIFT'; END IF;
 IF to_regprocedure('public.lf_profile_srcr_same_context_candidate_scope_v1(text)') IS NOT NULL
 THEN RAISE EXCEPTION 'LF_SRCR_SAME_CHAT_SCOPE_PREEXISTS_DRIFT'; END IF;
END
$pre$;
CREATE FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $scope$
DECLARE
 e public.lf_operation_execution%rowtype;
 v40 jsonb; v50 jsonb; v60 jsonb; changes jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    OR e.manifest->>'executor_mode'<>'GPT_NATIVE'
    OR e.manifest->>'governed_repair_write'<>'true'
    OR e.manifest->>'read_only'<>'false'
    OR e.manifest->>'no_write'<>'false'
    OR e.manifest->>'no_promotion'<>'true'
    OR e.manifest->>'automatic_impact'<>'false'
    OR e.manifest#>>'{router_profile_handoff,router_authorization_receipt,effect_authority}' IS DISTINCT FROM 'false'
 THEN RETURN false; END IF;
 SELECT evidence_payload INTO v40 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO v50 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='execute_profile' AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO v60 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='output_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 IF v40 IS NULL OR v50 IS NULL OR v60 IS NULL
    OR v40->>'analysis_scope'<>'READ_ONLY_WITH_IG_FINDINGS'
    OR v40->>'mutation_authorized' IS DISTINCT FROM 'false'
    OR v40->>'promotion_authorized' IS DISTINCT FROM 'false'
    OR v40#>>'{input_governance,analysis_scope}' IS DISTINCT FROM 'READ_ONLY_WITH_IG_FINDINGS'
    OR jsonb_typeof(v40->'allowed_actions')<>'array'
    OR NOT (v40->'allowed_actions' <@ '["ANALYZE","PROPOSE","VALIDATE","REPORT"]'::jsonb)
    OR v60#>>'{deterministic_validation,status}'<>'PASS'
 THEN RETURN false; END IF;
 changes:=v50#>'{profile_output,repair_execution,changes}';
 IF jsonb_typeof(changes)<>'array' OR jsonb_array_length(changes)=0 THEN RETURN false; END IF;
 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(changes) ch
   WHERE jsonb_typeof(ch)<>'object'
      OR coalesce(ch->>'target_ref','') !~ '^github://cristhianlujan/claude-persona-lf-patch@[0-9a-f]{40}/sandbox/lf_contract_gate_test/'
      OR coalesce(ch->>'after_ref','') IS DISTINCT FROM ch->>'target_ref'
      OR ch->>'before_ref' IS NOT NULL
      OR ch->>'change_type'<>'CREATE'
 ) THEN RETURN false; END IF;
 RETURN true;
END
$scope$;
REVOKE ALL ON FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_srcr_same_context_candidate_scope_v1(text) TO service_role;
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
         AND (
           (coalesce((e.manifest->>'read_only')::boolean,false) IS TRUE
            AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE
            AND coalesce((e.manifest->>'no_promotion')::boolean,false) IS TRUE)
           OR public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
         )
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
$function$
;
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_record_report_v1(p_execution_id text, p_evidence_ref text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_semantic public.lf_operation_execution_steps%rowtype;
  v_input jsonb;
  v_profile_output jsonb;
  v_report_findings jsonb;
  v_existing text;
  v_actor text;
  v_candidate text;
  v_scope text;
  v_semantic_receipt text;
  v_step jsonb;
  v_clean integer;
  v_terminal jsonb;
  v_attached jsonb;
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

  -- Read canonical evidence only. A security BLOCKED is never relabeled READY.
  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';
  IF v_input#>>'{input_governance,status}'='BLOCKED'
     AND v_input->>'analysis_scope' IS DISTINCT FROM 'READ_ONLY_WITH_IG_FINDINGS' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code','BLOCK_REPORT_IG_FINDINGS_WRITE_SCOPE');
  END IF;
  IF v_input->>'analysis_scope'='READ_ONLY_WITH_IG_FINDINGS' THEN
    IF NOT (
       (e.manifest->>'read_only'='true'
        AND e.manifest->>'no_write'='true'
        AND e.manifest->>'no_promotion'='true'
        AND e.manifest->>'automatic_impact'='false'
        AND e.manifest->>'governed_repair_write'='false'
        AND v_input#>>'{input_governance,status}'='BLOCKED'
        AND v_input->>'ig_security_clearance'='false'
        AND jsonb_typeof(v_input#>'{input_governance,governance_result}')='object')
       OR public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
    )
    THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_REPORT_IG_FINDINGS_SCOPE_OR_SOURCE_INVALID');
    END IF;
    SELECT evidence_payload->'profile_output' INTO v_profile_output
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id AND step_id='execute_profile'
      AND status='STEP_PASS_WITH_EVIDENCE';
    IF jsonb_typeof(v_profile_output)<>'object' THEN
      RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','BLOCK_REPORT_PROFILE_DECISION_SOURCE_MISSING');
    END IF;
    v_report_findings:=jsonb_build_object(
      'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
      'security_state',CASE WHEN v_input#>>'{input_governance,status}'='BLOCKED' THEN 'BLOCKED' ELSE 'FINDINGS_NOT_CLEARED' END,
      'security_clearance',false,
      'input_step_ref','supabase://public.lf_operation_execution_steps/'||p_execution_id||'/input_validate',
      'input_governance',v_input->'input_governance',
      'profile_decision_observed',v_profile_output#>'{traceability,ig_open_work_resolution}',
      'report_status',CASE WHEN v_input#>>'{input_governance,status}'='BLOCKED' THEN 'FINDINGS_REPORTED_NOT_RESOLVED' ELSE 'CANDIDATE_REVIEWED_NO_EFFECT_APPROVAL' END,
      'mutation_authorized',false,
      'promotion_authorized',false);
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
        'family_source_receipts',public.lf_input_family_catalog_receipts_for_run_v1(p_execution_id),
        'family_source_receipt_schema','LF_FAMILY_SOURCE_RECEIPTS_BY_REFERENCE_V1',
        'result',v_semantic.evidence_payload#>>'{semantic_judge_result,verdict}',
        'execution_id',p_execution_id,
        'profile_code',e.target_code,
        'no_write_performed',true,
        'candidate_sha256',v_candidate,
        'scope_packet_sha256',v_scope,
        'semantic_review_receipt_ref',v_semantic_receipt,
        'independent_semantic_receipt_ref',case
          when v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW' then null
          else v_semantic.evidence_payload->>'independent_semantic_receipt_ref' end,
        'judge_independence_status',coalesce(
          v_semantic.evidence_payload->>'judge_independence_status',
          CASE WHEN v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
          THEN 'NOT_PROVEN' ELSE 'REQUIRES_PROVIDER_VERIFICATION' END),
        'content_findings',coalesce(v_semantic.evidence_payload->'content_findings',
          CASE WHEN v_semantic.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
             THEN jsonb_build_array(jsonb_build_object('finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN','continuation_allowed',true))
             ELSE '[]'::jsonb END),
        'next_gate','RETURN_TO_ROUTER'
      ) || CASE WHEN v_report_findings IS NOT NULL
           THEN jsonb_build_object('ig_findings',v_report_findings,
                                   'ig_findings_reported',true)
           ELSE '{}'::jsonb END,
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

  -- Attach the terminal route after the canonical 11/11 clean step and
  -- terminal receipt are proven. Reuse the existing idempotent CAS writer.
  v_attached:=public.lf_profile_execution_attach_terminal_authority_receipt_v1(
    p_execution_id,p_execution_id
  );
  IF v_attached->>'result' NOT IN (
    'TERMINAL_AUTHORITY_RECEIPT_ATTACHED',
    'TERMINAL_AUTHORITY_RECEIPT_ALREADY_ATTACHED'
  )
  OR v_attached->>'terminal_authority_receipt_sha256' IS DISTINCT FROM
     v_terminal->>'terminal_authority_receipt_sha256'
  OR jsonb_typeof(v_attached->'post_profile_route')<>'object'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','PD_EXECUTOR_TERMINAL_ROUTER_RETURN_NOT_ATTACHED',
      'attach_result',v_attached
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
    'post_profile_route',v_attached->'post_profile_route',
    'next_action',v_attached->>'next_action',
    'next_gate',CASE WHEN v_attached->>'next_action'='REENTER_ROUTER_STAGE1'
                  THEN 'ACT-0001_STAGE1' ELSE 'RETURN_TO_ROUTER' END
  );
END
$function$
;
COMMIT;
