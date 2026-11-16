-- Exact live source snapshots from Supabase SELECT, E9 prepatch.
CREATE OR REPLACE FUNCTION public.lf_router_profile_execution_handoff_v1(p_request jsonb, p_result jsonb, p_channel text, p_business text, p_scope jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_validation jsonb;
  v_binding jsonb;
  v_profile text;
  v_slug text;
  v_router_md5 text;
  v_operation_revision text;
  v_auth_core jsonb;
  v_auth_fp text;
  v_auth_receipt jsonb;
  v_body jsonb;
  v_fp text;
  v_task_intent text;
  v_repair_write_allowed boolean:=false;
  v_repair_core jsonb;
  v_repair_fp text;
  v_repair_authority jsonb;
BEGIN
  IF upper(coalesce(p_channel,'')) NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
     OR upper(coalesce(p_business,'')) <> 'LF' THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_CHANNEL_OR_BUSINESS_INVALID',
      'downstream_execution_allowed',false
    );
  END IF;

  v_validation:=public.lf_router_semantic_resume_validate_v1(
    p_request,p_result
  );

  IF v_validation->>'status' IS DISTINCT FROM 'VALID'
     OR coalesce((v_validation->>'router_resume_allowed')::boolean,false) IS NOT TRUE
     OR p_result->>'decision' IS DISTINCT FROM 'RESOLVED'
     OR jsonb_array_length(coalesce(p_result->'positive_target_refs','[]'::jsonb))<>1
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_GATE2_INVALID',
      'resume_validation',v_validation,
      'downstream_execution_allowed',false
    );
  END IF;

  v_profile:=p_result#>>'{positive_target_refs,0}';

  v_binding:=public.lf_router_semantic_action_binding_validate_v1(
    p_request,
    v_profile,
    'PERFIL'
  );

  IF coalesce((v_binding->>'valid')::boolean,false) IS NOT TRUE
     OR v_binding->>'candidate_action_code' IS DISTINCT FROM 'PROFILE_EXECUTION'
     OR v_binding->>'operation_code' IS DISTINCT FROM 'EJECUCION_PERFIL_LF'
  THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_ACTION_BINDING_INVALID',
      'binding_validation',v_binding,
      'downstream_execution_allowed',false
    );
  END IF;

  v_task_intent:=upper(coalesce(
    p_request#>>'{router_action_binding,profile_task_intent}',
    ''
  ));

  v_repair_write_allowed:=
    v_profile=public.lf_router_repair_profile_code_v1()
    AND v_task_intent='REPAIR_MISSING_PRODUCT_STRUCTURE';

  SELECT a.metadata->>'profile_slug'
    INTO v_slug
  FROM public.lf_activos a
  JOIN public.lf_profile_selection_registry_v1 r
    ON r.profile_code=a.codigo_activo
   AND r.descriptor_status='CURRENT'
  WHERE a.codigo_activo=v_profile
    AND a.tipo_activo='PERFIL'
    AND a.archived_at IS NULL
    AND nullif(a.metadata->>'canonical_profile_key','') IS NOT NULL
  LIMIT 1;

  IF nullif(v_profile,'') IS NULL OR nullif(v_slug,'') IS NULL THEN
    RETURN jsonb_build_object(
      'status','BLOCKED',
      'blocking_code','BLOCK_PROFILE_HANDOFF_PROFILE_BINDING_UNRESOLVED',
      'downstream_execution_allowed',false
    );
  END IF;

  v_router_md5:=md5(pg_get_functiondef(
    'public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure
  ));

  v_operation_revision:=
    public.lf_operation_revision_sha256_v1('EJECUCION_PERFIL_LF');

  v_auth_core:=jsonb_build_object(
    'schema_version','LF_ROUTER_PROFILE_AUTHORIZATION_RECEIPT_V1',
    'router','ACT-0001',
    'authority_ref','ROUTER_PROFILE_EXECUTION_AUTHORIZATION',
    'source','ACT-0001_PRE_SEMANTIC_BINDING_PLUS_GATE2',
    'request_sha256',p_request->>'request_sha256',
    'profile_code',v_profile,
    'asset_type','PERFIL',
    'action_code',v_binding->>'candidate_action_code',
    'operation_code',v_binding->>'operation_code',
    'router_action_binding_sha256',v_binding->>'binding_sha256',
    'gate2_semantic_receipt_sha256',p_result->>'semantic_receipt_sha256',
    'router_source_md5',v_router_md5,
    'operation_revision_sha256',v_operation_revision,
    'channel',upper(p_channel),
    'business',upper(p_business),
    'scope',p_scope,
    'profile_execution_allowed',true,
    'effect_authority',false,
    'router_reentry_before_execution',false,
    'issued_at',to_char(
      clock_timestamp() at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )
  );

  v_auth_fp:=encode(
    extensions.digest(convert_to(v_auth_core::text,'UTF8'),'sha256'),
    'hex'
  );
  v_auth_receipt:=v_auth_core||jsonb_build_object(
    'fingerprint_sha256',v_auth_fp
  );

  IF v_repair_write_allowed THEN
    v_repair_core:=jsonb_build_object(
      'schema_version','LF_SRCR_REPAIR_EXECUTION_AUTHORITY_V1',
      'mode','GOVERNED_REPAIR_WRITE',
      'profile_code',v_profile,
      'profile_task_intent',v_task_intent,
      'operation_code','EJECUCION_PERFIL_LF',
      'request_sha256',p_request->>'request_sha256',
      'router_action_binding_sha256',v_binding->>'binding_sha256',
      'router_authorization_fingerprint_sha256',v_auth_fp,
      'scope',p_scope,
      'readback_required',true,
      'rollback_required',true,
      'promotion_allowed',false,
      'automatic_impact',false,
      'direct_profile_invocation_allowed',false,
      'return_to_router_after_result',true,
      'issued_at',to_char(
        clock_timestamp() at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
      )
    );
    v_repair_fp:=encode(
      extensions.digest(convert_to(v_repair_core::text,'UTF8'),'sha256'),
      'hex'
    );
    v_repair_authority:=v_repair_core||jsonb_build_object(
      'fingerprint_sha256',v_repair_fp
    );
  ELSE
    v_repair_authority:=NULL;
  END IF;

  v_body:=jsonb_build_object(
    'schema_version','LF_ROUTER_PROFILE_EXECUTION_HANDOFF_V1',
    'router','ACT-0001',
    'channel',upper(p_channel),
    'business',upper(p_business),
    'scope',p_scope,
    'literal_request',p_request->>'literal_request',
    'request_sha256',p_request->>'request_sha256',
    'profile_code',v_profile,
    'profile_slug',v_slug,
    'operation_code','EJECUCION_PERFIL_LF',
    'semantic_request',p_request,
    'semantic_result',p_result,
    'router_authorization_receipt',v_auth_receipt,
    'repair_execution_authority',v_repair_authority,
    'router_source_md5',v_router_md5,
    'operation_revision_sha256',v_operation_revision,
    'profile_execution_allowed',true,
    'effect_authority',false,
    'reenter_router_before_execution',false,
    'return_to_router_after_profile_result',true,
    'issued_at',to_char(
      clock_timestamp() at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    )
  );

  v_fp:=encode(
    extensions.digest(convert_to(v_body::text,'UTF8'),'sha256'),
    'hex'
  );

  RETURN jsonb_build_object(
    'status','READY',
    'blocking_code',null,
    'handoff',v_body||jsonb_build_object('fingerprint_sha256',v_fp),
    'downstream_execution_allowed',true,
    'router_reentered',false,
    'governed_repair_write_allowed',v_repair_write_allowed
  );
END
$function$
;
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
$function$
;
