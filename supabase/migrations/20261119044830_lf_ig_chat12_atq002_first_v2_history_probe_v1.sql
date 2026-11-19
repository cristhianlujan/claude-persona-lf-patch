-- IG chat12, primer CORRECT_VIGENTE/FUNCTIONAL tras PR4163 evidencia exacta.
-- No UPDATE directo a lf_ops.reglas. El oficial owner_decide_v2 ejecuta
-- skill child + finalize atomico, con recibo de PG17 en Train.
-- VERSIONES: el historico guarda preimagenes; la vista computa version 2.
BEGIN;
SET LOCAL lf.reglas_cambio_motivo='FAMILIA_A_PARAMETRIZACION_CONFIG';
SET LOCAL lf.reglas_cambiado_por='IG_CHAT12_V2_MERGE_TRAIN';
DO $ig_chat12_v2$
DECLARE
 p constant text:='EXEC-PROFILE-GATE2-5F8B40E1F29B23126EB8B797';
 r constant text:='REG_ATQ_002';
 s constant text:='cc10104d94ad195f133998934d8af2efeb3f03a59a837777a6bef7f007182765';
 h constant text:='293ae9e3847b7ba9b3253f09289c27f2d62dadeae2f8f02ff80e430553e80488';
 c constant text:='813f429c1aa339c651715975d551c338cfa0edd3dd568142567fd835954847e4';
 v_auto jsonb; v_step jsonb; v_approved jsonb;
 v_other_before text; v_other_after text; v_total bigint;
 v_profile jsonb; v_patch jsonb;
BEGIN
 IF public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM s
  OR NOT EXISTS (SELECT 1 FROM lf_ops.reglas WHERE codigo=r AND estado='VIGENTE')
  OR NOT EXISTS (SELECT 1 FROM public.lf_operation_execution e
      WHERE e.execution_id=p AND e.status='IN_PROGRESS'
        AND e.operation_code='EJECUCION_PERFIL_LF'
        AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
        AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_001'
        AND e.manifest->>'read_only'='true'
        AND e.manifest->>'no_write'='true')
  OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2
      WHERE parent_execution_id=p AND rule_code=r)
  OR (SELECT count(*) FROM lf_ops.reglas_versiones
       WHERE codigo=r AND version=1 AND vigente_hasta IS NULL)<>1
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_PREIMAGE_OR_HISTORY_DRIFT'; END IF;

 SELECT evidence_payload->'profile_output' INTO v_profile
 FROM public.lf_operation_execution_steps
 WHERE execution_id=p AND step_id='execute_profile'
   AND status='STEP_PASS_WITH_EVIDENCE';
 v_patch:=v_profile#>'{deliverable_created,governed_rule_patch}';
 IF v_profile#>>'{deliverable_created,product_decision,proposed_by}'
         IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
  OR v_patch->>'rule_code' IS DISTINCT FROM r
  OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
  OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')
        IS DISTINCT FROM h
  OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
      WHERE execution_id=p AND step_id='output_validate'
        AND status='STEP_PASS_WITH_EVIDENCE'
        AND evidence_payload->>'output_contract_result'='PASS')
  OR NOT EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1 e
      WHERE e.rule_code=r AND e.source_snapshot_sha256=s
        AND e.proposal_sha256=h AND e.candidate_snapshot_sha256=c
        AND e.train_run_id='44453107449'
        AND e.pg_rollback_status='PASS' AND e.independent_readback_status='PASS'
        AND e.functional_checks_status='PASS' AND e.negative_checks_status='PASS')
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_RAW_OR_TRAIN_UNVERIFIED'; END IF;

 SELECT count(*) INTO v_total FROM lf_ops.reglas;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_before FROM lf_ops.reglas x WHERE x.codigo<>r;

 v_auto:=public.lf_ig_step70_functional_train_auto_v1(p);
 IF v_auto->>'status' IS DISTINCT FROM 'PASS'
     OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
     OR v_auto#>>'{train_evidence,rule_code}' IS DISTINCT FROM r
     OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_STEP70_TRAIN_NOT_PASS:%',v_auto->>'blocking_code'; END IF;

 v_step:=public.lf_record_profile_execution_step_v1(
  p,'semantic_judge',
  'supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_002',
  jsonb_build_object(
   'semantic_judge_result',v_auto,
   'unsupported_claims','[]'::jsonb,
   'semantic_review_receipt_ref','supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_002',
   'independent_semantic_receipt_ref',NULL,
   'judge_independence_status','NOT_ASSERTED',
   'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
   'content_findings',jsonb_build_array(jsonb_build_object(
      'finding_code','SEMANTIC_JUDGE_NOT_PERFORMED',
      'evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
  ),p);
 IF coalesce(v_step->>'status',v_step->>'step_status') IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_STEP70_OFFICIAL_FAILED:%',v_step; END IF;

 v_approved:=public.lf_ig_rule_owner_decide_v2(p,r,s,
      '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
 IF v_approved->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
    OR v_approved->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
    OR v_approved->>'proposal_sha256' IS DISTINCT FROM h
    OR v_approved->>'finalized_snapshot_sha256' IS DISTINCT FROM c
    OR public.lf_asset_snapshot_sha_v1('REGLA',r) IS DISTINCT FROM c
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_OWNER_V2_VERIFY_FAILED:%',v_approved; END IF;

 IF (SELECT valor_config FROM lf_ops.reglas WHERE codigo=r)
     IS DISTINCT FROM '{"scope":"AUTH","config_key":"CAPTCHA_MAX_ESCALATIONS_BEFORE_BLOCK"}'::jsonb
    OR (SELECT estado FROM lf_ops.reglas WHERE codigo=r)<>'VIGENTE'
    OR (SELECT count(*) FROM lf_ops.reglas)<>v_total
    OR (SELECT count(*) FROM lf_ops.reglas_versiones WHERE codigo=r AND version=1
        AND vigente_hasta IS NOT NULL)<>1
    OR (SELECT version FROM lf_ops.v_reglas_historial WHERE codigo=r AND es_actual)<>2
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_POSTIMAGE_OR_VIRTUAL_HISTORY_BAD'; END IF;

 SELECT md5(coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.codigo)::text,'[]'))
 INTO v_other_after FROM lf_ops.reglas x WHERE x.codigo<>r;
 IF v_other_before IS DISTINCT FROM v_other_after
 THEN RAISE EXCEPTION 'IG_CHAT12_ATQ002_OUTSIDE_RULE_CHANGED'; END IF;
 RAISE NOTICE 'IG_CHAT12_ATQ002_V2_PASS; VERSION_2_VIEW; TABLE_ONLY_PREIMAGE_1; PARENT_STEP80_PENDING';
END $ig_chat12_v2$;
COMMIT;
