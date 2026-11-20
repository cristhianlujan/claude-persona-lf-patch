-- Contract-level proof only for three Niubiz proposals already emitted as
-- actual RAW Product Director Step50/60. No rule/owner/evidence inserts here.
-- Train receipt and real PG17 artifact are prerequisites for later owner V2.
BEGIN;
DO $niubiz_contract_proof$
DECLARE
 v record;
 v_patch jsonb;
 v_hash text;
 v_refs jsonb;
 v_rules_before text;
 v_rules_after text;
 v_config_before text;
 v_config_after text;
 v_expected jsonb:='[
   {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_TEMPLATE"},
   {"scope":"PAGOS","config_key":"NIUBIZ_EMAIL_DOMAIN"}
 ]'::jsonb;
BEGIN
 IF to_regclass('lf_ops.reglas') IS NULL
    OR to_regclass('public.lf_global_config') IS NULL
    OR to_regclass('public.lf_operation_execution_steps') IS NULL
 THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_CANONICAL_SOURCES_MISSING'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
 INTO v_rules_before FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.scope,g.config_key)::text,'[]'))
 INTO v_config_before FROM public.lf_global_config g;
 IF (SELECT count(*) FROM lf_ops.reglas)<583 OR
    (SELECT count(*) FROM public.lf_global_config)<46
 THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_BASELINE_BELOW_VERIFIED'; END IF;
 IF (SELECT count(*) FROM public.lf_global_config
    WHERE scope='PAGOS' AND config_key IN
    ('NIUBIZ_EMAIL_TEMPLATE','NIUBIZ_EMAIL_DOMAIN')
    AND value_type='TEXT' AND value_status='REAL')<>2
 THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_CONFIG_AUTHORITY_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM lf_ops.reglas WHERE codigo IN
   ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
    'REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
    'REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001'))
 THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_ALREADY_CREATED'; END IF;
 FOR v IN SELECT * FROM (VALUES
   ('REG_CLIENT_NIUBIZ_UNIQUE_EMAIL_001',
    'EXEC-PROFILE-GATE2-8A32C42D5DE64233CB4ABE3E',
    'CHECKOUT_ESTADO_TARJETA',
    'b054d2d03bfa02d7730198c4cd19eb27ecc77a5fad7aa2fa36fbb07070e31eaa'),
   ('REG_CLIENT_PAYMENT_RECEIPT_REAL_EMAIL_001',
    'EXEC-PROFILE-GATE2-C1988A78EEC630B2C7D3348A',
    'CHECKOUT_PAGO_EXITOSO',
    '4ec80cae76a148a798fb6ceb69c2e53cc8f4f00346181e41582f3039e03bc3d4'),
   ('REG_CLIENT_NIUBIZ_GENERIC_BOUNCE_001',
    'EXEC-PROFILE-GATE2-447657D25F743AE8121267AC',
    'CHECKOUT_ESTADO_CONFIRMANDO',
    'b0d1b49a366397a69e7edff29bf604c3717c81e9a20e23b9a32f2314a46fa52c')
 ) x(rule_code,parent,screen,expected_patch_sha) LOOP
   SELECT s.evidence_payload#>'{profile_output,deliverable_created,governed_rule_patch}'
     INTO v_patch
   FROM public.lf_operation_execution_steps s
   JOIN public.lf_operation_execution e ON e.execution_id=s.execution_id
   WHERE s.execution_id=v.parent AND s.step_id='execute_profile'
     AND s.status='STEP_PASS_WITH_EVIDENCE'
     AND e.operation_code='EJECUCION_PERFIL_LF'
     AND e.target_code='PERFIL-PRODUCT-DIRECTOR-LF'
     AND e.status='IN_PROGRESS'
     AND e.manifest->>'read_only'='true'
     AND e.manifest->>'no_write'='true'
     AND e.manifest#>>'{screen_selection_result,selected_screen_code}'=v.screen
     AND e.manifest#>>'{router_profile_handoff,router_authorization_receipt,profile_execution_allowed}'='true';
   IF v_patch IS NULL
      OR v_patch->>'rule_code' IS DISTINCT FROM v.rule_code
      OR v_patch->>'change_kind'<>'CREATE'
      OR jsonb_typeof(v_patch->'changes')<>'object'
   THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_REAL_STEP50_PATCH_REQUIRED:%',v.rule_code; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.lf_operation_execution_steps s
      WHERE s.execution_id=v.parent AND s.step_id='output_validate'
        AND s.status='STEP_PASS_WITH_EVIDENCE'
        AND s.evidence_payload->>'output_contract_result'='PASS')
   THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_STEP60_REQUIRED:%',v.rule_code; END IF;
   v_hash:=encode(extensions.digest(convert_to(v_patch::text,'UTF8'),'sha256'),'hex');
   IF v_hash IS DISTINCT FROM v.expected_patch_sha
   THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_EXACT_PATCH_SHA_DRIFT:%',v.rule_code; END IF;
   v_refs:=v_patch#>'{changes,valor_config,niubiz_email_config_refs}';
   IF v_refs IS DISTINCT FROM v_expected
      OR coalesce(v_patch#>>'{changes,valor_config,production_authorized}','true')<>'false'
      OR v_patch#>>'{changes,categoria}'<>'pago'
      OR v_patch#>>'{changes,es_transversal}'<>'false'
      OR v_patch#>>'{changes,descripcion}' NOT LIKE '%public.lf_global_config%'
      OR v_patch#>>'{changes,descripcion}' NOT LIKE '%NIUBIZ_EMAIL_TEMPLATE%'
      OR v_patch#>>'{changes,descripcion}' NOT LIKE '%NIUBIZ_EMAIL_DOMAIN%'
      OR v_patch#>>'{changes,descripcion}' LIKE '%gmail.com%'
      OR v_patch#>>'{changes,descripcion}' LIKE '%lf-{codigo}%'
   THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_REFERENCES_OR_TEXT_DRIFT:%',v.rule_code; END IF;
   IF EXISTS(SELECT 1 FROM public.lf_ig_owner_decision_v2
      WHERE rule_code=v.rule_code)
   OR EXISTS(SELECT 1 FROM public.lf_ig_functional_train_evidence_v1
      WHERE rule_code=v.rule_code)
   THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_PREMATURE_DECISION_OR_EVIDENCE:%',v.rule_code; END IF;
   RAISE NOTICE 'NIUBIZ_RULE_CONTRACT_RAW_SOURCE_BOUND:%:%',v.rule_code,v.expected_patch_sha;
 END LOOP;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.codigo)::text,'[]'))
 INTO v_rules_after FROM lf_ops.reglas r;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.scope,g.config_key)::text,'[]'))
 INTO v_config_after FROM public.lf_global_config g;
 IF v_rules_after IS DISTINCT FROM v_rules_before
    OR v_config_after IS DISTINCT FROM v_config_before
 THEN RAISE EXCEPTION 'NIUBIZ_CONTRACT_UNEXPECTED_CANONICAL_MUTATION'; END IF;
 RAISE NOTICE 'NIUBIZ_3_RULE_CONTRACT_PROOF_ONLY_NO_RULE_WRITES';
END $niubiz_contract_proof$;
COMMIT;
