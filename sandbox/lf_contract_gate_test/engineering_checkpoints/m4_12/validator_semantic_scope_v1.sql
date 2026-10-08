-- Dedicated IG selector used by the three candidate Validator routes.
-- Uses only the frozen run scope, registered family policy and run universe;
-- does not grant an independent semantic verdict or issue a receipt.
-- This is candidate source only, not a production migration.
CREATE OR REPLACE FUNCTION programacion.fn_input_validator_semantic_scope_v1(
  p_run_id bigint
) RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = 'pg_catalog'
AS $ig_scope$
DECLARE
  v_scope jsonb;
  v_selection jsonb;
  v_version bigint;
  v_families jsonb;
  v_result text[]:=ARRAY[]::text[];
  v_code text;
BEGIN
  SELECT r.scope,r.version_id INTO v_scope,v_version
  FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATOR_SCOPE_RUN_NOT_FOUND:%',p_run_id;
  END IF;

  -- No comparison requested is a valid structural-only test; nothing is
  -- implicitly expanded to the entire 47-family Registry.
  IF NOT v_scope ? 'validator_semantic_comparison_families' THEN
    RETURN v_result;
  END IF;
  v_selection:=v_scope->'validator_semantic_comparison_families';
  IF jsonb_typeof(v_selection) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_SCOPE_INVALID:%',p_run_id;
  END IF;

  SELECT c.especificacion->'families' INTO v_families
  FROM programacion.contratos c
  WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    AND c.version_id=v_version AND c.estado='defined'
  ORDER BY c.id DESC LIMIT 1;
  IF v_families IS NULL OR jsonb_typeof(v_families)<>'object' THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_FAMILY_REGISTRY_MISSING:%',p_run_id;
  END IF;

  IF EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_selection) t(value)
    WHERE jsonb_typeof(value)<>'string'
       OR value#>>'{}' !~ '^[A-Z][A-Z0-9_]*$'
  ) THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_FAMILY_INVALID:%',p_run_id;
  END IF;
  FOR v_code IN SELECT x.value FROM jsonb_array_elements_text(v_selection) x(value) LOOP
    IF v_code=ANY(v_result) THEN
      RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_DUPLICATE:%',v_code;
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM programacion.input_family_assessments a
      WHERE a.run_id=p_run_id AND a.family_code=v_code
    ) OR coalesce(v_families->v_code->'validator_oracle_strategy'->>'strategy','')='' THEN
      RAISE EXCEPTION 'VALIDATOR_SEMANTIC_COMPARISON_FAMILY_UNREGISTERED:%',v_code;
    END IF;
    v_result:=array_append(v_result,v_code);
  END LOOP;
  RETURN v_result;
END;
$ig_scope$;
-- Internal only; a caller must use the governed validator entrypoint.
REVOKE ALL ON FUNCTION programacion.fn_input_validator_semantic_scope_v1(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION programacion.fn_input_validator_semantic_scope_v1(bigint) FROM anon,authenticated,service_role;
