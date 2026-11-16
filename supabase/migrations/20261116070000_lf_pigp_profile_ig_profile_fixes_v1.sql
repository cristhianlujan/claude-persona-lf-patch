BEGIN;
DO $pigp$
DECLARE d text; d0 text;
BEGIN
  -- LF-PIGP-01: resolve a validated screen selection from the same run BEFORE
  -- Step40 persists input_validate; never grant eligibility from unsigned hints.
  d:=pg_get_functiondef('public.lf_profile_execution_plan_for_run_v1(text,jsonb)'::regprocedure);
  d0:=d;
  d:=replace(d,$s$v_input jsonb;v_ctx jsonb;$s$,
    $s$v_input jsonb;v_ctx jsonb;
 v_screen_request jsonb; v_screen_validation jsonb;$s$);
  d:=replace(d,$s$ v_input:=jsonb_build_object('execution_id',p_execution_id,$s$,
  $s$ IF (v_scope IS NULL OR v_scope='{}'::jsonb)
     AND e.manifest#>>'{screen_selection_result,decision}'='SELECTED'
     AND nullif(e.manifest#>>'{screen_selection_result,selected_screen_code}','') IS NOT NULL
 THEN
   v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
     v_handoff->>'literal_request',v_handoff->'scope');
   v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
     v_screen_request,e.manifest->'screen_selection_result');
   IF v_screen_validation->>'status'='VALID' THEN
      v_scope:=coalesce(v_handoff->'scope','{}'::jsonb)||
        jsonb_build_object('resolved_screen_code',
          e.manifest#>>'{screen_selection_result,selected_screen_code}',
          'resolution_status','RESOLVED');
   END IF;
 END IF;
 v_input:=jsonb_build_object('execution_id',p_execution_id,$s$);
  IF d=d0 OR position('v_screen_validation' in d)=0
    OR position('selected_screen_code' in d)=0 THEN
    RAISE EXCEPTION 'LF_PIGP_01_SOURCE_OR_SCREEN_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;

  -- LF-PIGP-02: separate skill selection findings from actual IG findings.
  -- E12 governed repair takes precedence over read-only IG findings.
  d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
  d0:=d;
  IF position('GOVERNED_REPAIR' in d)=0 THEN
    RAISE EXCEPTION 'LF_PIGP_E12_GOVERNED_REPAIR_BASE_NOT_INSTALLED';
  END IF;
  d:=replace(d,$s$v_skill_findings jsonb:='[]'::jsonb;$s$,
    $s$v_skill_findings jsonb:='[]'::jsonb;
  v_input_governance_findings jsonb:='[]'::jsonb;$s$);
  d:=replace(d,$s$    v_input:=v_input||jsonb_build_object($s$,
    $s$    FOR v_skill_item IN SELECT value FROM jsonb_array_elements(v_skill_receipts)
    LOOP
      IF v_skill_item->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
         AND (v_skill_item#>>'{result,status}' NOT IN
               ('READY','COMPLETED','SKIPPED','PASS')
              OR v_skill_ig->>'status'='BLOCKED') THEN
        v_input_governance_findings:=v_input_governance_findings||
          jsonb_build_array(v_skill_item);
      END IF;
    END LOOP;
    v_input:=v_input||jsonb_build_object(
      'input_governance_findings',v_input_governance_findings,
      'skill_selection_findings',coalesce(
        (SELECT jsonb_agg(f) FROM jsonb_array_elements(v_skill_findings) f
         WHERE f->>'skill_code' IN ('SKILL_SELECTION','OPTIONAL_SKILL_SELECTION')
         OR f->>'finding_code' IN
           ('SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED','SKILL_SELECTION_PENDING_FINDING')),
         '[]'::jsonb),$s$);
  d:=replace(d,'jsonb_array_length(v_skill_findings)>0',
               'jsonb_array_length(v_input_governance_findings)>0');
  IF d=d0 OR position('v_input_governance_findings jsonb' in d)=0
   OR position('skill_selection_findings' in d)=0
   OR position('jsonb_array_length(v_skill_findings)>0' in d)>0
  THEN RAISE EXCEPTION 'LF_PIGP_02_STEP40_SOURCE_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;

  -- Step80: only an actual INPUT_GOVERNANCE_CONTEXT_PACK execution receipt
  -- with IG findings can set ig_findings_reported=true.
  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
  d0:=d;
  d:=replace(d,$s$  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';$s$,
    $s$  IF v_input->>'analysis_scope'='GOVERNED_REPAIR'
     AND jsonb_typeof(v_input->'input_governance_findings')='array'
     AND jsonb_array_length(v_input->'input_governance_findings')>0
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(
        coalesce(v_input->'skill_execution_receipts','[]'::jsonb)) ig
        WHERE ig->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK') THEN
      v_report_findings:=jsonb_build_object(
        'analysis_scope','GOVERNED_REPAIR',
        'input_governance_findings',v_input->'input_governance_findings',
        'mutation_authorized',v_input->'mutation_authorized',
        'promotion_authorized',false);
  END IF;
  v_candidate:=v_semantic.evidence_payload#>>'{semantic_judge_result,candidate_sha256}';$s$);
  d:=replace(d,$s$'ig_findings_reported',true$s$,
    $s$'ig_findings_reported',(
      coalesce(jsonb_array_length(v_input->'input_governance_findings'),0)>0
      AND EXISTS(SELECT 1 FROM jsonb_array_elements(
         coalesce(v_input->'skill_execution_receipts','[]'::jsonb)) ig
         WHERE ig->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'))$s$);
  IF d=d0 OR position('ig_findings_reported' in d)=0
    OR position('input_governance_findings' in d)=0
    OR position($s$'ig_findings_reported',true$s$ in d)>0
  THEN RAISE EXCEPTION 'LF_PIGP_02_STEP80_SOURCE_PATCH_NOT_APPLIED'; END IF;
  EXECUTE d;
END $pigp$;
COMMIT;
