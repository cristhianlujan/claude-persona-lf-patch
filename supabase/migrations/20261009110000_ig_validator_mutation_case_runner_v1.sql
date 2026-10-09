-- IG package 4 (slice 4): reproducible runner for the 10 M4_9 Validator mutation cases. Status stays CANDIDATO.
-- Each case already names its entrypoint (programacion.fn_engineering_ig_validator_mutation_case_v2) and its campaign ordinal,
-- but lacked the pantalla it runs on. This migration stores pantalla_id=1 in input_payload and adds
-- programacion.fn_input_validator_mutation_case_run_v1(test_code), which calls the entrypoint inside a sub-transaction that is
-- always rolled back (defence in depth: the entrypoint also restores the functions it temporarily mutates) and compares the
-- result with expected_output. Each execution takes ~10-30 s, so activation is NOT done here: verifying 10 cases inside one
-- migration would take minutes. passed=true requires: status PASS, detected, no false pass, rollback clean, no durable residue,
-- runtime functions restored, matching test_code and expected decision DETECTED_FAIL_CLOSED.
-- generic_surface flags detections whose surface is VALIDATOR_CLASSIFIER_MISMATCH (a classifier-level mismatch rather than a
-- mutation-specific guard) so that weak specificity stays visible.

CREATE OR REPLACE FUNCTION programacion.fn_input_validator_mutation_case_run_v1(p_test_code text)
 RETURNS TABLE(test_code text, expected_decision text, status text, detected boolean, false_pass boolean, detection_surface text,
               generic_surface boolean, rollback_clean boolean, passed boolean)
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO 'pg_catalog'
AS $fn$
DECLARE
  v_case record; v_r jsonb;
BEGIN
  SELECT c.test_code AS tc, c.expected_output->>'decision' AS dec,
         (c.metadata->>'campaign_ordinal')::integer AS ord, (c.input_payload->>'pantalla_id')::integer AS pant,
         c.metadata->>'case_entrypoint' AS ep INTO v_case
  FROM public.lf_test_suite_cases c WHERE c.test_code=p_test_code AND c.test_code LIKE 'M4\_9\_T%';
  IF v_case.tc IS NULL THEN RAISE EXCEPTION 'MUTATION_CASE_NOT_FOUND:%', p_test_code; END IF;
  IF v_case.ep IS DISTINCT FROM 'programacion.fn_engineering_ig_validator_mutation_case_v2' OR v_case.ord IS NULL OR v_case.pant IS NULL THEN
    RAISE EXCEPTION 'MUTATION_CASE_NOT_EXECUTABLE:%', p_test_code;
  END IF;

  BEGIN
    v_r := programacion.fn_engineering_ig_validator_mutation_case_v2(v_case.ord, v_case.pant);
    RAISE EXCEPTION USING ERRCODE='P0099', MESSAGE=v_r::text;
  EXCEPTION WHEN SQLSTATE 'P0099' THEN
    v_r := SQLERRM::jsonb;
  END;

  RETURN QUERY SELECT v_case.tc, v_case.dec, v_r->>'status', (v_r->>'detected')::boolean, (v_r->>'false_pass')::boolean,
    v_r->>'detection_surface', (v_r->>'detection_surface')='VALIDATOR_CLASSIFIER_MISMATCH', (v_r->>'rollback_clean')::boolean,
    (v_r->>'status'='PASS' AND (v_r->>'detected')::boolean AND NOT (v_r->>'false_pass')::boolean
     AND (v_r->>'rollback_clean')::boolean AND NOT (v_r->>'durable_fixture_residue')::boolean
     AND (v_r->>'runtime_functions_restored')::boolean AND v_r->>'test_code'=v_case.tc AND v_case.dec='DETECTED_FAIL_CLOSED');
END
$fn$;

DO $ig_mutation_inputs$
DECLARE v_n int; v_ok int;
BEGIN
  SELECT count(*) INTO v_n FROM public.lf_test_suite_cases
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'M4\_9\_T%'
     AND metadata->>'case_entrypoint'='programacion.fn_engineering_ig_validator_mutation_case_v2' AND metadata ? 'campaign_ordinal';
  IF v_n <> 10 THEN RAISE EXCEPTION 'IG_MUTATION_CASES_UNEXPECTED_COUNT:%', v_n; END IF;
  UPDATE public.lf_test_suite_cases SET input_payload = input_payload || '{"pantalla_id":1}'::jsonb
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'M4\_9\_T%' AND NOT input_payload ? 'pantalla_id';
  SELECT count(*) INTO v_ok FROM public.lf_test_suite_cases
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'M4\_9\_T%' AND input_payload->>'pantalla_id'='1' AND status='CANDIDATO';
  IF v_ok <> 10 THEN RAISE EXCEPTION 'IG_MUTATION_CASES_READBACK_MISMATCH:%', v_ok; END IF;
END
$ig_mutation_inputs$;
