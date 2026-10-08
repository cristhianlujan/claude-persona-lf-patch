-- Dedicated IG selector used by the three candidate Validator routes.
-- Uses only the frozen run scope, registered family policy and run universe;
-- does not grant an independent semantic verdict or issue a receipt.
-- This is a bounded internal selector; install only as part of governed migration.
-- It never declares independent semantic evidence or runs an external judge.
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
  v_mode text;
BEGIN
  SELECT r.scope,r.version_id INTO v_scope,v_version
  FROM programacion.input_readiness_runs r WHERE r.id=p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VALIDATOR_SCOPE_RUN_NOT_FOUND:%',p_run_id;
  END IF;

  -- Every run must state its intended validation mode. Absence is not
  -- equivalent to "no independent semantic proof needed".
  -- SOURCE_INTEGRITY_ONLY is an explicit, non-promotable test mode.
  -- SELECTED_SEMANTIC_COMPARISON must enumerate the selected families.
  -- Neither mode grants APPLIED / N/A or production readiness.
  v_mode:=v_scope->>'validator_semantic_mode';
  v_selection:=v_scope->'validator_semantic_comparison_families';
  IF v_mode IS NULL OR v_selection IS NULL THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_SCOPE_UNDECLARED:%',p_run_id;
  END IF;
  IF v_mode NOT IN ('SOURCE_INTEGRITY_ONLY','SELECTED_SEMANTIC_COMPARISON')
      OR jsonb_typeof(v_selection) IS DISTINCT FROM 'array'
      OR v_scope->>'semantic_promotion_authorized' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'VALIDATOR_SEMANTIC_SCOPE_MODE_INVALID:%',p_run_id;
  END IF;
  IF v_mode='SOURCE_INTEGRITY_ONLY' AND jsonb_array_length(v_selection)<>0 THEN
    RAISE EXCEPTION 'VALIDATOR_SOURCE_ONLY_SCOPE_MUST_BE_EMPTY:%',p_run_id;
  END IF;
  IF v_mode='SELECTED_SEMANTIC_COMPARISON'
     AND jsonb_array_length(v_selection)=0 THEN
    RAISE EXCEPTION 'VALIDATOR_SELECTED_SEMANTIC_FAMILIES_REQUIRED:%',p_run_id;
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
