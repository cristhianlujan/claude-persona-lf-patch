-- LF sandbox only. Same-run historical Step70/80 evidence stays immutable.
-- Independent reviewer status needs a separate cryptographically verified
-- provider receipt. CURRENT_CONTEXT_REVIEW preserves content review with finding.
BEGIN;
DO $pre$ DECLARE v text; BEGIN
 SELECT md5(pg_get_functiondef(p.oid)) INTO v FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='lf_profile_native_bridge_record_report_v1'; IF v IS DISTINCT FROM '086bc1c8e73e20a799794e8dd972ab77' THEN RAISE EXCEPTION 'LF_JUDGE_PREIMAGE_DRIFT_lf_profile_native_bridge_record_report_v1'; END IF;
 SELECT md5(pg_get_functiondef(p.oid)) INTO v FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='lf_profile_native_bridge_record_semantic_v1'; IF v IS DISTINCT FROM '78cb1b8fab6975f4539a79baa2ab11fd' THEN RAISE EXCEPTION 'LF_JUDGE_PREIMAGE_DRIFT_lf_profile_native_bridge_record_semantic_v1'; END IF;
 SELECT md5(pg_get_functiondef(p.oid)) INTO v FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid WHERE n.nspname='public' AND p.proname='lf_profile_skill_selection_prepare_v1'; IF v IS DISTINCT FROM 'ecb345ad6cd7a9f83f77720b92345f69' THEN RAISE EXCEPTION 'LF_JUDGE_PREIMAGE_DRIFT_lf_profile_skill_selection_prepare_v1'; END IF;
END $pre$;

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
  IF p_semantic_judge_result->>'verdict'='PASS_INDEPENDENT_SEMANTIC' THEN
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
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW' then null
          else v_verified_native->>'provider_receipt_ref' end,
        'judge_independence_status',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then 'NOT_PROVEN' else 'PROVIDER_VERIFIED' end,
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
    IF e.manifest->>'read_only'<>'true'
       OR e.manifest->>'no_write'<>'true'
       OR e.manifest->>'no_promotion'<>'true'
       OR e.manifest->>'automatic_impact'<>'false'
       OR e.manifest->>'governed_repair_write'<>'false'
       OR v_input#>>'{input_governance,status}'<>'BLOCKED'
       OR v_input->>'ig_security_clearance'<>'false'
       OR jsonb_typeof(v_input#>'{input_governance,governance_result}')<>'object'
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
      'security_state','BLOCKED',
      'security_clearance',false,
      'input_step_ref','supabase://public.lf_operation_execution_steps/'||p_execution_id||'/input_validate',
      'input_governance',v_input->'input_governance',
      'profile_decision_observed',v_profile_output#>'{traceability,ig_open_work_resolution}',
      'report_status','FINDINGS_REPORTED_NOT_RESOLVED',
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
$function$
;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_v1(
 p_profile_code text,p_channel text,p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE
 SET search_path TO 'pg_catalog','public'
AS $function$
 WITH selection AS (
  SELECT public.lf_profile_skill_selection_prepare_context_v1(
      p_profile_code,p_channel,p_semantic_decision,'{}'::jsonb) AS receipt
 )
 SELECT receipt || CASE WHEN receipt->>'status'='READY' THEN
   jsonb_build_object(
    'selection_status',coalesce(receipt->>'selection_status','SKILL_SELECTION_REQUESTED'),
    'finding_status',CASE WHEN receipt->>'selection_status'='SKILL_SELECTION_PENDING_FINDING'
       THEN 'SKILL_SELECTION_PENDING_FINDING' ELSE NULL END,
    'next_action','SUBMIT_SKILL_SELECTION',
    'selected_skill_codes',coalesce(receipt->'selected_skill_codes','[]'::jsonb),
    'skill_candidates',coalesce(receipt->'skill_candidates','[]'::jsonb),
    'continuation_allowed',true)
 ELSE '{}'::jsonb END
 FROM selection
$function$;


-- A new, append-only finding is an audited retrospective observation, NOT a replay.
CREATE TABLE public.lf_profile_semantic_independence_finding_v1(
 execution_id text NOT NULL,
 step70_sha256 text NOT NULL CHECK(step70_sha256 ~ '^[0-9a-f]{64}$'),
 step80_sha256 text NOT NULL CHECK(step80_sha256 ~ '^[0-9a-f]{64}$'),
 finding_code text NOT NULL DEFAULT 'JUDGE_INDEPENDENCE_NOT_PROVEN'
   CHECK (finding_code='JUDGE_INDEPENDENCE_NOT_PROVEN'),
 independence_status text NOT NULL DEFAULT 'NOT_PROVEN'
   CHECK (independence_status='NOT_PROVEN'),
 candidate_sha256 text NOT NULL,
 scope_packet_sha256 text NOT NULL,
 original_step70_ref text NOT NULL,
 original_step80_ref text NOT NULL,
 audit_source text NOT NULL DEFAULT 'ORIGINAL_LEDGER_READBACK',
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(execution_id,step70_sha256)
);
REVOKE ALL ON TABLE public.lf_profile_semantic_independence_finding_v1 FROM PUBLIC;
REVOKE ALL ON TABLE public.lf_profile_semantic_independence_finding_v1 FROM anon,authenticated;
-- The read-only reviewer can only inspect, never mutate the original ledger.
GRANT SELECT ON public.lf_profile_semantic_independence_finding_v1 TO supabase_read_only_user;
CREATE OR REPLACE FUNCTION public.lf_profile_semantic_independence_finding_immutable_v1()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN RAISE EXCEPTION 'LF_SEMANTIC_INDEPENDENCE_FINDING_APPEND_ONLY'; END $fn$;
CREATE TRIGGER lf_profile_semantic_independence_finding_immutable_v1
BEFORE UPDATE OR DELETE ON public.lf_profile_semantic_independence_finding_v1
FOR EACH ROW EXECUTE FUNCTION public.lf_profile_semantic_independence_finding_immutable_v1();

-- Owner-authorized retrospective finding: exactly three historical completed RUNs.
-- Do not change those RUNs' status, execution_id, step70 or step80 source evidence.
DO $legacy$
DECLARE v_count integer;
BEGIN
 SELECT count(*) INTO v_count
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps s70 ON s70.execution_id=e.execution_id
  AND s70.step_id='semantic_judge' AND s70.status='STEP_PASS_WITH_EVIDENCE'
 JOIN public.lf_operation_execution_steps s80 ON s80.execution_id=e.execution_id
  AND s80.step_id='report_output' AND s80.status='STEP_PASS_WITH_EVIDENCE'
 WHERE e.execution_id IN (
 'EXEC-PROFILE-GATE2-0248912F0BB40220F116168D',
 'EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
 'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1')
 AND e.status='COMPLETED'
 AND s70.evidence_payload#>>'{semantic_judge_result,review_mode}'='CURRENT_CONTEXT_REVIEW'
 AND s70.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}'='false'
 AND s70.evidence_payload#>>'{semantic_judge_result,reviewer_is_producer}'='true'
 AND s70.evidence_payload#>>'{semantic_judge_result,model_call_count}'='0'
 AND s70.evidence_payload->>'independent_semantic_receipt_ref' IS NULL
 AND s80.evidence_payload->>'independent_semantic_receipt_ref' IS NULL;
 IF v_count<>3 THEN RAISE EXCEPTION 'LF_JUDGE_HISTORICAL_RUN_PREIMAGE_DRIFT_%',v_count;END IF;
 INSERT INTO public.lf_profile_semantic_independence_finding_v1(
  execution_id,step70_sha256,step80_sha256,candidate_sha256,scope_packet_sha256,
  original_step70_ref,original_step80_ref)
 SELECT e.execution_id,
  encode(extensions.digest(convert_to(s70.evidence_payload::text,'UTF8'),'sha256'),'hex'),
  encode(extensions.digest(convert_to(s80.evidence_payload::text,'UTF8'),'sha256'),'hex'),
  s70.evidence_payload#>>'{semantic_judge_result,candidate_sha256}',
  s70.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}',
  s70.evidence_ref,s80.evidence_ref
 FROM public.lf_operation_execution e
 JOIN public.lf_operation_execution_steps s70 ON s70.execution_id=e.execution_id
  AND s70.step_id='semantic_judge'
 JOIN public.lf_operation_execution_steps s80 ON s80.execution_id=e.execution_id
  AND s80.step_id='report_output'
 WHERE e.execution_id IN (
 'EXEC-PROFILE-GATE2-0248912F0BB40220F116168D',
 'EXEC-PROFILE-GATE2-15B9B3F0FA7D6B7C3BFC037A',
 'EXEC-PROFILE-GATE2-C506666157F990238F37B2C1')
 AND e.status='COMPLETED';
END $legacy$;

CREATE OR REPLACE FUNCTION public.lf_profile_semantic_independence_readback_v1(p_execution_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE
SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE e public.lf_operation_execution%ROWTYPE;
 s70 public.lf_operation_execution_steps%ROWTYPE;
 s80 public.lf_operation_execution_steps%ROWTYPE;
 v_f public.lf_profile_semantic_independence_finding_v1%ROWTYPE;
 v_sha70 text;v_sha80 text;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 SELECT * INTO s70 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='semantic_judge';
 SELECT * INTO s80 FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='report_output';
 IF e.execution_id IS NULL OR e.operation_code<>'EJECUCION_PERFIL_LF'
 OR s70.step_id IS NULL OR s80.step_id IS NULL THEN
  RETURN jsonb_build_object('status','BLOCKED','code','JUDGE_SOURCE_UNREADABLE');END IF;
 v_sha70:=encode(extensions.digest(convert_to(s70.evidence_payload::text,'UTF8'),'sha256'),'hex');
 v_sha80:=encode(extensions.digest(convert_to(s80.evidence_payload::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_f FROM public.lf_profile_semantic_independence_finding_v1
 WHERE execution_id=p_execution_id AND step70_sha256=v_sha70;
 IF v_f.execution_id IS NULL THEN
  RETURN jsonb_build_object('status','SOURCE_ONLY','execution_id',p_execution_id,
    'judge_review_mode',s70.evidence_payload#>>'{semantic_judge_result,review_mode}',
    'independence_proven',false,'finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN',
    'finding_persisted',false,'step70_sha256',v_sha70,'step80_sha256',v_sha80,
    'original_run_status',e.status,
    'canonical_step70_80_unchanged',true);
 END IF;
 IF v_f.step80_sha256 IS DISTINCT FROM v_sha80 THEN
  RETURN jsonb_build_object('status','BLOCKED','code','JUDGE_REPORT_EVIDENCE_DRIFT');END IF;
 RETURN jsonb_build_object('status','FINDING_RECORDED',
  'execution_id',p_execution_id,'original_run_status',e.status,
  'step70','ORIGINAL_COMPLETED_EVIDENCE','step80','ORIGINAL_COMPLETED_EVIDENCE',
  'finding_code','JUDGE_INDEPENDENCE_NOT_PROVEN',
  'finding_persisted',true,'independence_proven',false,
  'model_call_count',0,'independent_semantic_receipt_ref',null,
  'step70_sha256',v_sha70,'step80_sha256',v_sha80,
  'candidate_sha256',v_f.candidate_sha256,
  'scope_packet_sha256',v_f.scope_packet_sha256,
  'original_step70_ref',v_f.original_step70_ref,
  'original_step80_ref',v_f.original_step80_ref,
  'canonical_step70_80_unchanged',true,
  'content_continuation_allowed',true,'effect_authority',false);
END $fn$;

CREATE OR REPLACE FUNCTION public.lf_profile_semantic_terminal_recheck_v1(p_execution_id text)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'pg_catalog','public'
AS $fn$
 SELECT public.lf_profile_semantic_independence_readback_v1(p_execution_id)
     ||jsonb_build_object('recheck_type','READ_ONLY_STEP70_STEP80_REEVALUATION',
       'same_execution_id',true,'canonical_step_reexecution_performed',false,
       'new_execution_created',false);
$fn$;

COMMIT;
