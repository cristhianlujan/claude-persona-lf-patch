-- LF Input Governance / specialist feedback: sandbox candidate ONLY.
-- Not a production migration. When tested in a governed DB transaction,
-- BEGIN/ROLLBACK leave the live function unchanged. Does not write IG.
-- Binds critique to the existing run+family+source SHA (no hard-coded family),
-- uses existing ACT-0001 post-profile RETURN_TO_ROUTER, never creates IG run.
BEGIN;

DO $patch$
DECLARE
  d text;
  old_decl text:=$old$  v_untyped_unresolved boolean:=false;$old$;
  new_decl text:=$new$  v_untyped_unresolved boolean:=false;
  v_ig_feedback jsonb:=p_profile_output#>'{deliverable_created,input_governance_feedback}';
  v_ig_feedback_kind text;
  v_ig_feedback_bound boolean:=false;$new$;
  old_anchor text:=$old$  IF jsonb_typeof(v_repair_execution)='object'$old$;
  new_anchor text:=$new$  -- Optional specialist feedback is ADVISORY. It never mutates IG,
  -- re-runs Curator/Validator or confers authority to publish a rule.
  IF v_ig_feedback IS NOT NULL THEN
    v_ig_feedback_kind:=upper(coalesce(v_ig_feedback->>'kind',''));
    IF jsonb_typeof(v_ig_feedback) IS DISTINCT FROM 'object'
       OR v_ig_feedback->>'schema_version' IS DISTINCT FROM 'IG_PROFILE_FEEDBACK_V1'
       OR v_ig_feedback_kind NOT IN (
         'EVIDENCE_CHALLENGE','NONCANONICAL_RULE_PROPOSAL','UNSUPPORTED_DISAGREEMENT'
       )
       OR coalesce(v_ig_feedback->>'run_id','') !~ '^[1-9][0-9]{0,16}$'
       OR coalesce(v_ig_feedback->>'pantalla_id','') !~ '^[1-9][0-9]{0,8}$'
       OR coalesce(v_ig_feedback->>'source_snapshot_sha256','') !~ '^[a-f0-9]{64}$'
       OR nullif(btrim(coalesce(v_ig_feedback->>'family_code','')),'') IS NULL
       OR nullif(btrim(coalesce(v_ig_feedback->>'reason','')),'') IS NULL
       OR v_ig_feedback ?| ARRAY[
            'target_profile','auto_publish','force_recurate',
            'force_new_run','promotion_authorized','authority_granted'
          ]
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_IG_FEEDBACK_CONTRACT_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM programacion.input_readiness_runs r
      JOIN programacion.input_family_assessments a ON a.run_id=r.id
      -- A valid run+family alone is not an entitlement to challenge it.
      -- Bind to the exact IG receipt consumed by this profile execution.
      JOIN public.lf_operation_execution e
        ON e.execution_id=p_execution_id
       AND e.operation_code='EJECUCION_PERFIL_LF'
       AND e.target_type='PERFIL'
       AND e.target_code=p_profile_code
       AND e.status IN ('IN_PROGRESS','COMPLETED')
      JOIN public.lf_operation_execution_steps s
        ON s.execution_id=e.execution_id
       AND s.step_id='input_validate'
       AND s.status='STEP_PASS_WITH_EVIDENCE'
       AND s.evidence_payload#>>'{input_governance,run_id}'=r.id::text
       AND s.evidence_payload#>>'{input_governance,pantalla_id}'=r.pantalla_id::text
       AND s.evidence_payload#>>'{input_governance,context_manifest,run,source_snapshot_sha256}'=r.source_snapshot_sha256
      WHERE r.id=(v_ig_feedback->>'run_id')::bigint
        AND r.pantalla_id=(v_ig_feedback->>'pantalla_id')::integer
        AND r.source_snapshot_sha256=v_ig_feedback->>'source_snapshot_sha256'
        AND a.family_code=v_ig_feedback->>'family_code'
        AND r.status='COMPLETED'
    ) INTO v_ig_feedback_bound;

    IF NOT v_ig_feedback_bound THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_IG_FEEDBACK_RUN_FAMILY_BINDING_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    IF v_ig_feedback_kind='EVIDENCE_CHALLENGE'
       AND (jsonb_typeof(v_ig_feedback->'evidence_refs') IS DISTINCT FROM 'array'
            OR jsonb_array_length(coalesce(v_ig_feedback->'evidence_refs','[]'::jsonb))=0
            OR EXISTS(
              SELECT 1
              FROM jsonb_array_elements(coalesce(v_ig_feedback->'evidence_refs','[]'::jsonb)) f(ref)
              WHERE jsonb_typeof(f.ref)<>'string'
                 OR nullif(btrim(f.ref#>>'{}'),'') IS NULL
            ))
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_IG_FEEDBACK_EVIDENCE_MISSING',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    IF v_ig_feedback_kind='NONCANONICAL_RULE_PROPOSAL'
       AND (v_ig_feedback->>'canonical_status' IS DISTINCT FROM 'PROPOSED_NOT_CANONICAL'
            OR nullif(btrim(coalesce(v_ig_feedback->>'proposed_change','')),'') IS NULL)
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_IG_FEEDBACK_PROPOSAL_AUTHORITY_INVALID',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    IF v_ig_feedback_kind='UNSUPPORTED_DISAGREEMENT'
       AND jsonb_typeof(v_routing)='object'
       AND upper(coalesce(v_routing->>'resolution_target',''))='AUTHORITY_OR_CONTEXT_RESOLUTION'
    THEN
      RETURN jsonb_build_object(
        'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
        'status','BLOCKED','code','PROFILE_IG_FEEDBACK_UNSUPPORTED_LOOP_FORBIDDEN',
        'source_execution_id',p_execution_id,
        'source_profile_code',p_profile_code
      );
    END IF;

    IF v_ig_feedback_kind IN ('EVIDENCE_CHALLENGE','NONCANONICAL_RULE_PROPOSAL')
    THEN
      -- The router reclassifies the work from scratch. No direct IG dispatch.
      IF jsonb_typeof(v_routing) IS DISTINCT FROM 'object' THEN
        v_routing:=jsonb_build_object(
          'via','ORCHESTRATOR',
          'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
          'resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION'
        );
      ELSIF upper(coalesce(v_routing->>'via',''))<>'ORCHESTRATOR'
         OR upper(coalesce(v_routing->>'pipeline_action','')) NOT IN (
              'CONTINUE','CONTINUE_WITH_RESTRICTIONS'
            )
         OR upper(coalesce(v_routing->>'resolution_target',''))
              <>'AUTHORITY_OR_CONTEXT_RESOLUTION'
      THEN
        RETURN jsonb_build_object(
          'schema_version','LF_PROFILE_RESULT_ROUTER_RETURN_DECISION_V1',
          'status','BLOCKED','code','PROFILE_IG_FEEDBACK_ROUTING_CONFLICT',
          'source_execution_id',p_execution_id,
          'source_profile_code',p_profile_code
        );
      END IF;
    END IF;
    -- UNSUPPORTED_DISAGREEMENT alone does not ask IG to re-run.
  END IF;

  IF jsonb_typeof(v_repair_execution)='object'$new$;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
  );
  IF md5(d)<>'7517e452f5fa3ab2686c073bd6604b78' THEN
    RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_CLASSIFIER_SOURCE_DRIFT';
  END IF;
  IF (length(d)-length(replace(d,old_decl,'')))/length(old_decl)<>1
    OR (length(d)-length(replace(d,old_anchor,'')))/length(old_anchor)<>1
  THEN
    RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_PATCH_ANCHOR_MISMATCH';
  END IF;
  d:=replace(replace(d,old_decl,new_decl),old_anchor,new_anchor);
  EXECUTE d;
END
$patch$;

-- All checks exercise the patched function only inside rollback transaction.
DO $postcheck$
DECLARE
  src jsonb;
  run_hash text;
  test_execution_id text;
  x jsonb;
BEGIN
  SELECT source_snapshot_sha256 INTO run_hash
  FROM programacion.input_readiness_runs WHERE id=949 AND pantalla_id=51;
  IF run_hash IS NULL THEN
    RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_TEST_FIXTURE_RUN_MISSING';
  END IF;
  SELECT e.execution_id INTO test_execution_id
  FROM public.lf_operation_execution e
  JOIN public.lf_operation_execution_steps s ON s.execution_id=e.execution_id
  WHERE e.operation_code='EJECUCION_PERFIL_LF'
    AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
    AND s.step_id='input_validate'
    AND s.status='STEP_PASS_WITH_EVIDENCE'
    AND s.evidence_payload#>>'{input_governance,run_id}'='949'
    AND s.evidence_payload#>>'{input_governance,context_manifest,run,source_snapshot_sha256}'=run_hash
  LIMIT 1;
  IF test_execution_id IS NULL THEN
    RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_TEST_PROFILE_IG_RECEIPT_MISSING';
  END IF;

  src:=jsonb_build_object(
    'schema_version','IG_PROFILE_FEEDBACK_V1','kind','EVIDENCE_CHALLENGE',
    'run_id',949,'pantalla_id',51,'family_code','SESSION',
    'source_snapshot_sha256',run_hash,
    'reason','Session recovery requirement is absent from existing coverage.',
    'evidence_refs',jsonb_build_array('supabase://lf_ops/politicas_sesion')
  );
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'status'<>'RETURN_TO_ROUTER'
     OR x->>'next_action'<>'REENTER_ROUTER_STAGE1'
     OR x#>>'{router_return_request,next_entrypoint}'<>'ACT-0001_STAGE1'
     OR x#>>'{router_return_request,unresolved_payload,upstream_profile_output,deliverable_created,input_governance_feedback,run_id}'<>'949'
     OR x#>>'{router_return_request,unresolved_payload,routing,resolution_target}'<>'AUTHORITY_OR_CONTEXT_RESOLUTION'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_EVIDENCE_CHALLENGE_NOT_ROUTED:%',x; END IF;

  src:=jsonb_set(src,'{kind}','"NONCANONICAL_RULE_PROPOSAL"'::jsonb)
    ||jsonb_build_object('canonical_status','PROPOSED_NOT_CANONICAL',
      'proposed_change','Definir comportamiento funcional para recuperacion de cuenta');
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'status'<>'RETURN_TO_ROUTER' OR
     x#>>'{router_return_request,unresolved_payload,upstream_profile_output,deliverable_created,input_governance_feedback,canonical_status}'<>'PROPOSED_NOT_CANONICAL'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_PROPOSAL_NOT_ROUTED:%',x; END IF;

  src:=jsonb_set(src,'{kind}','"UNSUPPORTED_DISAGREEMENT"'::jsonb);
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'status'<>'COMPLETE' OR x->>'next_action'<>'EMIT_PROFILE_RESULT'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_UNSUPPORTED_DISAGREEMENT_LOOP:%',x; END IF;

  src:=jsonb_set(src,'{kind}','"EVIDENCE_CHALLENGE"'::jsonb);
  src:=jsonb_set(src,'{evidence_refs}','[]'::jsonb);
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_EVIDENCE_MISSING'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_NO_EVIDENCE_NOT_REJECTED:%',x; END IF;

  src:=jsonb_set(src,'{family_code}','"FAMILY_DOES_NOT_EXIST"'::jsonb);
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_RUN_FAMILY_BINDING_INVALID'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_BAD_FAMILY_NOT_REJECTED:%',x; END IF;

  -- Same run/family but wrong execution: no feedback-routing entitlement.
  src:=jsonb_set(src,'{family_code}','"SESSION"'::jsonb);
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B','UNKNOWN-EXECUTION-ID','PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_RUN_FAMILY_BINDING_INVALID'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_UNBOUND_EXECUTION_NOT_REJECTED:%',x; END IF;

  -- Same execution, incorrect profile identity must also fail.
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-UI-ARCHITECT');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_RUN_FAMILY_BINDING_INVALID'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_UNBOUND_PROFILE_NOT_REJECTED:%',x; END IF;

  src:=jsonb_set(src,'{source_snapshot_sha256}',to_jsonb(repeat('a',64)));
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_RUN_FAMILY_BINDING_INVALID'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_WRONG_SOURCE_SHA_NOT_REJECTED:%',x; END IF;

  src:=jsonb_set(src,'{source_snapshot_sha256}',to_jsonb(run_hash));
  src:=jsonb_set(src,'{kind}','"EVIDENCE_CHALLENGE"'::jsonb);
  src:=jsonb_set(src,'{evidence_refs}','[""]'::jsonb);
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src)),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_EVIDENCE_MISSING'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_EMPTY_REF_NOT_REJECTED:%',x; END IF;

  src:=jsonb_set(src,'{kind}','"UNSUPPORTED_DISAGREEMENT"'::jsonb);
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
      'status','PASS','deliverable_created',
       jsonb_build_object('input_governance_feedback',src),
      'routing',jsonb_build_object('via','ORCHESTRATOR',
        'pipeline_action','CONTINUE','resolution_target','AUTHORITY_OR_CONTEXT_RESOLUTION')),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_IG_FEEDBACK_UNSUPPORTED_LOOP_FORBIDDEN'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_UNSUPPORTED_LOOP_NOT_REJECTED:%',x; END IF;

  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC','status','PASS',
      'self_verdict','PASS','target_profile','PERFIL-UI-ARCHITECT'),
    'Revisar reglas de login B2B',test_execution_id,'PERFIL-PRODUCT-DIRECTOR-LF');
  IF x->>'code'<>'PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN'
  THEN RAISE EXCEPTION 'IG_PROFILE_FEEDBACK_DIRECT_PROFILE_REGRESSION:%',x; END IF;
END
$postcheck$;

ROLLBACK;
