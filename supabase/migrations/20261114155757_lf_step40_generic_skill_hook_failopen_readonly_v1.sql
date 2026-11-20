-- LF Step40 generic skill hook (owner correction, sandbox only).
-- No IG binding in operation contract. Selection exclusively from
-- public.lf_skill_selector_policy_v1 through plan/invoke; read-only findings.
-- Strict live preimages and transactional rollback on any drift.
BEGIN;
DO $guard$
DECLARE v_ref text; v_keys jsonb; v_count int;
BEGIN
  SELECT resolver_ref,required_evidence_keys INTO STRICT v_ref,v_keys
  FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_PERFIL_LF' AND step_order=40
    AND step_id='input_validate' AND status='ACTIVE_ENFORCEMENT';
  IF v_ref <> 'public.lf_profile_execution_input_validate_v1 + programacion.fn_lf_profile_input_governance_resolve_v1'
     OR v_keys <> '["input_scope","activation_trigger_match","scope_authority_packet","scope_authority_packet_sha256"]'::jsonb
  THEN RAISE EXCEPTION 'LF_STEP40_CONTRACT_SOURCE_DRIFT'; END IF;
  IF md5(pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure))
     <> '1a6c6c81538f3c83286c581528e4c80d' THEN
     RAISE EXCEPTION 'LF_STEP40_BRIDGE_SOURCE_DRIFT'; END IF;
  IF md5(pg_get_functiondef('public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)'::regprocedure))
     <> 'f6087f356ccd5ece078170c2ff414cd9' THEN
     RAISE EXCEPTION 'LF_STEP40_POLICY_INVOKER_SOURCE_DRIFT'; END IF;
  IF md5(pg_get_functiondef('public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)'::regprocedure))
     <> 'cafccb4e256f8bbb9530f2e1b2e611ca' THEN
     RAISE EXCEPTION 'LF_STEP40_TICKET_ISSUER_SOURCE_DRIFT'; END IF;
  SELECT count(*) INTO v_count FROM public.lf_operation_steps
    WHERE operation_code='EJECUCION_PERFIL_LF' AND step_order=40
      AND step_id='input_validate' AND active AND required;
  IF v_count<>1 THEN RAISE EXCEPTION 'LF_STEP40_STEP_REGISTRY_DRIFT'; END IF;
END $guard$;
UPDATE public.lf_operation_step_contracts
SET resolver_ref='public.lf_profile_execution_input_validate_v1'
WHERE operation_code='EJECUCION_PERFIL_LF' AND step_order=40
  AND step_id='input_validate' AND status='ACTIVE_ENFORCEMENT';
CREATE OR REPLACE FUNCTION public.lf_profile_native_bridge_prepare_v1(p_execution_id text, p_source_revision text, p_source_digest text, p_actor_execution_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  e public.lf_operation_execution%rowtype;
  v_handoff jsonb;
  v_valid jsonb;
  v_actor text;
  v_slug text;
  v_source_ref text;
  v_existing text;
  v_step jsonb;
  v_input jsonb;
  v_base_context jsonb;
  v_context jsonb;
  v_baseline jsonb;
  v_clean integer;
  v_policy_selection jsonb;
  v_ig_ticket jsonb;
  v_skill_plan jsonb;
  v_skill_item jsonb;
  v_skill_result jsonb;
  v_skill_findings jsonb:='[]'::jsonb;
  v_skill_receipts jsonb:='[]'::jsonb;
  v_skill_input jsonb;
  v_skill_code text;
  v_skill_ig jsonb;
BEGIN
  IF nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR coalesce(p_source_revision,'') !~ '^[0-9a-f]{40}$'
     OR coalesce(p_source_digest,'') !~ '^sha256:[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_SOURCE_BINDING_INVALID'
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
       OR (e.manifest->>'executor_mode'='CLAUDE_NATIVE'
        AND e.manifest->>'executor_provider'='ANTHROPIC_CLAUDE_NATIVE'),
       false) THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_EXECUTION_INVALID'
    );
  END IF;

  v_handoff:=e.manifest->'router_profile_handoff';
  v_valid:=public.lf_router_profile_execution_handoff_validate_v1(
    v_handoff,
    v_handoff->>'literal_request',
    e.target_code
  );
  IF coalesce((v_valid->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_HANDOFF_INVALID',
      'handoff_validation',v_valid
    );
  END IF;

  SELECT metadata->>'profile_slug' INTO v_slug
  FROM public.lf_activos
  WHERE codigo_activo=e.target_code
    AND tipo_activo='PERFIL'
    AND archived_at IS NULL;

  IF nullif(v_slug,'') IS NULL
     OR nullif(e.target_repo,'') IS NULL
     OR nullif(e.target_path,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_UNRESOLVED'
    );
  END IF;

  v_actor:=coalesce(nullif(btrim(p_actor_execution_id),''),p_execution_id);
  v_source_ref:='github://'||e.target_repo||'@'||p_source_revision||'/'||e.target_path;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_resolve';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_resolve',
      'supabase://public.lf_activos/'||e.target_code,
      jsonb_build_object(
        'exact_profile_resolved',true,
        'codigo_activo',e.target_code,
        'profile_slug',v_slug
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_RESOLVE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT status INTO v_existing
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id AND step_id='profile_source_read';

  IF v_existing IS NULL THEN
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'profile_source_read',
      v_source_ref,
      jsonb_build_object(
        'profile_source_ref',v_source_ref,
        'source_revision',p_source_revision,
        'profile_source_digest',p_source_digest,
        'profile_source_path',e.target_path
      ),
      v_actor
    );
  ELSIF v_existing<>'STEP_PASS_WITH_EVIDENCE' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PROFILE_SOURCE_NOT_CLEAN',
      'step_status',v_existing
    );
  END IF;

  SELECT evidence_payload INTO v_input
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='input_validate'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_input IS NULL THEN
    v_input:=public.lf_profile_execution_input_validate_v1(
      p_execution_id,
      v_handoff->>'literal_request',
      v_source_ref,
      v_handoff
    );

    IF v_input->>'status'<>'READY' THEN
      IF v_input->>'status'='SCREEN_SELECTION_REQUIRED'
         AND v_input->>'next_action'='RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
         AND jsonb_typeof(v_input->'screen_selection_request')='object'
      THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_input->'screen_selection_request',
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'next_action','SUBMIT_SCREEN_SELECTION_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;


      RETURN jsonb_build_object(
        'status',coalesce(v_input->>'status','BLOCKED'),
        'blocking_code',coalesce(
          v_input->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_INPUT_VALIDATE_NOT_READY'
        ),
        'execution_id',p_execution_id,
        'input_validate',v_input,
        'router_reentry_required',false
      );
    END IF;


    -- Step40 executes all policy-selected READ_ONLY skills; never Router-owned.
    v_skill_plan:=public.lf_profile_execution_plan_v1(e.target_code,v_handoff->>'channel',null::jsonb);
    -- Selected skills are optional to profile continuation. A missing/invalid
    -- skill plan produces an auditable READ_ONLY finding, never implicit skill
    -- execution or permission to write. Router/scope validation is unchanged.
    IF v_skill_plan->>'status'='SEMANTIC_SELECTION_REQUIRED'
       AND jsonb_typeof(v_skill_plan#>'{selection_receipt,required_skills}')='array' THEN
      -- Optional semantic choice is NOT automatically selected. Execute
      -- deterministic mandatory skills from verified DB policy while leaving
      -- optional selection as an auditable finding. No skill scope expansion.
      v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
        'skill_code','OPTIONAL_SKILL_SELECTION',
        'status','SKILL_FAILED_AS_FINDING',
        'blocking_code','SKILL_OPTIONAL_SEMANTIC_DECISION_DEFERRED',
        'remediation_action','NATIVE_SEMANTIC_REVIEW_IN_GOVERNED_FOLLOWUP',
        'continuation_allowed',true,'production_authorized',false,
        'policy_receipt',v_skill_plan->'selection_receipt'));
      v_skill_plan:=v_skill_plan||jsonb_build_object(
        'status','READY',
        'skills',v_skill_plan#>'{selection_receipt,required_skills}',
        'selection_mode','REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED');
    ELSIF v_skill_plan->>'status'<>'READY' THEN
      v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
        'skill_code','SKILL_POLICY_SELECTION',
        'status','SKILL_FAILED_AS_FINDING',
        'blocking_code',coalesce(v_skill_plan->>'blocking_code','SKILL_POLICY_NOT_READY'),
        'remediation_action','REPAIR_PROFILE_SKILL_POLICY_AND_RERUN_SKILL',
        'continuation_allowed',true,'production_authorized',false,
        'policy_receipt',v_skill_plan));
      v_skill_plan:=jsonb_build_object('status','READY','skills','[]'::jsonb);
    END IF;
    FOR v_skill_item IN SELECT x FROM jsonb_array_elements(v_skill_plan->'skills') x LOOP
      v_skill_code:=v_skill_item->>'skill_code';
      IF v_skill_item->>'effect'<>'READ_ONLY' THEN
        v_skill_receipts:=v_skill_receipts||jsonb_build_array(
          jsonb_build_object('skill_code',v_skill_code,'status','DEFERRED_NOT_STEP40',
             'effect_authorized',false));
        CONTINUE;
      END IF;
      v_skill_input:=jsonb_build_object(
        'execution_id',p_execution_id,
        'request_text',v_handoff->>'literal_request',
        'profile_code',e.target_code,
        'scope',v_input->'resolved_scope',
        'consumer','CONTEXT_PACK',
        'pantalla_codigo',v_input#>>'{resolved_scope,resolved_screen_code}'
      );
      v_skill_result:=public.lf_profile_skill_invoke_selected_v1(
        p_execution_id,v_handoff->>'channel',v_skill_code,v_skill_input,null
      );
      IF v_skill_result->>'status'='RUNTIME_REQUIRED' THEN
        v_ig_ticket:=public.lf_profile_skill_runtime_ticket_issue_v1(
          p_execution_id,v_skill_code,v_skill_input);
        IF v_ig_ticket->>'status'='AUTHORIZED' THEN
          RETURN jsonb_build_object(
            'status','SKILL_RUNTIME_REQUIRED','skill_code',v_skill_code,
            'execution_id',p_execution_id,'input_validate',v_input,
            'input_governance_runtime_request',jsonb_build_object(
              'transport','DIRECT_EDGE_INVOCATION',
              'runtime_orchestrator','SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1',
              'runtime_slug',v_ig_ticket->>'runtime_slug',
              'request_headers',jsonb_build_object(
                'X-LF-Profile-Runtime-Ticket',v_ig_ticket->>'ticket'),
              'request_body',jsonb_build_object(
                'action','profile_skill_runtime_v1','execution_id',p_execution_id,
                'skill_code',v_skill_code),
              'terminal_statuses',jsonb_build_array('READY','BLOCKED','HUMAN_DECISION_REQUIRED','FAILED'),
              'continuation_statuses',jsonb_build_array('VALIDATOR_RESUME_REQUIRED'),
              'ticket_expires_at',v_ig_ticket->'expires_at',
              'queue_required',false,'polling_required',false),
            'next_action','INVOKE_SELECTED_SKILL_RUNTIME_AND_RETRY_SAME_BRIDGE',
            'router_reentry_required',false);
        END IF;
        v_skill_result:=jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
          'blocking_code',coalesce(v_ig_ticket->>'code','SKILL_RUNTIME_TICKET_NOT_AUTHORIZED'),
          'ticket_status',v_ig_ticket->>'status','skill_code',v_skill_code,
          'attempt_count',v_ig_ticket->'attempt_count',
          'remediation_action','INVESTIGATE_SKILL_RUNTIME_AND_RECURATE_SOURCES_GOVERNED',
          'continuation_allowed',true,'production_authorized',false);
      END IF;
      v_skill_receipts:=v_skill_receipts||jsonb_build_array(jsonb_build_object(
        'skill_code',v_skill_code,'result',v_skill_result));
      IF v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' THEN
        v_skill_ig:=coalesce(v_skill_result#>'{output,input_governance}',
          v_skill_result->'input_governance','{}'::jsonb);
        IF v_skill_result->>'status' NOT IN ('READY','COMPLETED','SKIPPED','PASS') THEN
          -- IG is only a policy-selected READ_ONLY skill; its failure is a
          -- finding, not a success claim or a gate for Step45/50/70/80.
          v_skill_ig:=v_skill_ig||jsonb_build_object(
            'status','BLOCKED',
            'blocking_code',coalesce(v_skill_result->>'blocking_code',
                                     v_skill_result->>'status','IG_SKILL_NOT_READY'),
            'continuation_allowed',true,
            'remediation_action',coalesce(v_skill_result->>'remediation_action',
              'RECURATE_IG_FROM_CURRENT_CANONICAL_SOURCES'),
            'production_authorized',false,'promotion_authorized',false);
        END IF;
      END IF;
      IF v_skill_result->>'status' NOT IN ('READY','COMPLETED','SKIPPED','PASS') THEN
        v_skill_findings:=v_skill_findings||jsonb_build_array(jsonb_build_object(
           'skill_code',v_skill_code,'status','SKILL_FAILED_AS_FINDING',
           'blocking_code',coalesce(v_skill_result->>'blocking_code',
                                     v_skill_result->>'status','SKILL_FAILED'),
           'continuation_allowed',true,
           'remediation_action',coalesce(v_skill_result->>'remediation_action',
             'REVIEW_SKILL_SOURCE_POLICY_AND_RETRY_GOVERNED'),
           'evidence_ref',v_skill_result->>'evidence_ref',
           'receipt',v_skill_result));
      END IF;
    END LOOP;
    v_input:=v_input||jsonb_build_object(
      'skill_execution_receipts',v_skill_receipts,
      'skill_findings',v_skill_findings,
      'analysis_scope',case when jsonb_array_length(v_skill_findings)>0
        then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
      'input_governance',coalesce(v_skill_ig,'{}'::jsonb)
          ||jsonb_build_object('analysis_scope',
              case when jsonb_array_length(v_skill_findings)>0
                then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
              'production_authorized',false,'promotion_authorized',false),
      'production_authorized',false,'promotion_authorized',false,
      'mutation_authorized',false,
      'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT')
    );
    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'input_validate',
      'supabase://public.lf_profile_execution_input_validate_v1/'||p_execution_id,
      v_input,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_context
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='context_admission'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_context IS NULL THEN
    v_base_context:=public.lf_profile_execution_context_admission_v1(p_execution_id);
    IF v_base_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_base_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_BASE_CONTEXT_NOT_READY'
        ),
        'base_context',v_base_context
      );
    END IF;

    v_context:=public.lf_profile_execution_channel_context_v1(
      p_execution_id,
      v_base_context,
      v_handoff
    );
    IF v_context->>'status'<>'READY' THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code',coalesce(
          v_context->>'blocking_code',
          'BLOCK_PROFILE_NATIVE_BRIDGE_CHANNEL_CONTEXT_NOT_READY'
        ),
        'channel_context',v_context
      );
    END IF;

    v_step:=public.lf_record_profile_execution_step_v1(
      p_execution_id,
      'context_admission',
      v_context->>'context_receipt_ref',
      v_context,
      v_actor
    );
  END IF;

  SELECT evidence_payload INTO v_baseline
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND step_id='research_baseline_freeze'
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_baseline IS NULL THEN
    v_baseline:=public.lf_profile_execution_research_baseline_v1(
      p_execution_id,
      NULL,
      v_actor
    );
    IF coalesce(v_baseline->>'outcome','') NOT IN (
         'STEP_RECORDED',
         'STEP_ALREADY_RECORDED'
       )
       AND NOT EXISTS(
         SELECT 1
         FROM public.lf_operation_execution_steps
         WHERE execution_id=p_execution_id
           AND step_id='research_baseline_freeze'
           AND status='STEP_PASS_WITH_EVIDENCE'
       ) THEN
      RETURN jsonb_build_object(
        'status','BLOCKED',
        'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_BASELINE_NOT_READY',
        'baseline_result',v_baseline
      );
    END IF;

    SELECT evidence_payload INTO v_baseline
    FROM public.lf_operation_execution_steps
    WHERE execution_id=p_execution_id
      AND step_id='research_baseline_freeze'
      AND status='STEP_PASS_WITH_EVIDENCE';
  END IF;

  SELECT count(*) INTO v_clean
  FROM public.lf_operation_execution_steps
  WHERE execution_id=p_execution_id
    AND status='STEP_PASS_WITH_EVIDENCE';

  IF v_clean<>7 THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_NATIVE_BRIDGE_PRE_MODEL_STEP_COUNT',
      'clean_step_count',v_clean,
      'expected_clean_step_count',7
    );
  END IF;

  v_policy_selection:=public.lf_profile_policy_selection_prepare_v1(p_execution_id);

  IF v_policy_selection->>'status'<>'READY' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_policy_selection->>'blocking_code','BLOCK_PROFILE_POLICY_SELECTION_PREPARE_FAILED'),
      'policy_selection',v_policy_selection
    );
  END IF;

  RETURN jsonb_build_object(
    'status','NATIVE_MODEL_INPUT_READY',
    'execution_id',p_execution_id,
    'operation_code','EJECUCION_PERFIL_LF',
    'profile_code',e.target_code,
    'profile_slug',v_slug,
    'profile_source_ref',v_source_ref,
    'profile_source_digest',p_source_digest,
    'literal_request',v_handoff->>'literal_request',
    'input_governance',v_input->'input_governance',
    'ig_open_work',public.lf_profile_ig_open_work_v1(p_execution_id),
    'ig_open_work_count',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id)),
    'ig_open_work_response_contract',jsonb_build_object(
      'required',jsonb_array_length(public.lf_profile_ig_open_work_v1(p_execution_id))>0,
      'output_field','traceability.ig_open_work_resolution',
      'coverage','EXACT_ONE_RESPONSE_PER_FAMILY',
      'allowed_statuses',jsonb_build_array(
        'RESUELTA','NO_CORRESPONDE','DEPENDENCIA','DECISIÓN_REQUERIDA'
      ),
      'resolved_requires_evidence',true,
      'dependency_or_decision_requires_next_action',true
    ),
    'context_receipt_ref',v_context->>'context_receipt_ref',
    'context_receipt_digest',v_context->>'context_receipt_digest',
    'context_capsule',v_context->'context_capsule',
    'research_baseline',v_baseline,
    'policy_resolution_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
    'policy_selection_request',v_policy_selection,
    'repair_execution_authority',
      e.manifest->'repair_execution_authority',
    'execution_write_mode',
      case
        when coalesce((e.manifest->>'governed_repair_write')::boolean,false)
          then 'GOVERNED_REPAIR_WRITE'
        else 'READ_ONLY'
      end,
    'clean_step_count',v_clean,
    'next_step','execute_profile',
    'next_action',CASE e.manifest->>'executor_mode' WHEN 'CLAUDE_NATIVE' THEN 'EXECUTE_PROFILE_IN_CURRENT_CLAUDE_NATIVE_CONTEXT' ELSE 'EXECUTE_PROFILE_IN_CURRENT_GPT_NATIVE_CONTEXT' END,
    'semantic_judge_after_output','INDEPENDENT_CONTEXT_REQUIRED',
    'router_reentry_required',false
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_invoke_selected_v1(p_execution_id text, p_channel text, p_skill_code text, p_input jsonb, p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE e record; v_plan jsonb; v_skill jsonb; v_out jsonb; v_receipt jsonb;
 v_app_contract jsonb; v_app_evidence jsonb; v_app_path text[];
 v_app_value text;
BEGIN
 SELECT target_code,status,operation_code,manifest INTO e FROM public.lf_operation_execution
 WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF' THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PARENT_RUN_NOT_ACTIVE'); END IF;
 IF e.manifest#>>'{router_profile_handoff,channel}' IS DISTINCT FROM p_channel THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CHANNEL_NOT_BOUND_TO_PARENT_RUN'); END IF;
 v_plan:=public.lf_profile_execution_plan_v1(e.target_code,p_channel,p_semantic_decision);
 -- Required deterministic skills are not vetoed by a pending OPTIONAL choice.
 -- The optional candidate is NOT automatically selected.
 IF v_plan->>'status'='SEMANTIC_SELECTION_REQUIRED'
    AND p_semantic_decision IS NULL
    AND jsonb_typeof(v_plan#>'{selection_receipt,required_skills}')='array'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(
       v_plan#>'{selection_receipt,required_skills}') x
       WHERE x->>'skill_code'=p_skill_code
         AND x->>'selection_mode'='DETERMINISTIC_POLICY') THEN
   v_plan:=v_plan||jsonb_build_object(
     'status','READY',
     'skills',v_plan#>'{selection_receipt,required_skills}',
     'selection_mode','SKILL_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED');
 END IF;
 IF v_plan->>'status'<>'READY' THEN
  RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code',coalesce(v_plan->>'blocking_code', 'SKILL_SEMANTIC_DECISION_PENDING')); END IF;
 SELECT x INTO v_skill FROM jsonb_array_elements(v_plan->'skills') x
 WHERE x->>'skill_code'=p_skill_code;
 IF v_skill IS NULL THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_NOT_SELECTED_BY_DB_POLICY'); END IF;
 -- Generic, policy-bound applicability; no skill/IG/profile name is encoded
 -- in the invoker or in the Step40/50 operation contract. A legacy NOT_REQUIRED
 -- receipt MUST NOT trigger a skill invocation.
 SELECT applicability_contract INTO v_app_contract
 FROM public.lf_skill_selector_policy_v1
 WHERE profile_code=e.target_code AND skill_code=p_skill_code
   AND required_operation=v_skill->>'required_operation'
   AND enabled AND p_channel=ANY(channels);
 IF v_app_contract IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_POLICY_NOT_FOUND');
 END IF;
 IF coalesce((v_app_contract->>'only_if_applicable')::boolean,false) THEN
   IF v_app_contract->>'evaluation'<>'EVIDENCE_PAYLOAD' OR
      coalesce(v_app_contract->>'evidence_step_id','')='' OR
      jsonb_typeof(v_app_contract->'evidence_json_path')<>'array' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_POLICY_INVALID');
   END IF;
   SELECT array_agg(path_element ORDER BY ord) INTO v_app_path
   FROM jsonb_array_elements_text(v_app_contract->'evidence_json_path')
       WITH ORDINALITY AS path(path_element,ord);
   IF v_app_path IS NULL OR cardinality(v_app_path)<1 THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_PATH_INVALID');
   END IF;
   SELECT evidence_payload INTO v_app_evidence
   FROM public.lf_operation_execution_steps
   WHERE execution_id=p_execution_id
     AND step_id=v_app_contract->>'evidence_step_id'
     AND status='STEP_PASS_WITH_EVIDENCE';
   IF v_app_evidence IS NULL THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_APPLICABILITY_EVIDENCE_NOT_READY');
   END IF;
   v_app_value:=jsonb_extract_path_text(v_app_evidence,VARIADIC v_app_path);
   IF v_app_value IS DISTINCT FROM v_app_contract->>'positive_literal' THEN
     RETURN jsonb_build_object('status','BLOCKED',
       'blocking_code',case when v_app_value='false'
             then 'SKILL_NOT_REQUIRED_BY_INPUT_VALIDATE'
             else 'SKILL_APPLICABILITY_NOT_ATTESTED' end);
   END IF;
 END IF;
 v_receipt:=jsonb_build_object('execution_id',p_execution_id,'skill_code',p_skill_code,
     'selection_mode',v_skill->>'selection_mode',
     'selection_evidence',v_skill->'selection_evidence','channel',p_channel);
 -- Source authority, input validation, dedupe, handler and child opener belong to official invoker.
 BEGIN
   v_out:=public.lf_skill_invoke_v1(p_skill_code,p_execution_id,p_input);
 EXCEPTION WHEN OTHERS THEN
   RETURN jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'parent_execution_id',p_execution_id,'skill_code',p_skill_code,
     'blocking_code',SQLSTATE,'error_message',left(SQLERRM,500),
     'selection_receipt',v_receipt,'effect_authorized',false,
     'next_action','CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS');
 END;
 IF v_out->>'status' IN ('BLOCKED','FAILED','SKILL_FAILED_AS_FINDING') THEN
   RETURN v_out||jsonb_build_object('status','SKILL_FAILED_AS_FINDING',
     'parent_execution_id',p_execution_id,'selection_receipt',v_receipt,
     'effect_authorized',false,
     'next_action','CONTINUE_PROFILE_READ_ONLY_WITH_SKILL_FINDINGS');
 END IF;
 IF v_out->>'status'='COMPLETED' AND nullif(v_out->>'skill_run_id','') IS NOT NULL THEN
   INSERT INTO public.lf_profile_skill_selection_receipt_v1(
     skill_run_id,parent_execution_id,skill_code,profile_code,channel,
     selection_mode,selection_evidence,selection_sha256)
   VALUES (v_out->>'skill_run_id',p_execution_id,p_skill_code,e.target_code,p_channel,
       v_skill->>'selection_mode',v_receipt,
       encode(extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),'hex'))
   ON CONFLICT(skill_run_id) DO NOTHING;
   IF NOT EXISTS(SELECT 1 FROM public.lf_profile_skill_selection_receipt_v1 s
                 WHERE s.skill_run_id=v_out->>'skill_run_id'
                   AND s.parent_execution_id=p_execution_id AND s.skill_code=p_skill_code
                   AND s.selection_evidence=v_receipt) THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_REPLAY_RECEIPT_MISMATCH');
   END IF;
 END IF;
 RETURN v_out||jsonb_build_object('parent_execution_id',p_execution_id,
     'selection_mode',v_skill->>'selection_mode','selection_receipt',v_receipt);
END;
$function$;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_runtime_ticket_issue_v1(p_execution_id text, p_skill_code text, p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions'
AS $function$
DECLARE
 v_e public.lf_operation_execution%rowtype;
 v_plan jsonb;v_invoked jsonb;v_req jsonb;
 v_catalog_runtime_slug text;
 v_id uuid:=extensions.gen_random_uuid();
 v_exp timestamptz:=clock_timestamp()+interval '5 minutes';
 v_screen integer;
 v_existing_tickets integer;
BEGIN
 IF jsonb_typeof(p_input)<>'object'
   OR p_input->>'execution_id' IS DISTINCT FROM p_execution_id THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_INPUT_INVALID');
 END IF;
 SELECT * INTO v_e FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.target_type='PERFIL' AND e.status='IN_PROGRESS';
 IF NOT FOUND OR p_input->>'profile_code' IS DISTINCT FROM v_e.target_code THEN
  RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_PARENT_INVALID');
 END IF;
 v_plan:=public.lf_profile_execution_plan_v1(v_e.target_code,
   v_e.manifest#>>'{router_profile_handoff,channel}',NULL);
 -- Follow the same deterministic-required policy despite optional semantic
 -- pending. Do not issue runtime tickets for unselected optional skills.
 IF v_plan->>'status'='SEMANTIC_SELECTION_REQUIRED'
   AND jsonb_typeof(v_plan#>'{selection_receipt,required_skills}')='array'
   AND EXISTS(SELECT 1 FROM jsonb_array_elements(
        v_plan#>'{selection_receipt,required_skills}') x
       WHERE x->>'skill_code'=p_skill_code
         AND x->>'selection_mode'='DETERMINISTIC_POLICY') THEN
   v_plan:=v_plan||jsonb_build_object(
     'status','READY',
     'skills',v_plan#>'{selection_receipt,required_skills}',
     'selection_mode','TICKET_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED');
 END IF;
 IF v_plan->>'status'<>'READY' OR NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_plan->'skills') sk
    WHERE sk->>'skill_code'=p_skill_code AND sk->>'effect'='READ_ONLY'
 ) THEN RETURN jsonb_build_object(
   'status','BLOCKED','code','SKILL_TICKET_NOT_POLICY_SELECTED'); END IF;
 v_invoked:=public.lf_profile_skill_invoke_selected_v1(
    p_execution_id,v_e.manifest#>>'{router_profile_handoff,channel}',
    p_skill_code,p_input,NULL);
 v_req:=v_invoked->'runtime_request';
 SELECT c.runtime_slug INTO v_catalog_runtime_slug FROM public.lf_skill_catalog_v1 c
 WHERE c.skill_code=p_skill_code AND c.status='READY' AND c.effect='READ_ONLY';
 IF coalesce(v_catalog_runtime_slug,'') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
 OR v_catalog_runtime_slug IS DISTINCT FROM v_req->>'runtime_slug' THEN
   RETURN jsonb_build_object('status','BLOCKED','code','SKILL_RUNTIME_CATALOG_SLUG_MISMATCH');
 END IF;
 IF v_invoked->>'status'<>'RUNTIME_REQUIRED'
    OR v_req->>'transport'<>'DIRECT_EDGE_INVOCATION'
    OR coalesce(v_req->>'runtime_slug','') !~ '^[a-z0-9][a-z0-9-]{0,62}$'
    OR jsonb_typeof(v_req->'request_body')<>'object' THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SKILL_TICKET_RUNTIME_NOT_ATTESTED',
      'skill_status',v_invoked->>'status');
 END IF;
 -- Strong DB-side bound and serialized ticket issue: no third ticket,
 -- including retries racing across native clients for the same RUN.
 PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('LF_PROFILE_SKILL_TICKET_CAP:'||
       p_execution_id||':'||p_skill_code,0));
 SELECT count(*)::integer INTO v_existing_tickets
 FROM private.lf_profile_skill_runtime_ticket_v1
 WHERE execution_id=p_execution_id AND skill_code=p_skill_code;
 IF v_existing_tickets>=2 THEN
   RETURN jsonb_build_object('status','BLOCKED',
     'code','SKILL_RUNTIME_TICKET_CAP_EXHAUSTED',
     'attempt_count',v_existing_tickets,'production_authorized',false);
 END IF;
 INSERT INTO private.lf_profile_skill_runtime_ticket_v1(
   ticket_id,execution_id,skill_code,runtime_slug,request_body,
   request_sha256,expires_at
 ) VALUES (
   v_id,p_execution_id,p_skill_code,v_req->>'runtime_slug',v_req->'request_body',
   encode(extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),'hex'),v_exp
 );
 IF v_req->>'legacy_ticket_adapter'='INPUT_GOVERNANCE_CONTEXT_PACK_V1' THEN
   v_screen:=nullif(v_req#>>'{request_body,pantalla_id}','')::integer;
   IF p_skill_code<>'INPUT_GOVERNANCE_CONTEXT_PACK'
     OR v_screen IS NULL OR v_screen<1
     OR v_req#>>'{request_body,consumer}'<>'CONTEXT_PACK' THEN
     RAISE EXCEPTION 'SKILL_IG_ADAPTER_SCOPE_INVALID';
   END IF;
   INSERT INTO private.lf_profile_input_governance_runtime_ticket_v1(
     ticket_id,execution_id,pantalla_id,consumer,
     router_handoff_fingerprint,expires_at
   ) VALUES(
     v_id,p_execution_id,v_screen,'CONTEXT_PACK',
     v_e.manifest#>>'{router_profile_handoff,fingerprint_sha256}',v_exp
   );
 END IF;
 RETURN jsonb_build_object('status','AUTHORIZED','ticket',v_id::text,
   'execution_id',p_execution_id,'skill_code',p_skill_code,
   'runtime_slug',v_req->>'runtime_slug',
   'expires_at',v_exp,'transport','DIRECT_EDGE_INVOCATION');
END
$function$;

DO $post$
BEGIN
 IF (SELECT resolver_ref FROM public.lf_operation_step_contracts
    WHERE operation_code='EJECUCION_PERFIL_LF' AND step_order=40
      AND step_id='input_validate' AND status='ACTIVE_ENFORCEMENT')
    IS DISTINCT FROM 'public.lf_profile_execution_input_validate_v1' THEN
    RAISE EXCEPTION 'LF_STEP40_CONTRACT_POSTREAD_FAILED';
 END IF;
 IF position('REVIEW_SKILL_SOURCE_POLICY_AND_RETRY_GOVERNED' in pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'LF_STEP40_BRIDGE_POSTREAD_FAILED';
 END IF;
 IF position('SKILL_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED' in pg_get_functiondef(
    'public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'LF_STEP40_INVOKER_POSTREAD_FAILED';
 END IF;
 IF position('TICKET_REQUIRED_POLICY_WITH_OPTIONAL_DEFERRED' in pg_get_functiondef(
    'public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'LF_STEP40_TICKET_POSTREAD_FAILED';
 END IF;
END $post$;
COMMIT;
