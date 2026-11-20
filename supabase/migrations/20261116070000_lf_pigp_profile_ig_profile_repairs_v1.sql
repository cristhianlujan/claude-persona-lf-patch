BEGIN;
DO $pigp$
DECLARE d text; d0 text;
BEGIN
  -- LF-PIGP-01: hydrate screen from the current semantically validated selector receipt,
  -- BEFORE skill selection and while Step40 is not yet recorded.
  d:=pg_get_functiondef('public.lf_profile_execution_plan_for_run_v1(text,jsonb)'::regprocedure);
  d0:=d;
  d:=replace(d,
    'v_input jsonb;v_ctx jsonb;v_decision jsonb;v_selected jsonb;v_oldplan jsonb;',
    'v_input jsonb;v_ctx jsonb;v_decision jsonb;v_selected jsonb;v_oldplan jsonb;v_screen_request jsonb;v_screen_validation jsonb;');
  d:=replace(d,
    $old$ v_input:=jsonb_build_object('execution_id',p_execution_id,$old$,
    $new$
 IF v_scope IS NULL AND upper(coalesce(v_handoff#>>'{scope,target_type}',''))='PANTALLA'
   AND jsonb_typeof(e.manifest->'screen_selection_result')='object' THEN
   v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
     v_handoff->>'literal_request',v_handoff->'scope');
   v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
     v_screen_request,e.manifest->'screen_selection_result');
   IF v_screen_validation->>'status'='VALID'
      AND v_screen_validation->>'decision'='SELECTED'
      AND nullif(v_screen_validation->>'selected_screen_code','') IS NOT NULL THEN
     v_scope:=coalesce(v_handoff->'scope','{}'::jsonb)||
       jsonb_build_object('resolved_screen_code',
         v_screen_validation->>'selected_screen_code',
         'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC');
   END IF;
 END IF;
 v_input:=jsonb_build_object('execution_id',p_execution_id,$new$);
  IF d=d0 OR position('v_screen_validation' IN d)=0 OR
     position('v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1' IN d)=0
  THEN RAISE EXCEPTION 'LF_PIGP01_SOURCE_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;

  -- LF-PIGP-02: selector findings stay selector findings, never IG findings.
  -- IG findings may exist ONLY when INPUT_GOVERNANCE_CONTEXT_PACK has a runtime receipt.
  d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
  d0:=d;
  d:=replace(d,
    $old$  v_skill_receipts jsonb:='[]'::jsonb;$old$,
    $new$  v_skill_receipts jsonb:='[]'::jsonb;
  v_skill_selection_findings jsonb:='[]'::jsonb;
  v_input_governance_findings jsonb:='[]'::jsonb;$new$);
  d:=replace(d,
    $old$    v_input:=v_input||jsonb_build_object(
      'skill_execution_receipts',$old$,
    $new$
    SELECT coalesce(jsonb_agg(f.value),'[]'::jsonb)
      INTO v_skill_selection_findings
      FROM jsonb_array_elements(v_skill_findings) f
      WHERE f.value->>'skill_code' IN
        ('SKILL_SELECTION','OPTIONAL_SKILL_SELECTION','SKILL_POLICY_SELECTION');
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_skill_receipts) r
               WHERE r.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
                 AND jsonb_typeof(r.value->'result')='object') THEN
      SELECT coalesce(jsonb_agg(f.value),'[]'::jsonb)
        INTO v_input_governance_findings
        FROM jsonb_array_elements(v_skill_findings) f
        WHERE f.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK';
      IF jsonb_typeof(v_skill_ig->'findings')='array' THEN
        v_input_governance_findings:=v_input_governance_findings||
          (v_skill_ig->'findings');
      END IF;
    END IF;
    v_input:=v_input||jsonb_build_object(
      'skill_selection_findings',v_skill_selection_findings,
      'input_governance_findings',v_input_governance_findings,
      'skill_execution_receipts',$new$);
  d:=replace(d,
    'when jsonb_array_length(v_skill_findings)>0 then',
    'when jsonb_array_length(v_input_governance_findings)>0 then');
  IF d=d0 OR position('v_input_governance_findings jsonb' IN d)=0 OR
     position('when jsonb_array_length(v_skill_findings)>0 then' IN d)>0
  THEN RAISE EXCEPTION 'LF_PIGP02_STEP40_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
  d0:=d;
  d:=replace(d,
    $old$  IF v_input->>'analysis_scope'='READ_ONLY_WITH_IG_FINDINGS' THEN$old$,
    $new$  IF v_input->>'analysis_scope'='READ_ONLY_WITH_IG_FINDINGS'
     AND jsonb_typeof(v_input->'input_governance_findings')='array'
     AND jsonb_array_length(v_input->'input_governance_findings')>0
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(
            coalesce(v_input->'skill_execution_receipts','[]'::jsonb)) r
        WHERE r.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
          AND jsonb_typeof(r.value->'result')='object') THEN$new$);
  IF d=d0 OR position('jsonb_array_length(v_input->''input_governance_findings'')>0' IN d)=0
  THEN RAISE EXCEPTION 'LF_PIGP02_STEP80_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;
END $pigp$;
COMMIT;
