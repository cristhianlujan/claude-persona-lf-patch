-- Readback of function definitions only; not an executable migration.

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(p_execution_id text, p_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;v_handoff jsonb;v_scope jsonb;
 v_input jsonb;v_ctx jsonb;v_decision jsonb;v_selected jsonb;v_oldplan jsonb;
BEGIN
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id;
 IF NOT FOUND OR e.operation_code<>'EJECUCION_PERFIL_LF' OR e.status<>'IN_PROGRESS' THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_RUN_INVALID'); END IF;
 v_handoff:=e.manifest->'router_profile_handoff';
 IF jsonb_typeof(v_handoff)<>'object' OR coalesce(v_handoff->>'literal_request','')='' OR
    coalesce(v_handoff->>'channel','')='' THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_RUN_HANDOFF_UNREADABLE'); END IF;
 SELECT evidence_payload->'resolved_scope' INTO v_scope
 FROM public.lf_operation_execution_steps WHERE execution_id=p_execution_id
 AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 v_input:=jsonb_build_object('execution_id',p_execution_id,
   'request_text',v_handoff->>'literal_request',
   'profile_code',e.target_code,'consumer','CONTEXT_PACK');
 IF jsonb_typeof(v_scope)='object' AND v_scope<>'{}'::jsonb THEN
   v_input:=v_input||jsonb_build_object('scope',v_scope,
       'pantalla_codigo',v_scope->>'resolved_screen_code');
 END IF;
 v_ctx:=jsonb_build_object('profile_code',e.target_code,
    'channel',v_handoff->>'channel',
    'step',CASE WHEN v_scope IS NOT NULL THEN '40' ELSE '30' END,
    'request_text',v_handoff->>'literal_request',
    'intent',coalesce(v_handoff->>'intent',v_handoff->>'literal_request'),
    'input',v_input,
    'input_summary',jsonb_build_object('available_keys',
      (SELECT jsonb_agg(k ORDER BY k) FROM jsonb_object_keys(v_input) k),
      'screen_code',v_input->>'pantalla_codigo'));
 v_decision:=coalesce(e.manifest->'skill_selection_decision',p_decision);
 IF v_decision IS NOT NULL AND v_decision ? 'selected_skill_code' THEN
   v_decision:=public.lf_skill_selection_legacy_running_compat_v1(p_execution_id,v_decision);
 END IF;
 v_selected:=public.lf_profile_skill_selection_prepare_context_v1(
   e.target_code,v_handoff->>'channel',v_decision,v_ctx);
 v_oldplan:=public.lf_profile_execution_plan_v1(e.target_code,v_handoff->>'channel',NULL);
 IF v_oldplan->>'operation_code'<>'EJECUCION_PERFIL_LF' OR
    jsonb_array_length(coalesce(v_oldplan->'steps','[]'::jsonb))<>11 THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_OPERATION_PLAN_CONTRACT_INVALID'); END IF;
 RETURN v_oldplan||jsonb_build_object(
    'status',v_selected->>'status','skills',coalesce(v_selected->'skills','[]'::jsonb),
    'selection_receipt',v_selected,
    'skill_candidates',v_selected->'skill_candidates',
    'selected_skill_codes',v_selected->'selected_skill_codes',
    'skill_selection_status',v_selected->>'selection_status',
    'content_findings',v_selected->'content_findings',
    'continuation_allowed',v_selected->'continuation_allowed',
    'next_action',v_selected->>'next_action',
    'blocking_code',v_selected->>'blocking_code');
END $function$


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
  v_selector_finding jsonb;
  v_late jsonb;
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

    v_skill_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,NULL::jsonb);
    -- Content findings from the selector are part of Step40's evidence even
    -- when the plan is READY with zero skills. They are not a blocking gate.
    IF jsonb_typeof(v_skill_plan->'content_findings')='array' THEN
      FOR v_selector_finding IN
        SELECT value FROM jsonb_array_elements(v_skill_plan->'content_findings') LOOP
        v_skill_findings:=v_skill_findings||jsonb_build_array(
          v_selector_finding||jsonb_build_object(
            'skill_code','SKILL_SELECTION','status','SKILL_CONTENT_FINDING',
            'continuation_allowed',true,'production_authorized',false));
      END LOOP;
    END IF;
    -- Selected skills are optional to profile continuation. A missing/invalid
    -- skill plan produces an auditable READ_ONLY finding, never implicit skill
    -- execution or permission to write. Router/scope validation is unchanged.
    IF v_skill_plan->>'status'='SKILL_SELECTION_PENDING_FINDING'
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
        p_execution_id,v_handoff->>'channel',v_skill_code,v_skill_input,e.manifest->'skill_selection_decision'
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

  -- Reconcile a semantic choice made after Step40 was persisted, before Step50.
  -- The old Step40 PASS is never rewritten. The new receipt is append-only.
  v_late:=public.lf_profile_skill_reconcile_late_v1(p_execution_id);
  IF v_late->>'status'='SKILL_RUNTIME_REQUIRED' THEN RETURN v_late; END IF;
  IF v_late->>'status'<>'READY' THEN
    RETURN jsonb_build_object('status','BLOCKED',
      'blocking_code',coalesce(v_late->>'blocking_code','SKILL_LATE_RECONCILIATION_INVALID'),
      'late_skill_reconciliation',v_late);
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
    'late_skill_findings',v_late->'findings',
    'late_skill_execution_receipts',v_late->'receipts',
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
$function$


CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(p_profile_code text, p_channel text, p_decision jsonb, p_ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_required jsonb:='[]'::jsonb;v_candidates jsonb:='[]'::jsonb;
 v_selected jsonb:='[]'::jsonb;v_findings jsonb:='[]'::jsonb;
 v_unavailable jsonb:='[]'::jsonb;v_input jsonb;
 v_item jsonb;v_choices jsonb;v_one jsonb;v_reason text;v_refs jsonb;
 v_ctx jsonb:=coalesce(p_ctx,'{}'::jsonb);
 r record;n integer;k text;
BEGIN
 IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL
 OR p_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PROFILE_CHANNEL_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_selection_registry_v1 d
  JOIN public.lf_profile_selector_policy_v1 p USING(profile_code)
  WHERE d.profile_code=p_profile_code AND d.descriptor_status='CURRENT'
    AND p_channel=ANY(p.channels))
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PROFILE_AUTHORITY_INVALID'); END IF;
 IF jsonb_typeof(v_ctx)<>'object' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CONTEXT_TRANSPORT_INVALID'); END IF;
 IF v_ctx<>'{}'::jsonb AND (
     v_ctx->>'profile_code' IS DISTINCT FROM p_profile_code
     OR v_ctx->>'channel' IS DISTINCT FROM p_channel
     OR coalesce(v_ctx->>'step','') !~ '^(30|40|45|47|50|60|70|80)$')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CONTEXT_BINDING_INVALID'); END IF;
 v_input:=coalesce(v_ctx->'input','{}'::jsonb);
 IF jsonb_typeof(v_input)<>'object' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_INPUT_TRANSPORT_INVALID'); END IF;
 FOR r IN SELECT p.skill_code,p.selection_mode,p.required_operation,p.allowed_effects,
      c.status AS catalog_status,c.effect,c.required_operation AS catalog_operation,c.handler_fn,
      c.input_required,d.descriptor_status,d.descriptor,d.source_revision,d.source_ref
   FROM public.lf_skill_selector_policy_v1 p
   LEFT JOIN public.lf_skill_catalog_v1 c USING(skill_code)
   LEFT JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
   WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   ORDER BY p.skill_code
 LOOP
   IF r.selection_mode NOT IN ('SEMANTIC_OPTIONAL','DETERMINISTIC_REQUIRED')
   OR r.catalog_status IS DISTINCT FROM 'READY'
   OR r.descriptor_status IS DISTINCT FROM 'CURRENT'
   OR r.catalog_operation IS DISTINCT FROM r.required_operation
   OR r.effect IS NULL OR NOT r.effect=ANY(r.allowed_effects)
   OR coalesce(r.source_revision,'')='' OR r.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_POLICY_CATALOG_SOURCE_INVALID',
          'skill_code',r.skill_code); END IF;
   IF EXISTS (SELECT 1 FROM public.lf_skill_selector_policy_v1 p
      WHERE p.profile_code=p_profile_code AND p.skill_code=r.skill_code
        AND p.owner_decision_required)
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_OWNER_AUTHORITY_REQUIRED'); END IF;
   IF r.catalog_operation<>'EJECUCION_PERFIL_LF' OR r.effect<>'READ_ONLY' THEN
      v_unavailable:=v_unavailable||jsonb_build_array(jsonb_build_object(
       'skill_code',r.skill_code,'reason','OTHER_OPERATION_OR_EFFECT_NOT_STEP40'));
      CONTINUE;
   END IF;
   IF EXISTS(SELECT 1 FROM unnest(r.input_required) f
      WHERE NOT (v_input ? f)
      OR v_input->f IN ('null'::jsonb,'""'::jsonb,'"{}"'::jsonb,'{}'::jsonb,'[]'::jsonb)
      OR (jsonb_typeof(v_input->f)='string' AND btrim(v_input->>f)=''))
   THEN v_unavailable:=v_unavailable||jsonb_build_array(jsonb_build_object(
      'skill_code',r.skill_code,'reason','INPUT_REQUIRED_NOT_AVAILABLE',
      'required',to_jsonb(r.input_required),'step',v_ctx->>'step'));
      CONTINUE;
   END IF;
   v_item:=jsonb_build_object('skill_code',r.skill_code,'handler_fn',r.handler_fn,
      'required_operation',r.catalog_operation,'effect',r.effect,
      'input_required',to_jsonb(r.input_required),'source_revision',r.source_revision,
      'source_ref',r.source_ref,'descriptor',r.descriptor,
      'selection_context',jsonb_build_object(
        'request_text',v_ctx->>'request_text','intent',v_ctx->>'intent',
        'profile_code',p_profile_code,'channel',p_channel,
        'step',v_ctx->>'step','input_summary',v_ctx->'input_summary'));
   IF r.selection_mode='DETERMINISTIC_REQUIRED' THEN
      v_required:=v_required||jsonb_build_array(v_item||
      jsonb_build_object('selection_mode','DETERMINISTIC_POLICY',
       'selection_evidence',jsonb_build_object('source_revision',r.source_revision)));
   ELSE v_candidates:=v_candidates||jsonb_build_array(v_item); END IF;
 END LOOP;
 IF p_decision IS NULL THEN
   IF jsonb_array_length(v_candidates)=1 AND v_candidates->0->>'effect'='READ_ONLY' THEN
     v_item:=v_candidates->0;
     v_selected:=jsonb_build_array(v_item||jsonb_build_object(
      'selection_mode','DETERMINISTIC_INPUT_UNIQUE',
      'selection_evidence',jsonb_build_object(
       'reason','ONE_ELIGIBLE_READ_ONLY_SKILL_WITH_VALID_INPUT',
       'source_revision',v_item->>'source_revision',
       'input_required',v_item->'input_required','step',v_ctx->>'step')));
   ELSE
     v_findings:=jsonb_build_array(jsonb_build_object(
       'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
       'finding_alias','SKILL_SELECTION_PENDING_FINDING',
       'continuation_allowed',true,'production_authorized',false,
       'candidate_count',jsonb_array_length(v_candidates),
       'remediation_action','SUBMIT_SKILL_SELECTION'));
   END IF;
 ELSE
   IF jsonb_typeof(p_decision)<>'object' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DECISION_TRANSPORT_INVALID'); END IF;
   IF p_decision ? 'legacy_block_code' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code',p_decision->>'legacy_block_code'); END IF;
   IF p_decision ? 'selected_skill_code' OR
      jsonb_typeof(p_decision->'selected_skill_codes')<>'array' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_LIST_SCHEMA_INVALID'); END IF;
   v_choices:=p_decision->'selected_skill_codes';
   n:=jsonb_array_length(v_choices);
   IF n>2 THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','SKILL_SELECTION_TICKET_LIMIT_EXCEEDED','maximum',2); END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_choices) v
     WHERE jsonb_typeof(v)<>'string' OR nullif(btrim(v#>>'{}'),'') IS NULL)
   OR (SELECT count(DISTINCT v#>>'{}') FROM jsonb_array_elements(v_choices) v)<>n
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LIST_INVALID_OR_DUPLICATE'); END IF;
   v_reason:=nullif(btrim(coalesce(p_decision->>'reason','')),'');
   v_refs:=p_decision->'evidence_refs';
   IF v_reason IS NULL THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_REASON_MISSING'); END IF;
   IF n>0 AND (jsonb_typeof(v_refs)<>'array' OR jsonb_array_length(v_refs)=0
       OR p_decision->>'review_mode'<>'CURRENT_CONTEXT_REVIEW') THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_EVIDENCE_INVALID'); END IF;
   FOR v_one IN SELECT value FROM jsonb_array_elements(v_choices) LOOP
      k:=v_one#>>'{}';
      SELECT x INTO v_item FROM jsonb_array_elements(v_candidates) x WHERE x->>'skill_code'=k;
      IF v_item IS NULL THEN RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','SKILL_SELECTION_NOT_IN_ELIGIBLE_INPUT_CANDIDATES','skill_code',k); END IF;
      IF (p_decision->'descriptor_revisions'->>k) IS DISTINCT FROM v_item->>'source_revision' THEN
         RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_SOURCE_STALE',
             'skill_code',k); END IF;
      v_selected:=v_selected||jsonb_build_array(v_item||jsonb_build_object(
        'selection_mode','SEMANTIC_DESCRIPTOR',
        'selection_evidence',jsonb_build_object('reason',v_reason,'evidence_refs',v_refs,
           'descriptor_revision',v_item->>'source_revision',
           'review_mode','CURRENT_CONTEXT_REVIEW','source_ref',v_item->>'source_ref')));
   END LOOP;
   IF n=0 THEN v_findings:=jsonb_build_array(jsonb_build_object(
     'finding_code','SKILL_EXPLICIT_NONE','reason',v_reason,
     'continuation_allowed',true,'production_authorized',false)); END IF;
 END IF;
 RETURN jsonb_build_object('status','READY','skills',v_required||v_selected,
  'selection_status',CASE WHEN jsonb_array_length(v_candidates)>1 AND p_decision IS NULL
      THEN 'SKILL_SELECTION_PENDING_FINDING' ELSE 'SKILL_SELECTION_REQUESTED' END,
  'next_action','SUBMIT_SKILL_SELECTION','selected_skill_codes',coalesce(v_choices,'[]'::jsonb),
  'skill_candidates',v_candidates,'unavailable_skills',v_unavailable,
  'content_findings',v_findings,'required_skills',v_required,
  'profile_code',p_profile_code,'channel',p_channel,'continuation_allowed',true,
  'selection_mode','OPTIONAL_FAIL_OPEN','maximum_selected_skills',2);
END $function$


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
