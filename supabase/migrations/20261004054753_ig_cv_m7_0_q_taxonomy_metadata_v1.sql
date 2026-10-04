-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.0 / PAULO-109
-- Q0-Q8 taxonomy metadata for INPUT_GOVERNANCE_REGRESSION.
-- Reuses ASSURANCE_EVALUATOR + lf_assurance_claim_catalog + lf_assurance_obligation_catalog.
-- No Validator/runtime behavior change, no new registry/table/evaluator, no benchmark IGQ ingestion.

BEGIN;

DO $m7_0_preflight$
DECLARE
  v_total integer;
  v_preclassified integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_activos
    WHERE codigo_activo='ASSURANCE_EVALUATOR'
      AND archived_at IS NULL
      AND estado_documental='VIGENTE'
      AND estado_operativo='READ_ONLY'
      AND version='1.0.0'
      AND owner_name='SUPER_ADMIN'
  ) THEN
    RAISE EXCEPTION 'M7_0_ASSURANCE_EVALUATOR_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.lf_assurance_claim_catalog)
     OR NOT EXISTS (SELECT 1 FROM public.lf_assurance_obligation_catalog) THEN
    RAISE EXCEPTION 'M7_0_ASSURANCE_CATALOGS_MISSING';
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE metadata ? 'q_class' OR metadata ? 'oracle')
    INTO v_total,v_preclassified
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION';

  IF v_total<>77 THEN
    RAISE EXCEPTION 'M7_0_CASE_COUNT_DRIFT:expected=77 observed=%',v_total;
  END IF;
  IF v_preclassified<>0 THEN
    RAISE EXCEPTION 'M7_0_PREEXISTING_CLASSIFICATION:rows=%',v_preclassified;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code NOT LIKE 'M7_1_%'
      AND test_code NOT LIKE 'M2_1_%'
      AND test_code NOT LIKE 'M2_2_%'
      AND test_code NOT LIKE 'M1_A9_%'
  ) THEN
    RAISE EXCEPTION 'M7_0_UNMAPPED_CASE_FAMILY';
  END IF;
END
$m7_0_preflight$;

-- Q0: exact binding/provenance. A SHA match proves binding identity, not correctness.
UPDATE public.lf_test_suite_cases
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'q_class','Q0',
      'dimension','BINDING_PROVENANCE',
      'property','EXACT_COMPONENT_BINDING',
      'oracle',CASE test_code
        WHEN 'M7_1_BUILD_SHA' THEN 'EXACT_BUILD_SHA_READBACK'
        WHEN 'M7_1_CONTRACT_SHA' THEN 'INPUT_READINESS_CONTRACT_SHA_READBACK'
        WHEN 'M7_1_REGISTRY_SHA' THEN 'EJECUCION_INPUT_GOVERNANCE_REGISTRY_SHA_READBACK'
        ELSE 'LF_ACTIVOS_COMPONENT_SHA_READBACK'
      END,
      'expected','EXACT_SHA_MATCH',
      'evidence',jsonb_build_object(
        'authority','public.lf_test_suites.metadata.bindings',
        'suite_code','INPUT_GOVERNANCE_REGRESSION',
        'test_code',test_code,
        'claim_scope','BINDING_ONLY_NOT_CORRECTNESS'
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-0-20261004'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
  AND test_code LIKE 'M7_1_%';

-- Q1: source identity/resolution structure. Includes positive and negative contract behavior.
UPDATE public.lf_test_suite_cases
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'q_class','Q1',
      'dimension','STRUCTURAL',
      'property','SOURCE_KIND_IDENTITY_RESOLUTION',
      'oracle','programacion.fn_input_resolve_source_ref',
      'expected',CASE metadata->>'polarity'
        WHEN 'POSITIVE' THEN 'RESOLVES'
        WHEN 'NEGATIVE' THEN 'REJECTS'
        ELSE 'UNMAPPED'
      END,
      'evidence',jsonb_build_object(
        'authority',coalesce(metadata->>'source_resolution_policy','POL-LF-SOURCE-RESOLUTION'),
        'resolver','programacion.fn_input_resolve_source_ref',
        'source_kind',metadata->>'source_kind',
        'polarity',metadata->>'polarity',
        'claim_scope','STRUCTURAL_ONLY_NOT_SEMANTIC_OR_READINESS'
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-0-20261004'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
  AND test_code LIKE 'M2_1_%';

-- Q1: collection/cardinality semantics are structural contracts of the source resolver.
UPDATE public.lf_test_suite_cases
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'q_class','Q1',
      'dimension','STRUCTURAL',
      'property','SOURCE_COLLECTION_CARDINALITY_SEMANTICS',
      'oracle','programacion.fn_input_resolve_source_ref',
      'expected',CASE metadata->>'scenario'
        WHEN 'EMPTY_POSITIVE' THEN 'RESOLVES_EMPTY_COLLECTION'
        WHEN 'NONEMPTY_POSITIVE' THEN 'RESOLVES_NONEMPTY_COLLECTION'
        WHEN 'MISSING_REF_NEGATIVE' THEN 'REJECTS_MISSING_REF'
        WHEN 'CARDINALITY_NEGATIVE' THEN 'REJECTS_INVALID_CARDINALITY'
        ELSE 'UNMAPPED'
      END,
      'evidence',jsonb_build_object(
        'authority','POL-LF-SOURCE-RESOLUTION@v1.4-transversal-supabase-authority-visual-support',
        'resolver','programacion.fn_input_resolve_source_ref',
        'source_kind',metadata->>'source_kind',
        'scenario',metadata->>'scenario',
        'empty_collection_semantics',metadata->>'empty_collection_semantics',
        'claim_scope','STRUCTURAL_ONLY_NOT_SEMANTIC_OR_READINESS'
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-0-20261004'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
  AND test_code LIKE 'M2_2_%';

-- Q2: parity/compatibility. Explicitly does not claim semantic correctness.
UPDATE public.lf_test_suite_cases
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'q_class','Q2',
      'dimension','PARITY_COMPATIBILITY',
      'property','VERSIONED_CONTRACT_CLAUSE_PARITY',
      'oracle','programacion.fn_input_contract_clause_v1',
      'expected',CASE test_code
        WHEN 'M1_A9_CONTRACT_CLAUSE_PARITY_POSITIVE' THEN 'PARITY_MATCH'
        WHEN 'M1_A9_CONTRACT_VERSION_UNPINNED_NEGATIVE' THEN 'REJECTS_UNPINNED_VERSION'
        WHEN 'M1_A9_CONTRACT_CLAUSE_MISSING_NEGATIVE' THEN 'REJECTS_MISSING_CLAUSE'
        ELSE 'UNMAPPED'
      END,
      'evidence',jsonb_build_object(
        'authority','programacion.contratos',
        'oracle','programacion.fn_input_contract_clause_v1',
        'test_code',test_code,
        'claim_scope','PARITY_ONLY_NOT_CORRECTNESS'
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-0-20261004'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
  AND test_code LIKE 'M1_A9_%';

UPDATE public.lf_test_suites
SET metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'm7_0_q_taxonomy',jsonb_build_object(
        'version','Q_TAXONOMY_V1',
        'unit_code','M7.0',
        'work_code','PAULO-109',
        'doc_path','docs/ig_refactor/test_taxonomy_q0_q8.md',
        'classified_case_count',77,
        'q_classes',jsonb_build_object(
          'Q0','BINDING_PROVENANCE',
          'Q1','STRUCTURAL',
          'Q2','PARITY_COMPATIBILITY',
          'Q3','SEMANTIC',
          'Q4','CROSS_FAMILY_COHERENCE',
          'Q5','READINESS',
          'Q6','ADVERSARIAL_FALSE_PASS',
          'Q7','CURRENTNESS_LINEAGE_REPLAY',
          'Q8','END_TO_END_RELEASE_ASSURANCE'
        ),
        'parity_equals_correctness',false,
        'structural_equals_semantic',false,
        'semantic_equals_readiness',false,
        'assurance_reuse',jsonb_build_object(
          'evaluator','ASSURANCE_EVALUATOR@1.0.0',
          'claim_catalog','public.lf_assurance_claim_catalog',
          'obligation_catalog','public.lf_assurance_obligation_catalog',
          'parallel_taxonomy_created',false
        )
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-0-20261004'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION';

DO $m7_0_readback$
DECLARE
  v_total integer;
  v_incomplete integer;
  v_q0 integer;
  v_q1 integer;
  v_q2 integer;
BEGIN
  SELECT count(*),
         count(*) FILTER (
           WHERE nullif(metadata->>'q_class','') IS NULL
              OR nullif(metadata->>'dimension','') IS NULL
              OR nullif(metadata->>'property','') IS NULL
              OR nullif(metadata->>'oracle','') IS NULL
              OR nullif(metadata->>'expected','') IS NULL
              OR NOT (metadata ? 'evidence')
              OR metadata->'evidence' IS NULL
              OR metadata->'evidence'='null'::jsonb
         ),
         count(*) FILTER (WHERE metadata->>'q_class'='Q0'),
         count(*) FILTER (WHERE metadata->>'q_class'='Q1'),
         count(*) FILTER (WHERE metadata->>'q_class'='Q2')
    INTO v_total,v_incomplete,v_q0,v_q1,v_q2
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION';

  IF v_total<>77 OR v_incomplete<>0 OR v_q0<>10 OR v_q1<>64 OR v_q2<>3 THEN
    RAISE EXCEPTION 'M7_0_CLASSIFICATION_READBACK_FAILED:total=% incomplete=% q0=% q1=% q2=%',
      v_total,v_incomplete,v_q0,v_q1,v_q2;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND metadata->>'q_class' NOT IN ('Q0','Q1','Q2','Q3','Q4','Q5','Q6','Q7','Q8')
  ) THEN
    RAISE EXCEPTION 'M7_0_INVALID_Q_CLASS';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND metadata->>'expected'='UNMAPPED'
  ) THEN
    RAISE EXCEPTION 'M7_0_UNMAPPED_EXPECTED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND metadata->>'q_class'='Q2'
      AND metadata->>'dimension' IN ('SEMANTIC','READINESS')
  ) THEN
    RAISE EXCEPTION 'M7_0_PARITY_OVERCLAIMS_CORRECTNESS';
  END IF;
END
$m7_0_readback$;

COMMIT;
