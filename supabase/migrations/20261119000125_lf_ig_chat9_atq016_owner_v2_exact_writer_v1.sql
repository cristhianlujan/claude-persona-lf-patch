-- IG Chat9 lot2: source-bound CORRECT_VIGENTE/FUNCTIONAL, REG_ATQ_016 only.
-- No direct rule UPDATE: official owner_decide_v2 invokes child+finalize atomically.
-- Owner authorization 2026-11-18 18:10 America/Lima; documentary, not identity proof.
-- Backend E2E / production NOT authorized. Do not alter other chats' objects.
BEGIN;
DO $atq016_v2$
DECLARE
  parent_run CONSTANT text:='EXEC-PROFILE-GATE2-35B76F932357FEA442705DB8';
  rule CONSTANT text:='REG_ATQ_016';
  src CONSTANT text:='c16436927a07128022e33b932ea8ee6f8e3dc550264b059b8130e56e4ce143c7';
  proposal CONSTANT text:='b7b4f96167366592d1da5b7ea167f32525d9a7bb91b02d04eadbe1908e422293';
  candidate CONSTANT text:='37c1394198971e65902d444205dc0cf48a8c839958df53f14fb2db7914b58bae';
  v_count bigint;
  v_other_before text; v_other_after text;
  v_parent_output jsonb; v_patch jsonb;
  v_auto jsonb; v_written jsonb; v_approved jsonb;
  v_config jsonb;
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.lf_operation_execution e
    WHERE e.execution_id=parent_run AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND e.status='IN_PROGRESS'
      AND e.manifest->>'read_only'='true'
      AND e.manifest->>'no_write'='true'
      AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true'
      AND e.manifest#>>'{screen_selection_result,selected_screen_code}'='ONB_003'
  ) OR public.lf_asset_snapshot_sha_v1('REGLA',rule) IS DISTINCT FROM src
    OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo=rule AND estado='VIGENTE')<>1
    OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2
       WHERE parent_execution_id=parent_run AND rule_code=rule)
    OR EXISTS(SELECT 1 FROM public.lf_ig_rule_change_v2
       WHERE rule_code=rule AND parent_execution_id=parent_run)
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_PARENT_OR_SOURCE_DRIFT'; END IF;

  SELECT s.evidence_payload->'profile_output'
  INTO v_parent_output
  FROM public.lf_operation_execution_steps s
  WHERE s.execution_id=parent_run AND s.step_id='execute_profile'
    AND s.status='STEP_PASS_WITH_EVIDENCE';
  v_patch:=v_parent_output#>'{deliverable_created,governed_rule_patch}';
  IF v_parent_output#>>'{deliverable_created,product_decision,proposed_by}'
       IS DISTINCT FROM 'PERFIL-PRODUCT-DIRECTOR-LF'
     OR v_patch->>'rule_code' IS DISTINCT FROM rule
     OR v_patch->>'change_kind' IS DISTINCT FROM 'FUNCTIONAL'
     OR encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex')
         IS DISTINCT FROM proposal
     OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
       WHERE s.execution_id=parent_run AND s.step_id='output_validate'
         AND s.status='STEP_PASS_WITH_EVIDENCE'
         AND s.evidence_payload->>'output_contract_result'='PASS')
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_PRODUCT_RAW_OR_PATCH_DRIFT'; END IF;

  IF (SELECT count(*) FROM public.lf_global_config
      WHERE scope='CLIENT' AND config_key IN (
        'ATQ_DISTINCT_DNI_PER_IP_SIGNAL_LIMIT',
        'ATQ_DISTINCT_IP_PER_DNI_SIGNAL_LIMIT',
        'ATQ_SIGNAL_WINDOW_MINUTES',
        'ATQ_ACCOUNT_HOLD_MINUTES')
        AND value_type='INTEGER' AND value_status='REAL')<>4
    OR (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1 t
      WHERE t.rule_code=rule AND t.source_snapshot_sha256=src
        AND t.proposal_sha256=proposal AND t.candidate_snapshot_sha256=candidate
        AND t.train_run_id='44422905263'
        AND t.pg_rollback_status='PASS'
        AND t.independent_readback_status='PASS'
        AND t.functional_checks_status='PASS'
        AND t.negative_checks_status='PASS')<>1
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_CONFIG_OR_TRAIN_PROOF_UNVERIFIED'; END IF;

  SELECT count(*) INTO v_count FROM lf_ops.reglas;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
  INTO v_other_before FROM lf_ops.reglas r WHERE r.codigo<>rule;

  v_auto:=public.lf_ig_step70_functional_train_auto_v1(parent_run);
  IF v_auto->>'status' IS DISTINCT FROM 'PASS'
    OR v_auto->>'verdict' IS DISTINCT FROM 'PASS_TRAIN_EVIDENCE_AUTOMATICO'
    OR v_auto#>>'{train_evidence,rule_code}' IS DISTINCT FROM rule
    OR v_auto#>>'{train_evidence,source_snapshot_sha256}' IS DISTINCT FROM src
    OR v_auto#>>'{train_evidence,proposal_sha256}' IS DISTINCT FROM proposal
    OR v_auto#>>'{train_evidence,candidate_snapshot_sha256}' IS DISTINCT FROM candidate
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_AUTO_TRAIN_NOT_PASS:%',v_auto->>'blocking_code'; END IF;

  v_written:=public.lf_record_profile_execution_step_v1(
    parent_run,'semantic_judge',
    'supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_016',
    jsonb_build_object(
      'semantic_judge_result',v_auto,
      'unsupported_claims','[]'::jsonb,
      'semantic_review_receipt_ref',
        'supabase://public.lf_ig_functional_train_evidence_v1/REG_ATQ_016',
      'independent_semantic_receipt_ref',null,
      'judge_independence_status','NOT_ASSERTED',
      'evaluator','TRAIN_EVIDENCE_AUTOMATICO',
      'content_findings',jsonb_build_array(
        jsonb_build_object('finding_code','SEMANTIC_JUDGE_NOT_PERFORMED',
                           'evaluator','TRAIN_EVIDENCE_AUTOMATICO'))
    ),parent_run);
  IF coalesce(v_written->>'status',v_written->>'step_status')
       IS DISTINCT FROM 'STEP_PASS_WITH_EVIDENCE'
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_CANONICAL_STEP70_FAILED:%',v_written; END IF;

  v_approved:=public.lf_ig_rule_owner_decide_v2(
    parent_run,rule,src,
    '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
  IF v_approved->>'status' IS DISTINCT FROM 'APPROVED_AND_VIGENTE_VERIFIED'
     OR v_approved->>'kind' IS DISTINCT FROM 'CORRECT_VIGENTE'
     OR v_approved->>'source_sha256' IS DISTINCT FROM src
     OR v_approved->>'proposal_sha256' IS DISTINCT FROM proposal
     OR v_approved->>'finalized_snapshot_sha256' IS DISTINCT FROM candidate
     OR v_approved->>'write_performed' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_OFFICIAL_V2_APPROVAL_FAILED:%',v_approved; END IF;

  SELECT r.valor_config INTO v_config
  FROM lf_ops.reglas r WHERE r.codigo=rule AND r.estado='VIGENTE';
  IF public.lf_asset_snapshot_sha_v1('REGLA',rule) IS DISTINCT FROM candidate
     OR v_config ? 'accion' OR v_config ? 'patron_1' OR v_config ? 'patron_2'
     OR v_config#>>'{shared_ip_hard_block}' IS DISTINCT FROM 'DENY'
     OR v_config#>>'{account_restriction_scope}' IS DISTINCT FROM 'RESOLVED_USER_ACCOUNT_ONLY'
     OR v_config#>>'{additional_abuse_evidence}' IS DISTINCT FROM 'REQUIRED'
     OR v_config#>>'{signal_mode}' IS DISTINCT FROM 'PREVENTIVE_ALERT_ONLY'
     OR v_config#>>'{distinct_documents_signal_limit_config_ref,scope}' IS DISTINCT FROM 'CLIENT'
     OR v_config#>>'{distinct_documents_signal_limit_config_ref,config_key}'
           IS DISTINCT FROM 'ATQ_DISTINCT_DNI_PER_IP_SIGNAL_LIMIT'
     OR v_config#>>'{distinct_ips_signal_limit_config_ref,scope}' IS DISTINCT FROM 'CLIENT'
     OR v_config#>>'{distinct_ips_signal_limit_config_ref,config_key}'
           IS DISTINCT FROM 'ATQ_DISTINCT_IP_PER_DNI_SIGNAL_LIMIT'
     OR v_config#>>'{signal_window_minutes_config_ref,scope}' IS DISTINCT FROM 'CLIENT'
     OR v_config#>>'{signal_window_minutes_config_ref,config_key}'
           IS DISTINCT FROM 'ATQ_SIGNAL_WINDOW_MINUTES'
     OR v_config#>>'{account_hold_minutes_config_ref,scope}' IS DISTINCT FROM 'CLIENT'
     OR v_config#>>'{account_hold_minutes_config_ref,config_key}'
           IS DISTINCT FROM 'ATQ_ACCOUNT_HOLD_MINUTES'
     OR EXISTS(SELECT 1 FROM jsonb_each(v_config) j
         WHERE jsonb_typeof(j.value)='number')
     OR (SELECT count(*) FROM lf_ops.reglas)<>v_count
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_RULE_POSTIMAGE_INCORRECT'; END IF;

  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
    INTO v_other_after FROM lf_ops.reglas r WHERE r.codigo<>rule;
  IF v_other_before IS DISTINCT FROM v_other_after
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_ADJACENT_RULE_CHANGED'; END IF;

  IF (SELECT count(*) FROM public.lf_operation_execution_steps
      WHERE execution_id=parent_run AND step_id='semantic_judge'
        AND status='STEP_PASS_WITH_EVIDENCE')<>1
     OR NOT EXISTS(SELECT 1 FROM public.lf_ig_rule_change_v2 ch
       WHERE ch.parent_execution_id=parent_run AND ch.rule_code=rule
         AND ch.state='VIGENTE_VERIFIED'
         AND ch.kind='CORRECT_VIGENTE'
         AND ch.source_snapshot_sha256=src
         AND ch.finalized_snapshot_sha256=candidate)
  THEN RAISE EXCEPTION 'IG_CHAT9_ATQ016_OFFICIAL_STEP_OR_CHILD_MISSING'; END IF;

  RAISE NOTICE 'IG_CHAT9_ATQ016_CORRECT_VIGENTE_FUNCTIONAL_PASS owner_decide_v2=TRUE source_bound=TRUE backend_e2e=NOT_TESTED parent_step80=PENDING';
END $atq016_v2$;
COMMIT;
