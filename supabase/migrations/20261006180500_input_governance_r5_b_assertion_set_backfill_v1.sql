-- R5-B — assertion-set backfill only.
-- Authorized snapshot: 10,131 inline assertion references / 3,379 unique assertion sets.
-- This migration INSERTS ONLY into input_validator_assertion_sets_v1.
-- It does not update or compact input_family_assessments.

SET LOCAL statement_timeout = '120s';

DO $r5b_preflight$
DECLARE
  v_refs bigint;
  v_unique bigint;
  v_existing bigint;
BEGIN
  IF to_regclass('programacion.input_validator_assertion_sets_v1') IS NULL
     OR to_regprocedure('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'R5B_REQUIRES_R5A';
  END IF;

  SELECT count(*),
         count(DISTINCT validator_evidence->'assertions')
    INTO v_refs, v_unique
  FROM programacion.input_family_assessments
  WHERE validator_evidence ? 'assertions';

  SELECT count(*) INTO v_existing
  FROM programacion.input_validator_assertion_sets_v1;

  IF v_refs <> 10131 THEN
    RAISE EXCEPTION 'R5B_ASSERTION_REFERENCE_SNAPSHOT_MOVED expected=10131 actual=%', v_refs;
  END IF;
  IF v_unique <> 3379 THEN
    RAISE EXCEPTION 'R5B_UNIQUE_ASSERTION_SET_SNAPSHOT_MOVED expected=3379 actual=%', v_unique;
  END IF;
  IF v_existing <> 0 THEN
    RAISE EXCEPTION 'R5B_ASSERTION_SET_TABLE_NOT_EMPTY expected=0 actual=%', v_existing;
  END IF;
END
$r5b_preflight$;

WITH unique_assertions AS MATERIALIZED (
  SELECT DISTINCT validator_evidence->'assertions' AS assertions
  FROM programacion.input_family_assessments
  WHERE validator_evidence ? 'assertions'
)
INSERT INTO programacion.input_validator_assertion_sets_v1(
  assertion_set_sha256,
  assertions
)
SELECT
  programacion.fn_v09_sha256_jsonb(assertions),
  assertions
FROM unique_assertions;

DO $r5b_postcheck$
DECLARE
  v_sets bigint;
BEGIN
  SELECT count(*) INTO v_sets
  FROM programacion.input_validator_assertion_sets_v1;

  IF v_sets <> 3379 THEN
    RAISE EXCEPTION 'R5B_BACKFILL_CARDINALITY_MISMATCH expected=3379 actual=%', v_sets;
  END IF;
END
$r5b_postcheck$;
