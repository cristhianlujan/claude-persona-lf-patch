-- LF Input Governance | G2 DEV candidate only | 2026-10-28
-- NOT A MIGRATION. DO NOT APPLY TO ANY SHARED OR PRODUCTION SUPABASE.
-- The only changed owner is existing N-4 clause matcher. No business-specific IDs.
-- EKB IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.
-- Isolated DB / disposable transaction ONLY; the tail ROLLBACK is intentional.
-- Publication authority, universal scopes, conflict precedence, manager signatures
-- are OUTSIDE this matcher; do not grant authority through a boolean MATCH.

BEGIN;

DO $preimage$
BEGIN
  IF md5(pg_get_functiondef(
    'programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'::regprocedure
  )) <> '1123257c0c6c7eb1e2aa26783f3ccc0a' THEN
    RAISE EXCEPTION 'N4_CLAUSE_MATCHER_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef(
    'programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'::regprocedure
  )) <> '3b912c7872aceff83de24e9e8d1ad934' THEN
    RAISE EXCEPTION 'N4_SELECTOR_MATCHER_SOURCE_DRIFT';
  END IF;
END;
$preimage$;

CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_clause_matches_v1(
  p_clause jsonb,
  p_context jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_path text[];
  v_actual jsonb;
  v_op text;
BEGIN
  IF jsonb_typeof(p_clause) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_context) IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;
  IF jsonb_typeof(p_clause->'path') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_clause->'path') < 2 THEN
    RETURN false;
  END IF;
  -- Reject numeric/null/object path elements: jsonb_array_elements_text would
  -- coerce them to strings, silently accepting a malformed selector.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_clause->'path') AS x(value)
    WHERE jsonb_typeof(x.value) <> 'string'
       OR btrim(x.value #>> '{}') = ''
  ) THEN
    RETURN false;
  END IF;

  SELECT array_agg(x.value ORDER BY x.ordinality)
  INTO v_path
  FROM jsonb_array_elements_text(p_clause->'path') WITH ORDINALITY AS x(value,ordinality);

  IF v_path[1] IS DISTINCT FROM 'target' THEN RETURN false; END IF;

  v_op := upper(coalesce(p_clause->>'op',''));
  IF v_op NOT IN ('EXISTS','EQ','IN') THEN RETURN false; END IF;

  -- Operator-specific contract: do not silently ignore required guards.
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_clause) AS k(key)
    WHERE k.key NOT IN ('path','op')
      AND NOT (v_op='EQ' AND k.key='value')
      AND NOT (v_op='IN' AND k.key='values')
  ) THEN
    RETURN false;
  END IF;

  IF v_op='EQ' AND (
    NOT p_clause ? 'value'
    OR jsonb_typeof(p_clause->'value')='null'
  ) THEN RETURN false; END IF;

  IF v_op='IN' THEN
    IF jsonb_typeof(p_clause->'values') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_clause->'values')=0 THEN
      RETURN false;
    END IF;
    -- An IN-list with unknown/null alternative is invalid in v1, not a shortcut
    -- to infer "missing" / "not present".
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_clause->'values') x(value)
      WHERE jsonb_typeof(x.value)='null'
    ) THEN RETURN false; END IF;
  END IF;

  v_actual := p_context #> v_path;
  IF v_actual IS NULL OR jsonb_typeof(v_actual)='null' THEN RETURN false; END IF;

  IF v_op='EXISTS' THEN
    RETURN true;
  ELSIF v_op='EQ' THEN
    RETURN v_actual=p_clause->'value';
  ELSE
    RETURN EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_clause->'values') AS x(value)
      WHERE x.value=v_actual
    );
  END IF;
END;
$function$;

-- Execute test vectors in disposable PostgreSQL before a future migration.
-- Confirm unchanged signatures, volatility, ACLs, search_path and the full
-- authoritative N-4 selector contract; this candidate alone does NOT prove them.
-- The production/source-parity migration must be separately authorized.
ROLLBACK;
