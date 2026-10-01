-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M1.4 / PAULO-119
-- Family Policy Registry 47/47, materialized in the existing programacion.contratos authority.
-- R16 Git-first. No runtime activation. Fail closed on authority drift.

DO $m14$
DECLARE
  v_readiness jsonb;
  v_universe jsonb;
  v_families jsonb;
  v_spec jsonb;
  v_registry_sha256 text;
  v_next_id bigint;
  v_missing_stage integer;
  v_rule_count integer;
  v_family_count integer;
BEGIN
  SELECT c.especificacion
    INTO v_readiness
  FROM programacion.contratos c
  WHERE c.version_id = 19
    AND c.contrato_codigo = 'INPUT_READINESS_CONTRACT';

  IF v_readiness IS NULL THEN
    RAISE EXCEPTION 'M14_INPUT_READINESS_CONTRACT_V19_NOT_FOUND';
  END IF;

  IF md5(v_readiness::text) <> '1d9709b94d20ee8036ad985edffaaf01' THEN
    RAISE EXCEPTION 'M14_INPUT_READINESS_CONTRACT_DRIFT:%', md5(v_readiness::text);
  END IF;

  SELECT r.valor_config->'families'
    INTO v_universe
  FROM lf_ops.reglas r
  WHERE r.codigo = 'B2B-RULE-STORY-READINESS-001'
    AND r.estado = 'VIGENTE'
    AND NOT r.pendiente_decision;

  IF v_universe IS NULL OR jsonb_typeof(v_universe) <> 'array' THEN
    RAISE EXCEPTION 'M14_CANONICAL_FAMILY_UNIVERSE_NOT_FOUND';
  END IF;

  v_rule_count := jsonb_array_length(v_universe);
  IF v_rule_count <> 47 THEN
    RAISE EXCEPTION 'M14_CANONICAL_FAMILY_COUNT_DRIFT:%', v_rule_count;
  END IF;

  SELECT count(*)
    INTO v_missing_stage
  FROM jsonb_array_elements_text(v_universe) f(family)
  WHERE nullif(v_readiness->'family_stage_requirements'->f.family->>'coverage_required_by','') IS NULL
     OR nullif(v_readiness->'family_stage_requirements'->f.family->>'authority','') IS NULL;

  IF v_missing_stage <> 0 THEN
    RAISE EXCEPTION 'M14_STAGE_POLICY_GAPS:%', v_missing_stage;
  END IF;

  IF md5(pg_get_functiondef('programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)'::regprocedure))
       <> '253a87db56a2b37f08532d020a74f097' THEN
    RAISE EXCEPTION 'M14_DETERMINISTIC_RESOLVER_DRIFT';
  END IF;

  IF md5(pg_get_functiondef('programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)'::regprocedure))
       <> '131d3d43204984ea646fe4536f83ad11' THEN
    RAISE EXCEPTION 'M14_SEMANTIC_RESOLVER_DRIFT';
  END IF;

  IF md5(pg_get_functiondef('programacion.fn_input_governance_shadow_family_spec_v2(text,bigint)'::regprocedure))
       <> 'd75e327ca3e31d4a239b01715cc6e3c1' THEN
    RAISE EXCEPTION 'M14_SHADOW_FAMILY_SPEC_DRIFT';
  END IF;

  IF md5(pg_get_functiondef('programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)'::regprocedure))
       <> 'd4e8c28fefab8a2cc7a4b95cc4bdb745' THEN
    RAISE EXCEPTION 'M14_SHADOW_ORACLE_DRIFT';
  END IF;

  SELECT jsonb_object_agg(
           f.family,
           jsonb_build_object(
             'family_code', f.family,
             'stage_policy', v_readiness->'family_stage_requirements'->f.family,
             'deterministic_resolver', jsonb_build_object(
               'function', 'programacion.fn_input_governance_bootstrap_classify_v2(integer,text,bigint)',
               'version_md5', '253a87db56a2b37f08532d020a74f097',
               'authority', 'CURRENT_CLASSIFIER_V2'
             ),
             'semantic_resolvers', jsonb_build_array(
               jsonb_build_object(
                 'function', 'programacion.fn_input_governance_semantic_probe_v3(integer,text,bigint)',
                 'version_md5', '131d3d43204984ea646fe4536f83ad11',
                 'role', 'GENERIC_SEMANTIC_RESOLVER'
               )
             ),
             'validator_oracle_strategy', jsonb_build_object(
               'strategy', 'SHADOW_FAMILY_POLICY_ORACLE_V2',
               'family_spec_function', 'programacion.fn_input_governance_shadow_family_spec_v2(text,bigint)',
               'family_spec_version_md5', 'd75e327ca3e31d4a239b01715cc6e3c1',
               'priority_oracle_function', 'programacion.fn_input_governance_shadow_priority_oracle_v2(integer,text,bigint)',
               'priority_oracle_version_md5', 'd4e8c28fefab8a2cc7a4b95cc4bdb745',
               'activation_state', 'DECLARED_FOR_M4_INDEPENDENT_ORACLE',
               'current_validator_independence_claim', false,
               'authority', 'AUD-045'
             ),
             'complete_semantics_contract', jsonb_build_object(
               'applicability_required', true,
               'complete_if_required', true,
               'partial_if_required', true,
               'missing_if_required', true,
               'not_applicable_positive_authority_required', true,
               'max_reachable_level_required', true,
               'authority', 'AUD-046'
             ),
             'test_obligations', jsonb_build_object(
               'positive_required', true,
               'negative_required', true,
               'metamorphic_required', true,
               'regression_required', true,
               'authority', 'TEST-008'
             )
           )
           ORDER BY f.family
         )
    INTO v_families
  FROM jsonb_array_elements_text(v_universe) f(family);

  SELECT count(*) INTO v_family_count FROM jsonb_object_keys(v_families);
  IF v_family_count <> 47 THEN
    RAISE EXCEPTION 'M14_REGISTRY_BUILD_COUNT_DRIFT:%', v_family_count;
  END IF;

  v_registry_sha256 := programacion.fn_v09_sha256_jsonb(v_families);

  v_spec := jsonb_build_object(
    'contract_revision', '1.0.0',
    'registry_code', 'INPUT_FAMILY_POLICY_REGISTRY',
    'version_id', 19,
    'family_count', 47,
    'canonical_universe_rule', 'B2B-RULE-STORY-READINESS-001',
    'readiness_contract', 'INPUT_READINESS_CONTRACT@19',
    'readiness_contract_md5', '1d9709b94d20ee8036ad985edffaaf01',
    'registry_sha256', v_registry_sha256,
    'families', v_families,
    'fail_closed', true,
    'source_migration', 'supabase/migrations/20261001222000_ig_cv_m14_family_policy_registry_v1.sql',
    'governance', jsonb_build_object(
      'ekb_refs', jsonb_build_array('AUD-044','AUD-045','AUD-046','TEST-008'),
      'runtime_activation', false,
      'production_authorized', false,
      'm3_3_absorbed', true
    )
  );

  IF EXISTS (
    SELECT 1
    FROM jsonb_each(v_families) e(family, spec)
    WHERE nullif(e.spec->'stage_policy'->>'coverage_required_by','') IS NULL
       OR nullif(e.spec->'stage_policy'->>'authority','') IS NULL
       OR nullif(e.spec->'deterministic_resolver'->>'function','') IS NULL
       OR nullif(e.spec->'deterministic_resolver'->>'version_md5','') IS NULL
       OR jsonb_array_length(e.spec->'semantic_resolvers') = 0
       OR nullif(e.spec->'validator_oracle_strategy'->>'strategy','') IS NULL
  ) THEN
    RAISE EXCEPTION 'M14_REGISTRY_REQUIRED_FIELD_GAP';
  END IF;

  LOCK TABLE programacion.contratos IN SHARE ROW EXCLUSIVE MODE;

  IF EXISTS (
    SELECT 1 FROM programacion.contratos
    WHERE version_id = 19
      AND contrato_codigo = 'INPUT_FAMILY_POLICY_REGISTRY'
  ) THEN
    RAISE EXCEPTION 'M14_REGISTRY_ALREADY_EXISTS_FOR_VERSION_19';
  END IF;

  SELECT coalesce(max(id),0) + 1 INTO v_next_id FROM programacion.contratos;

  INSERT INTO programacion.contratos(
    id, version_id, contrato_codigo, tipo, nombre, descripcion,
    productor_componente_id, consumidor_componente_id,
    especificacion, fail_closed, estado
  ) VALUES (
    v_next_id,
    19,
    'INPUT_FAMILY_POLICY_REGISTRY',
    'governance',
    'Input Family Policy Registry',
    'Registry 47/47 for deterministic resolver, semantic resolver version, Validator oracle strategy and stage policy.',
    NULL,
    NULL,
    v_spec,
    true,
    'defined'
  );

  IF NOT EXISTS (
    SELECT 1
    FROM programacion.contratos c
    WHERE c.version_id = 19
      AND c.contrato_codigo = 'INPUT_FAMILY_POLICY_REGISTRY'
      AND (c.especificacion->>'family_count')::integer = 47
      AND c.especificacion->>'registry_sha256' = programacion.fn_v09_sha256_jsonb(c.especificacion->'families')
  ) THEN
    RAISE EXCEPTION 'M14_REGISTRY_READBACK_FAILED';
  END IF;
END;
$m14$;
