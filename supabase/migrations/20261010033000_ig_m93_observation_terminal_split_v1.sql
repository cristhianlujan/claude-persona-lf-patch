-- IG M9.3: distinguish the unit of observation (one M9.4 cohort) from
-- the unit of admission (all seven independently collected cohort receipts).
-- A typed D4 semantic hold is observed, NOT equivalent and NOT promotable.
-- Never reinterpret a missing stage, false-PASS or authoritative write as success.
DO $m93$
DECLARE s jsonb; a jsonb; m jsonb;
BEGIN
 SELECT unit_metadata#>'{action_specs_v1,FULL_PIPELINE_CANDIDATE}'
 INTO STRICT s
 FROM programacion.engineering_plan_units
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M9.3'
 FOR UPDATE;
 a:=s->'evidence_acquisition_contract';
 IF s->>'contract_family' <> 'BOUNDED_CHECKPOINT_TEST'
    OR a->>'required_cohort_count' <> '7'
    OR a->>'baseline' <> '5.13'
    OR a->>'equivalence_capability' <> 'CONTROL_EQUIVALENCE_JUDGE'
    OR a->>'require_zero_authoritative_writes' <> 'true'
    OR a#>>'{rollback_e2e_preconditions,transaction_end}' <> 'ROLLBACK_ONLY'
 THEN RAISE EXCEPTION 'M93_MEASUREMENT_SOURCE_DRIFT';
 END IF;
 m:=jsonb_build_object(
   'schema_version','IG_M93_OBSERVATION_VS_TERMINAL_V1',
   'cohort_unit','M9_4_GOVERNED_COHORT',
   'cohort_observation_pass_when',jsonb_build_object(
     'four_real_stages','PASS_WITH_EXECUTION_EVIDENCE',
     'baseline_revision','5.13',
     't_equiv','D0_EXACT_OR_D4_TYPED_REVIEW_HOLD',
     'validator_blocked_family_count',0,
     'rollback_authority_fingerprints','EQUAL',
     'candidate_persisted_writes',0),
   'cohort_observation_exit_code',0,
   'cohort_observation_is_terminal_done',false,
   'terminal_unit','SEVEN_COHORT_GOVERNED_AGGREGATION',
   'terminal_pass_when',jsonb_build_object(
     'same_github_dispatch_run',true,
     'exact_merged_main_sha',true,
     'seven_independently_proven_receipts',7,
     'no_missing_or_duplicate_cohort',true,
     'independent_verifier_pass',true,
     'no_persistent_candidate_writes',true),
   'd4_classified_semantic_hold',jsonb_build_object(
     'observation_measured',true,
     'equivalence_approved',false,
     'promotion_authorized',false,
     'hold_remains_active',true),
   'failure_modes',jsonb_build_array(
     'MISSING_CORE','MISSING_SEMANTICS','MISSING_CURATOR','MISSING_VALIDATOR',
     'UNCLASSIFIED_SEMANTIC_DELTA','PERSISTED_WRITE','MISSING_BASELINE_5_13',
     'MISSING_ARTIFACT','UNVERIFIED_GITHUB_HEAD'),
   'no_synthetic_pass',true,
   'production_authorized',false);
 a:=a||jsonb_build_object('measurement_contract',m);
 s:=jsonb_set(s,'{evidence_acquisition_contract}',a,true);
 UPDATE programacion.engineering_plan_units
 SET unit_metadata=jsonb_set(unit_metadata,
    '{action_specs_v1,FULL_PIPELINE_CANDIDATE}',s,true)
 WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
   AND unit_code='M9.3';
END $m93$;
