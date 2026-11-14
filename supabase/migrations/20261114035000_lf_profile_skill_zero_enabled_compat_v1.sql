-- Emergency hotfix for regression introduced by PR #3845 / merge d4780da.
-- READBACK preimage: md5(pg_get_functiondef)=dc2dabde35b7d8e696ba6edbfd5cc39b.
-- Change ONLY v_n=0 return; all enabled policy and currentness gates preserved.
-- No policy activation, no extra gate, no second route; existing Step40 remains authoritative.
CREATE OR REPLACE FUNCTION public.lf_profile_skill_selection_prepare_v1(p_profile_code text, p_channel text, p_semantic_decision jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v_n int;
 v_missing int;
 v_stale int;
 v_required jsonb:='[]'::jsonb;
 v_optional jsonb:='[]'::jsonb;
 v_selected jsonb:='[]'::jsonb;
 v_choice text;
 v_reason text;
 v_refs jsonb;
 v_revision text;
 v_row record;
 v_sem_n int;
BEGIN
 IF nullif(btrim(coalesce(p_profile_code,'')),'') IS NULL OR
    coalesce(p_channel,'') NOT IN ('PRODUCTO','PROGRAMACION','OPERACIONES')
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_CHANNEL_INVALID'); END IF;
 -- Follow the existing profile selector registry/policy: no unauthorized profile+channel.
 IF NOT EXISTS (
    SELECT 1 FROM public.lf_profile_selection_registry_v1 d
    JOIN public.lf_profile_selector_policy_v1 p USING(profile_code)
    WHERE d.profile_code=p_profile_code AND d.descriptor_status='CURRENT'
      AND p_channel=ANY(p.channels))
 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SELECTION_PROFILE_SOURCE_OR_CHANNEL_NOT_CURRENT'); END IF;

 -- 'enabled' alone is not owner authorization in a candidate row.
 IF EXISTS (SELECT 1 FROM public.lf_skill_selector_policy_v1 p
   WHERE p.profile_code=p_profile_code AND p.enabled
     AND p_channel=ANY(p.channels) AND p.owner_decision_required) THEN
   RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_OWNER_DECISION_REQUIRED');
 END IF;
 SELECT count(*) INTO v_n FROM public.lf_skill_selector_policy_v1 p
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels);
 IF v_n=0 THEN
    RETURN jsonb_build_object('status','READY','skills','[]'::jsonb,
      'profile_code',p_profile_code,'channel',p_channel,
      'selection_mode','NO_ENABLED_SKILL_POLICY_LEGACY_STEP40_COMPAT');
 END IF;
 SELECT count(*) INTO v_missing
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_catalog_v1 c ON c.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND (c.skill_code IS NULL OR c.status<>'READY' OR c.required_operation<>p.required_operation
        OR NOT(c.effect=ANY(p.allowed_effects))
        OR (c.effect='WRITE_GOVERNED' AND NOT EXISTS (
            SELECT 1 FROM public.lf_profile_write_authority_v1 a
            WHERE a.profile_code=p_profile_code AND a.operation_code=c.required_operation
              AND a.status='ACTIVE')));
 IF v_missing>0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DETERMINISTIC_POLICY_OR_CATALOG_INVALID',
       'invalid_bindings',v_missing);
 END IF;
 SELECT count(*) INTO v_stale
 FROM public.lf_skill_selector_policy_v1 p
 LEFT JOIN public.lf_skill_selection_registry_v1 d ON d.skill_code=p.skill_code
 WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
   AND (d.skill_code IS NULL OR d.descriptor_status<>'CURRENT'
        OR d.descriptor->>'schema_version'<>'LF_SKILL_SELECTION_DESCRIPTOR_V1'
        OR coalesce(d.source_revision,'')='');
 IF v_stale>0 THEN
    RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_DESCRIPTOR_STALE_OR_MISSING',
       'stale_count',v_stale);
 END IF;
 FOR v_row IN
   SELECT p.skill_code,p.selection_mode,c.handler_fn,c.required_operation,c.effect,
          c.input_required,d.descriptor,d.source_ref,d.source_revision
     FROM public.lf_skill_selector_policy_v1 p
     JOIN public.lf_skill_catalog_v1 c USING(skill_code)
     JOIN public.lf_skill_selection_registry_v1 d USING(skill_code)
    WHERE p.profile_code=p_profile_code AND p.enabled AND p_channel=ANY(p.channels)
    ORDER BY p.skill_code
 LOOP
   IF v_row.selection_mode='DETERMINISTIC_REQUIRED' THEN
     v_required:=v_required||jsonb_build_array(jsonb_build_object(
       'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
       'required_operation',v_row.required_operation,'effect',v_row.effect,
       'input_required',to_jsonb(v_row.input_required),'selection_mode','DETERMINISTIC_POLICY',
       'selection_evidence',jsonb_build_object('reason','MANDATORY_POLICY_FOR_PROFILE_AND_CHANNEL',
         'descriptor_revision',v_row.source_revision,'source_ref',v_row.source_ref),
       'invoker','public.lf_skill_invoke_v1'));
   ELSE
     v_optional:=v_optional||jsonb_build_array(jsonb_build_object(
       'skill_code',v_row.skill_code,'handler_fn',v_row.handler_fn,
       'required_operation',v_row.required_operation,'effect',v_row.effect,
       'input_required',to_jsonb(v_row.input_required),'descriptor',v_row.descriptor,
       'source_ref',v_row.source_ref,'source_revision',v_row.source_revision));
   END IF;
 END LOOP;
 IF jsonb_array_length(v_optional)=0 THEN
   IF p_semantic_decision IS NOT NULL THEN
     RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_UNEXPECTED_SEMANTIC_DECISION');
   END IF;
   v_selected:=v_required;
 ELSE
   IF p_semantic_decision IS NULL THEN
     RETURN jsonb_build_object('status','SEMANTIC_SELECTION_REQUIRED',
       'blocking_code',null,'required_skills',v_required,
       'semantic_candidates',v_optional,'profile_code',p_profile_code,'channel',p_channel,
       'selection_mode','DETERMINISTIC_FILTER_THEN_NATIVE_SEMANTIC',
       'next_action','NATIVE_PROFILE_JUDGE_SKILL_AND_SUBMIT_SAME_EXECUTION');
   END IF;
   IF jsonb_typeof(p_semantic_decision)<>'object' OR
      p_semantic_decision ? 'selected_skill_codes' OR
      jsonb_typeof(p_semantic_decision->'selected_skill_code')<>'string'
   THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_SELECTION_AMBIGUOUS'); END IF;
   v_choice:=nullif(btrim(p_semantic_decision->>'selected_skill_code'),'');
   v_reason:=nullif(btrim(p_semantic_decision->>'reason'),'');
   v_refs:=p_semantic_decision->'evidence_refs';
   v_revision:=p_semantic_decision->>'descriptor_revision';
   SELECT count(*) INTO v_sem_n FROM jsonb_array_elements(v_optional) x
   WHERE x->>'skill_code'=v_choice AND x->>'source_revision'=v_revision;
   IF v_sem_n<>1 THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_CHOICE_NOT_ALLOWED_OR_STALE'); END IF;
   IF v_reason IS NULL OR jsonb_typeof(v_refs)<>'array' OR jsonb_array_length(v_refs)=0
      OR coalesce(p_semantic_decision->>'review_mode','')<>'CURRENT_CONTEXT_REVIEW' THEN
      RETURN jsonb_build_object('status','BLOCKED','blocking_code','SKILL_SEMANTIC_EVIDENCE_MISSING');
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'skill_code',x->>'skill_code','handler_fn',x->>'handler_fn',
      'required_operation',x->>'required_operation','effect',x->>'effect',
      'input_required',x->'input_required','selection_mode','SEMANTIC_DESCRIPTOR',
      'selection_evidence',jsonb_build_object('reason',v_reason,'evidence_refs',v_refs,
        'descriptor_revision',v_revision,'source_ref',x->>'source_ref',
        'review_mode','CURRENT_CONTEXT_REVIEW'),
      'invoker','public.lf_skill_invoke_v1')),'[]'::jsonb)
   INTO v_selected FROM jsonb_array_elements(v_optional) x
   WHERE x->>'skill_code'=v_choice;
   v_selected:=v_required||v_selected;
 END IF;
 RETURN jsonb_build_object('status','READY','skills',v_selected,
   'profile_code',p_profile_code,'channel',p_channel,
   'selection_mode','DETERMINISTIC_THEN_SEMANTIC',
   'source','lf_skill_selector_policy_v1+lf_skill_selection_registry_v1+lf_skill_catalog_v1',
   'independence_attested',false);
END;
$function$;
