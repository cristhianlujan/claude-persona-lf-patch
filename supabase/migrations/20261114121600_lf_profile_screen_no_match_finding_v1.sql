-- LF E2E Issue #3871: no-match is a read-only finding, not owner interruption.
-- Existing canonical semantic selector still validates catalog and receipt.
-- No pass on invalid/ambiguous/untrusted selection; no production promotion.
BEGIN;
DO $preflight$
BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_execution_input_validate_v1(text,text,text,jsonb)'::regprocedure)) <> '0c5314787a62e2996cb3e6794352d3ac'
 THEN RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_execution_input_validate_v1'; END IF;
END $preflight$;
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



  v_screen_request jsonb;
  v_screen_result jsonb;
  v_screen_validation jsonb;
  v_resolved_scope jsonb;


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

  -- Step40 validates scope and semantic screen; skill applicability belongs to
  -- the profile's live skill policy, NEVER to Router task binding metadata.
  IF upper(coalesce(p_handoff#>>'{scope,target_type}',''))='PANTALLA' THEN
      v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
        p_input_literal,
        p_handoff->'scope'
      );

      IF v_screen_request->>'status'<>'READY'
         OR coalesce((v_screen_request->>'candidate_screen_count')::integer,0)<=0 THEN
        v_resolved_scope:=coalesce(p_handoff->'scope','{}'::jsonb)
          || jsonb_build_object(
            'resolution_status','NO_MATCH',
            'resolved_screen_code',null,
            'resolution_method','GOVERNED_SEMANTIC_NO_MATCH_FINDING',
            'screen_selection_findings',jsonb_build_array(
               jsonb_build_object('code','SCREEN_CATALOG_NO_CANDIDATES',
                  'evidence',v_screen_request,'owner_decision_required',false,
                  'production_authorized',false))
          );
        RETURN jsonb_build_object(
          'status','READY','blocking_code',null,'server_validated',true,
          'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
          'activation_trigger_match',true,
          'scope_authority_packet',v_scope->'scope_authority_packet',
          'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
          'resolved_scope',v_resolved_scope,
          'screen_selection_findings',v_resolved_scope->'screen_selection_findings',
          'analysis_scope','READ_ONLY_WITH_SCREEN_FINDINGS',
          'production_authorized',false,'promotion_authorized',false,
          'mutation_authorized',false,
          'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT'),
          'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
          'router_reentry_required',false
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
        v_resolved_scope:=coalesce(p_handoff->'scope','{}'::jsonb)
          || jsonb_build_object(
            'resolution_status','NO_MATCH',
            'resolved_screen_code',null,
            'resolution_method','GOVERNED_SEMANTIC_NO_MATCH_FINDING',
            'screen_selection_findings',jsonb_build_array(
               jsonb_build_object('code','SCREEN_SEMANTIC_NO_MATCH',
                  'evidence',v_screen_result,'owner_decision_required',false,
                  'production_authorized',false))
          );
        RETURN jsonb_build_object(
          'status','READY','blocking_code',null,'server_validated',true,
          'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
          'activation_trigger_match',true,
          'scope_authority_packet',v_scope->'scope_authority_packet',
          'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
          'resolved_scope',v_resolved_scope,
          'screen_selection_findings',v_resolved_scope->'screen_selection_findings',
          'analysis_scope','READ_ONLY_WITH_SCREEN_FINDINGS',
          'production_authorized',false,'promotion_authorized',false,
          'mutation_authorized',false,
          'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT'),
          'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
          'router_reentry_required',false
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

  END IF;
  RETURN jsonb_build_object(
     'status','READY','blocking_code',null,'server_validated',true,
     'input_scope','ROUTER_AUTHORIZED_PROFILE_EXECUTION',
     'activation_trigger_match',true,
     'scope_authority_packet',v_scope->'scope_authority_packet',
     'scope_authority_packet_sha256',v_scope->>'scope_packet_sha256',
     'resolved_scope',coalesce(v_resolved_scope,p_handoff->'scope','{}'::jsonb),
     'analysis_scope','READ_ONLY_PROFILE_VALIDATION',
     'production_authorized',false,'promotion_authorized',false,
     'mutation_authorized',false,
     'allowed_actions',jsonb_build_array('ANALYZE','PROPOSE','VALIDATE','REPORT'),
     'router_handoff_fingerprint',p_handoff->>'fingerprint_sha256',
     'router_reentry_required',false
  );
END
$function$;

COMMIT;
