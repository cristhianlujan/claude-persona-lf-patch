-- IG M9.13 / checkpoint M9_INDEPENDENT_READBACK
-- Repair one missing bounded-test compiler field, and align unit governance.
-- No ledger checkpoint transition, event issuance, release activation, or shared-engine changes.
DO $m913$
DECLARE
  v_id bigint;
  v_metadata jsonb;
  v_test jsonb;
  v_spec jsonb;
  v_gov jsonb;
  v_exit text;
  v_title text;
  v_after jsonb;
BEGIN
  SELECT u.id, u.unit_metadata, u.exit_criterion, c.title
    INTO v_id, v_metadata, v_exit, v_title
  FROM programacion.engineering_plan_units u
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id
  WHERE u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND u.unit_code='M9.13'
    AND c.checkpoint_code='M9_INDEPENDENT_READBACK'
    AND c.status='PENDING'
  FOR UPDATE OF u;
  IF v_id IS NULL THEN RAISE EXCEPTION 'M913_CURRENT_CHECKPOINT_DRIFT'; END IF;

  v_spec := v_metadata#>'{action_specs_v1,M9_INDEPENDENT_READBACK}';
  v_test := v_spec->'test_execution_contract';
  IF v_spec->>'contract_family' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST'
     OR v_test->>'test_code' IS DISTINCT FROM 'ENG_M9_13_INDEPENDENT_READBACK'
     OR v_test->>'test_path' IS DISTINCT FROM 'cristhianlujan/claude-persona-lf-patch:sandbox/lf_contract_gate_test/engineering_checkpoints/m9_13/independent_readback.py'
     OR v_test ? 'canonical_exit_criterion'
     OR v_exit NOT LIKE 'R11:%'
  THEN RAISE EXCEPTION 'M913_TEST_CONTRACT_PRESTATE_DRIFT'; END IF;
  v_test := v_test || jsonb_build_object(
    'canonical_exit_criterion', v_exit,
    'checkpoint_title_context', v_title
  );
  v_spec := jsonb_set(v_spec, '{test_execution_contract}', v_test, true);
  v_metadata := jsonb_set(v_metadata, '{action_specs_v1,M9_INDEPENDENT_READBACK}', v_spec, true);

  v_gov := coalesce(v_metadata->'m9_13_ledger_handoff_governance_v1','{}'::jsonb);
  IF v_gov->>'independent_check' IS DISTINCT FROM 'SIGNED_DISTINCT_EXECUTOR_MANIFEST_AND_EVENT_COMPARISON'
    OR v_gov->>'manifest_source' IS DISTINCT FROM 'IG_ENGINEERING_CHECKPOINT_LEDGER'
  THEN RAISE EXCEPTION 'M913_GOVERNANCE_PRESTATE_DRIFT'; END IF;
  v_gov := v_gov || jsonb_build_object(
    'test_contract_compilation', 'CANONICAL_EXIT_CRITERION_BOUND_TO_BOUNDED_TEST_V1',
    'independent_test_path', v_test->>'test_path',
    'distinct_actor_and_manifest_parity', 'REQUIRED_BEFORE_CHECKPOINT_DONE'
  );
  v_metadata := jsonb_set(v_metadata, '{m9_13_ledger_handoff_governance_v1}', v_gov, true);
  UPDATE programacion.engineering_plan_units
  SET unit_metadata = v_metadata WHERE id=v_id;

  v_after := programacion.fn_engineering_unit_bootstrap_v3('IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.13');
  IF v_after->>'terminal_action' IS DISTINCT FROM 'CONTINUE_CURRENT_CHECKPOINT'
    OR v_after#>>'{execution_packet,status}' IS DISTINCT FROM 'READY'
    OR v_after#>>'{execution_packet,execution_allowed}' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'M913_PACKET_STILL_BLOCKED: % / %',v_after->>'terminal_action',v_after#>>'{execution_packet,status}'; END IF;
END $m913$;
