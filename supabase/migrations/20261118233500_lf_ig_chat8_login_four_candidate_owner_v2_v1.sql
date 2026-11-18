-- IG CHAT8 governed CREATE candidates (4): source-bound rule contract, not backend QA.
-- Only owner_decide_v2 executes RULE_CREATE_APPLY; every rule remains CANDIDATO.
-- Producing PG17 evidence: github://cristhianlujan/claude-persona-lf-patch/actions/runs/44405870605/artifacts/14474429575#RULE_CONTRACT_LEVEL
-- Evidence has real 6 PG17 checks + rollback/readback and SHA256 logs; per-rule
-- patch and AUTH refs are revalidated below against source-bound Step50 RAW.
-- Proposed candidate_snapshot_sha256 is a contract-model projection, NOT a live
-- candidate row; the official writer independently verifies the final live row.
-- No direct INSERT/UPDATE of lf_ops.reglas or promotion, no protect-main changes.
BEGIN;
DO $chat8_pre$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
 IS DISTINCT FROM '633648e23cbd3c5fbf27324881709cb9'
 OR md5(pg_get_functiondef('public.lf_ig_step70_functional_train_auto_v1(text)'::regprocedure))
 IS DISTINCT FROM '03ed54da90b74502f836e81ffebd1fe6'
 OR md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
 IS DISTINCT FROM '98372407a52b87a464da597d24a408cb'
 THEN RAISE EXCEPTION 'IG_CHAT8_DEPLOYED_SOURCE_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>579
 OR (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1
      WHERE rule_code LIKE 'PROP-B2B-AUTH-%')<>0
 OR EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo IN ('PROP-B2B-AUTH-MFA-CONDITIONAL-001','PROP-B2B-AUTH-TRUSTED-DEVICE-C-001','PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001','PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001'))
 THEN RAISE EXCEPTION 'IG_CHAT8_PREIMAGE_RULE_OR_EVIDENCE_DRIFT'; END IF;
 PERFORM set_config('ig_chat8.rules_before',
   (SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r),true);
 PERFORM set_config('ig_chat8.protected_auth_before',
   (SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r WHERE codigo IN ('B2B-RULE-AUTH-018','B2B-RULE-AUTH-019','B2B-RULE-AUTH-020')),true);
 RAISE NOTICE 'IG_CHAT8_PREIMAGE_579_OK';
END $chat8_pre$;

DO $chat8_evidence$
DECLARE
 v record; v_step50 jsonb; v_patch jsonb; v_cfg jsonb; v_key text; v_refs jsonb;
 v_actual text; v_source text; v_candidate_sha text; v_event_id bigint;
 v_count integer;
BEGIN
 SELECT evt.id INTO v_event_id
 FROM public.lf_operation_execution te
 JOIN public.lf_eventos evt ON evt.entidad_codigo=te.execution_id
   AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
   AND evt.origen='lf-migration-merge-train'
 WHERE te.execution_id='EXEC-DB-TRAIN-PR4097-20261118214500-R44406065297'
   AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
   AND te.manifest->>'train_run_id'='44406065297'
   AND te.manifest->>'head_sha'='a177eed550fc43aaaf6b8a7e01f7f7942e19e200'
   AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-44406065297'
   AND evt.payload#>>'{receipt,train_run_id}'='44406065297'
   AND evt.payload#>>'{receipt,heads,final_head}'='a177eed550fc43aaaf6b8a7e01f7f7942e19e200'
   AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
   AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
   AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
   AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
   AND evt.payload->>'receipt_sha256' ~ '^[0-9a-f]{64}$'
   AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
       =evt.payload->>'receipt_sha256';
 IF v_event_id IS NULL THEN RAISE EXCEPTION 'IG_CHAT8_PRODUCER_TRAIN_RECEIPT_INVALID'; END IF;
 FOR v IN SELECT * FROM (VALUES
  ('PROP-B2B-AUTH-MFA-CONDITIONAL-001','EXEC-PROFILE-GATE2-E3886082953D24524EA15729','df2aaddba2ce987a83ce1f132368d6a272173be69188286ccc6da0f452e8fe27', ARRAY['MFA_DEVICE_IDLE_DAYS','MFA_PASSWORD_AGE_MONTHS']::text[]),
  ('PROP-B2B-AUTH-TRUSTED-DEVICE-C-001','EXEC-PROFILE-GATE2-27FFC4A401F997B0CB61B615','27995378c199960ed3260abf4ca1fc1372416707c379bdd928188e8055e1fd9d', ARRAY['MFA_DEVICE_IDLE_DAYS']::text[]),
  ('PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001','EXEC-PROFILE-GATE2-0F1D77E7A86D2C78099973F3','a07b92e6e45e6737c9c40c7c828e61be77ed122c5ebed12c188a72d346dfb8b5', ARRAY[]::text[]),
  ('PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001','EXEC-PROFILE-GATE2-3CDA68BA22C5B9A162C67298','df14fc6b394defb42317cd80ec58433dbadd930369cb1b6b7954481b2de368f6', ARRAY['LOGIN_LOCKOUT_ATTEMPT_WINDOW_MINUTES','LOGIN_LOCKOUT_ATTEMPTS_1','LOGIN_LOCKOUT_MINUTES_1','LOGIN_LOCKOUT_ATTEMPTS_2','LOGIN_LOCKOUT_MINUTES_2','LOGIN_LOCKOUT_ATTEMPTS_3','LOGIN_LOCKOUT_MINUTES_3','LOGIN_LOCKOUT_RESET_MINUTES']::text[])
 ) AS candidates(code,parent,patch_sha,expected_refs) LOOP
  SELECT p.evidence_payload INTO v_step50
  FROM public.lf_operation_execution_steps p
  JOIN public.lf_operation_execution e ON e.execution_id=p.execution_id
  WHERE p.execution_id=v.parent AND p.step_id='execute_profile'
    AND p.status='STEP_PASS_WITH_EVIDENCE'
    AND e.operation_code='EJECUCION_PERFIL_LF' AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND e.status='IN_PROGRESS'
    AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-AUTH-001'
    AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true'
    AND e.manifest->>'read_only'='true' AND e.manifest->>'no_write'='true';
  v_patch:=v_step50#>'{profile_output,deliverable_created,governed_rule_patch}';
  v_cfg:=v_patch#>'{changes,valor_config}'; v_refs:=v_cfg->'parameter_refs';
  v_actual:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
  IF v_step50 IS NULL OR v_actual IS DISTINCT FROM v.patch_sha
    OR v_patch->>'rule_code' IS DISTINCT FROM v.code
    OR v_patch->>'change_kind'<>'CREATE'
    OR v_step50#>>'{profile_output,deliverable_created,product_decision,proposed_by}'<>'PERFIL-PRODUCT-DIRECTOR-LF'
    OR v_step50#>>'{profile_output,self_verdict}'<>'PASS'
    OR NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps o
       WHERE o.execution_id=v.parent AND o.step_id='output_validate'
         AND o.status='STEP_PASS_WITH_EVIDENCE' AND o.evidence_payload->>'output_contract_result'='PASS')
    OR jsonb_typeof(v_refs)<>'array'
    OR jsonb_array_length(v_refs)<>array_length(v.expected_refs,1)
    OR jsonb_path_exists(v_cfg, '$.** ? (@.type() == "number")')
    OR coalesce(v_patch#>>'{changes,descripcion}','') ~* '[0-9]+[[:space:]]*(intentos?|minutos?|horas?|d[ií]as?|meses?)'
    OR (SELECT count(*) FROM public.lf_operation_execution_steps s
        WHERE s.execution_id=v.parent AND s.status='STEP_PASS_WITH_EVIDENCE')<>9
  THEN RAISE EXCEPTION 'IG_CHAT8_EXACT_STEP50_60_PATCH_OR_PARAMETERS_INVALID:%',v.code; END IF;
  FOR v_key IN SELECT unnest(v.expected_refs) LOOP
   IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_refs) x
     JOIN public.lf_global_config g ON g.scope=x->>'scope' AND g.config_key=x->>'config_key'
     WHERE x->>'scope'='AUTH' AND x->>'config_key'=v_key
       AND x->>'source'='public.lf_global_config'
       AND x->>'resolver'='public.lf_auth_config_integer_v1'
       AND g.value_type='INTEGER' AND g.value_status='REAL')
   THEN RAISE EXCEPTION 'IG_CHAT8_PARAMETER_REF_MISSING_OR_INVALID:%:%',v.code,v_key; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_refs) x WHERE NOT (x->>'config_key'=ANY(v.expected_refs))
     OR x->>'scope'<>'AUTH')
  THEN RAISE EXCEPTION 'IG_CHAT8_UNEXPECTED_PARAMETER_REF:%',v.code; END IF;
  v_source:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v.code,'UTF8'),'sha256'),'hex');
  v_candidate_sha:=encode(extensions.digest(convert_to(
    jsonb_build_object('rule_code',v.code,'candidate_state','CANDIDATO',
        'change_kind','CREATE','candidate_changes',v_patch->'changes')::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.lf_ig_functional_train_evidence_v1(
   rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
   train_execution_id,train_run_id,train_event_id,train_head_sha,
   pg_rollback_status,independent_readback_status,functional_checks_status,negative_checks_status,
   pg_report_sha256,readback_sha256,check_manifest_sha256,report_ref
  ) VALUES(
   v.code,v_source,v.patch_sha,v_candidate_sha,
   'EXEC-DB-TRAIN-PR4097-20261118214500-R44406065297','44406065297',v_event_id,'a177eed550fc43aaaf6b8a7e01f7f7942e19e200',
   'PASS','PASS','PASS','PASS',
   '2e73f83fda1a663bbf3cc8019ba04d4223e26ce4c4d8338e93f9a854d3b4b9f6',
   '7b4fd0ba9010495580da16a9963e1d5b03275e942a12aab3fd0b0c6219f3721f',
   '3795d2004aee5f1c9663dc0a098d604cc17735a930bfcbe92cb6dd18302c480b',
   'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44405870605/artifacts/14474429575#RULE_CONTRACT_LEVEL');
  RAISE NOTICE 'IG_CHAT8_RULE_CONTRACT_EVIDENCE_BOUND:%:source_absent:patch_exact:params_verified',v.code;
 END LOOP;
 IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1
      WHERE rule_code IN ('PROP-B2B-AUTH-MFA-CONDITIONAL-001','PROP-B2B-AUTH-TRUSTED-DEVICE-C-001','PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001','PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001'))<>4
 THEN RAISE EXCEPTION 'IG_CHAT8_EVIDENCE_READBACK_NOT_FOUR'; END IF;
END $chat8_evidence$;

-- Only Step70 auto (not native-review or CORRECT_VIGENTE) changes inside bridge.
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
            AND coalesce((e.manifest->>'no_write')::boolean,false) IS TRUE)
           OR public.lf_profile_srcr_same_context_candidate_scope_v1(p_execution_id)
         )
       ) OR (
         p_semantic_judge_result->>'verdict'='PASS_TRAIN_EVIDENCE_AUTOMATICO'
         AND p_semantic_judge_result->>'review_mode'='TRAIN_EVIDENCE_AUTOMATICO'
         AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
         AND e.manifest->>'read_only'='true'
         AND e.manifest->>'no_write'='true'
         AND p_semantic_judge_result IS NOT DISTINCT FROM
              public.lf_ig_step70_functional_train_auto_v1(p_execution_id)
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
          when p_semantic_judge_result->>'review_mode' IN
              ('CURRENT_CONTEXT_REVIEW','TRAIN_EVIDENCE_AUTOMATICO') then null
          when p_semantic_judge_result->>'review_mode'='INDEPENDENT_EVAL_CONTEXT' then v_verified_native->>'context_receipt_ref'
          else v_verified_native->>'provider_receipt_ref' end,
        'judge_independence_status',case
          when p_semantic_judge_result->>'review_mode'='CURRENT_CONTEXT_REVIEW'
            then 'NOT_PROVEN'
          when p_semantic_judge_result->>'review_mode'='TRAIN_EVIDENCE_AUTOMATICO'
            then 'NOT_ASSERTED_TRAIN_RULE_CONTRACT_LEVEL'
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


DO $chat8_apply$
DECLARE
 v record; v_source text; v_auto jsonb; v_bridge jsonb; v_dec jsonb; v_report jsonb;
 v_dry_ok boolean; v_before_count int; v_after_count int; v_success_count int:=0;
 v_fail_count int:=0; v_err text;
BEGIN
 FOR v IN SELECT * FROM (VALUES
  ('PROP-B2B-AUTH-MFA-CONDITIONAL-001','EXEC-PROFILE-GATE2-E3886082953D24524EA15729'),
  ('PROP-B2B-AUTH-TRUSTED-DEVICE-C-001','EXEC-PROFILE-GATE2-27FFC4A401F997B0CB61B615'),
  ('PROP-B2B-AUTH-INTICO-SMS-CONTINGENCY-001','EXEC-PROFILE-GATE2-0F1D77E7A86D2C78099973F3'),
  ('PROP-B2B-AUTH-PASSWORD-LOCKOUT-TIERS-001','EXEC-PROFILE-GATE2-3CDA68BA22C5B9A162C67298')
 ) AS candidates(code,parent) LOOP
   v_source:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v.code,'UTF8'),'sha256'),'hex');
   v_dry_ok:=false;
   -- Real SQL subtransaction: exercise canonical Step70, official V2 and 7/7
   -- skill writer then ROLLBACK by sentinel. No test writes persist.
   BEGIN
     v_auto:=public.lf_ig_step70_functional_train_auto_v1(v.parent);
     IF v_auto->>'status'<>'PASS' THEN
       RAISE EXCEPTION 'AUTO_TRAIN_BLOCKED:%',v_auto->>'blocking_code'; END IF;
     v_bridge:=public.lf_profile_native_bridge_record_semantic_v1(
       v.parent,v_auto,'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44405870605/artifacts/14474429575#RULE_CONTRACT_LEVEL',v.parent);
     IF v_bridge->>'status'<>'SEMANTIC_JUDGE_RECORDED' THEN
       RAISE EXCEPTION 'STEP70_BRIDGE_BLOCKED:%',coalesce(v_bridge->>'blocking_code',v_bridge->>'code','UNKNOWN'); END IF;
     v_dec:=public.lf_ig_rule_owner_decide_v2(
       v.parent,v.code,v_source,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
     IF v_dec->>'status'<>'APPROVED_AND_CANDIDATO_VERIFIED' THEN
       RAISE EXCEPTION 'OWNER_V2_CANDIDATO_NOT_VERIFIED:%',v_dec->>'status'; END IF;
     IF (SELECT count(*) FROM public.lf_operation_execution_steps
        WHERE execution_id=v_dec->>'child_execution_id' AND status='PASS_CLEAN')<>7
       OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v.code)<>'CANDIDATO'
     THEN RAISE EXCEPTION 'CHILD_7_7_OR_CANDIDATO_TEST_FAILED'; END IF;
     RAISE EXCEPTION 'IG_CHAT8_REAL_SUBTRANSACTION_ROLLBACK_SENTINEL';
   EXCEPTION WHEN OTHERS THEN
     IF SQLERRM='IG_CHAT8_REAL_SUBTRANSACTION_ROLLBACK_SENTINEL' THEN
       v_dry_ok:=true;
       RAISE NOTICE 'IG_CHAT8_DRY_RUN_BEGIN_ROLLBACK_OK:%',v.code;
     ELSE
       RAISE NOTICE 'IG_CHAT8_DRY_RUN_BLOCKED:%:%',v.code,SQLERRM;
     END IF;
   END;
   IF NOT v_dry_ok THEN v_fail_count:=v_fail_count+1; CONTINUE; END IF;
   IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=v.code)
      OR EXISTS (SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v.code)
      OR EXISTS (SELECT 1 FROM public.lf_operation_execution_steps
        WHERE execution_id=v.parent AND step_id='semantic_judge')
   THEN RAISE EXCEPTION 'IG_CHAT8_DRY_ROLLBACK_INDEPENDENT_READBACK_DIRTY:%',v.code; END IF;
   SELECT count(*) INTO v_before_count FROM lf_ops.reglas;
   BEGIN
     v_auto:=public.lf_ig_step70_functional_train_auto_v1(v.parent);
     IF v_auto->>'status'<>'PASS' THEN RAISE EXCEPTION 'AUTO_TRAIN_RECHECK_BLOCKED:%',v_auto->>'blocking_code'; END IF;
     v_bridge:=public.lf_profile_native_bridge_record_semantic_v1(
       v.parent,v_auto,'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44405870605/artifacts/14474429575#RULE_CONTRACT_LEVEL',v.parent);
     IF v_bridge->>'status'<>'SEMANTIC_JUDGE_RECORDED' THEN
        RAISE EXCEPTION 'STEP70_BRIDGE_ACTUAL_BLOCKED:%',coalesce(v_bridge->>'blocking_code',v_bridge->>'code','UNKNOWN'); END IF;
     v_dec:=public.lf_ig_rule_owner_decide_v2(
       v.parent,v.code,v_source,'{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
     IF v_dec->>'status'<>'APPROVED_AND_CANDIDATO_VERIFIED' THEN
       RAISE EXCEPTION 'OWNER_V2_APPLY_BLOCKED:%',coalesce(v_dec->>'status','NULL'); END IF;
     SELECT count(*) INTO v_after_count FROM lf_ops.reglas;
     IF v_after_count<>v_before_count+1
       OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas
         WHERE codigo=v.code AND estado='CANDIDATO' AND pendiente_decision=true
           AND created_by=v_dec->>'child_execution_id')
       OR (SELECT count(*) FROM public.lf_operation_execution_steps
         WHERE execution_id=v_dec->>'child_execution_id' AND status='PASS_CLEAN')<>7
       OR EXISTS (SELECT 1 FROM public.lf_rule_promotion_v1 WHERE rule_code=v.code)
     THEN RAISE EXCEPTION 'IG_CHAT8_ACTUAL_CANDIDATE_READBACK_FAILED'; END IF;
     v_success_count:=v_success_count+1;
     RAISE NOTICE 'IG_CHAT8_CREATE_VERIFIED:%:owner_v2_user_cristhian:child=%:CANDIDATO',v.code,v_dec->>'child_execution_id';
   EXCEPTION WHEN OTHERS THEN
     v_fail_count:=v_fail_count+1;
     RAISE NOTICE 'IG_CHAT8_APPLY_BLOCKED:%:%',v.code,SQLERRM;
   END;
   IF EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=v.code AND estado='CANDIDATO') THEN
     BEGIN
       v_report:=public.lf_profile_native_bridge_record_report_v1(v.parent,
         'github://cristhianlujan/claude-persona-lf-patch/actions/runs/44405870605/artifacts/14474429575#RULE_CONTRACT_LEVEL',v.parent);
       RAISE NOTICE 'IG_CHAT8_STEP80:%:%',v.code,coalesce(v_report->>'status',v_report->>'blocking_code','UNKNOWN');
     EXCEPTION WHEN OTHERS THEN
       RAISE NOTICE 'IG_CHAT8_STEP80_PENDING:%:%',v.code,SQLERRM;
     END;
   END IF;
 END LOOP;
 IF (SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]')) FROM lf_ops.reglas r
 WHERE codigo IN ('B2B-RULE-AUTH-018','B2B-RULE-AUTH-019','B2B-RULE-AUTH-020'))
 IS DISTINCT FROM current_setting('ig_chat8.protected_auth_before')
 THEN RAISE EXCEPTION 'IG_CHAT8_PROTECTED_AUTH_018_019_020_MUTATED'; END IF;
 RAISE NOTICE 'IG_CHAT8_FINAL_RESULT:created=%:blocked=%:rule_count=%:candidate_count=%',
 v_success_count,v_fail_count,(SELECT count(*) FROM lf_ops.reglas),
 (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO');
END $chat8_apply$;
COMMIT;
