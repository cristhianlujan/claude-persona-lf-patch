-- R5-A — assertion-set storage and logical validator-evidence rehydration.
-- Additive only: no existing row/function/trigger is modified by this migration.

DO $r5a_preflight$
BEGIN
  IF to_regclass('programacion.input_validator_assertion_sets_v1') IS NOT NULL THEN
    RAISE EXCEPTION 'R5A_ASSERTION_SET_TABLE_ALREADY_EXISTS';
  END IF;
  IF to_regprocedure('programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION 'R5A_REHYDRATE_FUNCTION_ALREADY_EXISTS';
  END IF;
  IF to_regprocedure('programacion.fn_v09_sha256_jsonb(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'R5A_CANONICAL_SHA256_HELPER_MISSING';
  END IF;
END
$r5a_preflight$;

CREATE TABLE programacion.input_validator_assertion_sets_v1 (
  assertion_set_sha256 text PRIMARY KEY,
  assertions jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT input_validator_assertion_sets_v1_sha256_shape
    CHECK (assertion_set_sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT input_validator_assertion_sets_v1_assertions_array
    CHECK (jsonb_typeof(assertions) = 'array' AND jsonb_array_length(assertions) > 0),
  CONSTRAINT input_validator_assertion_sets_v1_content_addressed
    CHECK (
      assertion_set_sha256
      = programacion.fn_v09_sha256_jsonb(assertions)
    )
);

ALTER TABLE programacion.input_validator_assertion_sets_v1 ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE programacion.input_validator_assertion_sets_v1
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION programacion.fn_input_validator_evidence_rehydrate_v1(
  p_validator_evidence jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'programacion'
AS $function$
DECLARE
  v_ref text;
  v_assertions jsonb;
  v_actual_sha256 text;
BEGIN
  IF p_validator_evidence IS NULL THEN
    RETURN NULL;
  END IF;

  IF jsonb_typeof(p_validator_evidence) <> 'object' THEN
    RAISE EXCEPTION 'R5_REHYDRATE_EVIDENCE_MUST_BE_OBJECT';
  END IF;

  -- Legacy/full representation remains byte-logically unchanged.
  IF p_validator_evidence ? 'assertions' THEN
    IF p_validator_evidence ? 'assertion_set_sha256' THEN
      RAISE EXCEPTION 'R5_REHYDRATE_AMBIGUOUS_INLINE_AND_REFERENCE';
    END IF;
    RETURN p_validator_evidence;
  END IF;

  -- Evidence that never carried assertions (for example PENDING/{}) is unchanged.
  IF NOT (p_validator_evidence ? 'assertion_set_sha256') THEN
    RETURN p_validator_evidence;
  END IF;

  v_ref := p_validator_evidence->>'assertion_set_sha256';
  IF v_ref IS NULL OR v_ref !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'R5_REHYDRATE_INVALID_ASSERTION_SET_SHA256:%', coalesce(v_ref, '<NULL>');
  END IF;

  SELECT s.assertions
    INTO v_assertions
  FROM programacion.input_validator_assertion_sets_v1 s
  WHERE s.assertion_set_sha256 = v_ref;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'R5_REHYDRATE_ASSERTION_SET_NOT_FOUND:%', v_ref;
  END IF;

  v_actual_sha256 := programacion.fn_v09_sha256_jsonb(v_assertions);
  IF v_actual_sha256 IS DISTINCT FROM v_ref THEN
    RAISE EXCEPTION
      'R5_REHYDRATE_ASSERTION_SET_HASH_MISMATCH expected=% actual=%',
      v_ref, coalesce(v_actual_sha256, '<NULL>');
  END IF;

  RETURN (p_validator_evidence - 'assertion_set_sha256')
         || jsonb_build_object('assertions', v_assertions);
END;
$function$;

REVOKE ALL ON FUNCTION programacion.fn_input_validator_evidence_rehydrate_v1(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE programacion.input_validator_assertion_sets_v1 IS
  'R5 content-addressed assertion sets. Additive in R5-A; consumers remain unchanged until governed R5-C.';

COMMENT ON FUNCTION programacion.fn_input_validator_evidence_rehydrate_v1(jsonb) IS
  'R5 logical rehydration: legacy inline evidence is unchanged; compact evidence resolves assertion_set_sha256 and removes the storage-only reference before returning the logical evidence.';
