-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M10.0 ONLY (PAULO-159).
-- Close 3 engineering checkpoints from genuinely applied, signed evidence.
-- This is a NEW, strictly scoped Train migration. Never execute legacy SQL,
-- stamp the debt ledger, create human decisions, or authorize release/cutover.
-- Source proof: PR #2355, canonical Train ledger 20261013160002.
-- Historical source debt remains in Git; issue #2357.
DO $m100close$
DECLARE
  v_unit_id bigint;
  v_work_id bigint;
  v_meta jsonb;
  v_pre jsonb;
  v_accept jsonb;
  v_result jsonb;
  v_boot jsonb;
  v_next text;
  v_cp text;
  v_bundle programacion.provenance_receipts%ROWTYPE;
  v_ready programacion.provenance_receipts%ROWTYPE;
  v_evidence text;
  v_capabilities_ok boolean;
  v_expect jsonb;
BEGIN
  -- Exact-unit ledger prestate and applied independent migration.
  SELECT u.id,u.work_item_id,u.unit_metadata INTO v_unit_id,v_work_id,v_meta
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_items w ON w.id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M10.0' AND w.work_code='PAULO-159'
    AND w.status='IN_PROGRESS'
  FOR UPDATE OF u;
  IF v_unit_id IS DISTINCT FROM 283 OR v_work_id IS DISTINCT FROM 472
     OR NOT EXISTS (
       SELECT 1 FROM supabase_migrations.schema_migrations
       WHERE version='20261013160002'
         AND name='lf_ig_m100_sandbox_admission_coherent_v2'
         AND idempotency_key='gitblob:17c235d60114d7bd7d23d0cafd7cf9b95bced397'
         AND cardinality(statements)=1
     )
     OR EXISTS (
       SELECT 1 FROM supabase_migrations.schema_migrations
       WHERE version='20261012223000'
          OR name='ig_m100_sandbox_technical_vs_operational_authority_v1'
     )
  THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_EXACT_SOURCE_OR_PRESTATE_DRIFT';
  END IF;

  SELECT count(*)=3 AND bool_and(c.status='PENDING')
  INTO v_capabilities_ok
  FROM programacion.engineering_work_checkpoints c
  WHERE c.work_item_id=v_work_id AND c.sequence_no BETWEEN 5 AND 7;
  IF v_capabilities_ok IS DISTINCT FROM true OR
     (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_work_id AND sequence_no<=4 AND status='DONE')<>4
  THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_CHECKPOINT_PRESTATE_DRIFT';
  END IF;

  -- Genuine signed M9.0 and M9.12 frozen upstream anchors.
  SELECT * INTO v_bundle FROM programacion.provenance_receipts WHERE id=187;
  SELECT * INTO v_ready FROM programacion.provenance_receipts WHERE id=1667;
  IF v_bundle.id IS NULL OR v_ready.id IS NULL THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_PINNED_RECEIPTS_MISSING';
  END IF;
  PERFORM programacion.fn_assert_provenance_receipt(
    v_bundle.id,v_bundle.receipt_kind,v_bundle.execution_id,
    v_bundle.head_sha,v_bundle.subject_type,v_bundle.subject_ref,
    v_bundle.subject_sha256);
  PERFORM programacion.fn_assert_provenance_receipt(
    v_ready.id,v_ready.receipt_kind,v_ready.execution_id,
    v_ready.head_sha,v_ready.subject_type,v_ready.subject_ref,
    v_ready.subject_sha256);
  IF v_bundle.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
     OR v_ready.payload->>'verification_status' IS DISTINCT FROM 'VERIFIED'
     OR v_ready.payload->>'readiness_status' IS DISTINCT FROM 'CUTOVER_READY'
     OR v_ready.payload->>'bundle_sha256' IS DISTINCT FROM v_bundle.subject_sha256
     OR v_bundle.head_sha IS DISTINCT FROM v_ready.head_sha
  THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_SIGNED_BUNDLE_READINESS_DRIFT';
  END IF;

  v_pre:=v_meta#>'{m10_0_engineering_admission_v2,verification}';
  IF v_pre->>'result' IS DISTINCT FROM 'PASS'
     OR (v_pre->>'negative_test_count') IS DISTINCT FROM '5'
     OR (v_pre->>'signed_snapshot_components') IS DISTINCT FROM '7'
     OR (v_pre->>'bundle_receipt_id') IS DISTINCT FROM '187'
     OR (v_pre->>'readiness_receipt_id') IS DISTINCT FROM '1667'
     OR (v_pre->>'bundle_sha256') IS DISTINCT FROM v_bundle.subject_sha256
     OR (v_meta#>>'{m10_0_operational_admission_v2,status}')
        IS DISTINCT FROM 'BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY'
     OR (v_meta#>>'{m10_0_decision_routing_v1,route_policy,only_human_eligible_routes_to_queue}')
        IS DISTINCT FROM 'true'
  THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_TECHNICAL_EVIDENCE_NOT_APPLIED';
  END IF;

  -- Re-read actual proof, rather than equating an assertion string to PASS.
  SELECT jsonb_build_object(
    'preflight_pass',v_pre->>'result'='PASS',
    'five_negative_cases',v_pre->>'negative_test_count'='5'
       AND v_pre->>'negative_wrong_head_rejected'='true'
       AND v_pre->>'negative_wrong_bundle_rejected'='true'
       AND v_pre->>'negative_missing_receipt_rejected'='true'
       AND v_pre->>'negative_forged_authority_rejected'='true'
       AND v_pre->>'negative_wrong_readiness_subject_rejected'='true',
    'operational_blocked',v_meta#>>'{m10_0_operational_admission_v2,status}'='BLOCKED_PENDING_GOVERNED_HUMAN_AUTHORITY',
    'prehuman_gate_bound',v_meta#>>'{m10_0_decision_routing_v1,pre_human_gate}'='HUMAN_ESCALATION_ADMISSION',
    'only_eligible_human',v_meta#>>'{m10_0_decision_routing_v1,route_policy,only_human_eligible_routes_to_queue}'='true',
    'no_cutover_approval',NOT EXISTS(
      SELECT 1 FROM programacion.human_decisions h
      WHERE h.decision='APPROVE' AND h.head_sha=v_bundle.head_sha
        AND h.metadata->>'decision_class'='CUTOVER_AUTHORIZED'),
    'no_promotion',NOT EXISTS(
      SELECT 1 FROM programacion.promotions p WHERE p.head_sha=v_bundle.head_sha)
  ) INTO v_accept;
  v_expect:=jsonb_build_object(
    'preflight_pass',true,'five_negative_cases',true,
    'operational_blocked',true,'prehuman_gate_bound',true,
    'only_eligible_human',true,'no_cutover_approval',true,'no_promotion',true
  );
  IF v_accept IS NULL OR NOT (v_accept @> v_expect) THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_CANONICAL_READBACK_FAILED';
  END IF;

  -- Each canonical checkpoint must itself accept this same exact readback
  -- predicate before its individual state transition.
  v_evidence:='supabase://supabase_migrations.schema_migrations/20261013160002'
       ||'#lf_ig_m100_sandbox_admission_coherent_v2'
       ||';supabase://programacion.provenance_receipts/187'
       ||';supabase://programacion.provenance_receipts/1667'
       ||';github://cristhianlujan/claude-persona-lf-patch/pull/2355';
  FOREACH v_cp IN ARRAY ARRAY[
    'HUMAN_DECISION_RECORD','NEG_SHA_MISMATCH','AUTHORITY_READBACK'
  ] LOOP
    v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.0');
    IF v_boot->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
       OR v_boot#>>'{current_checkpoint,checkpoint_code}' IS DISTINCT FROM v_cp
    THEN
      RAISE EXCEPTION 'IG_M100_CLOSEOUT_NOT_CURRENT_CHECKPOINT:%',v_cp;
    END IF;
    SELECT u.unit_metadata#>ARRAY['action_specs_v1',v_cp,'assertion_contract','pass_when']
    INTO v_expect FROM programacion.engineering_plan_units u WHERE u.id=v_unit_id;
    IF v_expect IS NULL OR jsonb_typeof(v_expect) IS DISTINCT FROM 'object'
       OR NOT (v_accept @> v_expect)
       OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
            WHERE c.work_item_id=v_work_id AND c.checkpoint_code=v_cp
              AND c.status='PENDING')<>1
    THEN
      RAISE EXCEPTION 'IG_M100_CLOSEOUT_CHECKPOINT_ASSERTION_FAILED:%',v_cp;
    END IF;
    v_result:=programacion.fn_engineering_checkpoint_transition_v1(
      'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.0',
      v_cp,'DONE',v_evidence,'LF_MIGRATION_TRAIN_IG_M100_CLOSEOUT',
      'READBACK_ONCE: signed receipts and seven true canonical assertions; zero operational authorization; source PR #2355; historical source remains debt #2357');
    IF v_result#>>'{transition,status}' IS DISTINCT FROM 'APPLIED'
       OR v_result#>>'{transition,checkpoint_code}' IS DISTINCT FROM v_cp
    THEN
      RAISE EXCEPTION 'IG_M100_CLOSEOUT_TRANSITION_NOT_APPLIED:%',v_cp;
    END IF;
  END LOOP;

  v_boot:=programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M10.0');
  IF v_boot#>>'{state,progress_pct}' IS DISTINCT FROM '100'
     OR v_boot#>>'{state,done_checkpoint_count}' IS DISTINCT FROM '7'
     OR (SELECT status FROM programacion.engineering_work_items
         WHERE id=v_work_id) IS DISTINCT FROM 'DONE'
     OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_work_id AND status='DONE')<>7
     OR (SELECT count(*) FROM programacion.human_decisions
         WHERE decision='APPROVE' AND head_sha=v_bundle.head_sha
           AND metadata->>'decision_class'='CUTOVER_AUTHORIZED')<>0
     OR (SELECT count(*) FROM programacion.promotions
         WHERE head_sha=v_bundle.head_sha)<>0
  THEN
    RAISE EXCEPTION 'IG_M100_CLOSEOUT_TERMINAL_READBACK_FAILED';
  END IF;
END;
$m100close$;