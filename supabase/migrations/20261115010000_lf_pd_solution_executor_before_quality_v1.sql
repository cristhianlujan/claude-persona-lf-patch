-- Candidate ONLY: Product Director analysis -> ACT-0001 executor -> evidenced Quality.
-- Supabase sandbox / governed Migration Merge Train. No live write, promotion, or production here.
-- Reuses existing classifier, selector, config FALLBACK_PROFILE and Step50 evidence. No profile auto-invocation.
BEGIN;
DO $lf_pd_flow$
DECLARE
  d text;
  old_anchor text;
  new_anchor text;
  n integer;
  r jsonb;
  q jsonb;
  sample jsonb;
  v_original text := 'Entra por el router y revisa las reglas de carga masiva del b2b';
BEGIN
  d:=pg_get_functiondef('public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure);
  IF md5(d)<>'876a3ce6ffbb2d21a6a2d21372f459c9' THEN
    RAISE EXCEPTION 'PD_EXECUTOR_CLASSIFIER_SOURCE_STATE_DRIFT';
  END IF;
  old_anchor:=$old$
  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action',''))='RETURN_TO_ORCHESTRATOR' THEN
$old$;
  new_anchor:=$new$
  -- PD analysis with remaining work is NOT the implementation artifact.
  -- Override advisory Quality handoffs: ACT-0001 must select an executor first.
  ELSIF p_profile_code='PERFIL-PRODUCT-DIRECTOR-LF'
        AND v_output_type='PRODUCT_DIRECTION_SPEC'
        AND (
          jsonb_typeof(p_profile_output#>'{deliverable_created,implementation_package}')='object'
          OR (
            jsonb_typeof(p_profile_output#>'{deliverable_created,blockers}')='array'
            AND jsonb_array_length(p_profile_output#>'{deliverable_created,blockers}')>0
          )
          OR upper(coalesce(p_profile_output#>>'{deliverable_created,handoff_to_next,target}','')) LIKE '%QUALITY%'
        ) THEN
    v_redirect_kind:='PRODUCT_EXECUTOR_HANDOFF';
    v_payload:=jsonb_build_object(
      'workflow_phase','EXECUTION_OR_REPAIR',
      'solution_readiness',CASE
        WHEN jsonb_typeof(p_profile_output#>'{deliverable_created,implementation_package,actions}')='array'
         AND jsonb_array_length(p_profile_output#>'{deliverable_created,implementation_package,actions}')>0
         AND jsonb_typeof(p_profile_output#>'{deliverable_created,implementation_package,source_refs}')='array'
         AND jsonb_array_length(p_profile_output#>'{deliverable_created,implementation_package,source_refs}')>0
        THEN 'PROPOSED_IMPLEMENTATION_PACKAGE'
        ELSE 'MISSING_EXECUTABLE_PACKAGE'
      END,
      'required_next_gate','ROUTER_SELECT_EXECUTOR',
      'quality_allowed_before_executor',false,
      'automatic_promotion_allowed',false,
      'owner_decision_after_quality',true,
      'implementation_package',p_profile_output#>'{deliverable_created,implementation_package}',
      'upstream_profile_output_sha256','sha256:'||encode(
        extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),'hex'
      ),
      'upstream_profile_output',p_profile_output
    );

  ELSIF jsonb_typeof(v_routing)='object'
        AND upper(coalesce(v_routing->>'pipeline_action',''))='RETURN_TO_ORCHESTRATOR' THEN
$new$;
  n:=(length(d)-length(replace(d,old_anchor,'')))/length(old_anchor);
  IF n<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_CLASSIFIER_ANCHOR_DRIFT:%',n; END IF;
  EXECUTE replace(d,old_anchor,new_anchor);

  -- Fixture: an inventory-only historical PD output MUST return to ACT-0001;
  -- no invented implementation/evidence and no Quality admission.
  sample:=jsonb_build_object(
    'output_type','PRODUCT_DIRECTION_SPEC','self_verdict','PASS',
    'deliverable_created',jsonb_build_object(
      'blockers',jsonb_build_array('Missing implementation'),
      'handoff_to_next',jsonb_build_object('target','PERFIL-QUALITY-PACK')));
  r:=public.lf_profile_result_router_return_classify_v1(
    sample,v_original,'EXEC-FIXTURE-NOT-PERSISTED','PERFIL-PRODUCT-DIRECTOR-LF');
  IF r->>'status'<>'RETURN_TO_ROUTER'
     OR r->>'redirect_kind'<>'PRODUCT_EXECUTOR_HANDOFF'
     OR r#>>'{router_return_request,unresolved_payload,solution_readiness}'<>'MISSING_EXECUTABLE_PACKAGE'
     OR r#>>'{router_return_request,unresolved_payload,quality_allowed_before_executor}'<>'false'
     OR r#>>'{router_return_request,stage1_literal}'<>v_original
  THEN RAISE EXCEPTION 'PD_EXECUTOR_MISSING_PROPOSAL_REGRESSION:%',r; END IF;

  q:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'output_type','PRODUCT_DIRECTION_SPEC',
      'deliverable_created',jsonb_build_object(
        'implementation_package',jsonb_build_object(
          'actions',jsonb_build_array(jsonb_build_object('action','prepare governed candidate')),
          'source_refs',jsonb_build_array('supabase://lf_ops.reglas/example')))),
    v_original,'EXEC-FIXTURE-NOT-PERSISTED','PERFIL-PRODUCT-DIRECTOR-LF');
  IF q->>'status'<>'RETURN_TO_ROUTER'
     OR q#>>'{router_return_request,unresolved_payload,solution_readiness}'<>'PROPOSED_IMPLEMENTATION_PACKAGE'
  THEN RAISE EXCEPTION 'PD_EXECUTOR_PROPOSAL_READY_REGRESSION:%',q; END IF;

  q:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object('output_type','PRODUCT_DIRECTION_SPEC',
      'target_profile','PERFIL-QUALITY-PACK'),
    v_original,'EXEC-FIXTURE-NOT-PERSISTED','PERFIL-PRODUCT-DIRECTOR-LF');
  IF q->>'code'<>'PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN'
  THEN RAISE EXCEPTION 'PD_EXECUTOR_DIRECT_TARGET_REGRESSION'; END IF;
END $lf_pd_flow$;

-- Derive next phase from the *verified completed source run*, not caller-supplied
-- routing hints. Original request SHA and source_execution_id remain bound.
DO $lf_pd_derived$
DECLARE
  d text;
  old_decl text;
  new_decl text;
  old_gate text;
  new_gate text;
  old_select text;
  new_select text;
  old_return text;
  new_return text;
  old_derived_entry text;
  new_derived_entry text;
  v_count integer;
BEGIN
  d:=pg_get_functiondef('public.lf_profile_selector_semantic_prepare_v2(text,text,jsonb,jsonb)'::regprocedure);
  IF md5(d)<>'89bd02a1c46e41c156322ab9370b140b' THEN
    RAISE EXCEPTION 'PD_EXECUTOR_SELECTOR_SOURCE_STATE_DRIFT';
  END IF;
  old_decl:=$old$  v_entry text[]:='{}';
begin$old$;
  new_decl:=$new$  v_entry text[]:='{}';
  v_next_stage jsonb:=NULL;
  v_source_output jsonb;
  v_source_profile text;
  v_redirect jsonb;
  v_fallback text;
begin$new$;
  v_count:=(length(d)-length(replace(d,old_decl,'')))/length(old_decl);
  IF v_count<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_SELECTOR_DECLARE_DRIFT'; END IF;
  d:=replace(d,old_decl,new_decl);

  old_gate:=$old$  select coalesce(jsonb_agg(p order by p->>'profile_code'),'[]'::jsonb) into v_all$old$;
  new_gate:=$new$  -- Source identity was already checked above: COMPLETED, DIRECT and same request SHA.
  IF v_deriv IS NOT NULL THEN
    SELECT e.target_code,s.evidence_payload->'profile_output'
      INTO v_source_profile,v_source_output
    FROM public.lf_operation_execution e
    JOIN public.lf_operation_execution_steps s
      ON s.execution_id=e.execution_id AND s.step_id='execute_profile'
     AND s.status='STEP_PASS_WITH_EVIDENCE'
    WHERE e.execution_id=v_src AND e.status='COMPLETED';
    IF jsonb_typeof(v_source_output)='object' THEN
      v_redirect:=public.lf_profile_result_router_return_classify_v1(
        v_source_output,p_literal_request,v_src,v_source_profile);
      IF v_redirect->>'status'='RETURN_TO_ROUTER'
         AND v_redirect->>'redirect_kind'='PRODUCT_EXECUTOR_HANDOFF'
      THEN
        v_next_stage:=jsonb_build_object(
          'phase','EXECUTOR_BEFORE_QUALITY',
          'source_execution_id',v_src,
          'source_profile_code',v_source_profile,
          'solution_readiness',
          v_redirect#>>'{router_return_request,unresolved_payload,solution_readiness}',
          'source_output_sha256',
          v_redirect#>>'{router_return_request,unresolved_payload,upstream_profile_output_sha256}',
          'executor_selection_instruction','SELECT_SPECIALIST_IF_CURRENT_AND_APPLICABLE_ELSE_CONFIGURED_FALLBACK',
          'quality_allowed',false,
          'automatic_promotion_allowed',false
        );
        SELECT value->>'profile_code' INTO v_fallback
          FROM public.lf_router_architecture_config_v1
          WHERE config_key='FALLBACK_PROFILE';
        IF nullif(v_fallback,'') IS NULL THEN
          RAISE EXCEPTION 'PD_EXECUTOR_FALLBACK_CONFIG_MISSING';
        END IF;
      ELSIF v_redirect->>'status'='RETURN_TO_ROUTER'
            AND v_redirect->>'redirect_kind'='SYSTEMIC_REPAIR_EXECUTED_WITH_READBACK'
      THEN
        v_next_stage:=jsonb_build_object(
          'phase','QUALITY_ON_EXECUTED_ARTIFACT',
          'source_execution_id',v_src,
          'source_profile_code',v_source_profile,
          'quality_required',true,
          'automatic_promotion_allowed',false
        );
      END IF;
    END IF;
  END IF;
  select coalesce(jsonb_agg(p order by p->>'profile_code'),'[]'::jsonb) into v_all$new$;
  v_count:=(length(d)-length(replace(d,old_gate,'')))/length(old_gate);
  IF v_count<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_SELECTOR_GATE_DRIFT'; END IF;
  d:=replace(d,old_gate,new_gate);

  -- Derived repair continuations must be bound to a real Router-authorized
  -- completed profile; never accept a generic DERIVATION_ONLY as an entrypoint.
  old_derived_entry:=$old$
    where e.execution_id=v_src and e.operation_code='EJECUCION_PERFIL_LF' and e.status='COMPLETED'
      and e.request_sha256=v_request_sha and sp.entry_policy='DIRECT';
    -- Only canonical one-field envelope; DB proves COMPLETED, DIRECT and same SHA.
$old$;
  new_derived_entry:=$new$
    where e.execution_id=v_src and e.operation_code='EJECUCION_PERFIL_LF' and e.status='COMPLETED'
      and e.request_sha256=v_request_sha
      and (
        sp.entry_policy='DIRECT'
        OR (
          sp.entry_policy='DERIVATION_ONLY'
          AND e.manifest#>>'{router_profile_handoff,profile_code}'=e.target_code
          AND e.manifest#>>'{router_profile_handoff,request_sha256}'=e.request_sha256
          AND e.manifest#>>'{router_profile_handoff,return_to_router_after_profile_result}'='true'
          AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,authority_ref}'='ROUTER_PROFILE_EXECUTION_AUTHORIZATION'
          AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_code}'=e.target_code
          AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,request_sha256}'=e.request_sha256
          AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,fingerprint_sha256}'=
            encode(extensions.digest(convert_to(
              ((e.manifest#>'{router_profile_handoff,router_authorization_receipt}')-'fingerprint_sha256')::text,
              'UTF8'),'sha256'),'hex')
          AND e.manifest#>>'{router_profile_handoff,semantic_result,decision}'='RESOLVED'
          AND e.manifest#>>'{router_profile_handoff,semantic_result,positive_target_refs,0}'=e.target_code
        )
      );
    -- Only a source-bound completed run, with DIRECT or verified Router-derived authority.
$new$;
  v_count:=(length(d)-length(replace(d,old_derived_entry,'')))/length(old_derived_entry);
  IF v_count<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_SELECTOR_DERIVED_AUTH_DRIFT'; END IF;
  d:=replace(d,old_derived_entry,new_derived_entry);

  old_select:=$old$  where (v_channel is null or (p->'channels') ? v_channel)
    and ($old$;
  new_select:=$new$  where (v_channel is null or (p->'channels') ? v_channel)
    and (
      v_next_stage IS NULL
      OR (
        v_next_stage->>'phase'='EXECUTOR_BEFORE_QUALITY'
        AND (
          (v_next_stage->>'solution_readiness'='MISSING_EXECUTABLE_PACKAGE'
           AND p->>'profile_code'=v_fallback)
          OR
          (v_next_stage->>'solution_readiness'='PROPOSED_IMPLEMENTATION_PACKAGE'
           AND p->>'canonical_profile_key' NOT IN ('product_director_lf','quality_pack'))
        )
      )
      OR (v_next_stage->>'phase'='QUALITY_ON_EXECUTED_ARTIFACT'
          AND p->>'canonical_profile_key'='quality_pack')
    )
    and ($new$;
  v_count:=(length(d)-length(replace(d,old_select,'')))/length(old_select);
  IF v_count<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_SELECTOR_FILTER_DRIFT'; END IF;
  d:=replace(d,old_select,new_select);

  old_return:=$old$    'route_authority',false,'effect_authority',false,'downstream_execution_allowed',false);
end $function$$old$;
  new_return:=$new$    'derivation_next_stage',v_next_stage,
    'configured_fallback_profile',CASE WHEN v_next_stage->>'phase'='EXECUTOR_BEFORE_QUALITY'
      THEN v_fallback ELSE NULL END,
    'route_authority',false,'effect_authority',false,'downstream_execution_allowed',false);
end $function$$new$;
  v_count:=(length(d)-length(replace(d,old_return,'')))/length(old_return);
  IF v_count<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_SELECTOR_RETURN_DRIFT'; END IF;
  d:=replace(d,old_return,new_return);
  EXECUTE d;
END $lf_pd_derived$;

-- Reuse existing terminal receipt attacher. The native Step80 recorder previously
-- computed the terminal SHA but did NOT persist its ACT-0001 post-profile route.
-- This canonical step is still no product write and no profile auto-invocation.
DO $lf_pd_terminal_handoff$
DECLARE
  d text;
  old_decl text;
  new_decl text;
  old_return text;
  new_return text;
  n integer;
BEGIN
  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
  IF md5(d)<>'c545d192229d369bf26152a99de9899f' THEN
    RAISE EXCEPTION 'PD_EXECUTOR_REPORT_SOURCE_STATE_DRIFT';
  END IF;
  old_decl:=$old$  v_terminal jsonb;
BEGIN$old$;
  new_decl:=$new$  v_terminal jsonb;
  v_attached jsonb;
BEGIN$new$;
  n:=(length(d)-length(replace(d,old_decl,'')))/length(old_decl);
  IF n<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_REPORT_DECLARE_ANCHOR_DRIFT'; END IF;
  d:=replace(d,old_decl,new_decl);

  old_return:=$old$
  RETURN jsonb_build_object(
    'status','PROFILE_EXECUTION_COMPLETED',
    'execution_id',p_execution_id,
    'profile_code',e.target_code,
    'clean_step_count',v_clean,
    'last_completed_step','report_output',
    'execution_status',e.status,
    'terminal_authority_receipt_sha256',v_terminal->>'terminal_authority_receipt_sha256',
    'next_gate','RETURN_TO_ROUTER'
  );
END
$function$$old$;
  new_return:=$new$
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
$function$$new$;
  n:=(length(d)-length(replace(d,old_return,'')))/length(old_return);
  IF n<>1 THEN RAISE EXCEPTION 'PD_EXECUTOR_REPORT_RETURN_ANCHOR_DRIFT:%',n; END IF;
  EXECUTE replace(d,old_return,new_return);
END $lf_pd_terminal_handoff$;
COMMIT;
