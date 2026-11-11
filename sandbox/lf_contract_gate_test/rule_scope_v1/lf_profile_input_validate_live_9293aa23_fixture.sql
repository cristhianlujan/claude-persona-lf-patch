-- frozen exact live pg_get_functiondef source; isolated CI only, no use as prod patch
CREATE OR REPLACE FUNCTION public.lf_profile_execution_input_validate_v1(p_execution_id text, p_input_literal text, p_input_source_ref text, p_handoff jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'programacion'
AS $function$
DECLARE
  v_exec public.lf_operation_execution%rowtype;
  v_handoff_validation jsonb;
  v_scope jsonb;
  v_adapters jsonb:='[]'::jsonb;
  v_ig jsonb;
  v_direct_profile_ig boolean:=false;
  v_task_requirement jsonb;
  v_screen_request jsonb;
  v_screen_result jsonb;
  v_screen_validation jsonb;
  v_resolved_scope jsonb;
  v_ig_runtime_orchestrator text;
  v_ig_runtime_slug text;
BEGIN
  SELECT * INTO v_exec
  FROM public.lf_operation_execution
  WHERE execution_id=p_execution_id;

  IF NOT FOUND
     OR v_exec.operation_code<>'EJECUCION_PERFIL_LF'
     OR v_exec.target_type<>'PERFIL'
     OR v_exec.status<>'IN_PROGRESS' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_EXECUTION_INVALID',
      'router_reentry_required',false
    );
  END IF;

  v_handoff_validation:=public.lf_router_profile_execution_handoff_validate_v1(
    p_handoff,p_input_literal,v_exec.target_code
  );
  IF coalesce((v_handoff_validation->>'valid')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_HANDOFF_INVALID',
      'handoff_validation',v_handoff_validation,
      'router_reentry_required',false
    );
  END IF;

  v_scope:=public.lf_profile_execution_scope_authority_packet_v1(
    p_execution_id,p_input_literal,p_input_source_ref
  );
  IF v_scope->>'status' IS DISTINCT FROM 'READY'
     OR jsonb_typeof(v_scope->'scope_authority_packet')<>'object'
     OR nullif(v_scope->>'scope_packet_sha256','') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_INPUT_VALIDATE_SCOPE_NOT_READY',
      'scope_result',v_scope,
      'router_reentry_required',false
    );
  END IF;

  v_task_requirement:=public.lf_profile_input_governance_requirement_v1(p_handoff);
  IF v_task_requirement->>'status'='BLOCKED' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code',coalesce(v_task_requirement->>'blocking_code','BLOCK_PROFILE_IG_TASK_BINDING_INVALID'),
      'input_governance_task',v_task_requirement,
      'router_reentry_required',false
    );
  END IF;

  IF v_task_requirement->>'status'='NOT_REQUIRED' THEN
    v_ig:=jsonb_build_object(
      'applicable',false,
      'status','NOT_REQUIRED',
      'blocking_code',null,
      'decision','SKIP',
      'continuation_allowed',true,
      'binding_mode','DIRECT_PROFILE_CAPABILITY_NOT_INVOKED',
      'profile_task_intent',v_task_requirement->>'profile_task_intent',
      'input_governance_requirement',v_task_requirement->>'input_governance_requirement',
      'reason',v_task_requirement->>'reason'
    );
  ELSE
    SELECT EXISTS(
      SELECT 1
      FROM public.lf_activo_relaciones r
      WHERE r.codigo_activo=v_exec.target_code
        AND r.relacionado_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND r.relacion_tipo='GOBERNADO_POR'
    ) INTO v_direct_profile_ig;

    IF v_direct_profile_ig THEN
      IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))<>'PANTALLA' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_SCREEN_SCOPE_REQUIRED',
          'router_reentry_required',false
        );
      END IF;

      v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
        p_input_literal,
        p_handoff->'scope'
      );

      IF v_screen_request->>'status'<>'READY'
         OR coalesce((v_screen_request->>'candidate_screen_count')::integer,0)<=0 THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_NO_MATCH',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_NO_CANDIDATES',
          'screen_selection_request',v_screen_request,
          'router_reentry_required',false,
          'next_action','REFINE_OR_CLARIFY_SCREEN_SCOPE'
        );
      END IF;

      v_screen_result:=v_exec.manifest->'screen_selection_result';

      IF v_screen_result IS NULL OR jsonb_typeof(v_screen_result)<>'object' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_REQUIRED',
          'blocking_code',null,
          'execution_id',p_execution_id,
          'screen_selection_request',v_screen_request,
          'selection_mode','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'semantic_selection_required',true,
          'submit_entrypoint','public.lf_profile_screen_selector_semantic_submit_v1',
          'submit_raw_entrypoint','public.lf_profile_screen_selector_semantic_submit_raw_v1',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false,
          'next_action','RUN_SCREEN_SEMANTIC_SELECTION_AND_SUBMIT'
        );
      END IF;

      v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
        v_screen_request,v_screen_result
      );

      IF v_screen_validation->>'status'<>'VALID' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_RECEIPT_INVALID',
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false
        );
      END IF;

      IF v_screen_result->>'decision'='AMBIGUOUS' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_AMBIGUOUS',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_AMBIGUOUS',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result,
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false,
          'next_action','HUMAN_OR_CALLER_DECISION_REQUIRED'
        );
      ELSIF v_screen_result->>'decision'='NO_MATCH' THEN
        RETURN jsonb_build_object(
          'status','SCREEN_SELECTION_NO_MATCH',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_NO_MATCH',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result,
          'screen_selection_validation',v_screen_validation,
          'router_reentry_required',false,
          'next_action','REFINE_OR_CLARIFY_SCREEN_SCOPE'
        );
      ELSIF v_screen_result->>'decision'<>'SELECTED' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_SCREEN_SELECTION_DECISION_INVALID',
          'screen_selection_result',v_screen_result,
          'router_reentry_required',false
        );
      END IF;

      v_resolved_scope:=coalesce(p_handoff->'scope','{}'::jsonb)
        ||jsonb_build_object(
          'target_hint',v_screen_result->>'selected_screen_code',
          'resolution_status','RESOLVED',
          'resolved_screen_code',v_screen_result->>'selected_screen_code',
          'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC',
          'screen_selection_request',v_screen_request,
          'screen_selection_result',v_screen_result
        );

      v_ig:=programacion.fn_lf_profile_input_governance_resolve_v1(
        p_input_literal,
        v_exec.target_code,
        v_resolved_scope,
        'CONTEXT_PACK'
      );

      v_ig:=v_ig||jsonb_build_object(
        'screen_selection',jsonb_build_object(
          'request_sha256',v_screen_request->>'request_sha256',
          'catalog_sha256',v_screen_request->>'catalog_sha256',
          'decision',v_screen_result->>'decision',
          'selected_screen_code',v_screen_result->>'selected_screen_code',
          'semantic_receipt_sha256',v_screen_result->>'semantic_receipt_sha256'
        )
      );
    ELSE
      SELECT coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb)
        INTO v_adapters
      FROM public.v_lf_router_adapter_bindings x
      WHERE x.target_asset_code=v_exec.target_code;

      IF jsonb_array_length(v_adapters)>0 THEN
        v_ig:=programacion.fn_lf_profile_adapter_input_governance_resolve_v1(
          p_input_literal,v_adapters,'CONTEXT_PACK'
        );
      ELSE
        v_ig:=jsonb_build_object(
          'applicable',false,
          'status','NOT_REQUIRED',
          'blocking_code',null,
          'decision','N/A',
          'continuation_allowed',true,
          'required_by_adapters','[]'::jsonb,
          'binding_mode','NONE'
        );
      END IF;
    END IF;
  END IF;

  -- Scope validation and IG security clearance are distinct decisions.
  -- Read-only report work may continue with VERIFIED internal findings;
  -- downstream effects and any IG READY/production claim remain prohibited.
  IF v_task_requirement->>'status'='REQUIRED'
     AND v_exec.manifest->>'read_only'='true'
     AND v_exec.manifest->>'no_write'='true'
     AND v_exec.manifest->>'no_promotion'='true'
     AND v_exec.manifest->>'automatic_impact'='false'
     AND v_exec.manifest->>'governed_repair_write'='false'
     AND p_handoff#>>'{scope,target_type}'='PANTALLA'
     AND v_ig->>'applicable'='true'
     AND v_ig->>'status'='BLOCKED'
     AND v_ig->>'decision'='BLOCKED'
     AND v_ig->>'continuation_allowed'='false'
     AND v_ig->>'blocking_code'='BLOCK_PROFILE_INPUT_GOVERNANCE'
     AND v_ig->>'profile_code'=v_exec.target_code
     AND v_ig->>'consumer'='CONTEXT_PACK'
     AND v_ig->>'binding_mode'='DIRECT_PROFILE'
     AND v_ig->>'pantalla_id' ~ '^[1-9][0-9]*$'
     AND jsonb_typeof(v_ig->'governance_result')='object'
     AND v_ig#>>'{governance_result,status}'='BLOCKED'
     AND v_ig#>>'{governance_result,consumer}'='CONTEXT_PACK'
     AND v_ig#>>'{governance_result,pantalla_id}'=v_ig->>'pantalla_id'
     AND v_ig#>>'{governance_result,remediation_state}'='INTERNAL_REMEDIATION_REQUIRED'
     AND v_ig#>>'{governance_result,owner_interruption_required}'='false'
     AND v_ig#>>'{governance_result,promotion_authorized}'='false'
     AND v_ig#>>'{governance_result,production_authorized}'='false'
     AND v_ig#>>'{governance_result,execution_mode}'='REUSE_COMPLETED_CURRENT_RUN'
     AND v_ig#>>'{governance_result,run_id}' ~ '^[1-9][0-9]*$'
     AND coalesce(v_ig#>>'{governance_result,output_sha256}','') ~ '^[0-9a-f]{64}$'
     AND v_ig#>>'{governance_result,predecision_crosscheck,status}'='CANONICAL_READBACK_ONLY'
     AND v_ig#>>'{governance_result,predecision_crosscheck,run_id}'=v_ig#>>'{governance_result,run_id}'
     AND coalesce(v_ig#>>'{governance_result,predecision_crosscheck,deterministic_finding_count}','') ~ '^[1-9][0-9]*$'
  THEN
    RETURN jsonb_build_object(
      'status','READY',
      'blocking_code',null,
      'server_validated',true,
      'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
      'activation_trigger_match',true,
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
      'input_validation_only',true,
      'ig_security_state','BLOCKED',
      'ig_security_clearance',false,
      'ig_continuation_allowed',false,
      'production_authorized',false,
      'promotion_authorized',false,
      'mutation_authorized',false,
      'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT'),
      'input_governance',
        v_ig||jsonb_build_object(
          'analysis_scope','READ_ONLY_WITH_IG_FINDINGS',
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false
    );
  END IF;

  IF coalesce((v_ig->>'applicable')::boolean,false)
     AND coalesce((v_ig->>'continuation_allowed')::boolean,false) IS NOT TRUE THEN

    IF v_ig->>'status'='INPUT_GOVERNANCE_REQUIRED'
       AND v_ig->>'decision'='PENDING'
       AND v_ig->>'consumer'='CONTEXT_PACK'
       AND coalesce(v_ig->>'pantalla_id','') ~ '^[0-9]+$'
    THEN
      SELECT c.especificacion->>'runtime_orchestrator'
        INTO v_ig_runtime_orchestrator
      FROM programacion.contratos c
      JOIN programacion.versiones_agente v ON v.id=c.version_id
      JOIN programacion.agentes a ON a.id=v.agente_id
      WHERE a.agente_codigo='INPUT_GOVERNANCE_AGENT'
        AND c.contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT'
        AND c.estado='defined'
        AND c.fail_closed
        AND EXISTS(
          SELECT 1
          FROM jsonb_array_elements_text(c.especificacion->'allowed_consumers') x(v)
          WHERE x.v='CONTEXT_PACK'
        )
      ORDER BY c.version_id DESC
      LIMIT 1;

      v_ig_runtime_slug:=case
        when coalesce(v_ig_runtime_orchestrator,'') LIKE 'SUPABASE_EDGE_FUNCTION:%'
          then split_part(v_ig_runtime_orchestrator,':',2)
        else null
      end;

      IF nullif(v_ig_runtime_slug,'') IS NULL
         OR v_ig_runtime_slug !~ '^[a-z0-9][a-z0-9-]{0,62}$' THEN
        RETURN jsonb_build_object(
          'status','BLOCKED',
          'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_RUNTIME_ORCHESTRATOR_INVALID',
          'input_governance',v_ig,
          'router_reentry_required',false
        );
      END IF;

      RETURN jsonb_build_object(
        'status','INPUT_GOVERNANCE_RUNTIME_REQUIRED',
        'blocking_code',null,
        'execution_id',p_execution_id,
        'input_governance',
          v_ig||jsonb_build_object(
            'runtime_request',jsonb_build_object(
              'transport','DIRECT_EDGE_INVOCATION',
              'runtime_orchestrator',v_ig_runtime_orchestrator,
              'runtime_slug',v_ig_runtime_slug,
              'request_body',jsonb_build_object(
                'pantalla_id',(v_ig->>'pantalla_id')::integer,
                'consumer','CONTEXT_PACK'
              ),
              'terminal_statuses',jsonb_build_array(
                'READY','HUMAN_DECISION_REQUIRED','BLOCKED'
              ),
              'continuation_statuses',jsonb_build_array(
                'VALIDATOR_RESUME_REQUIRED'
              ),
              'continuation_action','REINVOKE_SAME_RUNTIME_IMMEDIATELY',
              'queue_required',false,
              'polling_required',false
            ),
            'dispatch_owner','INPUT_GOVERNANCE_INTERNAL_RUNTIME',
            'dispatch_transport','DIRECT_EDGE_INVOCATION',
            'resume_via','EJECUCION_PERFIL_LF/input_validate',
            'router_reentry_required',false
          ),
        'scope_authority_packet',v_scope->'scope_authority_packet',
        'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
        'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
        'router_reentry_required',false,
        'next_action','RUN_INPUT_GOVERNANCE_RUNTIME_AND_RETRY_SAME_NATIVE_BRIDGE_PREPARE'
      );
    END IF;

    RETURN jsonb_build_object(
      'status',coalesce(v_ig->>'status','BLOCKED'),
      'blocking_code',coalesce(v_ig->>'blocking_code','BLOCK_PROFILE_INPUT_GOVERNANCE_NOT_READY'),
      'input_governance',
        v_ig||jsonb_build_object(
          'resume_via','EJECUCION_PERFIL_LF/input_validate',
          'router_reentry_required',false
        ),
      'scope_authority_packet',v_scope->'scope_authority_packet',
      'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
      'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
      'router_reentry_required',false,
      'next_action','RETRY_INPUT_VALIDATE_AFTER_INPUT_GOVERNANCE'
    );
  END IF;

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'server_validated',true,
    'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
    'activation_trigger_match',true,
    'scope_authority_packet',v_scope->'scope_authority_packet',
    'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
    'input_governance',
      coalesce(v_ig,'{}'::jsonb)||jsonb_build_object(
        'resume_via','EJECUCION_PERFIL_LF/input_validate',
        'router_reentry_required',false
      ),
    'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
    'router_reentry_required',false
  );
END
$function$
;
