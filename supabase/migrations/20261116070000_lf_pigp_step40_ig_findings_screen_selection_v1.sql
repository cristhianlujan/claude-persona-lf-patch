BEGIN;
-- LF-PIGP-01 / LF-PIGP-02: patches are bound to the installed live PL/pgSQL
-- functions, with fail-closed pattern preimages and no historical run rewrites.
DO $pigp$
DECLARE
 d text; d0 text;
 marker text;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_execution_plan_for_run_v1(text,jsonb)'::regprocedure);
 d0:=d;
 IF position('v_input jsonb;v_ctx jsonb;' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_01_PLAN_DECLARATION_DRIFT';
 END IF;
 d:=replace(d,'v_input jsonb;v_ctx jsonb;',
   'v_input jsonb;v_ctx jsonb;v_screen_request jsonb;v_screen_validation jsonb;');
 marker:=$m$ AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 v_input:=jsonb_build_object($m$;
 IF position(marker in d)=0 THEN RAISE EXCEPTION 'LF_PIGP_01_PLAN_SCOPE_DRIFT'; END IF;
 d:=replace(d,marker,$m$ AND step_id='input_validate' AND status='STEP_PASS_WITH_EVIDENCE';
 -- Before Step40 is persisted, consume the current, semantically validated
 -- per-run selection receipt. Never infer a screen from unvalidated hint text.
 IF v_scope IS NULL
   AND upper(coalesce(v_handoff#>>'{scope,target_type}',''))='PANTALLA'
   AND e.manifest#>>'{screen_selection_result,decision}'='SELECTED'
 THEN
   v_screen_request:=public.lf_profile_screen_selector_semantic_prepare_v1(
     v_handoff->>'literal_request',v_handoff->'scope');
   v_screen_validation:=public.lf_profile_screen_selector_semantic_validate_v1(
     v_screen_request,e.manifest->'screen_selection_result');
   IF v_screen_validation->>'status'='VALID' THEN
     v_scope:=coalesce(v_handoff->'scope','{}'::jsonb)||jsonb_build_object(
       'resolved_screen_code',e.manifest#>>'{screen_selection_result,selected_screen_code}',
       'resolution_status','RESOLVED',
       'resolution_method','VALIDATED_PRE_STEP40_SEMANTIC_SELECTION');
   END IF;
 END IF;
 v_input:=jsonb_build_object($m$);
 IF d=d0 OR position('VALIDATED_PRE_STEP40_SEMANTIC_SELECTION' in d)=0
    OR position('v_screen_validation' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_01_NOT_APPLIED';
 END IF;
 EXECUTE d;

 d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
 d0:=d;
 IF position('GOVERNED_REPAIR' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_REQUIRES_E12_GOVERNED_SCOPE';
 END IF;
 IF position('v_skill_findings jsonb:=''[]''::jsonb;' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_FINDINGS_DECLARATION_DRIFT';
 END IF;
 d:=replace(d,'v_skill_findings jsonb:=''[]''::jsonb;',
   'v_skill_findings jsonb:=''[]''::jsonb;'||E'\n  '||
   'v_input_governance_findings jsonb:=''[]''::jsonb;');
 marker:=$m$      IF v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' THEN
        v_skill_ig:=coalesce($m$;
 IF position(marker in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_IG_RECEIPT_ANCHOR_DRIFT';
 END IF;
 d:=replace(d,marker,$m$      IF v_skill_code='INPUT_GOVERNANCE_CONTEXT_PACK' THEN
        -- This branch is reached only after an actual skill execution receipt
        -- has been appended. Unrelated selector findings cannot masquerade as IG.
        IF v_skill_result->>'status' NOT IN ('READY','COMPLETED','SKIPPED','PASS') THEN
          v_input_governance_findings:=v_input_governance_findings||
            jsonb_build_array(jsonb_build_object(
              'skill_code','INPUT_GOVERNANCE_CONTEXT_PACK',
              'status','IG_SKILL_FAILED_AS_FINDING',
              'blocking_code',coalesce(v_skill_result->>'blocking_code',
                                      v_skill_result->>'status','IG_SKILL_FAILED')));
        END IF;
        IF jsonb_typeof(v_skill_result#>'{output,input_governance,content_findings}')='array' THEN
          v_input_governance_findings:=v_input_governance_findings||
            (v_skill_result#>'{output,input_governance,content_findings}');
        END IF;
        v_skill_ig:=coalesce($m$);
 IF position('''skill_findings'',v_skill_findings,' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_FINAL_OUTPUT_DRIFT';
 END IF;
 d:=replace(d,'''skill_findings'',v_skill_findings,',
   $m$'skill_findings',v_skill_findings,
      'skill_selection_findings',coalesce((
        SELECT jsonb_agg(t.value) FROM jsonb_array_elements(v_skill_findings) AS t(value)
        WHERE t.value->>'skill_code' IN
          ('SKILL_SELECTION','OPTIONAL_SKILL_SELECTION','SKILL_POLICY_SELECTION')
      ),'[]'::jsonb),
      'input_governance_findings',v_input_governance_findings,$m$);
 IF (length(d)-length(replace(d,
      'jsonb_array_length(v_skill_findings)>0 then ''READ_ONLY_WITH_IG_FINDINGS''','')))
      / length('jsonb_array_length(v_skill_findings)>0 then ''READ_ONLY_WITH_IG_FINDINGS''') <> 2
 THEN RAISE EXCEPTION 'LF_PIGP_02_ANALYSIS_SCOPE_PATTERN_COUNT_DRIFT'; END IF;
 d:=replace(d,
  'jsonb_array_length(v_skill_findings)>0 then ''READ_ONLY_WITH_IG_FINDINGS''',
  'jsonb_array_length(v_input_governance_findings)>0 then ''READ_ONLY_WITH_IG_FINDINGS''');
 IF d=d0 OR position('''input_governance_findings'',v_input_governance_findings' in d)=0
    OR position('jsonb_array_length(v_input_governance_findings)>0' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_PREPARE_NOT_APPLIED';
 END IF;
 EXECUTE d;

 d:=pg_get_functiondef('public.lf_profile_native_bridge_record_report_v1(text,text,text)'::regprocedure);
 d0:=d;
 marker:=$m$CASE WHEN v_report_findings IS NOT NULL
           THEN jsonb_build_object('ig_findings',v_report_findings,$m$;
 IF position(marker in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_REPORT_RECEIPT_ANCHOR_DRIFT';
 END IF;
 d:=replace(d,marker,$m$CASE WHEN v_report_findings IS NOT NULL
         AND EXISTS (
           SELECT 1 FROM jsonb_array_elements(
             CASE WHEN jsonb_typeof(v_input->'skill_execution_receipts')='array'
               THEN v_input->'skill_execution_receipts' ELSE '[]'::jsonb END
           ) AS ir(receipt)
           WHERE ir.receipt->>'skill_code'='INPUT_GOVERNANCE_CONTEXT_PACK'
         )
           THEN jsonb_build_object('ig_findings',v_report_findings,$m$);
 IF d=d0 OR position('ir.receipt->>''skill_code''=''INPUT_GOVERNANCE_CONTEXT_PACK''' in d)=0 THEN
   RAISE EXCEPTION 'LF_PIGP_02_REPORT_NOT_APPLIED';
 END IF;
 EXECUTE d;
END $pigp$;
COMMIT;
