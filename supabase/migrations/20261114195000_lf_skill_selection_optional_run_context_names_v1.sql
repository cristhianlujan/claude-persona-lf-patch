-- LF sandbox: optional skill semantics, verified RUN context, independent profile vocabulary.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_v2(
 p_profile_code text,p_channel text,p_selection jsonb,p_run_context jsonb DEFAULT NULL::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE
 v_n integer; v_missing integer; v_stale integer; v_required jsonb:='[]'::jsonb;
 v_eligible jsonb:='[]'::jsonb; v_excluded jsonb:='[]'::jsonb;
 v_selected jsonb:='[]'::jsonb; v_codes jsonb; v_refs jsonb; v_revs jsonb;
 v_reason text;v_rev text;v_code text;v_ncodes integer;v_row record;v_field text;
 v_ready boolean;v_legacy boolean:=coalesce((p_run_context->>'legacy_run')::boolean,false);
 v_hard_max constant integer:=2;
BEGIN
 IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL OR
    coalesce(p_channel,'') NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_CHANNEL_INVALID'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_selection_registry_v1 d
  JOIN public.lf_profile_selector_policy_v1 p USING(profile_code)
  WHERE d.profile_code=p_profile_code AND d.descriptor_status='CURRENT'
  AND p_channel=ANY(p.channels))
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_SOURCE_OR_CHANNEL_NOT_CURRENT'); END IF;
 IF EXISTS(SELECT 1 FROM public.lf_skill_selector_policy_v1 p
  WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND p.owner_decision_required)
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_OWNER_DECISION_REQUIRED'); END IF;
 SELECT count(*) INTO v_n FROM public.lf_skill_selector_policy_v1 p
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels);
 IF v_n=0 THEN RETURN jsonb_build_object('status','READY','skills','[]'::jsonb,
 'profile_code',p_profile_code,'channel',p_channel,'selection_mode','NO_ENABLED_SKILLS');END IF;
 SELECT count(*) INTO v_missing FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_catalog_v1 c ON c.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
 AND (c.skill_code IS NULL OR c.status<>'READY' OR c.required_operation<>p.required_operation
      OR NOT(c.effect=ANY(p.allowed_effects)) OR
      (c.effect='WRITE_GOVERNED' AND NOT EXISTS(
       SELECT 1 FROM public.lf_profile_write_authority_v1 a
       WHERE a.profile_code=p_profile_code AND a.operation_code=c.required_operation AND a.status='ACTIVE')));
 IF v_missing>0 THEN RETURN jsonb_build_object('status','BLOCKED',
  'blocking_code','SKILL_POLICY_OR_CATALOG_INVALID','count',v_missing);END IF;
 SELECT count(*) INTO v_stale FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_selection_registry_v1 d ON d.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
 AND (d.skill_code IS NULL OR d.descriptor_status<>'CURRENT'
 OR d.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
 OR coalesce(d.source_revision,'')='');
 IF v_stale>0 THEN RETURN jsonb_build_object('status','BLOCKED',
  'blocking_code','SKILL_DESCRIPTOR_STALE_OR_MISSING','count',v_stale);END IF;
 FOR v_row IN SELECT p.skill_code,p.selection_mode,c.handler_fn,c.required_operation,
  c.effect,c.input_required,d.descriptor,d.source_ref,d.source_revision
 FROM public.lf_skill_selector_policy_v1 p
 JOIN public.lf_skill_catalog_v1 c USING(skill_code)
 JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
 ORDER BY p.skill_code LOOP
  v_ready:=jsonb_typeof(p_run_context)='object';
  FOREACH v_field IN ARRAY v_row.input_required LOOP
   IF v_field='request_text' THEN v_ready:=v_ready AND
     nullif(btrim(coalesce(p_run_context->>'request_text','')),'') IS NOT NULL;
   ELSIF v_field='profile_code' THEN v_ready:=v_ready AND
     p_run_context->>'profile_code'=p_profile_code;
   ELSIF v_field='scope' THEN v_ready:=v_ready AND
     jsonb_typeof(p_run_context->'scope')='object'
     AND p_run_context->'scope'<>'{}'::jsonb
     AND p_run_context#>>'{scope,resolution_status}'='RESOLVED';
   ELSIF v_field='consumer' THEN v_ready:=v_ready AND
     p_run_context->>'consumer'='CONTEXT_PACK';
   ELSIF v_field='pantalla_codigo' THEN v_ready:=v_ready AND
     nullif(p_run_context->>'pantalla_codigo','') IS NOT NULL;
   ELSIF v_field='target_code' THEN v_ready:=v_ready AND
     nullif(p_run_context->>'target_code','') IS NOT NULL;
   ELSIF v_field='target_path' THEN v_ready:=v_ready AND
     nullif(p_run_context->>'target_path','') IS NOT NULL;
   ELSE v_ready:=false;
   END IF;
  END LOOP;
  IF v_row.selection_mode='DETERMINISTIC_REQUIRED' AND v_ready THEN
    v_required:=v_required||jsonb_build_array(jsonb_build_object(
     'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
     'required_operation',v_row.required_operation,'effect',v_row.effect,
     'input_required',to_jsonb(v_row.input_required),
     'selection_mode','DETERMINISTIC_POLICY',
     'selection_evidence',jsonb_build_object('reason','REQUIRED_POLICY_INPUT_PRESENT',
     'descriptor_revision',v_row.source_revision,'source_ref',v_row.source_ref),
     'invoker','public.lf_skill_invoke_v1'));
  ELSIF v_ready THEN
    v_eligible:=v_eligible||jsonb_build_array(jsonb_build_object(
     'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
     'required_operation',v_row.required_operation,'effect',v_row.effect,
     'input_required',to_jsonb(v_row.input_required),'descriptor',v_row.descriptor,
     'source_ref',v_row.source_ref,'source_revision',v_row.source_revision));
  ELSE
    v_excluded:=v_excluded||jsonb_build_array(jsonb_build_object(
      'skill_code',v_row.skill_code,'reason','INPUT_REQUIRED_NOT_PRESENT_AT_RUN_STEP',
      'input_required',to_jsonb(v_row.input_required)));
  END IF;
 END LOOP;
 v_selected:=v_required;
 IF p_selection IS NULL THEN
   IF jsonb_array_length(v_eligible)=1
      AND v_eligible->0->>'effect'='READ_ONLY' THEN
      SELECT v_selected||jsonb_build_array(jsonb_build_object(
       'skill_code',x->>'skill_code','handler_fn',x->>'handler_fn',
       'required_operation',x->>'required_operation','effect',x->>'effect',
       'input_required',x->'input_required',
       'selection_mode','DETERMINISTIC_SINGLE_ELIGIBLE_READ_ONLY',
       'selection_evidence',jsonb_build_object(
         'reason','SINGLE_READ_ONLY_SKILL_WITH_VERIFIED_INPUT_REQUIRED',
         'descriptor_revision',x->>'source_revision',
         'source_ref',x->>'source_ref','run_step',p_run_context->>'step_id'),
       'invoker','public.lf_skill_invoke_v1')) INTO v_selected
       FROM jsonb_array_elements(v_eligible) x;
   END IF;
   RETURN jsonb_build_object('status','READY','skills',v_selected,
    'skill_candidates',v_eligible,'excluded_skills',v_excluded,
    'skill_selection_context',p_run_context,
    'profile_code',p_profile_code,'channel',p_channel,
    'selection_mode',CASE WHEN jsonb_array_length(v_eligible)=1
     AND v_eligible->0->>'effect'='READ_ONLY' THEN 'SINGLE_READ_ONLY_AUTO_SELECTED'
     ELSE 'OPTIONAL_UNSELECTED_FAIL_OPEN' END,
    'finding_code','SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED',
    'finding_status','SKILL_SELECTION_PENDING_FINDING',
    'continuation_allowed',true,'production_authorized',false,
    'next_action','SUBMIT_SKILL_SELECTION');
 END IF;
 IF jsonb_typeof(p_selection)<>'object' THEN RETURN jsonb_build_object('status','BLOCKED',
  'blocking_code','SKILL_SELECTION_CONTRACT_INVALID'); END IF;
 IF p_selection ? 'selected_skill_code' THEN
   IF NOT v_legacy OR p_selection ? 'selected_skill_codes' THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_LEGACY_CHOICE_NOT_ALLOWED');END IF;
   v_codes:=jsonb_build_array(p_selection->>'selected_skill_code');
 ELSE
   v_codes:=p_selection->'selected_skill_codes';
 END IF;
 IF jsonb_typeof(v_codes)<>'array' OR jsonb_array_length(v_codes)>v_hard_max THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_CARDINALITY_INVALID');END IF;
 IF v_codes='["ninguna"]'::jsonb THEN v_codes:='[]'::jsonb;END IF;
 v_reason:=nullif(btrim(coalesce(p_selection->>'reason','')),'');
 v_refs:=p_selection->'evidence_refs';
 v_revs:=p_selection->'descriptor_revisions';
 IF v_reason IS NULL OR
    (jsonb_array_length(v_codes)>0 AND
      (jsonb_typeof(v_refs)<>'array' OR jsonb_array_length(v_refs)=0
       OR p_selection->>'review_mode'<>'CURRENT_CONTEXT_REVIEW')) THEN
  RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_EVIDENCE_INVALID');END IF;
 SELECT count(*),count(DISTINCT x#>>'{}') INTO v_ncodes,v_n
 FROM jsonb_array_elements(v_codes) x;
 IF v_ncodes<>v_n OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_codes) x
  WHERE jsonb_typeof(x)<>'string' OR nullif(btrim(x#>>'{}'),'') IS NULL)
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_DUPLICATE_OR_INVALID');END IF;
 FOR v_code IN SELECT x#>>'{}' FROM jsonb_array_elements(v_codes) x LOOP
   v_rev:=CASE WHEN v_legacy AND p_selection ? 'selected_skill_code'
      THEN p_selection->>'descriptor_revision'
      ELSE v_revs->>v_code END;
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_eligible) x
     WHERE x->>'skill_code'=v_code AND x->>'source_revision'=v_rev) THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_NOT_ELIGIBLE_OR_STALE',
      'skill_code',v_code);END IF;
   SELECT v_selected||jsonb_build_array(jsonb_build_object(
     'skill_code',x->>'skill_code','handler_fn',x->>'handler_fn',
     'required_operation',x->>'required_operation','effect',x->>'effect',
     'input_required',x->'input_required','selection_mode','SKILL_DESCRIPTOR_SELECTED',
     'selection_evidence',jsonb_build_object('reason',v_reason,'evidence_refs',v_refs,
        'descriptor_revision',v_rev,'source_ref',x->>'source_ref',
        'review_mode','CURRENT_CONTEXT_REVIEW'),
     'invoker','public.lf_skill_invoke_v1')) INTO v_selected
   FROM jsonb_array_elements(v_eligible) x WHERE x->>'skill_code'=v_code;
 END LOOP;
 RETURN jsonb_build_object('status','READY','skills',v_selected,
  'skill_candidates',v_eligible,'excluded_skills',v_excluded,
  'skill_selection_context',p_run_context,'profile_code',p_profile_code,'channel',p_channel,
  'selection_mode','SKILL_DESCRIPTOR_SELECTED',
  'selection_reason',v_reason,
  'continuation_allowed',true,'production_authorized',false,
  'next_action','SUBMIT_SKILL_SELECTION');
END
$fn$;


CREATE OR REPLACE FUNCTION public.lf_profile_execution_plan_for_run_v1(
 p_execution_id text,p_skill_selection jsonb DEFAULT NULL::jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog','public'
AS $fn$
DECLARE v_run public.lf_operation_execution%ROWTYPE;
 v_step jsonb;v_scope jsonb;v_handoff jsonb;v_ctx jsonb;v_base jsonb;v_selector jsonb;
BEGIN
 SELECT * INTO v_run FROM public.lf_operation_execution e
 WHERE e.execution_id=p_execution_id AND e.operation_code='EJECUCION_PERFIL_LF'
   AND e.status='IN_PROGRESS';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED',
  'blocking_code','SKILL_PARENT_EXECUTION_NOT_ACTIVE');END IF;
 v_handoff:=v_run.manifest->'router_profile_handoff';
 IF jsonb_typeof(v_handoff)<>'object' OR nullif(v_handoff->>'literal_request','') IS NULL
 THEN RETURN jsonb_build_object('status','BLOCKED',
 'blocking_code','SKILL_SOURCE_HANDOFF_UNREADABLE');END IF;
 SELECT evidence_payload INTO v_step FROM public.lf_operation_execution_steps
 WHERE execution_id=p_execution_id AND step_id='input_validate'
  AND status='STEP_PASS_WITH_EVIDENCE';
 v_scope:=v_step->'resolved_scope';
 v_ctx:=jsonb_build_object(
  'execution_id',p_execution_id,
  'request_text',v_handoff->>'literal_request',
  'intent',v_handoff->'stage1_payload',
  'profile_code',v_run.target_code,
  'channel',v_handoff->>'channel',
  'step_id',CASE WHEN v_step IS NULL THEN 'profile_read' ELSE 'input_validate' END,
  'input_summary',jsonb_build_object('screen',v_scope->>'resolved_screen_code',
    'scope_resolution',v_scope->>'resolution_status','input_step_recorded',v_step IS NOT NULL),
  'scope',coalesce(v_scope,'{}'::jsonb),
  'consumer','CONTEXT_PACK',
  'pantalla_codigo',v_scope->>'resolved_screen_code',
  'target_code',v_run.target_code,'target_path',v_run.target_path,
  'legacy_run',v_run.created_at<'2026-11-14 19:00:00+00'::timestamptz
 );
 v_base:=public.lf_profile_execution_plan_v1(v_run.target_code,v_handoff->>'channel',null::jsonb);
 IF jsonb_typeof(v_base->'steps')<>'array' OR jsonb_array_length(v_base->'steps')<>11 THEN
  RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','SKILL_PARENT_STEP_CONTRACT_INVALID');END IF;
 v_selector:=public.lf_profile_skill_selection_prepare_v2(
    v_run.target_code,v_handoff->>'channel',
    coalesce(p_skill_selection,v_run.manifest->'skill_selection_v2'),v_ctx);
 RETURN v_base||jsonb_build_object('status',v_selector->>'status',
  'skills',coalesce(v_selector->'skills','[]'::jsonb),
  'selection_receipt',v_selector,
  'skill_candidates',v_selector->'skill_candidates',
  'skill_selection_context',v_ctx,
  'finding_status',v_selector->>'finding_status',
  'finding_code',v_selector->>'finding_code',
  'next_action',v_selector->>'next_action',
  'continuation_allowed',v_selector->'continuation_allowed')
  || CASE WHEN v_selector->>'status'='BLOCKED' THEN
     jsonb_build_object('blocking_code',v_selector->>'blocking_code')
     ELSE '{}'::jsonb END;
END
$fn$;

COMMIT;
