-- LF IG M4.11 / PAULO-143: CP2 governed one-time ledger reconciliation.
-- Source-first via LF Migration Merge Train ONLY. This is not a reusable DML
-- transport, runtime activation, role grant, or change to CP3/CP4/CP5/CP6.
-- Authority: current M4.11 CP2 contract M411_UPSTREAM_READBACK_ONLY_V1
-- and existing EVIDENCE_VERIFICATION receipt M9.12 #1667 (exact SHA/bundle).
-- EKB: RTE-001, IG-ENGINEERING-TRANSITION-EMPTY-EVIDENCE-001,
-- IG-EKB-READ-WITHOUT-SEMANTIC-PREFLIGHT-001,
-- IG-M99-SANDBOX-LIVE-ADMISSION-CONFLATION-001.
-- Negative exercises are subtransactions that roll back; positive transition
-- uses ONLY fn_engineering_checkpoint_transition_v1.
DO $m411_cp2$
DECLARE
  v_unit record;
  v_cp2 record;
  v_upstream_count integer;
  v_receipt_count integer;
  v_spec jsonb;
  v_cp3_spec jsonb;
  v_before jsonb;
  v_outcome jsonb;
  v_after jsonb;
  v_negative_rejected boolean := false;
  v_evidence text :=
    'supabase://programacion.provenance_receipts/1667'
    || '#sha=b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
    || ';readback=IG_M411_UPSTREAM_READBACK_V1:PASS'
    || ';upstream=3/3'
    || ';bundle=db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
    || ';scope=SANDBOX_UPSTREAM_READBACK_ONLY';
BEGIN
  SELECT u.id, u.work_item_id, w.status
    INTO STRICT v_unit
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND u.unit_code='M4.11'
     AND u.disposition='ASSIGNED'
   FOR UPDATE OF u,w;

  IF v_unit.status IS DISTINCT FROM 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'M411_CP2_WORK_STATUS_CHANGED:%',v_unit.status;
  END IF;
  SELECT c.status,c.evidence_ref INTO STRICT v_cp2
    FROM programacion.engineering_work_checkpoints c
   WHERE c.work_item_id=v_unit.work_item_id
     AND c.checkpoint_code='PREREQ_GATES_PASS'
   FOR UPDATE;
  IF v_cp2.status IS DISTINCT FROM 'PENDING'
     OR v_cp2.evidence_ref IS NOT NULL THEN
    RAISE EXCEPTION 'M411_CP2_STATE_CHANGED_REASSESS:%',v_cp2.status;
  END IF;
  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints
     WHERE work_item_id=v_unit.work_item_id
       AND sequence_no > 2
       AND status <> 'PENDING'
  ) THEN
    RAISE EXCEPTION 'M411_CP3_PLUS_OUT_OF_SEQUENCE';
  END IF;

  v_before:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
  IF v_before->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
     OR v_before#>>'{current_checkpoint,checkpoint_code}'
        IS DISTINCT FROM 'PREREQ_GATES_PASS'
     OR (v_before#>>'{state,open_blockers}')::integer <> 0
     OR (v_before#>>'{state,unmet_deps}')::integer <> 0
  THEN RAISE EXCEPTION 'M411_CP2_BOOTSTRAP_NO_LONGER_READY:%',v_before->>'terminal_action';
  END IF;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','PREREQ_GATES_PASS');
  v_cp3_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE');
  IF v_spec->>'status' IS DISTINCT FROM 'READY'
    OR v_spec->>'precision' IS DISTINCT FROM 'M411_UPSTREAM_READBACK_ONLY_V1'
    OR v_spec->>'action_kind' IS DISTINCT FROM 'READBACK_ONCE'
    OR v_spec#>>'{required_evidence_contract,evidence_ref_required}' IS DISTINCT FROM 'true'
    OR v_spec#>>'{required_evidence_contract,independence_claim}' IS DISTINCT FROM 'NOT_MADE'
    OR v_spec#>>'{required_evidence_contract,production_authorized}' IS DISTINCT FROM 'false'
    OR v_spec#>>'{required_evidence_contract,signed_cutover_receipt_id}' IS DISTINCT FROM '1667'
    OR v_cp3_spec->>'status' = 'READY'
  THEN
    RAISE EXCEPTION 'M411_CP2_CONTRACT_OR_CP3_GOVERNANCE_DRIFT';
  END IF;

  SELECT count(*) INTO v_upstream_count
    FROM programacion.engineering_plan_units u
    JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
   WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
     AND u.unit_code IN ('M4.10','M9.8','M9.12')
     AND w.status='DONE';
  IF v_upstream_count <> 3 THEN
    RAISE EXCEPTION 'M411_CP2_UPSTREAM_NOT_3_OF_3:%',v_upstream_count;
  END IF;
  SELECT count(*) INTO v_receipt_count
    FROM programacion.provenance_receipts
   WHERE id=1667
     AND receipt_kind='EVIDENCE_VERIFICATION'
     AND subject_type='IG_CUTOVER_READINESS'
     AND subject_ref='plan://IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.12/CUTOVER_READY'
     AND receipt_sha256='b4b8174360d8478c122340ca25973ba54cdcd7785d2d168ae8271840fc0c7fc5'
     AND issuer_identity='SUPABASE:IG_M912_READINESS_VERIFIER_V1'
     AND payload->>'verification_status'='VERIFIED'
     AND payload->>'readiness_status'='CUTOVER_READY'
     AND payload->>'bundle_sha256'='db84f4ab3cdcc0fe3dcdd463be70ad9b4c96ec7beb9be9cc56b9d344793e7f2f'
     AND payload#>>'{manifest,bundle_sha256}'=payload->>'bundle_sha256'
     AND payload#>>'{manifest,production_activation}'='false';
  IF v_receipt_count<>1 THEN
    RAISE EXCEPTION 'M411_CP2_SIGNED_RECEIPT_NOT_VERIFIED:%',v_receipt_count;
  END IF;

  -- Negative gate: invented/missing evidence must never permit a terminal CP2.
  -- PL/pgSQL exception subtransaction rolls back any accidental effects.
  BEGIN
    PERFORM programacion.fn_engineering_checkpoint_transition_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','PREREQ_GATES_PASS',
      'DONE','','IG_M411_CP2_NEGATIVE_TEST',NULL);
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%Terminal checkpoint transition requires evidence%'
       OR SQLERRM LIKE '%ENGINEERING_EXPLICIT_EVIDENCE_REF_REQUIRED%'
    THEN
      v_negative_rejected:=true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_negative_rejected THEN
    RAISE EXCEPTION 'M411_CP2_NEGATIVE_EMPTY_EVIDENCE_FALSE_PASS';
  END IF;
  IF (SELECT c.status FROM programacion.engineering_work_checkpoints c
      WHERE c.work_item_id=v_unit.work_item_id
        AND c.checkpoint_code='PREREQ_GATES_PASS') IS DISTINCT FROM 'PENDING'
  THEN
    RAISE EXCEPTION 'M411_CP2_NEGATIVE_TEST_LEFT_RESIDUE';
  END IF;
  IF EXISTS (SELECT 1 FROM programacion.provenance_receipts
     WHERE id=-1667) THEN
    RAISE EXCEPTION 'M411_CP2_NEGATIVE_SENTINEL_COLLISION';
  END IF;

  -- One and only one governed transition on the canonical checkpoint.
  v_outcome:=programacion.fn_engineering_checkpoint_transition_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','PREREQ_GATES_PASS',
    'DONE',v_evidence,'IG_M411_CP2_TRAIN_CANONICAL',
    'CP2 3/3 M4.10 M9.8 M9.12 DONE; receipt #1667 exact VERIFIED SHA and bundle; '
    || 'CP2 READBACK_ONLY. No T-INDEP claim, no oracle or production activation. '
    || 'Transport: governed one-time Merge Train reconciliation.');
  IF v_outcome#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
     OR v_outcome#>>'{transition,checkpoint_code}' IS DISTINCT FROM 'PREREQ_GATES_PASS'
  THEN
    RAISE EXCEPTION 'M411_CP2_CANONICAL_TRANSITION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints c
    WHERE c.work_item_id=v_unit.work_item_id
      AND c.checkpoint_code='PREREQ_GATES_PASS'
      AND c.status='DONE'
      AND c.evidence_ref=v_evidence
      AND c.completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'M411_CP2_POSTWRITE_EVIDENCE_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1 FROM programacion.engineering_work_checkpoints c
     WHERE c.work_item_id=v_unit.work_item_id
       AND c.sequence_no>2
       AND (c.status<>'PENDING' OR c.evidence_ref IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'M411_CP2_UNAUTHORIZED_CP3_PLUS_MUTATION';
  END IF;

  v_after:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11');
  IF (v_after#>>'{state,done_checkpoint_count}')::integer<>2
     OR (v_after#>>'{state,checkpoint_count}')::integer<>6
     OR v_after#>>'{current_checkpoint,checkpoint_code}'
        IS DISTINCT FROM 'DECISIONAL_BINDING_VIA_RELEASE'
  THEN
    RAISE EXCEPTION 'M411_CP2_BOOTSTRAP_READBACK_DRIFT:%',v_after#>>'{current_checkpoint,checkpoint_code}';
  END IF;
  IF (SELECT w.status FROM programacion.engineering_work_items w
      WHERE w.id=v_unit.work_item_id) IS DISTINCT FROM 'IN_PROGRESS'
  THEN RAISE EXCEPTION 'M411_CP2_UNIT_WAS_FALSELY_CLOSED'; END IF;
  IF programacion.fn_engineering_checkpoint_action_spec_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M4.11','DECISIONAL_BINDING_VIA_RELEASE'
    )->>'status' = 'READY'
  THEN RAISE EXCEPTION 'M411_CP3_INDEPENDENCE_GATE_MUST_REMAIN_CLOSED'; END IF;
END;
$m411_cp2$;
