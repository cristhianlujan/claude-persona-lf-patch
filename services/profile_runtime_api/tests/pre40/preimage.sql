-- Exact pre-migration definitions from the 2026-11-20 readback. Isolated PG only.
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(p_execution_id text, p_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;v_handoff jsonb;v_scope jsonb;
 v_input jsonb;v_ctx jsonb;v_decision jsonb;v_selected jsonb;v_oldplan jsonb;v_screen_request jsonb;v_screen_validation jsonb;
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

 IF v_scope IS NULL AND upper(coalesce(v_handoff#>>'{scope,target_type}',''))='PANTALLA'
   AND jsonb_typeof(e.manifest->'screen_selection_result')='object' THEN
   v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
     v_handoff->>'literal_request',v_handoff->'scope');
   v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
     v_screen_request,e.manifest->'screen_selection_result');
   IF v_screen_validation->>'status'='VALID'
      AND v_screen_validation->>'decision'='SELECTED'
      AND nullif(v_screen_validation->>'selected_screen_code','') IS NOT NULL THEN
     v_scope:=coalesce(v_handoff->'scope','{}'::jsonb)||
       jsonb_build_object('resolved_screen_code',
         v_screen_validation->>'selected_screen_code',
         'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC');
   END IF;
 END IF;
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
END $function$;

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
  v_skill_selection_findings jsonb:='[]'::jsonb;
  v_input_governance_findings jsonb:='[]'::jsonb;
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
                'skill_code',v_skill_code) ||
                CASE WHEN v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK'
                     THEN jsonb_build_object('pantalla_id',v_ig_ticket->'pantalla_id')
                     ELSE '{}'::jsonb END,
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

    SELECT coalesce(jsonb_agg(f.value),'[]'::jsonb)
      INTO v_skill_selection_findings
      FROM jsonb_array_elements(v_skill_findings) f
      WHERE f.value->>'skill_code' IN
        ('SKILL_SELECTION','OPTIONAL_SKILL_SELECTION','SKILL_POLICY_SELECTION');
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_skill_receipts) r
               WHERE r.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
                 AND jsonb_typeof(r.value->'result')='object') THEN
      SELECT coalesce(jsonb_agg(f.value),'[]'::jsonb)
        INTO v_input_governance_findings
        FROM jsonb_array_elements(v_skill_findings) f
        WHERE f.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK';
      IF jsonb_typeof(v_skill_ig->'findings')='array' THEN
        v_input_governance_findings:=v_input_governance_findings||
          (v_skill_ig->'findings');
      END IF;
    END IF;
    v_input:=v_input||jsonb_build_object(
      'skill_selection_findings',v_skill_selection_findings,
      'input_governance_findings',v_input_governance_findings,
      'skill_execution_receipts',v_skill_receipts,
      'skill_findings',v_skill_findings,
      'analysis_scope',case when coalesce((e.manifest->>'governed_repair_write')::boolean,false) then 'GOVERNED_REPAIR' when jsonb_array_length(v_input_governance_findings)>0 then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
      'input_governance',coalesce(v_skill_ig,'{}'::jsonb)
          ||jsonb_build_object('analysis_scope',
              case when coalesce((e.manifest->>'governed_repair_write')::boolean,false) then 'GOVERNED_REPAIR' when jsonb_array_length(v_input_governance_findings)>0 then 'READ_ONLY_WITH_IG_FINDINGS' else 'READ_ONLY_PROFILE_VALIDATION' end,
              'production_authorized',false,'promotion_authorized',false),
      'production_authorized',false,'promotion_authorized',false,
      'ig_security_clearance',false,
      'mutation_authorized',coalesce((e.manifest->>'governed_repair_write')::boolean,false),
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
      'output_field',public.lf_profile_ig_open_work_output_field_v2(e.target_code,NULL::jsonb),
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

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_run_bind_v1(p_execution_id text, p_decision jsonb, p_actor_execution_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;v_plan jsonb;v_decision jsonb;v_existing jsonb;
BEGIN
 IF current_setting('request.jwt.claim.role',true)<>'service_role'
    AND session_user NOT IN ('postgres','service_role') THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_AUTHORITY_INVALID'); END IF;
 IF p_actor_execution_id IS DISTINCT FROM p_execution_id OR
    nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL OR
    jsonb_typeof(p_decision)<>'object' THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_ACTOR_OR_TRANSPORT_INVALID'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id FOR UPDATE;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_type<>'PERFIL' THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_RUN_INVALID'); END IF;
 v_decision:=p_decision;
 IF p_decision ? 'selected_skill_code' THEN
   v_decision:=public.lf_skill_selection_legacy_running_compat_v1(p_execution_id,p_decision);
 END IF;
 v_existing:=e.manifest->'skill_selection_decision';
 IF v_existing IS NOT NULL THEN
   IF v_existing=v_decision THEN RETURN jsonb_build_object('status','ALREADY_BOUND',
     'execution_id',p_execution_id); END IF;
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_REPLAY_DIFFERENT_DECISION');
 END IF;
 v_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,v_decision);
 IF v_plan->>'status'<>'READY' OR jsonb_typeof(v_plan->'skills')<>'array' THEN
 RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code',coalesce(v_plan->>'blocking_code','SKILL_BIND_PLAN_INVALID')); END IF;
 UPDATE public.lf_operation_execution SET manifest=manifest||
   jsonb_build_object('skill_selection_decision',v_decision,
     'skill_selection_readback',jsonb_build_object(
        'selected_skill_codes',v_plan->'selected_skill_codes',
        'skill_selection_status',v_plan->>'skill_selection_status',
        'source','OFFICIAL_SKILL_POLICY_CURRENT_RUN')),
    updated_at=now(),updated_by_execution_id=p_execution_id
 WHERE execution_id=p_execution_id;
 RETURN jsonb_build_object('status','BOUND','execution_id',p_execution_id,
   'selected_skill_codes',v_plan->'selected_skill_codes','selection_receipt',v_plan->'selection_receipt');
END $function$;

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
     AND (
       NOT (p.applicability_contract ? 'selection_business')
       OR EXISTS (
         SELECT 1
         FROM public.lf_operation_execution parent
         WHERE parent.execution_id=v_ctx#>>'{input,execution_id}'
           AND parent.operation_code='EJECUCION_PERFIL_LF'
           AND parent.status='IN_PROGRESS'
           AND parent.target_code=p_profile_code
           AND parent.manifest#>>'{router_profile_handoff,channel}'=p_channel
           AND parent.manifest#>>'{router_profile_handoff,business}'=
               p.applicability_contract->>'selection_business'
           AND parent.manifest#>>'{router_profile_handoff,literal_request}'=
               v_ctx->>'request_text'
       )
     )
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
END $function$;
