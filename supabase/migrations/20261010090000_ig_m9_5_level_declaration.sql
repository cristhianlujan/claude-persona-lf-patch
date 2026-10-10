-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M9.5 / LEVEL_DECLARATION
-- Only programacion.contratos; no T-EQUIV engine modification or activation.
DO $ig_m95$
DECLARE
  v_source programacion.contratos%ROWTYPE;
  v_spec jsonb := '{"schema_version":"IG_DIVERGENCE_LEVEL_DECLARATION_V1","contract_revision":"1.0","status":"DECLARED_NOT_ACTIVATED","owner":"INPUT_GOVERNANCE_CONSUMER","provider_capability":"CONTROL_EQUIVALENCE_JUDGE","provider_owns_engine":true,"consumer_owns_level_mapping":true,"level_codes":["D0","D1","D2","D3","D4","D5"],"global_semantics":{"D0":"EXACT_EQUALITY","D4":"KNOWN_FALSE_PASS_RISK_ALWAYS_BLOCKING"},"consumer_defined_semantics":["D1","D2","D3","D5"],"declaration_policy":{"granularity":"PER_CONSUMER_PER_FIELD","selection":"DYNAMIC_FROM_CURRENT_VERSIONED_CONSUMER_DECLARATION","fixed_screen_or_field_lists":false,"no_implicit_level_default":true,"required_per_field":["consumer_code","subject_scope","field_path","level_code","meaning","mapping_ref","policy_ref","policy_version","evidence_ref"],"unmapped":"BLOCKED_UNCLASSIFIED_DIVERGENCE","missing_current_policy":"BLOCKED","D4_override":"ALWAYS_BLOCK","D0_requirements":"EXACT_EQUALITY"},"declarations":[],"execution":{"runs_engine":false,"creates_comparator":false,"production_activation":false,"adopts_existing_transversal_only":true},"owner_checkpoint":"IG_CURATOR_VALIDATOR_REFACTOR_V2/M9.5/LEVEL_DECLARATION","source_authority":"CONTROL_EQUIVALENCE_JUDGE/1.0.0"}'::jsonb;
  v_existing programacion.contratos%ROWTYPE;
BEGIN
  SELECT * INTO v_source
  FROM programacion.contratos
  WHERE contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' AND estado='defined'
  ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'M95_SOURCE_CONTRACT_MISSING'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.lf_capability_registry r
    JOIN public.lf_capability_current cur USING(capability_code)
    JOIN public.lf_capability_version_registry v
      ON v.capability_code=cur.capability_code AND v.version=cur.version
    WHERE r.capability_code='CONTROL_EQUIVALENCE_JUDGE'
      AND r.status='ACTIVE' AND cur.version='1.0.0'
      AND v.release_state='RELEASED'
  ) THEN RAISE EXCEPTION 'M95_TEQUIV_NOT_CURRENT'; END IF;
  SELECT * INTO v_existing
  FROM programacion.contratos
  WHERE version_id=v_source.version_id
    AND contrato_codigo='INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT';
  IF FOUND THEN
    IF v_existing.especificacion IS DISTINCT FROM v_spec OR v_existing.fail_closed IS NOT TRUE THEN
      RAISE EXCEPTION 'M95_LEVEL_CONTRACT_DRIFT';
    END IF;
    RETURN;
  END IF;
  INSERT INTO programacion.contratos (
    version_id,contrato_codigo,tipo,nombre,descripcion,estado,especificacion,
    fail_closed,productor_componente_id
  ) VALUES (
    v_source.version_id,'INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT','governance',
    'Input Governance per-field divergence-level declaration',
    'Versioned declarative D0-D5 field policy for transversal T-EQUIV; D0 exact and D4 false-pass blocking are global. D1 D2 D3 D5 meanings require explicit consumer policy.',
    'defined',v_spec,true,v_source.productor_componente_id
  );
  IF NOT EXISTS (
    SELECT 1 FROM programacion.contratos
    WHERE version_id=v_source.version_id
      AND contrato_codigo='INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT'
      AND fail_closed
      AND especificacion=v_spec
  ) THEN RAISE EXCEPTION 'M95_LEVEL_CONTRACT_READBACK_FAILED'; END IF;
END
$ig_m95$;