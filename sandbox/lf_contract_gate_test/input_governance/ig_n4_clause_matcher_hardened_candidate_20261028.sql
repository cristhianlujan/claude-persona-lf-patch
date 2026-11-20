-- DEV-ONLY CANDIDATE, LF IG N-4 v1 hardening (28 test vectors), 2026-10-28.
-- NOT A MIGRATION. NEVER run against shared/production Supabase. Use isolated DB.
-- Existing N-4 matcher stays the owner. One small schema validator is reused by
-- both existing matchers; no new scope engine or hardcoded business codes.
-- Publication / management authority is NOT granted by a boolean matcher.
-- EKB IG-TRANSVERSAL-RULE-SCOPE-AUTHORITY-GAP-001.
BEGIN;

DO $preimage$
BEGIN
  IF md5(pg_get_functiondef('programacion.fn_input_rule_selector_clause_matches_v1(jsonb,jsonb)'::regprocedure))
     <> '1123257c0c6c7eb1e2aa26783f3ccc0a' THEN
    RAISE EXCEPTION 'N4_CLAUSE_MATCHER_SOURCE_DRIFT';
  END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_rule_selector_matches_v1(jsonb,jsonb)'::regprocedure))
     <> '3b912c7872aceff83de24e9e8d1ad934' THEN
    RAISE EXCEPTION 'N4_SELECTOR_MATCHER_SOURCE_DRIFT';
  END IF;
END;
$preimage$;

-- Syntax-only predicate; crucially independent of the target. A malformed
-- clause must invalidate the WHOLE selector, even inside an OR branch.
CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_clause_schema_valid_v1(
  p_clause jsonb
)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_op text;
BEGIN
  IF jsonb_typeof(p_clause) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  IF jsonb_typeof(p_clause->'path') IS DISTINCT FROM 'array' THEN RETURN false; END IF;
  IF jsonb_array_length(p_clause->'path') < 2 THEN RETURN false; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_clause->'path') AS x(value)
    WHERE jsonb_typeof(x.value) <> 'string'
       OR btrim(x.value #>> '{}')=''
  ) THEN RETURN false; END IF;
  IF p_clause #>> '{path,0}' IS DISTINCT FROM 'target' THEN RETURN false; END IF;
  IF jsonb_typeof(p_clause->'op') IS DISTINCT FROM 'string' THEN RETURN false; END IF;

  v_op:=upper(p_clause->>'op');
  IF v_op NOT IN ('EXISTS','EQ','IN') THEN RETURN false; END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_clause) AS k(key)
    WHERE k.key NOT IN ('path','op')
      AND NOT (v_op='EQ' AND k.key='value')
      AND NOT (v_op='IN' AND k.key='values')
  ) THEN RETURN false; END IF;

  IF v_op='EQ' THEN
    IF NOT (p_clause?'value') OR jsonb_typeof(p_clause->'value')='null'
      THEN RETURN false; END IF;
  ELSIF v_op='IN' THEN
    IF jsonb_typeof(p_clause->'values') IS DISTINCT FROM 'array'
      THEN RETURN false; END IF;
    IF jsonb_array_length(p_clause->'values')=0 THEN RETURN false; END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_clause->'values') AS x(value)
      WHERE jsonb_typeof(x.value)='null'
    ) THEN RETURN false; END IF;
  END IF;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_clause_matches_v1(
 p_clause jsonb,p_context jsonb
)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog','programacion'
AS $function$
DECLARE v_path text[];v_actual jsonb;v_op text;
BEGIN
  IF jsonb_typeof(p_context) IS DISTINCT FROM 'object'
     OR programacion.fn_input_rule_selector_clause_schema_valid_v1(p_clause) IS NOT TRUE
    THEN RETURN false; END IF;
  SELECT array_agg(x.value ORDER BY x.ordinality)
    INTO v_path
    FROM jsonb_array_elements_text(p_clause->'path') WITH ORDINALITY x(value,ordinality);
  v_actual:=p_context #> v_path;
  IF v_actual IS NULL OR jsonb_typeof(v_actual)='null' THEN RETURN false; END IF;
  v_op:=upper(p_clause->>'op');
  IF v_op='EXISTS' THEN RETURN true;
  ELSIF v_op='EQ' THEN RETURN v_actual=p_clause->'value';
  ELSE
    RETURN EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_clause->'values') AS x(value)
      WHERE x.value=v_actual
    );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION programacion.fn_input_rule_selector_matches_v1(
  p_selector jsonb,p_context jsonb
)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
SET search_path TO 'pg_catalog','programacion'
AS $function$
DECLARE
 v_all jsonb;v_any jsonb;v_clause jsonb;
 v_any_match boolean:=false;
BEGIN
  IF jsonb_typeof(p_selector) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_context) IS DISTINCT FROM 'object'
    THEN RETURN false; END IF;
  IF p_selector->>'schema_version' IS DISTINCT FROM 'lf-rule-applicability/v1'
     OR p_selector->>'status' IS DISTINCT FROM 'ACTIVE'
    THEN RETURN false; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_selector) k(key)
    WHERE k.key NOT IN ('schema_version','status','consumer_roles','all','any','provenance')
  ) THEN RETURN false; END IF;

  -- Do not coerce caller consumer_role number/bool into a trusted text role.
  IF jsonb_typeof(p_context->'consumer_role') IS DISTINCT FROM 'string'
    THEN RETURN false; END IF;
  IF jsonb_typeof(p_selector->'consumer_roles') IS DISTINCT FROM 'array'
    THEN RETURN false; END IF;
  IF jsonb_array_length(p_selector->'consumer_roles')=0 THEN RETURN false; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_selector->'consumer_roles') x(value)
    WHERE jsonb_typeof(x.value)<>'string'
       OR btrim(x.value#>>'{}')=''
  ) THEN RETURN false; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(p_selector->'consumer_roles') x(value)
    WHERE x.value=p_context->>'consumer_role'
  ) THEN RETURN false; END IF;

  v_all:=coalesce(p_selector->'all','[]'::jsonb);
  v_any:=coalesce(p_selector->'any','[]'::jsonb);
  IF jsonb_typeof(v_all) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_any) IS DISTINCT FROM 'array'
    THEN RETURN false; END IF;
  IF jsonb_array_length(v_all)+jsonb_array_length(v_any)=0 THEN RETURN false; END IF;

  -- Entire selector MUST be well formed before OR short-circuiting.
  FOR v_clause IN
    SELECT x.value FROM jsonb_array_elements(v_all) x(value)
    UNION ALL
    SELECT x.value FROM jsonb_array_elements(v_any) x(value)
  LOOP
    IF programacion.fn_input_rule_selector_clause_schema_valid_v1(v_clause) IS NOT TRUE
      THEN RETURN false; END IF;
  END LOOP;

  FOR v_clause IN SELECT x.value FROM jsonb_array_elements(v_all) x(value)
  LOOP
    IF programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) IS NOT TRUE
      THEN RETURN false; END IF;
  END LOOP;

  IF jsonb_array_length(v_any)>0 THEN
    FOR v_clause IN SELECT x.value FROM jsonb_array_elements(v_any) x(value)
    LOOP
      IF programacion.fn_input_rule_selector_clause_matches_v1(v_clause,p_context) IS TRUE
        THEN v_any_match:=true; EXIT; END IF;
    END LOOP;
    IF NOT v_any_match THEN RETURN false; END IF;
  END IF;
  RETURN true;
END;
$function$;

-- Preserve all existing callable signatures, IMMUTABLE volatility, SECURITY
-- INVOKER flags, and explicit schema qualification. The NEW helper's grants
-- must be designed/verified by the governed owner before any future release.
-- Verify 28 synthetic test vectors AND 14 active-selector parity in isolated PG.
-- Publication approval is a SEPARATE boundary requiring trusted authority
-- receipt + independently measured scope; not implemented by these functions.
ROLLBACK;
