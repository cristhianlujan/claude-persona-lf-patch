-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.0 / PAULO-109
-- Rollback-only negative: removing q_class + oracle from one governed case must be detected.
-- Expected terminal result: transaction ROLLBACK, zero residue.

BEGIN;

DO $m7_0_negative$
DECLARE
  v_test_code text;
  v_detected integer;
BEGIN
  SELECT test_code
    INTO v_test_code
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
  ORDER BY test_order,test_code
  LIMIT 1;

  IF v_test_code IS NULL THEN
    RAISE EXCEPTION 'M7_0_NEGATIVE_NO_CASE_AVAILABLE';
  END IF;

  UPDATE public.lf_test_suite_cases
  SET metadata = coalesce(metadata,'{}'::jsonb) - 'q_class' - 'oracle'
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND test_code=v_test_code;

  SELECT count(*)
    INTO v_detected
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND test_code=v_test_code
    AND (
      nullif(metadata->>'q_class','') IS NULL
      OR nullif(metadata->>'dimension','') IS NULL
      OR nullif(metadata->>'property','') IS NULL
      OR nullif(metadata->>'oracle','') IS NULL
      OR nullif(metadata->>'expected','') IS NULL
      OR NOT (metadata ? 'evidence')
      OR metadata->'evidence' IS NULL
      OR metadata->'evidence'='null'::jsonb
    );

  IF v_detected<>1 THEN
    RAISE EXCEPTION 'M7_0_NEGATIVE_UNCLASSIFIED_NOT_DETECTED:test=% detected=%',v_test_code,v_detected;
  END IF;

  RAISE NOTICE 'M7_0_NEGATIVE_PASS:test=% detected=%',v_test_code,v_detected;
END
$m7_0_negative$;

ROLLBACK;
