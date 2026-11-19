-- IG Chat12 — ATQ002 exact source/patch proof only.
-- NO lf_ops.reglas mutations, NO owner decisions, NO Step70, NO invented CI
-- receipts. Real PG17 fixture report is separately produced by exact-head CI.
BEGIN;
DO $chat12_atq002_source_proof$
DECLARE
 v_rule constant text:='REG_ATQ_002';
 v_run constant text:='EXEC-PROFILE-GATE2-5F8B40E1F29B23126EB8B797';
 v_source constant text:='cc10104d94ad195f133998934d8af2efeb3f03a59a837777a6bef7f007182765';
 v_proposal constant text:='293ae9e3847b7ba9b3253f09289c27f2d62dadeae2f8f02ff80e430553e80488';
 v_candidate constant text:='813f429c1aa339c651715975d551c338cfa0edd3dd568142567fd835954847e4';
 v_patch jsonb; v_snap jsonb; v_current text; v_after text;
BEGIN
 IF (SELECT count(*) FROM lf_ops.reglas r WHERE codigo=v_rule AND estado='VIGENTE')<>1
    OR NOT EXISTS(
      SELECT 1 FROM public.lf_operation_execution e
      WHERE e.execution_id=v_run AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND e.status='IN_PROGRESS'
      AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001'
      AND e.manifest->>'no_write'='true'
    )
    OR NOT EXISTS(
      SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v_run AND s.step_id='output_validate'
      AND s.status='STEP_PASS_WITH_EVIDENCE'
      AND s.evidence_payload->>'output_contract_result'='PASS'
    )
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_PARENT_OR_STATUS_DRIFT'; END IF;
 SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
 INTO v_patch
 FROM public.lf_operation_execution_steps s
 WHERE s.execution_id=v_run AND s.step_id='execute_profile'
 AND s.status='STEP_PASS_WITH_EVIDENCE';
 SELECT to_jsonb(r)-'created_at'-'updated_at'
 INTO v_snap FROM lf_ops.reglas r WHERE r.codigo=v_rule AND r.estado='VIGENTE';
 v_current:=public.lf_asset_snapshot_sha_v1('REGLA',v_rule);
 v_after:=encode(extensions.digest(convert_to((
   v_snap||jsonb_build_object(
     'descripcion',v_patch#>>'{changes,descripcion}',
     'valor_config',v_patch#>'{changes,valor_config}'
   ))::text,'UTF8'),'sha256'),'hex');
 IF v_current IS DISTINCT FROM v_source
    OR v_patch->>'rule_code' IS DISTINCT FROM v_rule
    OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
    OR v_patch#>'{changes,valor_config}' IS DISTINCT FROM
        '{"scope":"AUTH","config_key":"CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK"}'::jsonb
    OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')
      IS DISTINCT FROM v_proposal
    OR v_after IS DISTINCT FROM v_candidate
    OR (SELECT count(*) FROM public.lf_global_config g
        WHERE g.scope='AUTH'
        AND g.config_key='CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK'
        AND g.value_type='INTEGER' AND g.value_status='REAL'
        AND g.config_value='2')<>1
    OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1
              WHERE rule_code=v_rule AND proposal_sha256=v_proposal)
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_SOURCE_PATCH_OR_CONFIG_DRIFT'; END IF;
 RAISE NOTICE 'IG_CHAT12_ATQ002_SOURCE_PATCH_VERIFIED; real_pg17_ci_is_separate; backend_e2e_not_tested; rules_untouched';
END $chat12_atq002_source_proof$;
COMMIT;
