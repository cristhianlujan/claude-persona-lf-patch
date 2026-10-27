-- LF / GPT Native / CONTEXT_PACK runtime handoff.
-- The Native bridge materializes a one-use ticket and returns the exact governed
-- caller invocation. No remote worker, Router re-entry, SQL queue, cron or polling.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
     )) <> 'a2d74a4d5763f97bca402ffc273e2449' THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_BRIDGE_SOURCE_DRIFT';
  END IF;

  IF to_regprocedure(
       'public.lf_profile_input_governance_runtime_ticket_issue_v1(text,text,text,jsonb)'
     ) IS NULL THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_TICKET_ISSUER_MISSING';
  END IF;

  IF NOT EXISTS(
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code='EJECUCION_PERFIL_LF'
      AND lifecycle_state_code='OP_OPERATIONAL'
  ) THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_OPERATION_NOT_OPERATIONAL';
  END IF;
END
$precheck$;

DO $patch$
DECLARE
  d text;
  old_decl text := $old$
  v_policy_selection jsonb;
BEGIN
$old$;
  new_decl text := $new$
  v_policy_selection jsonb;
  v_ig_ticket jsonb;
BEGIN
$new$;
  old_block text := $old$
      IF v_input->>'status'='INPUT_GOVERNANCE_RUNTIME_REQUIRED'
         AND v_input->>'next_action'='RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE'
         AND v_input#>>'{input_governance,runtime_request,transport}'='DIRECT_EDGE_INVOCATION'
         AND v_input#>>'{input_governance,runtime_request,request_body,consumer}'='CONTEXT_PACK'
      THEN
        RETURN jsonb_build_object(
          'status','INPUT_GOVERNANCE_RUNTIME_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'input_validate',v_input,
          'input_governance_runtime_request',
            v_input#>'{input_governance,runtime_request}',
          'input_governance_transport','DIRECT_EDGE_INVOCATION',
          'next_action','RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;
$old$;
  new_block text := $new$
      IF v_input->>'status'='INPUT_GOVERNANCE_RUNTIME_REQUIRED'
         AND v_input->>'next_action'='RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE'
         AND v_input#>>'{input_governance,runtime_request,transport}'='DIRECT_EDGE_INVOCATION'
         AND v_input#>>'{input_governance,runtime_request,request_body,consumer}'='CONTEXT_PACK'
      THEN
        v_ig_ticket:=public.lf_profile_input_governance_runtime_ticket_issue_v1(
          p_execution_id,
          v_handoff->>'literal_request',
          v_source_ref,
          v_handoff
        );

        IF v_ig_ticket->>'status'<>'AUTHORIZED'
           OR coalesce(v_ig_ticket->>'ticket','') !~
              '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
           OR v_ig_ticket->>'execution_id' IS DISTINCT FROM p_execution_id
           OR v_ig_ticket->>'consumer' IS DISTINCT FROM 'CONTEXT_PACK'
           OR coalesce((v_ig_ticket->>'queue_required')::boolean,true)
           OR coalesce((v_ig_ticket->>'polling_required')::boolean,true)
           OR coalesce((v_ig_ticket->>'router_reentry_required')::boolean,true)
        THEN
          RETURN jsonb_build_object(
            'status','BLOCKED',
            'blocking_code','BLOCK_PROFILE_NATIVE_IG_RUNTIME_TICKET_NOT_AUTHORIZED',
            'execution_id',p_execution_id,
            'ticket_result',v_ig_ticket,
            'router_reentry_required',false
          );
        END IF;

        RETURN jsonb_build_object(
          'status','INPUT_GOVERNANCE_RUNTIME_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'input_validate',v_input,
          'input_governance_runtime_request',
            jsonb_build_object(
              'transport','DIRECT_EDGE_INVOCATION',
              'runtime_orchestrator',
                'SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1',
              'runtime_slug','lf-profiles-governance-caller-v1',
              'request_headers',jsonb_build_object(
                'X-LF-Profile-Runtime-Ticket',v_ig_ticket->>'ticket'
              ),
              'request_body',jsonb_build_object(
                'action','input_readiness_context_pack_runtime_v1',
                'execution_id',p_execution_id,
                'pantalla_id',(v_ig_ticket->>'pantalla_id')::integer
              ),
              'terminal_statuses',jsonb_build_array(
                'READY','HUMAN_DECISION_REQUIRED','BLOCKED'
              ),
              'continuation_statuses',jsonb_build_array(
                'VALIDATOR_RESUME_REQUIRED'
              ),
              'continuation_action',
                'REINVOKE_CALLER_WITH_FRESH_NATIVE_BRIDGE_TICKET',
              'ticket_expires_at',v_ig_ticket->'expires_at',
              'queue_required',false,
              'polling_required',false
            ),
          'input_governance_transport','DIRECT_EDGE_INVOCATION',
          'next_action',
            'INVOKE_INPUT_GOVERNANCE_CALLER_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        );
      END IF;
$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF (length(d)-length(replace(d,old_decl,'')))/length(old_decl)<>1 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_DECL_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_decl,new_decl);

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_BLOCK_ANCHOR_DRIFT';
  END IF;
  d:=replace(d,old_block,new_block);

  EXECUTE d;
END
$patch$;

COMMENT ON FUNCTION public.lf_profile_native_bridge_prepare_v1(text,text,text,text) IS
'Prepares governed GPT_NATIVE profile execution. When CONTEXT_PACK refresh is required it issues a short-lived one-use ticket and returns the exact lf-profiles-governance-caller-v1 DIRECT_EDGE_INVOCATION, then the same EJECUCION_PERFIL_LF/input_validate is retried. No Router re-entry, SQL queue, cron polling or remote profile worker participates.';

DO $postcheck$
DECLARE
  s text;
BEGIN
  s:=pg_get_functiondef(
    'public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure
  );

  IF strpos(s,'lf_profile_input_governance_runtime_ticket_issue_v1')=0
     OR strpos(s,'''lf-profiles-governance-caller-v1''')=0
     OR strpos(s,'''input_readiness_context_pack_runtime_v1''')=0
     OR strpos(s,'''X-LF-Profile-Runtime-Ticket''')=0
     OR strpos(s,'''INVOKE_INPUT_GOVERNANCE_CALLER_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE''')=0
     OR strpos(s,'''DIRECT_EDGE_INVOCATION''')=0
     OR strpos(s,'''queue_required'',false')=0
     OR strpos(s,'''polling_required'',false')=0
     OR strpos(s,'''router_reentry_required'',false')=0
  THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_HANDOFF_POSTCHECK_FAILED';
  END IF;

  IF strpos(s,'lf_router_resolve_v1')>0
     OR strpos(s,'''STORY_CREATOR''')>0
     OR strpos(s,'fn_input_governance_queue_submit_v1')>0
  THEN
    RAISE EXCEPTION 'PROFILE_NATIVE_CONTEXT_PACK_SCOPE_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
