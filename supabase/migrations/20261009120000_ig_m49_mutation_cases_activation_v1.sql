-- IG package 4 (slice 5): activate the 10 M4_9 Validator mutation cases.
-- Basis: on 2026-10-09 each case was executed live through programacion.fn_input_validator_mutation_case_run_v1(test_code)
-- (always-rolled-back subtransaction, one case at a time) and returned passed=true, rollback_clean=true, false_pass=false.
-- The runner takes ~10-30 s per case, so this migration does not re-run it; it records the observed evidence and flips status.
-- Specificity caveat kept visible in metadata: 6 cases (T01-T04, T06, T08) are detected by the generic surface
-- VALIDATOR_CLASSIFIER_MISMATCH, not by a mutation-specific guard. They are valid regression checks for "this mutation is
-- detected and fails closed", but do not prove the mutation-specific guard exists. Re-run the runner for current behavior.
DO $ig_m49_activation$
DECLARE v_n int; v_act int;
BEGIN
  SELECT count(*) INTO v_n FROM public.lf_test_suite_cases
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'M4\_9\_T%' AND status='CANDIDATO'
     AND input_payload->>'pantalla_id'='1';
  IF v_n <> 10 THEN RAISE EXCEPTION 'IG_M49_ACTIVATION_UNEXPECTED_STATE:%', v_n; END IF;

  UPDATE public.lf_test_suite_cases
     SET status='ACTIVE',
         metadata = metadata || jsonb_build_object('activation', jsonb_build_object(
           'basis','LIVE_RUN_PASSED_2026-10-09_ROLLED_BACK_SUBTRANSACTION',
           'runner','programacion.fn_input_validator_mutation_case_run_v1',
           'generic_surface', (test_code ~ '^M4_9_T0(1|2|3|4|6|8)_'),
           'claim_scope','MUTATION_DETECTED_FAIL_CLOSED_NOT_MUTATION_SPECIFIC_GUARD_WHEN_GENERIC_SURFACE',
           'migration','supabase/migrations/20261009120000_ig_m49_mutation_cases_activation_v1.sql'))
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'M4\_9\_T%' AND status='CANDIDATO';

  SELECT count(*) INTO v_act FROM public.lf_test_suite_cases
   WHERE metadata->'activation'->>'runner'='programacion.fn_input_validator_mutation_case_run_v1' AND status='ACTIVE'
     AND (metadata->'activation'->>'generic_surface')::boolean IS NOT NULL;
  IF v_act <> 10 THEN RAISE EXCEPTION 'IG_M49_ACTIVATION_READBACK_MISMATCH:%', v_act; END IF;
  IF (SELECT count(*) FROM public.lf_test_suite_cases
       WHERE metadata->'activation'->>'runner'='programacion.fn_input_validator_mutation_case_run_v1'
         AND (metadata->'activation'->>'generic_surface')::boolean) <> 6 THEN
    RAISE EXCEPTION 'IG_M49_GENERIC_COUNT_MISMATCH';
  END IF;
END
$ig_m49_activation$;
