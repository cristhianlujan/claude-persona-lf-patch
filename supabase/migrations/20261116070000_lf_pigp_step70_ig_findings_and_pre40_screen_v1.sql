-- LF-PIGP-01/02: bind validated screen before Step40; distinguish IG from optional skill findings.
-- Exact live source guards; a changed upstream definition aborts without partial replacement.
BEGIN;
DO $pigp$
DECLARE d text; d0 text;
BEGIN
  d:=pg_get_functiondef('public.lf_profile_execution_plan_for_run_v1(text,jsonb)'::regprocedure);
  IF md5(d)<>'2dd5b6570e5a4b5cc08b2905ef2dae57' THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_execution_plan_for_run_v1';
  END IF;
  d0:=d;
  d:=replace(d,
    $old$ v_input:=jsonb_build_object('execution_id',p_execution_id,$old$,
    $new$ -- Resolve only a semantically selected and VALIDATED manifest screen.
 -- This also works before input_validate/Step40 has persisted its evidence.
 IF (jsonb_typeof(v_scope) IS DISTINCT FROM 'object'
     OR nullif(v_scope->>'resolved_screen_code','') IS NULL)
    AND e.manifest#>>'{screen_selection_result,decision}'='SELECTED'
    AND e.manifest#>>'{screen_selection_validation,status}'='VALID'
    AND e.manifest#>>'{screen_selection_validation,decision}'='SELECTED'
    AND nullif(e.manifest#>>'{screen_selection_result,selected_screen_code}','') IS NOT NULL
    AND e.manifest#>>'{screen_selection_result,selected_screen_code}'
        = e.manifest#>>'{screen_selection_validation,selected_screen_code}' THEN
   v_scope:=coalesce(v_handoff->'scope','{}'::jsonb)
      ||jsonb_build_object('resolution_status','RESOLVED',
       'resolved_screen_code',e.manifest#>>'{screen_selection_result,selected_screen_code}',
       'resolution_method','DETERMINISTIC_SHORTLIST_THEN_SEMANTIC');
 END IF;
 v_input:=jsonb_build_object('execution_id',p_execution_id,$new$);
  IF d=d0 OR position('screen_selection_validation,status' IN d)=0 THEN
    RAISE EXCEPTION 'LF_PIGP_01_PRE40_SCREEN_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
  IF md5(d)<>'f32dd30ddc095401eaa01e1499c924b8' THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_native_bridge_prepare_v1';
  END IF;
  d0:=d;
  d:=replace(d,
    $old$  v_skill_findings jsonb:='[]'::jsonb;$old$,
    $new$  v_skill_findings jsonb:='[]'::jsonb;
  v_skill_selection_findings jsonb:='[]'::jsonb;
  v_input_governance_findings jsonb:='[]'::jsonb;$new$);
  d:=replace(d,
    $old$    v_input:=v_input||jsonb_build_object(
      'skill_execution_receipts',$old$,
    $new$    -- A selector finding is NOT an Input Governance finding.
    v_skill_selection_findings:=coalesce((
      SELECT jsonb_agg(f.value)
      FROM jsonb_array_elements(v_skill_findings) AS f(value)
      WHERE f.value->>'skill_code' IN ('SKILL_SELECTION','OPTIONAL_SKILL_SELECTION')
         OR coalesce(f.value->>'blocking_code',f.value->>'finding_code','')
              IN ('SKILL_SEMANTIC_SELECTION_NOT_SUBMITTED','SKILL_SELECTION_PENDING_FINDING',
                  'SKILL_OPTIONAL_SEMANTIC_DECISION_DEFERRED')
    ),'[]'::jsonb);
    -- Never classify as IG without an actual execution receipt for that exact skill.
    v_input_governance_findings:=coalesce((
      SELECT jsonb_agg(f.value)
      FROM jsonb_array_elements(v_skill_findings) AS f(value)
      WHERE f.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
        AND EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_skill_receipts) AS r(value)
          WHERE r.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
            AND jsonb_typeof(r.value->'result')='object')
    ),'[]'::jsonb);
    v_input:=v_input||jsonb_build_object(
      'skill_selection_findings',v_skill_selection_findings,
      'input_governance_findings',v_input_governance_findings,
      'skill_execution_receipts',$new$);
  d:=replace(d,
     'when jsonb_array_length(v_skill_findings)>0',
     'when jsonb_array_length(v_input_governance_findings)>0');
  IF d=d0 OR position('v_input_governance_findings jsonb' IN d)=0
     OR position('v_input_governance_findings' IN d)=0
     OR position('skill_selection_findings' IN d)=0
     OR position('when jsonb_array_length(v_skill_findings)>0' IN d)>0 THEN
     RAISE EXCEPTION 'LF_PIGP_02_PREPARE_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;

  d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
  IF md5(d)<>'975a9d1ab81898f39dab93c058edf682' THEN
    RAISE EXCEPTION 'SOURCE_STATE_DRIFT:lf_profile_native_bridge_record_report_v1';
  END IF;
  d0:=d;
  d:=replace(d,
    $old$      ) || CASE WHEN v_report_findings IS NOT NULL
           THEN jsonb_build_object('ig_findings',v_report_findings,
                                   'ig_findings_reported',true)$old$,
    $new$      ) || CASE WHEN v_report_findings IS NOT NULL
           AND EXISTS (
             SELECT 1
             FROM jsonb_array_elements(coalesce(v_input->'skill_execution_receipts','[]'::jsonb)) AS r(value)
             WHERE r.value->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
               AND jsonb_typeof(r.value->'result')='object')
           THEN jsonb_build_object('ig_findings',v_report_findings,
                                   'ig_findings_reported',true)$new$);
  IF d=d0 OR position('r.value->>''skill_code''=''INPUT_GOVERNANCE_CONTEXT_PACK''' IN d)=0 THEN
    RAISE EXCEPTION 'LF_PIGP_02_REPORT_PATCH_NOT_APPLIED';
  END IF;
  EXECUTE d;
END $pigp$;
COMMIT;
