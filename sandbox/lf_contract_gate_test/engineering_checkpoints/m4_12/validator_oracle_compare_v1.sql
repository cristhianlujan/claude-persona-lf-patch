-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M4.12
-- Additive, bounded, non-decisional oracle comparison.
-- A shadow candidate is NOT independent semantic proof. No validator route
-- is replaced, no readiness/assessment/promotion data is written.
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validator_oracle_compare_v1(
  p_run_id bigint,
  p_family_codes text[] DEFAULT ARRAY[]::text[]
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = 'pg_catalog'
AS $validator$
DECLARE
  v_run record;
  v_registry jsonb;
  v_family text;
  v_strategy jsonb;
  v_oracle jsonb;
  v_spec jsonb;
  v_items jsonb := '[]'::jsonb;
  v_uncovered integer := 0;
  v_unproven integer := 0;
  v_invalid integer := 0;
  v_code text;
BEGIN
  IF p_run_id IS NULL OR p_run_id <= 0 OR p_family_codes IS NULL
     OR array_ndims(p_family_codes) > 1 THEN
    RETURN jsonb_build_object('status','BLOCKED','code','INVALID_COMPARISON_INPUT',
      'semantic_pass_authorized',false,'promotion_authorized',false);
  END IF;

  SELECT r.version_id,r.pantalla_id,r.status,p.codigo screen_code
    INTO v_run
  FROM programacion.input_readiness_runs r
  JOIN lf_ops.pantallas p ON p.id=r.pantalla_id
  WHERE r.id=p_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','BLOCKED','code','SELECTED_RUN_NOT_FOUND',
      'run_id',p_run_id,'semantic_pass_authorized',false,'promotion_authorized',false);
  END IF;

  IF cardinality(p_family_codes)=0 THEN
    RETURN jsonb_build_object('status','NOT_REQUESTED','run_id',p_run_id,
      'pantalla_id',v_run.pantalla_id,'comparison_count',0,'results','[]'::jsonb,
      'existing_validator_unchanged',true,
      'semantic_pass_authorized',false,'promotion_authorized',false);
  END IF;

  SELECT c.especificacion INTO v_registry
  FROM programacion.contratos c
  WHERE c.contrato_codigo='INPUT_FAMILY_POLICY_REGISTRY'
    AND c.version_id=v_run.version_id
    AND c.estado='defined' AND c.fail_closed
  ORDER BY c.id DESC LIMIT 1;
  IF v_registry IS NULL OR v_registry->'families' IS NULL THEN
    RETURN jsonb_build_object('status','BLOCKED','code','FAMILY_REGISTRY_UNAVAILABLE',
      'run_id',p_run_id,'semantic_pass_authorized',false,'promotion_authorized',false);
  END IF;

  IF EXISTS (SELECT 1 FROM unnest(p_family_codes) t(family)
             WHERE family IS NULL OR family !~ '^[A-Z][A-Z0-9_]*$')
     OR (SELECT count(*) FROM unnest(p_family_codes)) <>
        (SELECT count(DISTINCT family) FROM unnest(p_family_codes) t(family)) THEN
    RETURN jsonb_build_object('status','BLOCKED','code','COMPARISON_SCOPE_INVALID',
      'run_id',p_run_id,'semantic_pass_authorized',false,'promotion_authorized',false);
  END IF;

  FOREACH v_family IN ARRAY p_family_codes LOOP
    v_strategy:=v_registry->'families'->v_family->'validator_oracle_strategy';
    IF v_strategy IS NULL OR nullif(v_strategy->>'strategy','') IS NULL
       OR NOT EXISTS (SELECT 1 FROM programacion.input_family_assessments a
                      WHERE a.run_id=p_run_id AND a.family_code=v_family) THEN
      v_invalid:=v_invalid+1;
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'family_code',v_family,'status','OUT_OF_SCOPE',
        'independent_semantic_pass',false));
      CONTINUE;
    END IF;

    -- Bounded static dispatch to an existing, separately authored shadow
    -- oracle; registry is authority for strategy, never executable SQL.
    IF v_strategy->>'priority_oracle_function' IS DISTINCT FROM
       'programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)' THEN
      v_invalid:=v_invalid+1;
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'family_code',v_family,'status','ORACLE_ADAPTER_UNSUPPORTED',
        'independent_semantic_pass',false));
      CONTINUE;
    END IF;

    v_oracle:=programacion.fn_input_governance_shadow_priority_oracle_v2(
      v_run.pantalla_id,v_family,v_run.version_id);
    v_spec:=programacion.fn_input_governance_shadow_family_spec_v2(
      v_family,v_run.version_id);
    IF coalesce((v_oracle->>'implemented')::boolean,false) IS NOT TRUE
       OR v_oracle->>'pantalla_id' IS DISTINCT FROM v_run.pantalla_id::text
       OR v_oracle->>'version_id' IS DISTINCT FROM v_run.version_id::text
       OR v_oracle->>'family_code' IS DISTINCT FROM v_family THEN
      v_code:='NOT_COVERED';
      v_uncovered:=v_uncovered+1;
    ELSIF coalesce((v_oracle->>'comparison_only')::boolean,false) IS NOT TRUE
       OR coalesce((v_oracle->>'decisional')::boolean,true)
       OR jsonb_array_length(coalesce(v_oracle->'trace','[]'::jsonb))=0
       OR nullif(v_oracle->>'shadow_sha256','') IS NULL
       OR coalesce(v_spec->'test_obligations','[]'::jsonb)='[]'::jsonb THEN
      v_code:='EVIDENCE_UNPROVEN';
      v_unproven:=v_unproven+1;
    ELSE
      v_code:='SHADOW_CANDIDATE_ONLY';
      v_unproven:=v_unproven+1;
    END IF;
    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'family_code',v_family,'status',v_code,
      'oracle_classification',v_oracle->>'classification',
      'independent_semantic_pass',false));
  END LOOP;

  RETURN jsonb_build_object(
    'contract','IG_VALIDATOR_ADDITIVE_ORACLE_COMPARISON_V1',
    'status',CASE WHEN v_invalid>0 THEN 'BLOCKED'
      WHEN v_uncovered>0 THEN 'NOT_COVERED'
      ELSE 'INDEPENDENCE_UNPROVEN' END,
    'run_id',p_run_id,'pantalla_id',v_run.pantalla_id,
    'comparison_count',cardinality(p_family_codes),
    'uncovered_count',v_uncovered,'unproven_count',v_unproven,
    'invalid_count',v_invalid,'results',v_items,
    'comparison_only',true,'existing_validator_unchanged',true,
    'semantic_pass_authorized',false,'promotion_authorized',false,
    'production_authorized',false);
END;
$validator$;

-- Internal non-decisional adapter. No public or service_role entrypoint.
REVOKE ALL ON FUNCTION programacion.fn_input_governance_validator_oracle_compare_v1(bigint,text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION programacion.fn_input_governance_validator_oracle_compare_v1(bigint,text[]) FROM anon,authenticated,service_role;
