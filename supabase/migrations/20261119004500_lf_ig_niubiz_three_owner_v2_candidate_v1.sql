-- IG NIUBIZ: three owner V2 CREATE/CANDIDATO only, source-bound
-- evidence from actual PG17 + exact authenticated Merge Train.
-- Never INSERT/UPDATE lf_ops.reglas directly; only owner_decide_v2 invokes writer.
-- Never promote or activate production. External Niubiz hyphen remains NOT_TESTED.
BEGIN;
DO $niubiz_owner$
DECLARE
  v record;
  v_patch jsonb; v_cfg jsonb; v_ref jsonb;
  v_auto jsonb; v_bridge jsonb; v_dec jsonb; v_report jsonb;
  v_source text; v_patch_sha text; v_candidate_sha text;
  v_initial_count integer; v_event_id bigint;
  v_initial_rules_md5 text; v_untouched_rules_md5 text;
  v_config_md5 text; v_current_config_md5 text;
  v_dry_ok boolean; v_written integer:=0; v_j integer;
  v_report_ref text:='github://cristhianlujan/claude-persona-lf-patch/actions/runs/44428207532/artifacts/14484483531#RULE_CONTRACT_LEVEL';
  v_config_refs jsonb:='[
     {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_TEMPLATE"},
     {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_DOMAIN"}
   ]'::jsonb;
BEGIN
  -- Exact source preimage for all three official gates. Do not alter their implementation.
  IF md5(pg_get_functiondef('public.lf_profile_native_bridge_record_semantic_v1(text,jsonb,text,text)'::regprocedure))
      IS DISTINCT FROM 'e47b02b7c8cb450e23f39fdf1a36a2a3'
    OR md5(pg_get_functiondef('public.lf_ig_step70_functional_train_auto_v1(text)'::regprocedure))
      IS DISTINCT FROM '03ed54da90b74502f836e81ffebd1fe6'
    OR md5(pg_get_functiondef('public.lf_ig_rule_owner_decide_v2(text,text,text,jsonb)'::regprocedure))
      IS DISTINCT FROM '98372407a52b87a464da597d24a408cb'
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_GATE_PREIMAGE_DRIFT'; END IF;
  IF to_regclass('public.lf_ig_functional_train_evidence_v1') IS NULL
     OR to_regclass('lf_ops.reglas') IS NULL
     OR to_regclass('public.lf_global_config') IS NULL
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_CANONICAL_SOURCES_MISSING'; END IF;
  SELECT count(*) INTO v_initial_count FROM lf_ops.reglas;
  IF v_initial_count <> 583
    OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO') <> 145
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_RULE_BASELINE_DRIFT:%',v_initial_count; END IF;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]'))
    INTO v_initial_rules_md5 FROM lf_ops.reglas r;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY scope,config_key)::text,'[]'))
    INTO v_config_md5 FROM public.lf_global_config g;
  IF (SELECT count(*) FROM public.lf_global_config) <> 46
     OR (SELECT count(*) FROM public.lf_global_config
           WHERE scope='PAGOS' AND config_key IN
             ('NIUBIZ_EMAIL_TEMPLATE','NIUBIZ_EMAIL_DOMAIN')
             AND value_type='TEXT' AND value_status='REAL')<>2
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_CONFIG_PREIMAGE_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo IN
        ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
         'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
         'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001'))
     OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code IN
        ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
         'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
         'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001'))
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_DUPLICATE_OR_ALREADY_DECIDED'; END IF;
  -- Real Train authority: verify source, signed-event digest, current ledger.
  SELECT evt.id INTO v_event_id
  FROM public.lf_operation_execution te
  JOIN public.lf_eventos evt
    ON evt.entidad_codigo=te.execution_id
    AND evt.evento_tipo='MIGRATION_TRAIN_RECEIPT_RECORDED'
    AND evt.origen='lf-migration-merge-train'
  WHERE te.execution_id='EXEC-DB-TRAIN-PR4143-20261119003000-R44428506420'
    AND te.operation_code='ACTUALIZACION_DB_LF' AND te.status='COMPLETED'
    AND te.manifest->>'train_run_id'='44428506420'
    AND te.manifest->>'head_sha'='da56ce40d67a635a004247aeb9ed524690f6de64'
    AND te.updated_by_execution_id='LF-MIGRATION-TRAIN-RUN-44428506420'
    AND evt.payload#>>'{receipt,train_run_id}'='44428506420'
    AND evt.payload#>>'{receipt,heads,final_head}'='da56ce40d67a635a004247aeb9ed524690f6de64'
    AND evt.payload#>>'{receipt,heads,final_head_is_execution_head}'='true'
    AND evt.payload#>>'{receipt,terminal_status}'='COMPLETED'
    AND evt.payload#>>'{receipt,parity,migration_source_parity}'='PASS'
    AND evt.payload#>>'{receipt,ledger_readback,matches_target}'='true'
    AND evt.payload->>'receipt_sha256'='b43fa737b3fc80969aabc464c2f460632af31c613eeea859b67d2669d514a525'
    AND encode(extensions.digest(convert_to((evt.payload->'receipt')::text,'UTF8'),'sha256'),'hex')
        =evt.payload->>'receipt_sha256';
  IF v_event_id IS NULL OR (SELECT count(*)
    FROM supabase_migrations.schema_migrations
    WHERE version='20261119003000'
      AND name='lf_ig_niubiz_three_rule_contract_proof_only_v1')<>1
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_TRAIN_RECEIPT_OR_LEDGER_UNVERIFIED'; END IF;

  -- Each fresh Router-owned Product Director run has origin-bound proposed_by;
  -- previous immutable RAW without proposer stays historical and is not modified.
  -- Each run remains independent; evidence and decisions are source-bound per patch.
  FOR v IN SELECT * FROM (VALUES
    ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
     'EXEC-PROFILE-GATE2-DCE01AEE24CF00F0362D3E01',
     'CHECKOUT_ESTADO_TARJETA',
     'b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa'),
    ('REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
     'EXEC-PROFILE-GATE2-FEC6C217064FA241227B715D',
     'CHECKOUT_PAGO_EXITOSO',
     '4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4'),
    ('REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001',
     'EXEC-PROFILE-GATE2-9D48CA261787E2E9F3A7CB31',
     'CHECKOUT_ESTADO_CONFIRMANDO',
     'b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c')
  ) AS proposals(rule_code,parent,screen,expected_patch_sha) LOOP
    SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
      INTO v_patch
    FROM public.lf_operation_execution_steps s
    JOIN public.lf_operation_execution e ON e.execution_id=s.execution_id
    WHERE s.execution_id=v.parent AND s.step_id='execute_profile'
      AND s.status='STEP_PASS_WITH_EVIDENCE'
      AND e.operation_code='EJECUCION_PERFIL_LF'
      AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
      AND e.status='IN_PROGRESS'
      AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=v.screen
      AND e.manifest->>'read_only'='true'
      AND e.manifest->>'no_write'='true'
      AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true'
      AND s.evidence_payload#>>'{profile_output,deliverable_created,product_decision,proposed_by}'='PERFIL-PRODUCT-DIRECTOR-LF';
    IF v_patch IS NULL OR v_patch->>'rule_code' IS DISTINCT FROM v.rule_code
       OR v_patch->>'change_kind' IS DISTINCT FROM 'CREATE'
       OR jsonb_typeof(v_patch->'changes')<>'object'
       OR NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
           WHERE s.execution_id=v.parent AND s.step_id='output_validate'
             AND s.status='STEP_PASS_WITH_EVIDENCE'
             AND s.evidence_payload->>'output_contract_result'='PASS')
    THEN RAISE EXCEPTION 'NIUBIZ_OWNER_STEP50_STEP60_CURRENT_MISSING:%',v.rule_code; END IF;
    v_patch_sha:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
    IF v_patch_sha IS DISTINCT FROM v.expected_patch_sha
       OR v_patch#>'{changes,valor_config,niubiz_email_config_refs}' IS DISTINCT FROM v_config_refs
       OR v_patch#>>'{changes,valor_config,production_authorized}'<>'false'
       OR v_patch#>>'{changes,categoria}'<>'pago'
       OR v_patch#>>'{changes,descripcion}' NOT LIKE '%public.lf_global_config%'
       OR v_patch#>>'{changes,descripcion}' LIKE '%gmail.com%'
       OR v_patch#>>'{changes,descripcion}' LIKE '%lf-{codigo}%'
    THEN RAISE EXCEPTION 'NIUBIZ_OWNER_PATCH_OR_DYNAMIC_PARAM_DRIFT:%',v.rule_code; END IF;
    v_source:=encode(extensions.digest(convert_to('LF_RULE_ABSENT:'||v.rule_code,'UTF8'),'sha256'),'hex');
    v_candidate_sha:=encode(extensions.digest(convert_to(
       jsonb_build_object('rule_code',v.rule_code,'candidate_state','CANDIDATO',
         'change_kind','CREATE','candidate_changes',v_patch->'changes')::text,'UTF8'),'sha256'),'hex');
    INSERT INTO public.lf_ig_functional_train_evidence_v1(
       rule_code,source_snapshot_sha256,proposal_sha256,candidate_snapshot_sha256,
       train_execution_id,train_run_id,train_event_id,train_head_sha,
       pg_rollback_status,independent_readback_status,functional_checks_status,
       negative_checks_status,pg_report_sha256,readback_sha256,check_manifest_sha256,
       report_ref)
    VALUES (
       v.rule_code,v_source,v_patch_sha,v_candidate_sha,
       'EXEC-DB-TRAIN-PR4143-20261119003000-R44428506420',
       '44428506420',v_event_id,
       'da56ce40d67a635a004247aeb9ed524690f6de64',
       'PASS','PASS','PASS','PASS',
       'bb8b2150816cfbd9eb086675591297e8801e80353c601d11b7a5ebd414bfe047',
       '3e49dd16f3893026764455ec2610d4cabf5fb0e47c506543598c10a94bbca204',
       'ab0f74bcd6d5d6971a55d939265ca56816111c0f0a9c68f51c912e106d7b6da3',
       v_report_ref);
    IF (SELECT count(*) FROM public.lf_ig_functional_train_evidence_v1 t
      WHERE t.rule_code=v.rule_code AND t.proposal_sha256=v_patch_sha
        AND t.train_run_id='44428506420') <> 1
    THEN RAISE EXCEPTION 'NIUBIZ_OWNER_TRAIN_PROOF_READBACK_FAILED:%',v.rule_code; END IF;

    -- Actual live subtransaction: prove official Step70/owner V2 and writer 7/7
    -- then roll back via a controlled sentinel. A failed gate blocks the WHOLE batch.
    v_dry_ok:=false;
    BEGIN
      v_auto:=public.lf_ig_step70_functional_train_auto_v1(v.parent);
      IF v_auto->>'status' IS DISTINCT FROM 'PASS' THEN
        RAISE EXCEPTION 'NIUBIZ_DRY_AUTO_STEP70_BLOCKED:%:%',v.rule_code,v_auto->>'blocking_code'; END IF;
      v_bridge:=public.lf_profile_native_bridge_record_semantic_v1(
         v.parent,v_auto,v_report_ref,v.parent);
      IF v_bridge->>'status' IS DISTINCT FROM 'SEMANTIC_JUDGE_RECORDED' THEN
        RAISE EXCEPTION 'NIUBIZ_DRY_STEP70_BRIDGE_BLOCKED:%:%',
          v.rule_code,coalesce(v_bridge->>'blocking_code',v_bridge->>'status'); END IF;
      v_dec:=public.lf_ig_rule_owner_decide_v2(
         v.parent,v.rule_code,v_source,
         '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
      IF v_dec->>'status'<>'APPROVED_AND_CANDIDATO_VERIFIED' THEN
        RAISE EXCEPTION 'NIUBIZ_DRY_OWNER_V2_NOT_CANDIDATE:%',v.rule_code; END IF;
      IF (SELECT count(*) FROM public.lf_operation_execution_steps
        WHERE execution_id=v_dec->>'child_execution_id' AND status='PASS_CLEAN')<>7
        OR (SELECT estado FROM lf_ops.reglas WHERE codigo=v.rule_code)<>'CANDIDATO'
        OR EXISTS (SELECT 1 FROM public.lf_rule_promotion_v1 WHERE rule_code=v.rule_code)
      THEN RAISE EXCEPTION 'NIUBIZ_DRY_CHILD_SEVEN_OR_NO_PROMOTION_FAILED:%',v.rule_code; END IF;
      RAISE EXCEPTION 'NIUBIZ_OWNER_REAL_ROLLBACK_SENTINEL';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM='NIUBIZ_OWNER_REAL_ROLLBACK_SENTINEL' THEN
        v_dry_ok:=true;
        RAISE NOTICE 'NIUBIZ_OWNER_REAL_BEGIN_ROLLBACK_PASS:%',v.rule_code;
      ELSE
        RAISE NOTICE 'NIUBIZ_OWNER_DRY_BLOCKED:%:%',v.rule_code,SQLERRM;
      END IF;
    END;
    IF NOT v_dry_ok
      OR EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo=v.rule_code)
      OR EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2 WHERE rule_code=v.rule_code)
      OR EXISTS(SELECT 1 FROM public.lf_operation_execution_steps
            WHERE execution_id=v.parent AND step_id='semantic_judge')
    THEN RAISE EXCEPTION 'NIUBIZ_OWNER_SUBTX_ROLLBACK_READBACK_DIRTY_OR_BLOCKED:%',v.rule_code; END IF;

    -- Sequential real V2 for exactly this rule, no parallel owner decisions.
    v_auto:=public.lf_ig_step70_functional_train_auto_v1(v.parent);
    IF v_auto->>'status' IS DISTINCT FROM 'PASS' THEN
      RAISE EXCEPTION 'NIUBIZ_OWNER_STEP70_RECHECK_BLOCKED:%',v.rule_code; END IF;
    v_bridge:=public.lf_profile_native_bridge_record_semantic_v1(
      v.parent,v_auto,v_report_ref,v.parent);
    IF v_bridge->>'status' IS DISTINCT FROM 'SEMANTIC_JUDGE_RECORDED' THEN
      RAISE EXCEPTION 'NIUBIZ_OWNER_STEP70_ACTUAL_BLOCKED:%:%',v.rule_code,
        coalesce(v_bridge->>'blocking_code',v_bridge->>'status'); END IF;
    v_dec:=public.lf_ig_rule_owner_decide_v2(
      v.parent,v.rule_code,v_source,
      '{"usuario":"Cristhian Lujan","veredicto":"APROBAR"}'::jsonb);
    IF v_dec->>'status' IS DISTINCT FROM 'APPROVED_AND_CANDIDATO_VERIFIED'
       OR v_dec->>'kind'<>'CREATE'
       OR v_dec->>'promotion_authorized'<>'false'
       OR v_dec->>'production_authorized'<>'false'
    THEN RAISE EXCEPTION 'NIUBIZ_OWNER_V2_CREATE_CANDIDATO_ONLY:%',v.rule_code; END IF;
    IF NOT EXISTS(SELECT 1 FROM lf_ops.reglas r WHERE r.codigo=v.rule_code
       AND r.estado='CANDIDATO' AND r.pendiente_decision=true
       AND r.created_by=v_dec->>'child_execution_id'
       AND r.valor_config->'niubiz_email_config_refs' IS NOT DISTINCT FROM v_config_refs)
       OR (SELECT count(*) FROM public.lf_operation_execution_steps s
            WHERE s.execution_id=v_dec->>'child_execution_id'
              AND s.status='PASS_CLEAN')<>7
       OR EXISTS(SELECT 1 FROM public.lf_rule_promotion_v1
            WHERE rule_code=v.rule_code)
    THEN RAISE EXCEPTION 'NIUBIZ_OWNER_CREATE_READBACK_FAILED:%',v.rule_code; END IF;
    v_written:=v_written+1;
    RAISE NOTICE 'NIUBIZ_OWNER_V2_CANDIDATO_VERIFIED:%:child=%',v.rule_code,
       v_dec->>'child_execution_id';
    -- Report/Step80 is best-effort and must not be counted without a real receipt.
    BEGIN
      v_report:=public.lf_profile_native_bridge_record_report_v1(
        v.parent,v_report_ref,v.parent);
      RAISE NOTICE 'NIUBIZ_OWNER_STEP80:%:%',v.rule_code,
        coalesce(v_report->>'status',v_report->>'blocking_code','UNKNOWN');
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'NIUBIZ_OWNER_STEP80_NOT_VERIFIED:%:%',v.rule_code,SQLERRM;
    END;
  END LOOP;

  IF v_written<>3 OR (SELECT count(*) FROM lf_ops.reglas)<>v_initial_count+3
     OR (SELECT count(*) FROM lf_ops.reglas WHERE estado='CANDIDATO')<>148
     OR (SELECT count(*) FROM lf_ops.reglas WHERE codigo IN
        ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
         'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
         'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001') AND estado='CANDIDATO')<>3
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_POSTIMAGE_COUNT_NOT_PLUS_THREE'; END IF;
  SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY codigo)::text,'[]'))
    INTO v_untouched_rules_md5 FROM lf_ops.reglas r
    WHERE r.codigo NOT IN ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
        'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
        'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001');
  SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY scope,config_key)::text,'[]'))
    INTO v_current_config_md5 FROM public.lf_global_config g;
  IF v_untouched_rules_md5 IS DISTINCT FROM v_initial_rules_md5
     OR v_config_md5 IS DISTINCT FROM v_current_config_md5
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_UNRELATED_RULE_OR_CONFIG_DRIFT'; END IF;
  IF (SELECT count(*) FROM public.lf_ig_owner_decision_v2 d
      WHERE d.rule_code IN ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
         'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
         'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001')
      AND d.verdict='APROBAR' AND d.kind='CREATE'
      AND d.decisor='Cristhian Luján')<>3
  THEN RAISE EXCEPTION 'NIUBIZ_OWNER_V2_DECISION_READBACK_NOT_THREE'; END IF;
  RAISE NOTICE 'NIUBIZ_OWNER_FINAL_583_TO_586_3_CANDIDATO_NO_PROMOTION_PASS';
END $niubiz_owner$;
COMMIT;
