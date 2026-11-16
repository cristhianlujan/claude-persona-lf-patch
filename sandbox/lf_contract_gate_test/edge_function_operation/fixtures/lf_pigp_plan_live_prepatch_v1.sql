-- Live source snapshot for B/PIGP Step40 plan resolver PG17/18.
CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(p_execution_id text, p_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE e public.lf_operation_execution%ROWTYPE;v_handoff jsonb;v_scope jsonb;
 v_input jsonb;v_ctx jsonb;v_decision jsonb;v_selected jsonb;v_oldplan jsonb;
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
END $function$
;
