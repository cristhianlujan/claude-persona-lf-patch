-- LF sandbox: owner 2026-11-14 13:55+13:58. Only skill selection and Stage1 content truncation.
-- Compatibility for preexisting RUNs is isolated in one helper; source/drift fail-closed.
BEGIN;
DO $checks$ BEGIN
 IF md5(pg_get_functiondef('public.lf_profile_execution_plan_v1(text,text,jsonb'::regprocedure))<>'14e045fe02c9c635c166f8cced7ee4d8' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_profile_execution_plan_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text'::regprocedure))<>'bc85d57f8509728527efa62b2b6bd124' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_profile_native_bridge_prepare_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_invoke_selected_v1(text,text,text,jsonb,jsonb'::regprocedure))<>'ddf9f81751512a956c8027c79f966642' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_profile_skill_invoke_selected_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_runtime_ticket_issue_v1(text,text,jsonb'::regprocedure))<>'3b3fffdb37780f543546263cf732ab5d' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_profile_skill_runtime_ticket_issue_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_profile_skill_selection_prepare_v1(text,text,jsonb'::regprocedure))<>'24850ec585cecca9a54fe87e3d1ad2da' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_profile_skill_selection_prepare_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_pipeline_context_profile_semantic_prepare_v2(text'::regprocedure))<>'2d7b39fe0f89bfdf3ceef705588a1911' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_pipeline_context_profile_semantic_prepare_v2'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_pipeline_context_profile_semantic_submit_v2(text,text'::regprocedure))<>'269c144458c84beaa30ae8ffbf734186' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_pipeline_context_profile_semantic_submit_v2'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_pipeline_context_stage1_submit_v2(text,jsonb'::regprocedure))<>'db6767852494edcf725829e719096fd6' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_pipeline_context_stage1_submit_v2'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_pipeline_profile_semantic_prepare_v1(text'::regprocedure))<>'905b9dba6f033c78783ab513cc451a8d' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_pipeline_profile_semantic_prepare_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_pipeline_profile_semantic_submit_v1(text,text'::regprocedure))<>'9b0eef4e0cffab64a551ed27d33d823f' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_pipeline_profile_semantic_submit_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_pipeline_stage1_submit_v1(text,jsonb'::regprocedure))<>'82747605ce694ecb3b2ddee405d8bff7' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_pipeline_stage1_submit_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_route_v1(jsonb,jsonb,boolean'::regprocedure))<>'8a74d20e7ad65f1fb3f80f1cc4bbb313' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_route_v1'; END IF;
 IF md5(pg_get_functiondef('public.lf_router_stage1_validate_v2(jsonb'::regprocedure))<>'b9b8f68bc4cf02af657830857a80bfc2' THEN RAISE EXCEPTION 'LF_SOURCE_DRIFT_lf_router_stage1_validate_v2'; END IF;
 IF (SELECT count(*) FROM public.lf_skill_selector_policy_v1 WHERE enabled AND selection_mode='SEMANTIC_OPTIONAL')<>18
 OR (SELECT count(*) FROM public.lf_skill_selector_policy_v1 WHERE enabled AND selection_mode='DETERMINISTIC_REQUIRED')<>0
 THEN RAISE EXCEPTION 'LF_SKILL_POLICY_COUNT_DRIFT'; END IF;
END $checks$;

CREATE OR REPLACE FUNCTION public.lf_skill_selection_legacy_running_compat_v1(
 p_execution_id text,p_decision jsonb) RETURNS jsonb
 LANGUAGE plpgsql STABLE
 SET search_path TO 'pg_catalog','public'
AS $compat$
DECLARE e record;
BEGIN
 IF p_decision IS NULL THEN RETURN NULL; END IF;
 IF jsonb_typeof(p_decision)<>'object' THEN RETURN p_decision; END IF;
 IF NOT p_decision ? 'selected_skill_code' THEN RETURN p_decision; END IF;
 SELECT created_at,status INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id
   AND operation_code='EJECUCION_PERFIL_LF';
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.created_at >= timestamptz '2026-11-14 19:55:00+00'
 THEN RETURN jsonb_build_object('legacy_block_code','SKILL_LEGACY_DECISION_NOT_RUNNING'); END IF;
 IF p_decision ? 'selected_skill_codes' THEN
   RETURN jsonb_build_object('legacy_block_code','SKILL_CHOICE_CONFLICT'); END IF;
 IF p_decision->>'selected_skill_code'='ninguna' THEN
   RETURN (p_decision - 'selected_skill_code') || jsonb_build_object('selected_skill_codes','[]'::jsonb); END IF;
 RETURN (p_decision - 'selected_skill_code')
   || jsonb_build_object('selected_skill_codes',jsonb_build_array(p_decision->>'selected_skill_code'),
      'descriptor_revisions',jsonb_build_object(p_decision->>'selected_skill_code',
         p_decision->>'descriptor_revision'));
END $compat$;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_context_v1(
 p_profile_code text,p_channel text,p_decision jsonb,p_ctx jsonb) RETURNS jsonb
 LANGUAGE plpgsql STABLE
 SET search_path TO 'pg_catalog','public'
AS $skill$
DECLARE v_required jsonb:='[]'::jsonb;v_candidates jsonb:='[]'::jsonb;
 v_selected jsonb:='[]'::jsonb;v_findings jsonb:='[]'::jsonb;
 v_unavailable jsonb:='[]'::jsonb;v_input jsonb;
 v_item jsonb;v_choices jsonb;v_one jsonb;v_reason text;v_refs jsonb;
 v_ctx jsonb:=coalesce(p_ctx,'{}'::jsonb);
 r record;n integer;k text;
BEGIN
 IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL
 OR p_channel NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PROFILE_CHANNEL_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_selection_registry_v1 d
  JOIN public.lf_profile_selector_policy_v1 p USING(profile_code)
  WHERE d.profile_code=p_profile_code AND d.descriptor_status='CURRENT'
    AND p_channel=ANY(p.channels))
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_PROFILE_AUTHORITY_INVALID'); END IF;
 IF jsonb_typeof(v_ctx)<>'object' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CONTEXT_TRANSPORT_INVALID'); END IF;
 IF v_ctx<>'{}'::jsonb AND (
     v_ctx->>'profile_code' IS DISTINCT FROM p_profile_code
     OR v_ctx->>'channel' IS DISTINCT FROM p_channel
     OR coalesce(v_ctx->>'step','') !~ '^(30|40|45|47|50|60|70|80)$')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_CONTEXT_BINDING_INVALID'); END IF;
 v_input:=coalesce(v_ctx->'input','{}'::jsonb);
 IF jsonb_typeof(v_input)<>'object' THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_INPUT_TRANSPORT_INVALID'); END IF;
 FOR r IN SELECT p.skill_code,p.selection_mode,p.required_operation,p.allowed_effects,
      c.status AS catalog_status,c.effect,c.required_operation AS catalog_operation,c.handler_fn,
      c.input_required,d.descriptor_status,d.descriptor,d.source_revision,d.source_ref
   FROM public.lf_skill_selector_policy_v1 p
   LEFT JOIN public.lf_skill_catalog_v1 c USING(skill_code)
   LEFT JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
   WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   ORDER BY p.skill_code
 LOOP
   IF r.selection_mode NOT IN ('SEMANTIC_OPTIONAL','DETERMINISTIC_REQUIRED')
   OR r.catalog_status IS DISTINCT FROM 'READY'
   OR r.descriptor_status IS DISTINCT FROM 'CURRENT'
   OR r.catalog_operation IS DISTINCT FROM r.required_operation
   OR r.effect IS NULL OR NOT r.effect=ANY(r.allowed_effects)
   OR coalesce(r.source_revision,'')='' OR r.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_POLICY_CATALOG_SOURCE_INVALID',
          'skill_code',r.skill_code); END IF;
   IF EXISTS (SELECT 1 FROM public.lf_skill_selector_policy_v1 p
      WHERE p.profile_code=p_profile_code AND p.skill_code=r.skill_code
        AND p.owner_decision_required)
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_OWNER_AUTHORITY_REQUIRED'); END IF;
   IF r.catalog_operation<>'EJECUCION_PERFIL_LF' OR r.effect<>'READ_ONLY' THEN
      v_unavailable:=v_unavailable||jsonb_build_array(jsonb_build_object(
       'skill_code',r.skill_code,'reason','OTHER_OPERATION_OR_EFFECT_NOT_STEP40'));
      CONTINUE;
   END IF;
   IF EXISTS(SELECT 1 FROM unnest(r.input_required) f
      WHERE NOT (v_input ? f)
      OR v_input->f IN ('null'::jsonb,'""'::jsonb,'"{}"'::jsonb,'{}'::jsonb,'[]'::jsonb)
      OR (jsonb_typeof(v_input->f)='string' AND btrim(v_input->>f)=''))
   THEN v_unavailable:=v_unavailable||jsonb_build_array(jsonb_build_object(
      'skill_code',r.skill_code,'reason','INPUT_REQUIRED_NOT_AVAILABLE',
      'required',to_jsonb(r.input_required),'step',v_ctx->>'step'));
      CONTINUE;
   END IF;
   v_item:=jsonb_build_object('skill_code',r.skill_code,'handler_fn',r.handler_fn,
      'required_operation',r.catalog_operation,'effect',r.effect,
      'input_required',to_jsonb(r.input_required),'source_revision',r.source_revision,
      'source_ref',r.source_ref,'descriptor',r.descriptor,
      'selection_context',jsonb_build_object(
        'request_text',v_ctx->>'request_text','intent',v_ctx->>'intent',
        'profile_code',p_profile_code,'channel',p_channel,
        'step',v_ctx->>'step','input_summary',v_ctx->'input_summary'));
   IF r.selection_mode='DETERMINISTIC_REQUIRED' THEN
      v_required:=v_required||jsonb_build_array(v_item||
      jsonb_build_object('selection_mode','DETERMINISTIC_POLICY',
       'selection_evidence',jsonb_build_object('source_revision',r.source_revision)));
   ELSE v_candidates:=v_candidates||jsonb_build_array(v_item); END IF;
 END LOOP;
 IF p_decision IS NULL THEN
   IF jsonb_array_length(v_candidates)=1 AND v_candidates->0->>'effect'='READ_ONLY' THEN
     v_item:=v_candidates->0;
     v_selected:=jsonb_build_array(v_item||jsonb_build_object(
      'selection_mode','DETERMINISTIC_INPUT_UNIQUE',
      'selection_evidence',jsonb_build_object(
       'reason','ONE_ELIGIBLE_READ_ONLY_SKILL_WITH_VALID_INPUT',
       'source_revision',v_item->>'source_revision',
       'input_required',v_item->'input_required','step',v_ctx->>'step')));
   ELSE
     v_findings:=jsonb_build_array(jsonb_build_object(
       'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
       'finding_alias','SKILL_SELECTION_PENDING_FINDING',
       'continuation_allowed',true,'production_authorized',false,
       'candidate_count',jsonb_array_length(v_candidates),
       'remediation_action','SUBMIT_SKILL_SELECTION'));
   END IF;
 ELSE
   IF jsonb_typeof(p_decision)<>'object' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DECISION_TRANSPORT_INVALID'); END IF;
   IF p_decision ? 'legacy_block_code' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code',p_decision->>'legacy_block_code'); END IF;
   IF p_decision ? 'selected_skill_code' OR
      jsonb_typeof(p_decision->'selected_skill_codes')<>'array' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_LIST_SCHEMA_INVALID'); END IF;
   v_choices:=p_decision->'selected_skill_codes';
   n:=jsonb_array_length(v_choices);
   IF n>2 THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','SKILL_SELECTION_TICKET_LIMIT_EXCEEDED','maximum',2); END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_choices) v
     WHERE jsonb_typeof(v)<>'string' OR nullif(btrim(v#>>'{}'),'') IS NULL)
   OR (SELECT count(DISTINCT v#>>'{}') FROM jsonb_array_elements(v_choices) v)<>n
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LIST_INVALID_OR_DUPLICATE'); END IF;
   v_reason:=nullif(btrim(coalesce(p_decision->>'reason','')),'');
   v_refs:=p_decision->'evidence_refs';
   IF v_reason IS NULL THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_REASON_MISSING'); END IF;
   IF n>0 AND (jsonb_typeof(v_refs)<>'array' OR jsonb_array_length(v_refs)=0
       OR p_decision->>'review_mode'<>'CURRENT_CONTEXT_REVIEW') THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_EVIDENCE_INVALID'); END IF;
   FOR v_one IN SELECT value FROM jsonb_array_elements(v_choices) LOOP
      k:=v_one#>>'{}';
      SELECT x INTO v_item FROM jsonb_array_elements(v_candidates) x WHERE x->>'skill_code'=k;
      IF v_item IS NULL THEN RETURN jsonb_build_object('status','BLOCKED',
        'blocking_code','SKILL_SELECTION_NOT_IN_ELIGIBLE_INPUT_CANDIDATES','skill_code',k); END IF;
      IF (p_decision->'descriptor_revisions'->>k) IS DISTINCT FROM v_item->>'source_revision' THEN
         RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_SOURCE_STALE',
             'skill_code',k); END IF;
      v_selected:=v_selected||jsonb_build_array(v_item||jsonb_build_object(
        'selection_mode','SEMANTIC_DESCRIPTOR',
        'selection_evidence',jsonb_build_object('reason',v_reason,'evidence_refs',v_refs,
           'descriptor_revision',v_item->>'source_revision',
           'review_mode','CURRENT_CONTEXT_REVIEW','source_ref',v_item->>'source_ref')));
   END LOOP;
   IF n=0 THEN v_findings:=jsonb_build_array(jsonb_build_object(
     'finding_code','SKILL_EXPLICIT_NONE','reason',v_reason,
     'continuation_allowed',true,'production_authorized',false)); END IF;
 END IF;
 RETURN jsonb_build_object('status','READY','skills',v_required||v_selected,
  'selection_status',CASE WHEN jsonb_array_length(v_candidates)>1 AND p_decision IS NULL
      THEN 'SKILL_SELECTION_PENDING_FINDING' ELSE 'SKILL_SELECTION_REQUESTED' END,
  'next_action','SUBMIT_SKILL_SELECTION','selected_skill_codes',coalesce(v_choices,'[]'::jsonb),
  'skill_candidates',v_candidates,'unavailable_skills',v_unavailable,
  'content_findings',v_findings,'required_skills',v_required,
  'profile_code',p_profile_code,'channel',p_channel,'continuation_allowed',true,
  'selection_mode','OPTIONAL_FAIL_OPEN','maximum_selected_skills',2);
END $skill$;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_v1(
 p_profile_code text,p_channel text,p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE
 SET search_path TO 'pg_catalog','public'
AS $fn$
 SELECT public.lf_profile_skill_selection_prepare_context_v1(
  p_profile_code,p_channel,p_semantic_decision,'{}'::jsonb);
$fn$;

CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(
 p_execution_id text,p_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE
 SET search_path TO 'pg_catalog','public'
AS $plan$
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
END $plan$;

-- Bind once, guarded; no new Router entry; immutable decision for an existing run.
CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_run_bind_v1(
 p_execution_id text,p_decision jsonb,p_actor_execution_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'pg_catalog','public'
AS $bind$
DECLARE e public.lf_operation_execution%ROWTYPE;v_plan jsonb;v_decision jsonb;v_existing jsonb;
BEGIN
 IF current_setting('request.jwt.claim.role',true)<>'service_role'
    AND session_user NOT IN ('postgres','service_role') THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_AUTHORITY_INVALID'); END IF;
 IF p_actor_execution_id IS DISTINCT FROM p_execution_id OR
    nullif(btrim(coalesce(p_execution_id,'')),'') IS NULL OR
    jsonb_typeof(p_decision)<>'object' THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_ACTOR_OR_TRANSPORT_INVALID'); END IF;
 SELECT * INTO e FROM public.lf_operation_execution WHERE execution_id=p_execution_id FOR UPDATE;
 IF NOT FOUND OR e.status<>'IN_PROGRESS' OR e.operation_code<>'EJECUCION_PERFIL_LF'
    OR e.target_type<>'PERFIL' THEN
 RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_RUN_INVALID'); END IF;
 v_decision:=p_decision;
 IF p_decision ? 'selected_skill_code' THEN
   v_decision:=public.lf_skill_selection_legacy_running_compat_v1(p_execution_id,p_decision);
 END IF;
 v_existing:=e.manifest->'skill_selection_decision';
 IF v_existing IS NOT NULL THEN
   IF v_existing=v_decision THEN RETURN jsonb_build_object('status','ALREADY_BOUND',
     'execution_id',p_execution_id); END IF;
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_BIND_REPLAY_DIFFERENT_DECISION');
 END IF;
 v_plan:=public.lf_profile_execution_plan_for_run_v1(p_execution_id,v_decision);
 IF v_plan->>'status'<>'READY' OR jsonb_typeof(v_plan->'skills')<>'array' THEN
 RETURN jsonb_build_object('status','BLOCKED',
    'blocking_code',coalesce(v_plan->>'blocking_code','SKILL_BIND_PLAN_INVALID')); END IF;
 UPDATE public.lf_operation_execution SET manifest=manifest||
   jsonb_build_object('skill_selection_decision',v_decision,
     'skill_selection_readback',jsonb_build_object(
        'selected_skill_codes',v_plan->'selected_skill_codes',
        'skill_selection_status',v_plan->>'skill_selection_status',
        'source','OFFICIAL_SKILL_POLICY_CURRENT_RUN')),
    updated_at=now(),updated_by_execution_id=p_execution_id
 WHERE execution_id=p_execution_id;
 RETURN jsonb_build_object('status','BOUND','execution_id',p_execution_id,
   'selected_skill_codes',v_plan->'selected_skill_codes','selection_receipt',v_plan->'selection_receipt');
END $bind$;
REVOKE ALL ON FUNCTION public.lf_profile_skill_selection_run_bind_v1(text,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_profile_skill_selection_run_bind_v1(text,jsonb,text) TO service_role;

-- IG is an optional policy-selected skill, not an unconditional requirement.
UPDATE public.lf_skill_selector_policy_v1
 SET applicability_contract=applicability_contract-'selection_required',updated_at=now()
 WHERE selection_mode='SEMANTIC_OPTIONAL'
  AND applicability_contract ? 'selection_required';
