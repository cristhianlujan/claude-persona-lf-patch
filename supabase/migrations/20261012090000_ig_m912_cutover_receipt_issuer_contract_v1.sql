-- IG M9.12: bounded, signed CUTOVER_READY receipt; never activates runtime/production.
-- EKB: M9.9/M9.10 sandbox-vs-live separation, M9.12 missing receipt producer.
CREATE OR REPLACE FUNCTION programacion.fn_ig_m912_cutover_ready_receipt_v1(p_expected_bundle_sha text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, programacion
AS $f$
DECLARE
  v_bundle_id bigint;
  v_bundle programacion.provenance_receipts%rowtype;
  v_good_units integer;
  v_all_units integer;
  v_proofs jsonb;
  v_subject jsonb;
  v_subject_sha text;
  v_ref constant text := 'plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY';
  v_issuer constant text := 'SUPABASE:IG_M912_READINESS_VERIFIER_V1';
  v_token text;
  v_payload jsonb;
  v_receipt_id bigint;
  v_receipt_sha text;
BEGIN
  IF coalesce(p_expected_bundle_sha,'') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'M912_BUNDLE_SHA_REQUIRED';
  END IF;
  SELECT substring(c.evidence_ref FROM 'provenance_receipts/([0-9]+)')::bigint
    INTO v_bundle_id
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.0' AND c.checkpoint_code='BUNDLE_READBACK' AND c.status='DONE';
  IF v_bundle_id IS NULL THEN RAISE EXCEPTION 'M912_M90_PINNED_RECEIPT_MISSING'; END IF;
  SELECT * INTO v_bundle FROM programacion.provenance_receipts WHERE id=v_bundle_id;
  IF NOT FOUND OR v_bundle.receipt_kind IS DISTINCT FROM 'EVIDENCE_VERIFICATION'
    OR v_bundle.issuer_channel IS DISTINCT FROM 'EVIDENCE_VERIFIER_V1'
    OR v_bundle.subject_type IS DISTINCT FROM 'input_governance_release_bundle'
    OR v_bundle.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
    OR v_bundle.subject_sha256 IS DISTINCT FROM v_bundle.payload#>>'{manifest,bundle_sha256}'
    OR v_bundle.subject_sha256 IS DISTINCT FROM p_expected_bundle_sha
  THEN RAISE EXCEPTION 'M912_M90_PINNED_BUNDLE_CURRENTNESS_MISMATCH'; END IF;
  PERFORM programacion.fn_assert_provenance_receipt(
    v_bundle.id,'EVIDENCE_VERIFICATION',v_bundle.execution_id,v_bundle.head_sha,
    v_bundle.subject_type,v_bundle.subject_ref,v_bundle.subject_sha256);
  WITH unit_checks AS (
    SELECT u.unit_code,w.status AS unit_status, count(*) AS total,
      count(*) FILTER (WHERE c.status='DONE' AND nullif(c.evidence_ref,'') IS NOT NULL) AS attested,
      bool_or(u.unit_code='M9.8' AND c.checkpoint_code='GATE_VERDICT_READBACK'
        AND c.status='DONE' AND c.evidence_ref LIKE '%fn_ig_m98_engineering_assurance_v7%'
        AND u.unit_metadata#>>'{m9_8_gate_contract_v2,technical_positive_state}'='TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED') AS technical_ok,
      bool_or(u.unit_code='M9.10' AND c.checkpoint_code='DRILL_READBACK'
        AND c.status='DONE') AS drill_ok,
      bool_or(u.unit_code='M9.11' AND c.checkpoint_code='SOAK_READBACK'
        AND c.status='DONE') AS soak_ok,
      jsonb_agg(jsonb_build_object('checkpoint',c.checkpoint_code,'status',c.status,
        'evidence_ref',c.evidence_ref) ORDER BY c.sequence_no) AS checkpoints
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
    JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND u.unit_code IN ('M9.0','M9.8','M9.10','M9.11')
    GROUP BY u.unit_code,w.status
  )
  SELECT count(*)::integer,
    count(*) FILTER (WHERE unit_status='DONE' AND total=attested AND total>0)::integer,
    jsonb_agg(jsonb_build_object('unit_code',unit_code,'unit_status',unit_status,
      'checkpoint_total',total,'checkpoint_attested',attested,
      'technical_ok',technical_ok,'drill_ok',drill_ok,'soak_ok',soak_ok,
      'checkpoints',checkpoints) ORDER BY unit_code)
  INTO v_all_units,v_good_units,v_proofs FROM unit_checks;
  IF v_all_units<>4 OR v_good_units<>4
    OR NOT EXISTS (
      SELECT 1 FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
      WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
        AND u.unit_code='M9.8' AND c.checkpoint_code='GATE_VERDICT_READBACK'
        AND c.status='DONE' AND c.evidence_ref LIKE '%fn_ig_m98_engineering_assurance_v7%'
        AND u.unit_metadata#>>'{m9_8_gate_contract_v2,technical_positive_state}'='TECHNICAL_CONTROLS_VERIFIED_NOT_RELEASED'
    )
    OR NOT EXISTS (
      SELECT 1 FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
      WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
        AND u.unit_code='M9.10' AND c.checkpoint_code='DRILL_READBACK'
        AND c.status='DONE' AND nullif(c.evidence_ref,'') IS NOT NULL
    )
    OR NOT EXISTS (
      SELECT 1 FROM programacion.engineering_plan_units u
      JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
      WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
        AND u.unit_code='M9.11' AND c.checkpoint_code='SOAK_READBACK'
        AND c.status='DONE' AND nullif(c.evidence_ref,'') IS NOT NULL
    )
  THEN RAISE EXCEPTION 'M912_UPSTREAM_ENGINEERING_PROOFS_INCOMPLETE'; END IF;
  IF EXISTS(SELECT 1 FROM programacion.promotions) THEN
    RAISE EXCEPTION 'M912_PROMOTION_OR_PRODUCTION_NOT_ALLOWED';
  END IF;
  v_subject:=jsonb_build_object(
    'schema_version','IG_CUTOVER_READINESS_RECEIPT_V1',
    'readiness_status','CUTOVER_READY',
    'bundle_receipt_id',v_bundle.id,
    'bundle_receipt_sha256',v_bundle.receipt_sha256,
    'bundle_sha256',v_bundle.subject_sha256,
    'bundle_head_sha',v_bundle.head_sha,
    'prerequisites',v_proofs,
    'production_activation',false,
    'post_pase','DISABLED_NOT_REQUIRED',
    'm98_admission','TECHNICAL_VERIFIED_NOT_RELEASED');
  v_subject_sha:=programacion.fn_v09_sha256_jsonb(v_subject);
  SELECT id,receipt_sha256 INTO v_receipt_id,v_receipt_sha
  FROM programacion.provenance_receipts
  WHERE receipt_kind='EVIDENCE_VERIFICATION'
    AND issuer_channel='EVIDENCE_VERIFIER_V1'
    AND subject_type='IG_CUTOVER_READINESS'
    AND subject_ref=v_ref AND subject_sha256=v_subject_sha
    AND head_sha=v_bundle.head_sha
    AND payload->>'verification_status'='VERIFIED'
    AND payload->>'readiness_status'='CUTOVER_READY'
  ORDER BY id DESC LIMIT 1;
  IF v_receipt_id IS NULL THEN
    SELECT decrypted_secret INTO v_token
    FROM vault.decrypted_secrets
    WHERE name='EVIDENCE_VERIFIER_V1_TOKEN'
    ORDER BY created_at DESC LIMIT 1;
    IF length(coalesce(v_token,''))<32 THEN RAISE EXCEPTION 'M912_VERIFIER_CHANNEL_CREDENTIAL_UNAVAILABLE'; END IF;
    v_payload:=jsonb_build_object(
      'head_sha',v_bundle.head_sha,'subject_type','IG_CUTOVER_READINESS',
      'subject_ref',v_ref,'subject_sha256',v_subject_sha,
      'verification_status','VERIFIED','verifier_identity',v_issuer,
      'verification_method','SIGNED_IG_LEDGER_CURRENTNESS_V1',
      'readiness_status','CUTOVER_READY','bundle_sha256',v_bundle.subject_sha256,
      'production_inactive',true,'prerequisites_current',true,
      'manifest',v_subject);
    SELECT id,receipt_sha256 INTO v_receipt_id,v_receipt_sha
    FROM programacion.issue_provenance_receipt(
      'EVIDENCE_VERIFIER_V1',v_token,'EVIDENCE_VERIFICATION',
      null,v_bundle.head_sha,'IG_CUTOVER_READINESS',v_ref,v_subject_sha,
      v_issuer,'supabase://programacion.engineering_work_checkpoints/M9.12#pinned-m90-bundle',
      v_payload);
  END IF;
  PERFORM programacion.fn_assert_provenance_receipt(
    v_receipt_id,'EVIDENCE_VERIFICATION',null,v_bundle.head_sha,
    'IG_CUTOVER_READINESS',v_ref,v_subject_sha);
  RETURN jsonb_build_object(
    'status','CUTOVER_READY','receipt_id',v_receipt_id,
    'receipt_sha256',v_receipt_sha,'subject_sha256',v_subject_sha,
    'bundle_sha256',v_bundle.subject_sha256,'bundle_receipt_id',v_bundle.id,
    'prerequisites_current',true,'production_inactive',true,
    'semantic_authority_bound',true,'verified_cutover_receipt_current',true);
END;
$f$;

REVOKE ALL ON FUNCTION programacion.fn_ig_m912_cutover_ready_receipt_v1(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION programacion.fn_ig_m912_cutover_ready_receipt_v1(text) TO service_role;
COMMENT ON FUNCTION programacion.fn_ig_m912_cutover_ready_receipt_v1(text) IS
'IG M9.12: emits idempotent signed CUTOVER_READY bound to M9.0 pinned bundle and attested technical prerequisites; no runtime or production activation.';

DO $repair$
DECLARE v_w bigint; m jsonb; s jsonb; p jsonb; objs jsonb;
BEGIN
 SELECT work_item_id,unit_metadata INTO v_w,m
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.12'
 FOR UPDATE;
 IF v_w IS NULL OR m#>>'{action_specs_v1,CLOSURE_GATE_CONSUME,capability_execution_contract,result}' IS DISTINCT FROM 'CUTOVER_READY'
 THEN RAISE EXCEPTION 'M912_CONTRACT_SOURCE_DRIFT'; END IF;
 s:=m#>'{action_specs_v1,CLOSURE_GATE_CONSUME}';
 IF s IS NULL THEN RAISE EXCEPTION 'M912_CP3_ACTION_SPEC_MISSING'; END IF;
 objs:=coalesce(s#>'{target,declared_objects}','[]'::jsonb);
 IF NOT (objs ? 'programacion.fn_ig_m912_cutover_ready_receipt_v1') THEN
   objs:=objs||to_jsonb('programacion.fn_ig_m912_cutover_ready_receipt_v1'::text);
 END IF;
 s:=jsonb_set(s,'{target,declared_objects}',objs,true);
 s:=jsonb_set(s,'{capability_execution_contract,issuer_entrypoint}',
    to_jsonb('programacion.fn_ig_m912_cutover_ready_receipt_v1(text)'::text),true);
 s:=jsonb_set(s,'{capability_execution_contract,pinned_bundle_source}',
    to_jsonb('M9.0/BUNDLE_READBACK:EVIDENCE_VERIFIER_V1'::text),true);
 s:=jsonb_set(s,'{capability_execution_contract,receipt_production_stage}',
    to_jsonb('CLOSURE_GATE_CONSUME_BEFORE_POSITIVE_ASSERTION'::text),true);
 s:=jsonb_set(s,'{expected}',to_jsonb(
    'Consume actual signed IG CUTOVER_READY produced by authorized receipt issuer after M9.0 pinned bundle and current M9.8 technical/M9.10 drill/M9.11 soak; test output cannot substitute receipt.'::text),true);
 m:=jsonb_set(m,'{action_specs_v1,CLOSURE_GATE_CONSUME}',s,true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,receipt_producer}',
    to_jsonb('programacion.fn_ig_m912_cutover_ready_receipt_v1(text)'::text),true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,release_admission_state}',
    to_jsonb('SEPARATE_BLOCKED_UNTIL_LIVE_RECEIPTS'::text),true);
 m:=jsonb_set(m,'{cutover_readiness_governance_v1,pinned_m90_bundle}',
    to_jsonb('M9.0/BUNDLE_READBACK'::text),true);
 p:=m->'source_pack_v1';
 IF p IS NULL THEN RAISE EXCEPTION 'M912_SOURCE_PACK_MISSING'; END IF;
 p:=jsonb_set(p,'{checkpoint_inputs,CLOSURE_GATE_CONSUME,inputs,db_objects}',
   coalesce(p#>'{checkpoint_inputs,CLOSURE_GATE_CONSUME,inputs,db_objects}','[]'::jsonb)||
   jsonb_build_array('programacion.fn_ig_m912_cutover_ready_receipt_v1'),true);
 m:=jsonb_set(m,'{source_pack_v1}',p,true);
 UPDATE programacion.engineering_plan_units SET unit_metadata=m
 WHERE work_item_id=v_w AND plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2';
END $repair$;
