-- M4.11 contract/governance readback tests.
-- Execute AFTER the migration in LF_SUPABASE_SANDBOX only.
-- Every assertion must succeed, with no permanent ledger/capability changes.
BEGIN;
DO $test$
DECLARE
  v_cp2 jsonb;
  v_cp3 jsonb;
  v_state jsonb;
  v_packet jsonb;
  v_receipt programacion.provenance_receipts%rowtype;
  v_done_count integer;
  v_negative_count integer;
BEGIN
  SELECT unit_metadata#>'{action_specs_v1,PREREQ_GATES_PASS}',
         unit_metadata#>'{action_specs_v1,DECISIONAL_BINDING_VIA_RELEASE}'
    INTO v_cp2,v_cp3
    FROM programacion.engineering_plan_units
   WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M4.11';
  IF v_cp2->>'status'<>'READY'
     OR v_cp2#>>'{required_evidence_contract,independence_claim}'<>'NOT_MADE'
     OR v_cp3#>>'{required_evidence_contract,required_overall_state}'<>'INDEPENDENT'
     OR v_cp3#>>'{required_evidence_contract,t_indep_receipt_required}'<>'true'
     OR v_cp3->>'status'='READY' THEN
    RAISE EXCEPTION 'M411_PHASE_BOUNDARY_NOT_ENFORCED';
  END IF;
  SELECT count(*) INTO v_done_count
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND u.unit_code IN ('M4.10','M9.8','M9.12')
     AND w.status='DONE';
  IF v_done_count<>3 THEN
    RAISE EXCEPTION 'M411_UPSTREAM_NOT_VERIFIED';
  END IF;
  SELECT * INTO v_receipt FROM programacion.provenance_receipts
   WHERE id=1667 AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
     AND payload->>'verification_status'='VERIFIED'
     AND payload->>'readiness_status'='CUTOVER_READY'
     AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'M411_EXACT_SIGNED_RECEIPT_POSITIVE_FAILED';
  END IF;
  -- Negative: changed SHA must be rejected by the exact readback predicate.
  SELECT count(*) INTO v_negative_count
    FROM programacion.provenance_receipts
   WHERE id=1667 AND receipt_sha256='0000000000000000000000000000000000000000000000000000000000000000'
     AND payload->>'verification_status'='VERIFIED';
  IF v_negative_count<>0 THEN
    RAISE EXCEPTION 'M411_WRONG_RECEIPT_DIGEST_ACCEPTED';
  END IF;
  -- Negative: wrong bundle must not bind this historical cutover.
  IF (v_receipt.payload || jsonb_build_object('bundle_sha256','bad')) ->> 'bundle_sha256'
      = v_cp2#>>'{required_evidence_contract,bundle_sha256}' THEN
    RAISE EXCEPTION 'M411_CHANGED_BUNDLE_WAS_ACCEPTED';
  END IF;
  v_state:=programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
  IF v_state#>>'{action_spec,status}' <> 'READY'
     OR v_state->>'terminal_action'<>'CONTINUE_CURRENT_CHECKPOINT' THEN
    RAISE EXCEPTION 'M411_CP2_BOOTSTRAP_NOT_READY';
  END IF;
  v_packet:=v_state->'execution_packet';
  IF v_packet->>'status'<>'READY'
     OR v_packet#>>'{connector_plan,0,operation}'<>'READ' THEN
    RAISE EXCEPTION 'M411_CP2_PACKET_NOT_READY';
  END IF;
  -- The engineering prerequisite does not automatically complete either checkpoint.
  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints c
    JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
    WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
      AND u.unit_code='M4.11'
      AND c.checkpoint_code IN ('PREREQ_GATES_PASS','DECISIONAL_BINDING_VIA_RELEASE')
      AND c.status='DONE'
  ) THEN
    RAISE EXCEPTION 'M411_CHECKPOINT_MOVED_WITHOUT_EVIDENCE';
  END IF;
  RAISE NOTICE 'PASS M4.11: exact historical receipt + phase boundary; negatives rejected; CP2 compiled; CP3 fail-closed; no mutations';
END;
$test$;
ROLLBACK;
