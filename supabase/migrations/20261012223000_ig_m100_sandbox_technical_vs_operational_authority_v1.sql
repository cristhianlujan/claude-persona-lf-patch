-- IG M10.0 phase split. Engineering qualification is NOT operational authorization.
-- Scope: M10.0 contract/action_specs/source_pack/checkpoint wording + read-only IG-specific
-- guard-verification function. No writes to human_decisions, promotions, release current or runtime.
-- Original operational exit criterion is preserved verbatim in unit_metadata for future admission.

CREATE OR REPLACE FUNCTION programacion.fn_ig_m100_sandbox_guard_matrix_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = 'pg_catalog','programacion','public'
AS $test$
DECLARE
 v_bundle programacion.provenance_receipts%ROWTYPE;
 v_ready programacion.provenance_receipts%ROWTYPE;
 v_bundle_id bigint;
 v_ready_id bigint;
 v_components_ok boolean := false;
 v_triggers_ok boolean := false;
 v_constraints_ok boolean := false;
 v_no_human boolean := false;
 v_no_promotion boolean := false;
 v_wrong_head boolean := false;
 v_bad_bundle boolean := false;
 v_missing_receipt boolean := false;
 v_forged_authority boolean := false;
 v_bad_cutover boolean := false;
 v_positive boolean := false;
 v_decision_literal_rejected boolean := false;
 v_all boolean := false;
 v_constraint text;
BEGIN
 SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
 INTO v_bundle_id
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND u.unit_code='M9.0' AND c.checkpoint_code='BUNDLE_READBACK' AND c.status='DONE';
 SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
 INTO v_ready_id
 FROM programacion.engineering_plan_units u
 JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
 WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND u.unit_code='M9.12' AND c.checkpoint_code='CUTOVER_READY_READBACK' AND c.status='DONE';
 IF v_bundle_id IS NULL OR v_ready_id IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','reason','UPSTREAM_CHECKPOINT_PIN_MISSING');
 END IF;
 SELECT * INTO v_bundle FROM programacion.provenance_receipts WHERE id=v_bundle_id;
 SELECT * INTO v_ready FROM programacion.provenance_receipts WHERE id=v_ready_id;
 IF v_bundle.id IS NULL OR v_ready.id IS NULL THEN
   RETURN jsonb_build_object('status','BLOCKED','reason','PINNED_RECEIPT_MISSING');
 END IF;

 -- Positive: actual canonical receipt verifier accepts the exact snapshot.
 PERFORM programacion.fn_assert_provenance_receipt(
   v_bundle.id,v_bundle.receipt_kind,v_bundle.execution_id,v_bundle.head_sha,
   v_bundle.subject_type,v_bundle.subject_ref,v_bundle.subject_sha256);
 PERFORM programacion.fn_assert_provenance_receipt(
   v_ready.id,v_ready.receipt_kind,v_ready.execution_id,v_ready.head_sha,
   v_ready.subject_type,v_ready.subject_ref,v_ready.subject_sha256);
 v_positive := v_bundle.receipt_kind='EVIDENCE_VERIFICATION'
   AND v_ready.receipt_kind='EVIDENCE_VERIFICATION'
   AND v_bundle.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND v_ready.issuer_channel='EVIDENCE_VERIFIER_V1'
   AND v_bundle.payload->>'verification_status'='VERIFIED'
   AND v_ready.payload->>'verification_status'='VERIFIED'
   AND v_ready.payload->>'readiness_status'='CUTOVER_READY'
   AND v_bundle.head_sha=v_ready.head_sha
   AND v_bundle.subject_sha256=v_ready.payload->>'bundle_sha256'
   AND v_bundle.payload#>>'{manifest,bundle_sha256}'=v_bundle.subject_sha256
   AND programacion.fn_v09_sha256_jsonb(v_bundle.payload#>'{manifest,identities}')=v_bundle.subject_sha256;
 SELECT count(*)=7 AND bool_and(
   programacion.fn_v09_sha256_jsonb(v_bundle.payload#>array['manifest','components',t.k])
     =v_bundle.payload#>>array['manifest','identities',t.k||'_sha256'])
 INTO v_components_ok
 FROM (VALUES ('contracts'),('registry'),('core'),('semantics'),('curator'),('validator'),('edge')) t(k);

 -- 5 actual fail-closed verifier cases. Each calls the real receipt guard;
 -- there are no INSERTs, updates or synthetic approved decisions.
 BEGIN
   PERFORM programacion.fn_assert_provenance_receipt(v_bundle.id,v_bundle.receipt_kind,
     v_bundle.execution_id,repeat('0',40),v_bundle.subject_type,v_bundle.subject_ref,v_bundle.subject_sha256);
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   v_wrong_head := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
 END;
 BEGIN
   PERFORM programacion.fn_assert_provenance_receipt(v_bundle.id,v_bundle.receipt_kind,
     v_bundle.execution_id,v_bundle.head_sha,v_bundle.subject_type,v_bundle.subject_ref,repeat('0',64));
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   v_bad_bundle := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
 END;
 BEGIN
   PERFORM programacion.fn_assert_provenance_receipt(0,v_ready.receipt_kind,v_ready.execution_id,
     v_ready.head_sha,v_ready.subject_type,v_ready.subject_ref,v_ready.subject_sha256);
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   v_missing_receipt := SQLERRM LIKE 'verified provenance receipt 0 not found%';
 END;
 BEGIN
   PERFORM programacion.fn_assert_provenance_receipt(v_bundle.id,'HUMAN_DECISION',
     v_bundle.execution_id,v_bundle.head_sha,'human_decision','FORGED',v_bundle.subject_sha256);
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   v_forged_authority := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
 END;
 BEGIN
   PERFORM programacion.fn_assert_provenance_receipt(v_ready.id,v_ready.receipt_kind,
     v_ready.execution_id,v_ready.head_sha,'IG_CUTOVER_READINESS','WRONG_COHORT',v_ready.subject_sha256);
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
   v_bad_cutover := SQLERRM LIKE 'verified provenance receipt does not bind exact subject%';
 END;

 SELECT pg_get_constraintdef(oid) INTO v_constraint FROM pg_constraint
 WHERE conrelid='programacion.human_decisions'::regclass
   AND conname='human_decisions_decision_check';
 v_decision_literal_rejected := v_constraint LIKE '%APPROVE%'
   AND v_constraint LIKE '%REJECT%'
   AND v_constraint NOT LIKE '%CUTOVER_AUTHORIZED%';
 SELECT count(*)=1 INTO v_constraints_ok FROM pg_constraint
 WHERE conrelid='programacion.human_decisions'::regclass
   AND conname='human_decisions_head_sha_check'
   AND pg_get_constraintdef(oid) LIKE '%{40}%';
 SELECT count(*)=3 INTO v_triggers_ok FROM pg_trigger
 WHERE NOT tgisinternal AND
 ((tgrelid='programacion.human_decisions'::regclass AND tgname IN
    ('trg_human_decisions_insert_guard','trg_human_decisions_authority_receipt'))
 OR (tgrelid='programacion.promotions'::regclass AND tgname='trg_promotions_verified_authority'));
 SELECT NOT EXISTS(SELECT 1 FROM programacion.human_decisions
   WHERE head_sha=v_bundle.head_sha AND decision='APPROVE'
     AND metadata->>'decision_class'='CUTOVER_AUTHORIZED') INTO v_no_human;
 SELECT NOT EXISTS(SELECT 1 FROM programacion.promotions
   WHERE head_sha=v_bundle.head_sha) INTO v_no_promotion;

 v_all:=coalesce(v_positive,false) AND coalesce(v_components_ok,false)
  AND coalesce(v_wrong_head,false) AND coalesce(v_bad_bundle,false)
  AND coalesce(v_missing_receipt,false) AND coalesce(v_forged_authority,false)
  AND coalesce(v_bad_cutover,false) AND coalesce(v_decision_literal_rejected,false)
  AND coalesce(v_constraints_ok,false) AND coalesce(v_triggers_ok,false)
  AND coalesce(v_no_human,false) AND coalesce(v_no_promotion,false);
 RETURN jsonb_build_object(
  'status',CASE WHEN v_all THEN 'PASS' ELSE 'FAIL_CLOSED' END,
  'mode','SANDBOX_ENGINEERING_ONLY','schema','IG_M100_GUARD_MATRIX_V1',
  'bundle_receipt_id',v_bundle.id,'cutover_receipt_id',v_ready.id,
  'positive_receipts_verified',v_positive,'seven_components_valid',v_components_ok,
  'negative_wrong_head_rejected',v_wrong_head,
  'negative_bundle_hash_rejected',v_bad_bundle,
  'negative_missing_cutover_receipt_rejected',v_missing_receipt,
  'negative_forged_authority_rejected',v_forged_authority,
  'negative_wrong_cutover_subject_rejected',v_bad_cutover,
  'invalid_decision_literal_rejected',v_decision_literal_rejected,
  'head_constraint_present',v_constraints_ok,'authority_triggers_present',v_triggers_ok,
  'no_human_cutover_approval',v_no_human,'no_operational_promotion',v_no_promotion,
  'data_writes',0,'production_activated',false);
END;
$test$;

REVOKE ALL ON FUNCTION programacion.fn_ig_m100_sandbox_guard_matrix_v1() FROM PUBLIC;

DO $change$
DECLARE
 v_metadata jsonb;
 v_specs jsonb;
 v_src jsonb;
 v_spec jsonb;
 v_old_exit text;
 v_test jsonb;
 v_work_id bigint;
 v_sql text := 'select programacion.fn_ig_m100_sandbox_guard_matrix_v1() as sandbox_guard_result';
 v_cp text;
BEGIN
 SELECT work_item_id,unit_metadata,exit_criterion INTO v_work_id,v_metadata,v_old_exit
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0' FOR UPDATE;
 IF v_work_id IS NULL OR
    v_metadata#>>'{action_specs_v1,HUMAN_DECISION_RECORD,status}' IS DISTINCT FROM 'BLOCK_OWNER_DECISION_REQUIRED'
    OR v_metadata#>>'{m10_0_contract_governance_v3,schema}' IS DISTINCT FROM 'M100_M912_SIGNED_READINESS_GATE_V2'
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_id AND sequence_no <=4 AND status='DONE')<>4
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_id AND sequence_no >=5 AND status='PENDING')<>3
 THEN RAISE EXCEPTION 'M100_TWO_PHASE_PRESTATE_DRIFT'; END IF;
 v_test:=programacion.fn_ig_m100_sandbox_guard_matrix_v1();
 IF v_test->>'status'<>'PASS' THEN
   RAISE EXCEPTION 'M100_SANDBOX_PRECHECK_FAILED:%',v_test::text;
 END IF;
 v_specs:=v_metadata->'action_specs_v1';
 v_src:=v_metadata->'source_pack_v1';

 -- CP5 is a guard-qualification proof, NOT a human decision.
 v_spec:=v_specs->'HUMAN_DECISION_RECORD';
 v_metadata:=jsonb_set(v_metadata,'{m10_0_original_human_decision_spec_v1}',v_spec,true);
 v_spec:=(v_spec-'decision_authority_contract')
   ||jsonb_build_object(
    'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
    'contract_family','CANONICAL_LEDGER_READBACK',
    'precision','IG_M100_ENGINEERING_AUTHORITY_GUARD_V1',
    'expected','Verify owner approval guard is enforced and no human CUTOVER_AUTHORIZED or operational promotion exists. NEVER INSERT an approval as sandbox evidence.',
    'requires_material_execution',false,'verification_queries',jsonb_build_array(v_sql),
    'mutation_policy','NO_DOMAIN_MUTATION',
    'target',jsonb_build_object('declared_objects',jsonb_build_array(
       'programacion.human_decisions','programacion.promotions',
       'programacion.provenance_receipts','programacion.fn_ig_m100_sandbox_guard_matrix_v1'),
      'declared_artifacts','[]'::jsonb,'mutation_artifacts','[]'::jsonb,
      'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb));
 v_specs:=jsonb_set(v_specs,'{HUMAN_DECISION_RECORD}',v_spec,true);

 -- CP6 uses the real existing receipt guard, 1 positive + 5 adversarial
 -- subtransaction checks; no synthetic PASS and no new promotion engine.
 v_spec:=v_specs->'NEG_SHA_MISMATCH';
 v_metadata:=jsonb_set(v_metadata,'{m10_0_original_negative_spec_v1}',v_spec,true);
 v_spec:=(v_spec-'test_execution_contract'-'negative_contract_v1')
   ||jsonb_build_object(
    'status','READY','action_kind','READBACK_ONCE','recipe_mode','READBACK_EXACT',
    'contract_family','CANONICAL_LEDGER_READBACK',
    'precision','IG_M100_REAL_VERIFIER_NEGATIVES_V1',
    'expected','The existing canonical fn_assert_provenance_receipt rejects head mismatch, bundle mismatch, absent CUTOVER_READY, forged authority and wrong readiness subject. Invalid decision literal is rejected by the actual DB CHECK. No domain writes.',
    'requires_material_execution',false,
    'verification_queries',jsonb_build_array(v_sql),
    'mutation_policy','NO_DOMAIN_MUTATION',
    'target',jsonb_build_object('declared_objects',jsonb_build_array(
       'programacion.provenance_receipts','programacion.fn_assert_provenance_receipt',
       'programacion.fn_ig_m100_sandbox_guard_matrix_v1','pg_constraint','pg_trigger'),
      'declared_artifacts','[]'::jsonb,'mutation_artifacts','[]'::jsonb,
      'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb));
 v_specs:=jsonb_set(v_specs,'{NEG_SHA_MISMATCH}',v_spec,true);

 -- CP7 terminal readback is the engineering exit; separately frozen
 -- operational authority remains fail-closed even after engineering DONE.
 v_spec:=jsonb_build_object(
   'status','READY','checkpoint_code','AUTHORITY_READBACK',
   'schema_version','ENGINEERING_ACTION_SPEC_V3','action_kind','READBACK_ONCE',
   'recipe_mode','READBACK_EXACT','contract_family','CANONICAL_LEDGER_READBACK',
   'contract_source','EXPLICIT_ACTION_SPEC',
   'precision','IG_M100_ENGINEERING_CLOSURE_READBACK_V1',
   'expected','Re-read signed M9.0 and M9.12 identities, five negative controls and no approvals/promotions; check CP5 and CP6 ledger DONE. Engineering DONE does not authorize cutover.',
   'verification_queries',jsonb_build_array(v_sql),
   'mutation_policy','NO_DOMAIN_MUTATION','requires_material_execution',false,
   'target',jsonb_build_object('declared_objects',jsonb_build_array(
      'programacion.engineering_work_checkpoints','programacion.provenance_receipts',
      'programacion.human_decisions','programacion.promotions',
      'programacion.fn_ig_m100_sandbox_guard_matrix_v1'),
    'declared_artifacts','[]'::jsonb,'mutation_artifacts','[]'::jsonb,
    'declared_assets','[]'::jsonb,'declared_events','[]'::jsonb));
 v_specs:=jsonb_set(v_specs,'{AUTHORITY_READBACK}',v_spec,true);

 FOREACH v_cp IN ARRAY ARRAY['HUMAN_DECISION_RECORD','NEG_SHA_MISMATCH','AUTHORITY_READBACK'] LOOP
   v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'inputs','queries'],
      jsonb_build_array(v_sql),true);
   v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'inputs','db_objects'],
      '["programacion.fn_ig_m100_sandbox_guard_matrix_v1","programacion.provenance_receipts","programacion.engineering_work_checkpoints","programacion.human_decisions","programacion.promotions","pg_constraint","pg_trigger"]'::jsonb,true);
   v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'inputs','artifacts'],'[]'::jsonb,true);
   v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'missing'],'[]'::jsonb,true);
   v_src:=jsonb_set(v_src,ARRAY['checkpoint_inputs',v_cp,'missing_typed'],'[]'::jsonb,true);
 END LOOP;

 v_metadata:=jsonb_set(v_metadata,'{action_specs_v1}',v_specs,true);
 v_metadata:=jsonb_set(v_metadata,'{source_pack_v1}',v_src,true);
 v_metadata:=jsonb_set(v_metadata,'{m10_0_operational_admission_v1}',
   jsonb_build_object(
    'status','BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY',
    'original_operational_exit_criterion',v_old_exit,
    'human_decision_table','programacion.human_decisions',
    'required_decision','APPROVE','decision_class','CUTOVER_AUTHORIZED',
    'required_authority_receipt_kind','HUMAN_DECISION',
    'frozen_m90_receipt_checkpoint','BUNDLE_READBACK',
    'readiness_m912_receipt_checkpoint','CUTOVER_READY_READBACK',
    'exact_head_and_bundle_required',true,'approval_ref_required',true,
    'real_independent_audit_and_manifest_gate_unchanged',true,
    'operational_cutover_admitted',false,'production_activation',false,
    'technical_done_never_implies_operational_admission',true,
    'enforcement','EXISTING_HUMAN_DECISION_AND_PROMOTION_DB_GUARDS'),true);
 v_metadata:=jsonb_set(v_metadata,'{m10_0_engineering_admission_v1}',
   jsonb_build_object('scope','SANDBOX_ENGINEERING_QUALIFICATION_ONLY',
      'test_function','programacion.fn_ig_m100_sandbox_guard_matrix_v1',
      'positive_receipt_case',1,'negative_receipt_cases',5,
      'reusable_existing_verifier',true,'no_domain_mutation',true,
      'no_synthetic_human_decision',true,'operational_gate_separate',true),true);

 UPDATE programacion.engineering_plan_units
 SET unit_metadata=v_metadata,
 exit_criterion='ENGINEERING SANDBOX ONLY: CP5 verifies human authority guards and zero cutover approvals/promotions; CP6 proves one authentic receipt positive and five genuine wrong-head/bundle/receipt/authority negatives through the canonical verifier plus the decision CHECK; CP7 reads back signed M9.0/M9.12, controls, 0 domain writes and operational gate BLOCKED. DONE here never means operational CUTOVER_AUTHORIZED. Original operational exit stored unmodified in unit_metadata.m10_0_operational_admission_v1.'
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M10.0';
 UPDATE programacion.engineering_work_checkpoints
 SET title=CASE checkpoint_code
  WHEN 'HUMAN_DECISION_RECORD' THEN 'Sandbox: comprobar guard de autoridad humana, sin registrar decisiones'
  WHEN 'NEG_SHA_MISMATCH' THEN 'Sandbox: ejecutar verificador positivo y cinco rechazos adversariales reales'
  WHEN 'AUTHORITY_READBACK' THEN 'Readback terminal técnico; admisión operativa sigue bloqueada'
 END
 WHERE work_item_id=v_work_id AND sequence_no BETWEEN 5 AND 7 AND status='PENDING';
 IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_work_id AND sequence_no BETWEEN 5 AND 7 AND status='PENDING')<>3
 THEN RAISE EXCEPTION 'M100_CHECKPOINTS_CHANGED_UNEXPECTEDLY'; END IF;
END;
$change$;
