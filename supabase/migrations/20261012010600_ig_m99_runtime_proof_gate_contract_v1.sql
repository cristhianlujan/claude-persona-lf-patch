-- IG M9.9: paired checkpoint contract + governance evidence acceptance.
-- PR2252 emits simulated signals with runtime_canary_proven=false.
-- Such evidence must never make ROLLBACK_TRIGGER_NEGATIVE DONE.
-- Sandbox-only: no cohort switch, no production activation, no fake receipt.
DO $contract$
DECLARE v_spec jsonb; v_pass jsonb; v_built jsonb;
BEGIN
 SELECT unit_metadata#>'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE}' INTO v_spec
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 v_pass:=v_spec#>'{assertion_contract,pass_when}';
 IF v_spec->>'status' IS DISTINCT FROM 'READY'
 OR v_spec->>'action_kind' IS DISTINCT FROM 'BOUNDED_CHECKPOINT_TEST_AUTHORING'
 OR v_pass IS DISTINCT FROM
   '{"test_passed":true,"test_exit_code":0,"semantic_authority_bound":true,"adversarial_case_executed":true}'::jsonb
 OR NOT EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=267 AND checkpoint_code='ROLLBACK_TRIGGER_NEGATIVE' AND status='PENDING')
 THEN RAISE EXCEPTION 'M99_NEGATIVE_CONTRACT_BASELINE_DRIFT'; END IF;
 v_spec:=jsonb_set(v_spec,'{assertion_contract,pass_when}',
   v_pass||jsonb_build_object(
      'real_canary_receipts_verified',true,
      'runtime_canary_proven',true,
      'full_checkpoint_closure_authorized',true,
      'zero_residue',true,
      'rollback_executed_automatically',true),true);
 v_spec:=jsonb_set(v_spec,'{test_execution_contract}',
   v_spec->'test_execution_contract'||jsonb_build_object(
      'simulated_signals_suffice',false,
      'provenance_requirement','SIGNED_LIVE_IG_CANARY_OBSERVATION_WITH_COHORT_PIN',
      'rollback_requirement','AUTOMATIC_TRIGGERED_REVERSAL_WITH_PRE_POST_EQUIVALENCE',
      'required_negative_cases',jsonb_build_array('FALSE_PASS','DIVERGENCE','TIMEOUT','EXECUTION_ERROR','MISSING_RECEIPT'),
      'safety_boundary','SANDBOX_ONLY_ROLLBACK_NO_PRODUCTION'),true);
 v_spec:=jsonb_set(v_spec,'{target,declared_objects}',
   coalesce(v_spec#>'{target,declared_objects}','[]'::jsonb)||
   jsonb_build_array('programacion.provenance_receipts',
      'programacion.fn_ig_m99_canary_receipt_gate_v1',
      'programacion.fn_ig_m99_canary_rollback_decision_v1',
      'public.lf_capability_current',
      'programacion.input_governance_cohort_types',
      'programacion.input_governance_cohort_memberships'),true);
 v_spec:=v_spec||jsonb_build_object('expected',
   'PASS only with signed live canary receipts, five genuine triggers including elapsed_ms>150000, actual automatic rollback, preserved baseline pointer/manifest and zero residues. Decision-only/synthetic observations cannot close the checkpoint.');
 UPDATE programacion.engineering_plan_units SET unit_metadata=
   jsonb_set(unit_metadata,'{action_specs_v1,ROLLBACK_TRIGGER_NEGATIVE}',v_spec,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.9';
 IF NOT FOUND THEN RAISE EXCEPTION 'M99_NEGATIVE_CONTRACT_WRITE_MISSING'; END IF;
 v_built:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M9.9','ROLLBACK_TRIGGER_NEGATIVE');
 IF v_built->>'status' IS DISTINCT FROM 'READY'
 OR v_built#>>'{assertion_contract,pass_when,real_canary_receipts_verified}' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'M99_NEGATIVE_CONTRACT_COMPILED_UNSAFE'; END IF;
END $contract$;

-- Verified core decoupling; keep EKB guidance but record historical defect closure.
UPDATE public.lf_error_knowledge
SET estado='VERIFICADO',
    validacion='PR2253 merged; Git exact-source migration applied, core digest 7e5448a881ce0a88f3786f349ac3f169; shared reconciler has 0 references to IG cohort tables; historical M9.9 rule removed. Synthetic canary evidence remains rejected by a separate contract.',
    evidencia=coalesce(evidencia,'')||' | PR2253 merged commit 2c2ad18cf34e7e62ec2c34360578c9820440ce48; migration source 20261012005800_ig_m99_transversal_reconciler_decouple_v1.sql; Supabase migration 20261012003510; no pointer changes.',
    updated_at=now()
WHERE codigo='IG-M99-TRANSVERSAL-RECONCILER-IG-COUPLING-001'
  AND estado='ACTIVO'
  AND NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='programacion' AND p.proname='fn_engineering_blocker_reconcile_v1'
      AND position('input_governance_cohort' in pg_get_functiondef(p.oid))>0
  );
