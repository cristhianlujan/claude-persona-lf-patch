BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_result_router_return_classify_v1(
  p_profile_output jsonb,
  p_original_request text,
  p_execution_id text,
  p_profile_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $function$
DECLARE
  v_output_type text:=upper(coalesce(p_profile_output->>'output_type',''));
  v_pipeline_action text:=upper(coalesce(p_profile_output->>'pipeline_action',''));
  v_verdict text:=upper(coalesce(p_profile_output->>'verdict',''));
  v_status text:=upper(coalesce(p_profile_output->>'status',''));
  v_self_verdict text:=upper(coalesce(p_profile_output->>'self_verdict',''));
  v_routing jsonb:=coalesce(p_profile_output->'routing','null'::jsonb);
  v_repair_execution jsonb:=coalesce(p_profile_output->'repair_execution','null'::jsonb);
  v_redirect_kind text;
  v_payload jsonb;
  v_stage1_literal text;
  v_untyped_unresolved boolean:=false;
BEGIN
  IF jsonb_typeof(p_profile_output)<>'object'
     OR nullif(btrim(coalesce(p_original_request,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL
     OR nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_ROUTER_RETURN_INPUT_INVALID'
    );
  END IF;

  IF p_profile_output ? 'target_profile'
     OR (
       jsonb_typeof(v_routing)='object'
       AND v_routing ? 'target_profile'
     )
     OR (
       jsonb_typeof(p_profile_output->'safe_next_gate')='object'
       AND (p_profile_output->'safe_next_gate') ? 'target_profile'
     )
     OR (
       jsonb_typeof(p_profile_output->'handoff_to_next')='object'
       AND (p_profile_output->'handoff_to_next') ? 'target_profile'
     )
  THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code
    );
  END IF;

  IF jsonb_typeof(v_repair_execution)='object'
     AND upper(coalesce(v_repair_execution->>'mode',''))='EXECUTED_WITH_READBACK'
  THEN
    IF p_profile_code<>'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
       OR coalesce((v_repair_execution->>'returned_to_router')::boolean,false) IS NOT TRUE
       OR coalesce((v_repair_execution->>'promotion_performed')::boolean,true) IS NOT FALSE
       OR nullif(btrim(coalesce(v_repair_execution->>'authority_ref','')),'') IS NULL
       OR jsonb_typeof(v_repair_execution->'changes')<>'array'
       OR jsonb_array_length(v_repair_execution->'changes')=0
       OR jsonb_typeof(v_repair_execution->'preserved_constraints')<>'array'
       OR jsonb_array_length(v_repair_execution->'preserved_constraints')=0
       OR jsonb_typeof(v_repair_execution->'readback_refs')<>'array'
       OR jsonb_array_length(v_repair_execution->'readback_refs')=0
       OR nullif(btrim(coalesce(v_repair_execution->>'rollback_ref','')),'') IS NULL
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_SRCR_EXECUTED_REPAIR_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='SYSTEMIC_REPAIR_EXECUTED_WITH_READBACK';
    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'profile_pack_id',p_profile_output->>'profile_pack_id',
      'repair_execution',v_repair_execution,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'next_gate',p_profile_output->'next_gate'
    );

  ELSIF v_output_type='PRODUCT_MISSING_INPUT_STATE' THEN
    IF jsonb_typeof(p_profile_output->'missing_fields')<>'array'
       OR jsonb_array_length(p_profile_output->'missing_fields')=0
       OR jsonb_typeof(p_profile_output->'why_required')<>'array'
       OR jsonb_array_length(p_profile_output->'why_required')=0
       OR jsonb_typeof(p_profile_output->'risk_if_assumed')<>'array'
       OR jsonb_array_length(p_profile_output->'risk_if_assumed')=0
       OR jsonb_typeof(p_profile_output->'safe_next_gate')<>'object'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_PRODUCT_MISSING_INPUT_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='PRODUCT_MISSING_INPUT_STATE';
    v_payload:=jsonb_build_object(
      'missing_fields',p_profile_output->'missing_fields',
      'why_required',p_profile_output->'why_required',
      'risk_if_assumed',p_profile_output->'risk_if_assumed',
      'safe_next_gate',p_profile_output->'safe_next_gate'
    );

  ELSIF v_output_type='FRONTEND_MISSING_INPUT_STATE'
        OR v_pipeline_action='RETURN_TO_ORCHESTRATOR' THEN

    IF v_pipeline_action<>'RETURN_TO_ORCHESTRATOR'
       OR nullif(btrim(coalesce(p_profile_output->>'question_to_orchestrator','')),'') IS NULL
       OR jsonb_typeof(p_profile_output->'missing_fields')<>'array'
       OR jsonb_array_length(p_profile_output->'missing_fields')=0
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_RETURN_TO_ORCHESTRATOR_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:=case
      when v_output_type<>'' then v_output_type
      else 'GENERIC_RETURN_TO_ORCHESTRATOR'
    end;

    v_payload:=jsonb_build_object(
      'missing_fields',p_profile_output->'missing_fields',
      'resolved_from_context',coalesce(p_profile_output->'resolved_from_context','[]'::jsonb),
      'conflicts_detected',coalesce(p_profile_output->'conflicts_detected','[]'::jsonb),
      'why_required',coalesce(p_profile_output->'why_required','[]'::jsonb),
      'risk_if_assumed',coalesce(p_profile_output->'risk_if_assumed','[]'::jsonb),
      'resolution_target',p_profile_output->>'resolution_target',
      'question_to_orchestrator',p_profile_output->>'question_to_orchestrator'
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action',''))='RETURN_TO_ORCHESTRATOR' THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR upper(coalesce(v_routing->>'resolution_target','')) NOT IN (
         'PRODUCER_REPAIR',
         'AUTHORITY_OR_CONTEXT_RESOLUTION'
       )
       OR v_verdict NOT IN (
         'RETURN_TO_WORKER_FOR_SELF_REPAIR',
         'RETURN_TO_ORCHESTRATOR'
       )
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_QUALITY_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

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

  IF v_redirect_kind IS NOT NULL THEN
    v_stage1_literal:=
      'Solicitud original: '||p_original_request
      ||E'\n\nRetorno gobernado del perfil '
      ||p_profile_code
      ||': '
      ||v_payload::text;

    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','RETURN_TO_ROUTER',
      'code','PROFILE_RESULT_TYPED_RETURN_TO_ORCHESTRATOR',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code,
      'redirect_kind',v_redirect_kind,
      'router_return_request',jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_REQUEST_V1',
        'pipeline_action','RETURN_TO_ORCHESTRATOR',
        'route_policy','REPEAT_FULL_ROUTER_FLOW',
        'next_entrypoint','ACT-0001_STAGE1',
        'stage1_required',true,
        'reuse_prior_profile_selection',false,
        'prior_profile_is_advisory_only',true,
        'direct_profile_invocation_allowed',false,
        'original_request',p_original_request,
        'stage1_literal',v_stage1_literal,
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code,
        'unresolved_contract_type',v_redirect_kind,
        'unresolved_payload',v_payload,
        'advisory_profiles',coalesce(
          p_profile_output#>'{deliverable_created,profiles_to_activate}',
          '[]'::jsonb
        )
      ),
      'next_action','REENTER_ROUTER_STAGE1'
    );
  END IF;

  v_untyped_unresolved:=
       v_self_verdict IN ('NEEDS_INPUT','NEEDS_ADJUSTMENT','BLOCKED')
    OR v_status IN ('NEEDS_INPUT','BLOCKED','NEEDS_REPAIR')
    OR coalesce((p_profile_output->>'blocked')::boolean,false) IS TRUE
    OR (
      jsonb_typeof(p_profile_output->'missing_inputs')='array'
      AND jsonb_array_length(p_profile_output->'missing_inputs')>0
    )
    OR nullif(btrim(coalesce(p_profile_output->>'blocking_reason','')),'') IS NOT NULL;

  IF v_untyped_unresolved THEN
    RETURN jsonb_build_object(
      'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
      'status','BLOCKED',
      'code','PROFILE_RESULT_UNTYPED_ROUTING_SIGNAL',
      'source_execution_id',p_execution_id,
      'source_profile_code',p_profile_code,
      'next_action','FIX_PROFILE_ROUTING_CONTRACT'
    );
  END IF;

  RETURN jsonb_build_object(
    'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
    'status','COMPLETE',
    'code','PROFILE_RESULT_NO_ROUTER_RETURN_REQUIRED',
    'source_execution_id',p_execution_id,
    'source_profile_code',p_profile_code,
    'next_action','EMIT_PROFILE_RESULT'
  );
END
$function$;

COMMENT ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text) IS
'Classifies typed post-profile routing signals. Completed SRCR governed repairs with readback must return through ACT-0001 Stage1; direct target_profile remains forbidden.';

DO $postcheck$
DECLARE
  v_repair jsonb;
  v_bad_repair jsonb;
  v_complete jsonb;
BEGIN
  v_repair:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'worker','systemic_root_cause_repair_lf',
      'status','SYSTEMIC_REPAIR_SPEC',
      'profile_pack_id','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_6',
      'repair_execution',jsonb_build_object(
        'mode','EXECUTED_WITH_READBACK',
        'authority_ref','router-repair-authority://SYNTH',
        'changes',jsonb_build_array(jsonb_build_object(
          'target_ref','supabase://lf_ops/pantalla_elementos/B2B_CARGA002_CANCEL_ACTION',
          'change_type','MODIFY',
          'before_ref','evidence://before',
          'after_ref','evidence://after'
        )),
        'preserved_constraints',jsonb_build_array(
          'B2B_LOAD_CANCEL',
          'transitions:15,16',
          'requires_comment=true'
        ),
        'readback_refs',jsonb_build_array('evidence://after'),
        'rollback_ref','evidence://rollback',
        'returned_to_router',true,
        'promotion_performed',false
      )
    ),
    'Actualizar cancelación B2B-CARGA-002.',
    'EXEC-SYNTH-SRCR-RETURN',
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
  );

  IF v_repair->>'status'<>'RETURN_TO_ROUTER'
     OR v_repair->>'next_action'<>'REENTER_ROUTER_STAGE1'
     OR v_repair->>'redirect_kind'<>'SYSTEMIC_REPAIR_EXECUTED_WITH_READBACK'
     OR v_repair#>>'{router_return_request,next_entrypoint}'<>'ACT-0001_STAGE1'
     OR coalesce(
          (v_repair#>>'{router_return_request,reuse_prior_profile_selection}')::boolean,
          true
        ) IS NOT FALSE
     OR coalesce(
          (v_repair#>>'{router_return_request,direct_profile_invocation_allowed}')::boolean,
          true
        ) IS NOT FALSE
  THEN
    RAISE EXCEPTION 'SRCR_EXECUTED_REPAIR_RETURN_POSTCHECK_FAILED:%',
      left(v_repair::text,2200);
  END IF;

  v_bad_repair:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','SYSTEMIC_REPAIR_SPEC',
      'repair_execution',jsonb_build_object(
        'mode','EXECUTED_WITH_READBACK',
        'authority_ref','router-repair-authority://SYNTH',
        'changes','[]'::jsonb,
        'preserved_constraints',jsonb_build_array('x'),
        'readback_refs',jsonb_build_array('evidence://after'),
        'rollback_ref','evidence://rollback',
        'returned_to_router',true,
        'promotion_performed',false
      )
    ),
    'Actualizar cancelación B2B-CARGA-002.',
    'EXEC-SYNTH-SRCR-BAD',
    'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
  );

  IF v_bad_repair->>'status'<>'BLOCKED'
     OR v_bad_repair->>'code'<>'PROFILE_RESULT_SRCR_EXECUTED_REPAIR_CONTRACT_INVALID'
  THEN
    RAISE EXCEPTION 'SRCR_EXECUTED_REPAIR_INVALID_FALSE_PASS:%',
      left(v_bad_repair::text,1600);
  END IF;

  v_complete:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'worker','product_director_lf',
      'output_type','PRODUCT_DIRECTION_SPEC',
      'self_verdict','PASS'
    ),
    'Dame las reglas.',
    'EXEC-SYNTH-COMPLETE',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF v_complete->>'status'<>'COMPLETE'
     OR v_complete->>'next_action'<>'EMIT_PROFILE_RESULT'
  THEN
    RAISE EXCEPTION 'PROFILE_COMPLETE_REGRESSION:%',
      left(v_complete::text,1400);
  END IF;
END
$postcheck$;

COMMIT;
