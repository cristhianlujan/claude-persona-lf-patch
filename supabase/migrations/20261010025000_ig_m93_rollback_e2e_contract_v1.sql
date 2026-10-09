-- M9.3 candidate E2E rollback-only verification contract, sandbox only.
-- No runtime promotion and no permanent candidate writes.
DO $m93$
DECLARE s jsonb; c jsonb;
BEGIN
 SELECT unit_metadata#>'{action_specs_v1,FULL_PIPELINE_CANDIDATE}'
 INTO STRICT s FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3'
 FOR UPDATE;
 c:=s->'evidence_acquisition_contract';
 IF c->>'runtime_mode'<>'READ_ONLY_TRANSACTIONS'
 OR c->>'required_cohort_count'<>'7'
 OR c->>'baseline'<>'5.13'
 OR c->>'equivalence_capability'<>'CONTROL_EQUIVALENCE_JUDGE'
 THEN RAISE EXCEPTION 'M93_ROLLBACK_CONTRACT_SOURCE_DRIFT'; END IF;
 c:=c||jsonb_build_object(
  'allowed_evidence_modes',jsonb_build_array('READ_ONLY_TRANSACTIONS','ROLLBACK_ONLY_SANDBOX'),
  'rollback_e2e_preconditions',jsonb_build_object(
    'project_id','mhwmirqcgxxukpctffuv',
    'purpose','EXACT_LIVE_SANDBOX_ONLY',
    'production_allowed',false,
    'external_edge_invocation_allowed',false,
    'cohort_source','programacion.v_input_governance_representative_cohort_v1',
    'single_cohort_smoke_non_terminal',true,
    'transaction_end','ROLLBACK_ONLY',
    'commit_allowed',false,
    'candidate_persisted_writes_allowed',0,
    'before_after_authority_hash_required',true,
    'tequiv_policy','D0_EXACT_ONLY',
    'missing_stage_or_timeout','BLOCK',
    'positive_and_negative_machine_receipt_required',true
  ));
 s:=jsonb_set(s,'{evidence_acquisition_contract}',c,true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,'{action_specs_v1,FULL_PIPELINE_CANDIDATE}',s,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' AND unit_code='M9.3';
END $m93$;
