-- ACT-0001: positive profile continuations must return through the Router.
-- No profile may invoke the next profile directly. The upstream artifact is preserved
-- so the fresh Stage1 pass can select the next governed capability semantically.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
     )) <> 'c0fe5786ef96ac7d475a5e45fa6c747f' THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_SOURCE_DRIFT';
  END IF;
END
$precheck$;

DO $patch$
DECLARE
  d text;
  needle text;
  replacement text;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
  );

  needle:=$needle$
      'next_gate',p_profile_output->>'next_gate'
    );
  END IF;

  IF v_redirect_kind IS NOT NULL THEN
$needle$;

  replacement:=$replacement$
      'next_gate',p_profile_output->>'next_gate'
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action','')) IN (
          'CONTINUE',
          'CONTINUE_WITH_RESTRICTIONS'
        ) THEN

    IF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
       OR upper(coalesce(v_routing->>'activation_path','')) NOT IN (
         'DIRECT',
         'ROUTER'
       )
       OR nullif(btrim(coalesce(v_routing->>'resolution_target','')),'') IS NULL
       OR upper(coalesce(v_routing->>'resolution_target',''))='NONE'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED',
        'code','PROFILE_RESULT_CONTINUATION_ROUTING_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    v_redirect_kind:='PROFILE_CONTINUATION_ROUTING';
    v_payload:=jsonb_build_object(
      'profile_status',nullif(v_status,''),
      'profile_verdict',nullif(v_verdict,''),
      'profile_output_type',nullif(v_output_type,''),
      'routing',v_routing,
      'next_gate',p_profile_output->'next_gate',
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'upstream_profile_output',p_profile_output
    );
  END IF;

  IF v_redirect_kind IS NOT NULL THEN
$replacement$;

  IF (length(d)-length(replace(d,needle,'')))/length(needle)<>1 THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_PATCH_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,needle,replacement);
  EXECUTE d;
END
$patch$;

COMMENT ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text) IS
'Classifies typed post-profile routing signals. RETURN_TO_ORCHESTRATOR and positive CONTINUE/CONTINUE_WITH_RESTRICTIONS routes return through a fresh ACT-0001 Stage1 pass. Positive continuations preserve the upstream profile output for the next governed selection. Direct target_profile remains forbidden.';

COMMENT ON FUNCTION public.lf_profile_result_router_return_prepare_v1(text) IS
'At terminal profile completion, converts typed post-profile redirects, including positive CONTINUE/CONTINUE_WITH_RESTRICTIONS routing, into a request for a fresh ACT-0001 Stage1 pass. It never honors a direct target_profile.';

COMMENT ON FUNCTION public.lf_profile_execution_attach_terminal_authority_receipt_v1(text,text) IS
'Attaches terminal authority and the post-profile routing decision. Typed unresolved redirects and positive continuations return through ACT-0001 Stage1; no profile is invoked directly.';

DO $postcheck$
DECLARE
  v_continue_restricted jsonb;
  v_continue jsonb;
  v_bad jsonb;
  v_terminal jsonb;
  v_direct jsonb;
  v_existing_return jsonb;
  v_src text;
BEGIN
  v_continue_restricted:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'claim','Current value is evidenced; downstream quality review is required.',
      'authority_reads',jsonb_build_array(
        jsonb_build_object('source_ref','supabase://lf_ops.politicas_sesion/1')
      ),
      'source_readbacks',jsonb_build_array(
        jsonb_build_object('source_ref','supabase://lf_ops.politicas_sesion/1')
      ),
      'revision_binding',jsonb_build_object('mode','CURRENT_DIRECT_READ'),
      'structural_identifier_reconciliation',jsonb_build_object('reconciled',true),
      'evidence_map',jsonb_build_array(
        jsonb_build_object('assertion','900 is current','verdict','SUPPORTED')
      ),
      'blocking_codes',jsonb_build_array('NO_CURRENT_AUTHORITY_FOR_1200_SECONDS'),
      'next_gate','QUALITY_REVIEW',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Analiza el timeout B2B sin modificar nada.',
    'EXEC-SYNTH-CONTINUE-RESTRICTED',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF v_continue_restricted->>'status'<>'RETURN_TO_ROUTER'
     OR v_continue_restricted->>'redirect_kind'<>'PROFILE_CONTINUATION_ROUTING'
     OR v_continue_restricted->>'next_action'<>'REENTER_ROUTER_STAGE1'
     OR v_continue_restricted#>>'{router_return_request,route_policy}'<>'REPEAT_FULL_ROUTER_FLOW'
     OR v_continue_restricted#>>'{router_return_request,next_entrypoint}'<>'ACT-0001_STAGE1'
     OR coalesce(
          (v_continue_restricted#>>'{router_return_request,direct_profile_invocation_allowed}')::boolean,
          true
        )
     OR v_continue_restricted#>>'{router_return_request,unresolved_payload,routing,resolution_target}'
          <>'QUALITY_PACK'
     OR v_continue_restricted#>>'{router_return_request,unresolved_payload,upstream_profile_output,status}'
          <>'PASS_WITH_RESTRICTIONS'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_RESTRICTED_FAILED:%',
      left(v_continue_restricted::text,2200);
  END IF;

  v_continue:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_EVIDENCE_LINEAGE',
      'claim','Evidence lineage is complete.',
      'routing',jsonb_build_object(
        'activation_path','DIRECT',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE',
        'resolution_target','QUALITY_PACK'
      ),
      'next_gate','QUALITY_REVIEW'
    ),
    'Revisa evidencia.',
    'EXEC-SYNTH-CONTINUE',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF v_continue->>'status'<>'RETURN_TO_ROUTER'
     OR v_continue#>>'{router_return_request,unresolved_payload,routing,pipeline_action}'
          <>'CONTINUE'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_FAILED:%',
      left(v_continue::text,1800);
  END IF;

  v_bad:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','PROFILE',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Revisa evidencia.',
    'EXEC-SYNTH-CONTINUE-BAD',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF v_bad->>'status'<>'BLOCKED'
     OR v_bad->>'code'<>'PROFILE_RESULT_CONTINUATION_ROUTING_CONTRACT_INVALID'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_BAD_ROUTE_FALSE_PASS:%',
      left(v_bad::text,1600);
  END IF;

  v_direct:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'target_profile','PERFIL-QUALITY-PACK',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Revisa evidencia.',
    'EXEC-SYNTH-CONTINUE-DIRECT',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF v_direct->>'status'<>'BLOCKED'
     OR v_direct->>'code'<>'PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_DIRECT_TARGET_FALSE_PASS:%',
      left(v_direct::text,1600);
  END IF;

  v_existing_return:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'review_id','Q-SYNTH',
      'reviewed_artifact','artifact://synthetic',
      'verdict','RETURN_TO_ORCHESTRATOR',
      'blocking_codes',jsonb_build_array('MISSING_CURRENT_AUTHORITY'),
      'repair_actions','[]'::jsonb,
      'remaining_risks','[]'::jsonb,
      'next_gate','AUTHORITY_RESOLUTION',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','RETURN_TO_ORCHESTRATOR',
        'resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'
      )
    ),
    'Revisa el entregable.',
    'EXEC-SYNTH-EXISTING-RETURN',
    'PERFIL-QUALITY-PACK'
  );

  IF v_existing_return->>'status'<>'RETURN_TO_ROUTER'
     OR v_existing_return->>'redirect_kind'<>'QUALITY_ROUTING_REDIRECT'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_EXISTING_RETURN_REGRESSION:%',
      left(v_existing_return::text,1800);
  END IF;

  v_terminal:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'worker','product_director_lf',
      'output_type','PRODUCT_DIRECTION_SPEC',
      'self_verdict','PASS',
      'deliverable_created',jsonb_build_object(
        'profiles_to_activate','[]'::jsonb
      ),
      'handoff_to_next',jsonb_build_object(
        'target','ORCHESTRATOR'
      )
    ),
    'Analiza y responde.',
    'EXEC-SYNTH-TERMINAL',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF v_terminal->>'status'<>'COMPLETE'
     OR v_terminal->>'next_action'<>'EMIT_PROFILE_RESULT'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_TERMINAL_REGRESSION:%',
      left(v_terminal::text,1600);
  END IF;

  v_src:=pg_get_functiondef(
    'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
  );

  IF strpos(v_src,'''QUALITY_PACK''')>0
     OR strpos(v_src,'''COMPOSER''')>0
     OR strpos(v_src,'direct_profile_invocation_allowed' )=0
     OR strpos(v_src,'PROFILE_CONTINUATION_ROUTING')=0
     OR strpos(v_src,'upstream_profile_output')=0
  THEN
    RAISE EXCEPTION 'LF_PROFILE_POSITIVE_CONTINUATION_HARDCODE_OR_CONTRACT_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
