-- IG M7.14: remove a legacy FINAL_EVIDENCE route from the read-only ledger manifest checkpoint.
-- The current checkpoint contract requires only a deterministic M7 ledger manifest SHA-256.
-- FINAL_EVIDENCE would introduce a conflicting, unnecessary repository capability.
-- Scope: one unit_metadata routing entry, no checkpoint/state/evidence changes.
-- Reversible proof in sandbox (2026-10-09): within a PL/pgSQL exception-backed
-- subtransaction the exact UPDATE made bootstrap terminal_action=CONTINUE_CURRENT_CHECKPOINT;
-- the exception rolled the change back and readback confirmed original route retained.
DO $ig_m714$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_rows integer;
BEGIN
  v_before := programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.14'
  );

  IF v_before #>> '{current_checkpoint,checkpoint_code}' <> 'M7_EVIDENCE_BUNDLE'
     OR v_before #>> '{action_spec,action_kind}' <> 'READBACK_ONCE'
     OR position('No FINAL_EVIDENCE' in coalesce(v_before #>> '{action_spec,expected}','')) = 0
  THEN
    RAISE EXCEPTION 'M7.14 action contract changed; reassess routing before migration';
  END IF;

  UPDATE programacion.engineering_plan_units
  SET unit_metadata = jsonb_set(
    unit_metadata,
    '{transversal_execution_v1}',
    (unit_metadata -> 'transversal_execution_v1') - 'M7_EVIDENCE_BUNDLE',
    true
  )
  WHERE plan_code = 'IG_CURATOR_VALIDATOR_REFACTOR_V2'
    AND unit_code = 'M7.14'
    AND disposition = 'ASSIGNED'
    AND unit_metadata #>> '{transversal_execution_v1,M7_EVIDENCE_BUNDLE,activation}' = 'DECLARED_ONLY'
    AND unit_metadata #>> '{transversal_execution_v1,M7_EVIDENCE_BUNDLE,capabilities,0,capability_code}' = 'FINAL_EVIDENCE';

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'M7.14 expected exactly one obsolete route, found %',v_rows;
  END IF;

  v_after := programacion.fn_engineering_unit_bootstrap_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M7.14'
  );

  IF v_after ->> 'terminal_action' <> 'CONTINUE_CURRENT_CHECKPOINT'
     OR v_after #>> '{execution_readiness,status}' <> 'READY'
     OR v_after #>> '{current_checkpoint,checkpoint_code}' <> 'M7_EVIDENCE_BUNDLE'
  THEN
    RAISE EXCEPTION 'M7.14 routing cleanup postcheck failed: %',
      jsonb_build_object('terminal',v_after->'terminal_action',
                         'readiness',v_after->'execution_readiness');
  END IF;
END
$ig_m714$;
