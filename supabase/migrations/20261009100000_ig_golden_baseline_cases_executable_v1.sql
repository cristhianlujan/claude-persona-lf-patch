-- IG package 4 (slice 3): the 611 M7_2_GOLDEN_* cases become executable BASELINE READBACKS and are activated.
-- Each case pins (historical_run_id, family_code, pantalla_id) and the 7 expected statuses of that frozen run.
-- Runner programacion.fn_input_golden_case_run_v1(test_code) reads the stored assessment of that exact run/family and compares
-- coverage, well_defined, story/implementation/qa/production readiness and validator outcome with expected_output.
-- HONEST SCOPE: this proves the frozen M0.6 baseline rows still read exactly as pinned (tamper/drift detection of the golden).
-- It does NOT re-run the current Curator/Validator, so it is not evidence of current behaviour; a live-vs-golden comparison is a
-- separate step. contract_revision in expected_output is not compared with the live contract (the run is historical).
-- A case is activated only if it passes; the migration aborts if any of the 611 fails. No other case is touched.

CREATE OR REPLACE FUNCTION programacion.fn_input_golden_case_run_v1(p_test_code text)
 RETURNS TABLE(test_code text, found boolean, mismatched_fields text[], passed boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $fn$
WITH g AS (
  SELECT c.test_code, (c.input_payload->>'historical_run_id')::bigint AS run_id, c.input_payload->>'family_code' AS fam, c.expected_output AS eo
  FROM public.lf_test_suite_cases c
  WHERE c.test_code=p_test_code AND c.test_code LIKE 'M7\_2\_GOLDEN\_%'
), j AS (
  SELECT g.test_code, g.eo, a.id, a.coverage_status, a.well_defined_status, a.story_ready_status, a.implementation_ready_status,
         a.qa_ready_status, a.production_ready_status, a.validator_outcome
  FROM g LEFT JOIN programacion.input_family_assessments a ON a.run_id=g.run_id AND a.family_code=g.fam
), f AS (
  SELECT j.test_code, (j.id IS NOT NULL) AS found,
    array_remove(ARRAY[
      CASE WHEN j.eo->>'coverage_status' IS DISTINCT FROM j.coverage_status THEN 'coverage_status' END,
      CASE WHEN j.eo->>'well_defined_status' IS DISTINCT FROM j.well_defined_status THEN 'well_defined_status' END,
      CASE WHEN j.eo->>'story_ready_status' IS DISTINCT FROM j.story_ready_status THEN 'story_ready_status' END,
      CASE WHEN j.eo->>'implementation_ready_status' IS DISTINCT FROM j.implementation_ready_status THEN 'implementation_ready_status' END,
      CASE WHEN j.eo->>'qa_ready_status' IS DISTINCT FROM j.qa_ready_status THEN 'qa_ready_status' END,
      CASE WHEN j.eo->>'production_ready_status' IS DISTINCT FROM j.production_ready_status THEN 'production_ready_status' END,
      CASE WHEN j.eo->>'validator_outcome' IS DISTINCT FROM j.validator_outcome THEN 'validator_outcome' END
    ], NULL) AS bad
  FROM j
)
SELECT f.test_code, f.found, f.bad, (f.found AND cardinality(f.bad)=0) FROM f
UNION ALL
SELECT p_test_code, false, ARRAY['CASE_NOT_FOUND_OR_NOT_GOLDEN']::text[], false WHERE NOT EXISTS (SELECT 1 FROM g)
$fn$;

DO $ig_golden_cases$
DECLARE v_n int; v_bad int; v_act int;
BEGIN
  SELECT count(*) INTO v_n FROM public.lf_test_suite_cases
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND test_code LIKE 'M7\_2\_GOLDEN\_%';
  IF v_n <> 611 THEN RAISE EXCEPTION 'IG_GOLDEN_CASES_UNEXPECTED_COUNT:%', v_n; END IF;

  SELECT count(*) FILTER (WHERE NOT x.passed) INTO v_bad
  FROM public.lf_test_suite_cases c, LATERAL programacion.fn_input_golden_case_run_v1(c.test_code) x
  WHERE c.suite_code='INPUT_GOVERNANCE_REGRESSION' AND c.test_code LIKE 'M7\_2\_GOLDEN\_%';
  IF v_bad <> 0 THEN RAISE EXCEPTION 'IG_GOLDEN_CASES_FAILED:%', v_bad; END IF;

  UPDATE public.lf_test_suite_cases
     SET status='ACTIVE',
         metadata = metadata || jsonb_build_object('activation',jsonb_build_object(
           'basis','FROZEN_BASELINE_READBACK_MATCHED_EXPECTED','runner','programacion.fn_input_golden_case_run_v1',
           'claim_scope','BASELINE_READBACK_OF_FROZEN_HISTORICAL_RUN_NOT_CURRENT_CURATOR_BEHAVIOR',
           'migration','supabase/migrations/20261009100000_ig_golden_baseline_cases_executable_v1.sql'))
   WHERE suite_code='INPUT_GOVERNANCE_REGRESSION' AND status='CANDIDATO' AND test_code LIKE 'M7\_2\_GOLDEN\_%';

  SELECT count(*) INTO v_act FROM public.lf_test_suite_cases
   WHERE metadata->'activation'->>'runner'='programacion.fn_input_golden_case_run_v1' AND status='ACTIVE';
  IF v_act <> 611 THEN RAISE EXCEPTION 'IG_GOLDEN_CASES_READBACK_MISMATCH:%', v_act; END IF;
END
$ig_golden_cases$;
