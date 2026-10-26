-- ACT-0001: positive profile continuations must return through the Router/Orchestrator.
-- CONTINUE and CONTINUE_WITH_RESTRICTIONS are not terminal when routing declares
-- a non-NONE resolution_target. No direct target_profile is introduced.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
     )) <> 'c0fe5786ef96ac7d475a5e45fa6c747f' THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUE_SOURCE_DRIFT';
  END IF;
END
$precheck$;

DO $patch$
DECLARE
  d text;
  old_block text;
  new_block text;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
  );

  old_block:=$old$
    v_redirect_kind:='QUALITY_ROUTING_REDIRECT';
    v_payload:=jsonb_build_object(
      'verdict',v_verdict,
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate'
    );
  END IF;
$old$;

  new_block:=$new$
    v_redirect_kind:='QUALITY_ROUTING_REDIRECT';
    v_payload:=jsonb_build_object(
      'verdict',v_verdict,
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate'
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action','')) IN (
          'CONTINUE',
          'CONTINUE_WITH_RESTRICTIONS'
        ) THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR nullif(btrim(coalesce(v_routing->>'resolution_target','')),'') IS NULL
       OR upper(coalesce(v_routing->>'resolution_target',''))='NONE'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_CONTINUE_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:=case
      when upper(v_routing->>'pipeline_action')='CONTINUE_WITH_RESTRICTIONS'
        then 'PROFILE_CONTINUE_WITH_RESTRICTIONS'
      else 'PROFILE_CONTINUE'
    end;

    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'verdict',p_profile_output->>'verdict',
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate'
    );
  END IF;
$new$;

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUE_PATCH_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_block,new_block);
  EXECUTE d;
END
$patch$;

COMMENT ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text) IS
'Classifies typed post-profile routing signals. RETURN_TO_ORCHESTRATOR and positive CONTINUE/CONTINUE_WITH_RESTRICTIONS transitions return through ACT-0001 Stage1; direct target_profile remains forbidden. A positive continuation is terminal only when no governed downstream target is declared.';

DO $postcheck$
DECLARE
  x jsonb;
BEGIN
  -- Exact regression from the idle-timeout test:
  -- Evidence Lineage PASS_WITH_RESTRICTIONS must continue to the Router.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'claim','Current state proven; downstream quality review required.',
      'blocking_codes',jsonb_build_array('NO_CURRENT_AUTHORITY_FOR_1200_SECONDS'),
      'next_gate','QUALITY_PACK',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Analiza el timeout B2B sin modificar nada.',
    'POSTCHECK-EVIDENCE-CONTINUE-1',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF x->>'status' IS DISTINCT FROM 'RETURN_TO_ROUTER'
     OR x->>'redirect_kind' IS DISTINCT FROM 'PROFILE_CONTINUE_WITH_RESTRICTIONS'
     OR x->>'next_action' IS DISTINCT FROM 'REENTER_ROUTER_STAGE1'
     OR x#>>'{router_return_request,next_entrypoint}' IS DISTINCT FROM 'ACT-0001_STAGE1'
     OR x#>>'{router_return_request,unresolved_payload,routing,resolution_target}' IS DISTINCT FROM 'QUALITY_PACK'
     OR x#>>'{router_return_request,unresolved_payload,routing,pipeline_action}' IS DISTINCT FROM 'CONTINUE_WITH_RESTRICTIONS'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUE_RESTRICTIONS_REGRESSION:%',x;
  END IF;

  -- Plain CONTINUE also returns through the Router; it is not COMPLETE.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_EVIDENCE_LINEAGE',
      'next_gate','QUALITY_PACK',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Revisar evidencia.',
    'POSTCHECK-EVIDENCE-CONTINUE-2',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF x->>'status' IS DISTINCT FROM 'RETURN_TO_ROUTER'
     OR x->>'redirect_kind' IS DISTINCT FROM 'PROFILE_CONTINUE'
     OR x#>>'{router_return_request,unresolved_payload,routing,resolution_target}' IS DISTINCT FROM 'QUALITY_PACK'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUE_REGRESSION:%',x;
  END IF;

  -- Positive continuation cannot bypass the Orchestrator.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'routing',jsonb_build_object(
        'activation_path','DIRECT',
        'via','DIRECT',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Test invalid direct continuation.',
    'POSTCHECK-CONTINUE-DIRECT-NEG',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF x->>'status' IS DISTINCT FROM 'BLOCKED'
     OR x->>'code' IS DISTINCT FROM 'PROFILE_RESULT_CONTINUE_ROUTING_CONTRACT_INVALID'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUE_DIRECT_BYPASS_NOT_BLOCKED:%',x;
  END IF;

  -- A positive action without a downstream target is malformed, not an implicit target.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','NONE'
      )
    ),
    'Test missing continuation target.',
    'POSTCHECK-CONTINUE-NONE-NEG',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF x->>'status' IS DISTINCT FROM 'BLOCKED'
     OR x->>'code' IS DISTINCT FROM 'PROFILE_RESULT_CONTINUE_ROUTING_CONTRACT_INVALID'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUE_NONE_TARGET_NOT_BLOCKED:%',x;
  END IF;

  -- Existing negative/repair return semantics must remain unchanged.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'verdict','RETURN_TO_ORCHESTRATOR',
      'blocking_codes',jsonb_build_array('AUTHORITY_REQUIRED'),
      'repair_actions','[]'::jsonb,
      'remaining_risks','[]'::jsonb,
      'next_gate','AUTHORITY_OR_CONTEXT_RESOLUTION',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','RETURN_TO_ORCHESTRATOR',
        'resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'
      )
    ),
    'Resolve authority.',
    'POSTCHECK-EXISTING-RETURN-1',
    'PERFIL-QUALITY-PACK'
  );

  IF x->>'status' IS DISTINCT FROM 'RETURN_TO_ROUTER'
     OR x->>'redirect_kind' IS DISTINCT FROM 'QUALITY_ROUTING_REDIRECT'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_EXISTING_RETURN_REGRESSION:%',x;
  END IF;

  -- A truly terminal profile output with no routing signal remains terminal.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS',
      'self_verdict','PASS',
      'output_type','PRODUCT_DIRECTION_SPEC'
    ),
    'Emit final decision.',
    'POSTCHECK-TERMINAL-1',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF x->>'status' IS DISTINCT FROM 'COMPLETE'
     OR x->>'code' IS DISTINCT FROM 'PROFILE_RESULT_NO_ROUTER_RETURN_REQUIRED'
     OR x->>'next_action' IS DISTINCT FROM 'EMIT_PROFILE_RESULT'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_TERMINAL_COMPLETE_REGRESSION:%',x;
  END IF;
END
$postcheck$;

COMMIT;
