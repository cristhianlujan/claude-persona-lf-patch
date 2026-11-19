-- FASE 2: exact native Product Director RAW/contract proof for 2 writer negatives
-- plus one full-fidelity replacement candidate. No rule/owner/skill data changes.
-- PG17 BEGIN/ROLLBACK. Follows existing REAL Train -> Step70 -> owner V2 workflow.
BEGIN;
DO $lf_ig_three_raw_contract$
DECLARE
 v record; v_p jsonb; v_scope text; v_ids jsonb; v_expected text;
 v_old_cfg jsonb; v_count integer; v_initial text; v_final text;
 v_before_hist text; v_after_hist text; v_before_link text; v_after_link text;
BEGIN
 IF current_setting('server_version_num')::int / 10000 <> 17 THEN RAISE EXCEPTION 'IG_PG17_REQUIRED'; END IF;
 IF (SELECT count(*) FROM lf_ops.reglas)<>586 OR (SELECT count(*) FROM lf_ops.reglas_versiones)<>586
 THEN RAISE EXCEPTION 'IG_PG17_BASELINE_RULE_HISTORY_DRIFT'; END IF;
 SELECT valor_config INTO STRICT v_old_cfg FROM lf_ops.reglas
 WHERE codigo='B2B-RULE-VALIDATION-VALID-ONLY-001' AND estado='VIGENTE';
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_initial FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.codigo,h.version)::text,'[]')) INTO v_before_hist FROM lf_ops.reglas_versiones h;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id)::text,'[]')) INTO v_before_link FROM lf_ops.reglas_pantallas x;
 IF (SELECT array_agg(pantalla_id ORDER BY pantalla_id) FROM lf_ops.reglas_pantallas
  WHERE regla_id=(SELECT id FROM lf_ops.reglas WHERE codigo='B2B-RULE-VALIDATION-VALID-ONLY-001'))
   IS DISTINCT FROM ARRAY[44,66,67]::integer[] THEN RAISE EXCEPTION 'IG_PILOT_SCREEN_PREIMAGE_DRIFT'; END IF;
 IF (SELECT count(*) FROM lf_ops.regla_behavior_tests WHERE regla_codigo='B2B-RULE-VALIDATION-VALID-ONLY-001')<>1
 THEN RAISE EXCEPTION 'IG_PILOT_TEST_PREIMAGE_DRIFT'; END IF;
 FOR v IN SELECT * FROM (VALUES
 ('IG-PG17-NEG-SCOPE-001','EXEC-PROFILE-GATE2-E07A0C5B0789A44D1C2290C7','5449006f64ddf4c41ab405a4d952d37ca6fb903e4b2a7b22797ad8c6a9704d2e','MISSING_SCOPE'),
 ('IG-PG17-NEG-SCREEN-001','EXEC-PROFILE-GATE2-1AA506CAB88F4B1C0796AB6A','c8642124cc2348e408c6a52d5707d4206528b6c159889c9f3f16e9825bce70cc','MISSING_SCREEN'),
 ('B2B-RULE-VALIDATION-VALID-ONLY-002','EXEC-PROFILE-GATE2-8C1E23C6BB73FFDA7B9F88B5','f08fc4166cddd37b8d4c17157cb09b45039264a7ab0bb0da162f75cbffe51e9a','PILOT_REPLACEMENT')
 ) s(code,parent,sha,test_kind) LOOP
    SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
     INTO STRICT v_p FROM public.lf_operation_execution_steps s
     JOIN public.lf_operation_execution p ON p.execution_id=s.execution_id
     WHERE s.execution_id=v.parent AND s.step_id='execute_profile'
       AND s.status='STEP_PASS_WITH_EVIDENCE'
       AND p.operation_code='EJECUCION_PERFIL_LF'
       AND p.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
       AND p.status='IN_PROGRESS'
       AND p.manifest->>'read_only'='true'
       AND p.manifest->>'no_write'='true'
       AND p.manifest#>>'{screen_selection_result,selected_screen_code}'='B2B-CARGA-002'
       AND s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'='PERFIL-PRODUCT-DIRECTOR-LF';
    IF v_p->>'rule_code' IS DISTINCT FROM v.code
      OR v_p->>'change_kind' IS DISTINCT FROM 'CREATE'
      OR encode(extensions.digest(convert_to(v_p::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM v.sha
      OR NOT EXISTS (SELECT 1 FROM public.lf_operation_execution_steps s
       WHERE s.execution_id=v.parent AND s.step_id='output_validate'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload->>'output_contract_result'='PASS')
      OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v.code)
      OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v.code)
    THEN RAISE EXCEPTION 'IG_PG17_RAW_OR_SHA_OR_STEP60_DRIFT:%',v.code; END IF;
    v_scope:=v_p#>>'{changes,valor_config,lf_rule_scope}';
    v_ids:=v_p#>'{changes,valor_config,lf_screen_ids}';
    IF v.test_kind='MISSING_SCOPE' AND
       (v_scope IS NOT NULL OR v_ids IS DISTINCT FROM '[44]'::jsonb) THEN
         RAISE EXCEPTION 'IG_NEG_SCOPE_DEFECT_NOT_EXACT'; END IF;
    IF v.test_kind='MISSING_SCREEN' AND
       (v_scope IS DISTINCT FROM 'PANTALLA' OR v_ids IS DISTINCT FROM '[]'::jsonb) THEN
         RAISE EXCEPTION 'IG_NEG_SCREEN_DEFECT_NOT_EXACT'; END IF;
    IF v.test_kind='PILOT_REPLACEMENT' AND
       (v_scope IS DISTINCT FROM 'PANTALLA'
        OR v_ids IS DISTINCT FROM '[44,66,67]'::jsonb
        OR (((v_p#>'{changes,valor_config}')
         - 'lf_rule_scope' - 'lf_screen_ids' - 'lf_applicability'
         - 'lf_replaces_rule_code' - 'lf_promotion_authorized'))
          IS DISTINCT FROM v_old_cfg
        OR v_p#>>'{changes,valor_config,lf_replaces_rule_code}'
            IS DISTINCT FROM 'B2B-RULE-VALIDATION-VALID-ONLY-001') THEN
         RAISE EXCEPTION 'IG_PILOT_LEGACY_CONFIG_NOT_PRESERVED'; END IF;
    RAISE NOTICE 'LF_IG_06_RAW_CONTRACT_PASS:%:%:%',v.test_kind,v.code,v.sha;
 END LOOP;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]')) INTO v_final FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.codigo,h.version)::text,'[]')) INTO v_after_hist FROM lf_ops.reglas_versiones h;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id)::text,'[]')) INTO v_after_link FROM lf_ops.reglas_pantallas x;
 IF v_final IS DISTINCT FROM v_initial OR v_after_hist IS DISTINCT FROM v_before_hist
    OR v_after_link IS DISTINCT FROM v_before_link
 THEN RAISE EXCEPTION 'IG_PG17_CONTRACT_PROOF_MUTATED_CANONICAL'; END IF;
 RAISE NOTICE 'LF_IG_06_THREE_RAW_SOURCE_READY_NO_RULE_CHANGES:negative_cases=2:replacement=1';
END;
$lf_ig_three_raw_contract$;
ROLLBACK;
