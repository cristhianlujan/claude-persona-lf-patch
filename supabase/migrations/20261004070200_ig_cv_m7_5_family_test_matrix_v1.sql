-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M7.5 / PAULO-086
-- Governed 47 families x 6 test types matrix (282 cells) inside INPUT_GOVERNANCE_REGRESSION.
-- Reuses M7.0 taxonomy and all M7.3 negative cases. No second suite, taxonomy, or test engine.
-- R16 Git-first. No Validator/runtime changes.

BEGIN;

DO $m7_5_preflight$
DECLARE
  v_dep_status text;
  v_family_count integer;
  v_latest_run bigint;
  v_latest_family_count integer;
  v_non_applicable integer;
  v_m7_3_count integer;
  v_m7_3_incomplete integer;
  v_existing integer;
BEGIN
  SELECT status INTO v_dep_status
  FROM programacion.engineering_work_items
  WHERE work_code='PAULO-052';

  IF v_dep_status IS DISTINCT FROM 'DONE' THEN
    RAISE EXCEPTION 'M7_5_DEPENDENCY_NOT_DONE:PAULO-052 status=%', v_dep_status;
  END IF;

  SELECT count(DISTINCT family_code) INTO v_family_count
  FROM programacion.input_family_assessments;

  IF v_family_count<>47 THEN
    RAISE EXCEPTION 'M7_5_FAMILY_COUNT_DRIFT:expected=47 observed=%', v_family_count;
  END IF;

  SELECT max(run_id) INTO v_latest_run
  FROM programacion.input_family_assessments;

  SELECT count(*),
         count(*) FILTER (WHERE applicability<>'APPLICABLE')
    INTO v_latest_family_count,v_non_applicable
  FROM programacion.input_family_assessments
  WHERE run_id=v_latest_run;

  IF v_latest_family_count<>47 OR v_non_applicable<>0 THEN
    RAISE EXCEPTION
      'M7_5_LATEST_FAMILY_SET_INVALID:run_id=% rows=% non_applicable=%',
      v_latest_run,v_latest_family_count,v_non_applicable;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_test_suites
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND metadata->'m7_0_q_taxonomy'->>'version'='Q_TAXONOMY_V1'
  ) THEN
    RAISE EXCEPTION 'M7_5_M7_0_Q_TAXONOMY_MISSING';
  END IF;

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
         )
    INTO v_m7_3_count,v_m7_3_incomplete
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND metadata->>'unit_code'='M7.3';

  IF v_m7_3_count<>91 OR v_m7_3_incomplete<>0 THEN
    RAISE EXCEPTION
      'M7_5_M7_3_NEGATIVE_CATALOG_INVALID:count=% incomplete=%',
      v_m7_3_count,v_m7_3_incomplete;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code='M7_3_NEG_001_MISSING_SOURCE'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code='M7_3_NEG_002_CONTRADICTORY_SOURCE'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code='M7_3_NEG_007_STALE_EVIDENCE'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.lf_test_suite_cases
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND test_code='M7_3_NEG_042_SEMANTIC_DEPTH_MUTATION_AFTER_CURATOR'
  ) THEN
    RAISE EXCEPTION 'M7_5_REQUIRED_REUSED_M7_3_CASE_MISSING';
  END IF;

  SELECT count(*) INTO v_existing
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND (metadata->>'unit_code'='M7.5' OR test_code LIKE 'M7_5_%');

  IF v_existing<>0 THEN
    RAISE EXCEPTION 'M7_5_PREEXISTING_CASES:observed=%',v_existing;
  END IF;
END
$m7_5_preflight$;

WITH next_order AS (
  SELECT coalesce(max(test_order),0)+1 AS n
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
)
INSERT INTO public.lf_test_suite_cases (
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,
  execution_mode,severity,preconditions,input_payload,expected_output,
  prohibited_output,status,metadata,created_at,updated_at,
  created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION',
  'M7_5_POSITIVE_FAMILY_GOVERNED_ACCEPTANCE',
  n,
  NULL,
  ARRAY[]::text[],
  'M7.5 parameterized positive family acceptance',
  'POSITIVE',
  'AUTOMATED',
  'HIGH',
  jsonb_build_object(
    'family_parameter_required',true,
    'canonical_family_source','programacion.input_family_assessments',
    'q_taxonomy','Q_TAXONOMY_V1',
    'oracle_capability','ASSURANCE_EVALUATOR@1.0.0',
    'runtime_mutation_required',false
  ),
  jsonb_build_object(
    'schema_version','M7_5_FAMILY_POSITIVE_FIXTURE_V1',
    'family_code_parameter','{{family_code}}',
    'fixture_kind','GOVERNED_FAMILY_POSITIVE_PROPERTY',
    'synthetic_fixture',true,
    'side_effects',false
  ),
  jsonb_build_object(
    'decision','ACCEPT_ONLY_WITH_GOVERNED_EVIDENCE',
    'claim_scope','SEMANTIC_PROPERTY_ONLY_NOT_READINESS_OR_PARITY'
  ),
  jsonb_build_object(
    'accept_from_structure_only',true,
    'accept_from_parity_only',true,
    'infer_readiness_from_semantic_pass',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'unit_code','M7.5',
    'work_code','PAULO-086',
    'q_class','Q3',
    'dimension','SEMANTIC',
    'property','FAMILY_GOVERNED_POSITIVE_ACCEPTANCE',
    'oracle','ASSURANCE_EVALUATOR@1.0.0',
    'expected','ACCEPT_ONLY_WITH_GOVERNED_EVIDENCE',
    'evidence',jsonb_build_object(
      'authority','programacion.input_family_assessments',
      'locator','latest run_id; family_code={{family_code}}',
      'taxonomy_authority','INPUT_GOVERNANCE_REGRESSION.metadata.m7_0_q_taxonomy'
    ),
    'equivalence_key','M7_5_PARAMETRIC_POSITIVE_FAMILY_ACCEPTANCE_V1',
    'parameterized_family_count',47,
    'parity_equals_correctness',false,
    'semantic_equals_readiness',false,
    'structural_equals_semantic',false,
    'no_parallel_suite',true,
    'no_parallel_test_engine',true
  ),
  now(),now(),
  'CHATGPT-IG-CV-M7-5-20261004',
  'CHATGPT-IG-CV-M7-5-20261004'
FROM next_order;

WITH
families AS (
  SELECT DISTINCT family_code
  FROM programacion.input_family_assessments
),
primary_negative_map(family_code,test_code) AS (
  VALUES
    ('ACCESSIBILITY','M7_3_NEG_001_MISSING_SOURCE'),
    ('ACTIONS','M7_3_NEG_010_AMBIGUOUS_INPUT'),
    ('ANALYTICS','M7_3_NEG_052_ANALYTICS_GAP_AS_STORY_P0'),
    ('API_DATA_CONTRACT','M7_3_NEG_021_DESCRIPTIVE_API_RULE_AS_IMPLEMENTATION_READY_WITHOUT_RESOLVABLE_SCHEMA'),
    ('APPLICABILITY_READINESS','M7_3_NEG_017_APPLICABLE_WITH_NOT_APPLICABLE_STATUS'),
    ('ASSETS_ICONS','M7_3_NEG_001_MISSING_SOURCE'),
    ('AUDIT','M7_3_NEG_035_CURATOR_VALIDATOR_SAME_EXECUTION_ID'),
    ('BROWSER_PLATFORM','M7_3_NEG_045_BROWSER_PLATFORM_QA_GAP_AS_STORY_BLOCKER'),
    ('CONFLICT_PRECEDENCE','M7_3_NEG_002_CONTRADICTORY_SOURCE'),
    ('CONTEXT_BUDGET_RETRIEVAL_POLICY','M7_3_NEG_005_TIMEOUT_WITHOUT_SOURCE'),
    ('DEPENDENCIES','M7_3_NEG_013_MISSING_COMPONENT_BINDING'),
    ('DESIGN_SYSTEM','M7_3_NEG_015_AMBIGUOUS_DESIGN_REF'),
    ('EKB','M7_3_NEG_008_HISTORICAL_PASS_OVERRIDES_NEWER_FAILURE'),
    ('ERRORS','M7_3_NEG_025_UNRESOLVED_SEVERITY'),
    ('FEATURE_FLAGS','M7_3_NEG_090_HARDCODED_CONFIGURABLE_THRESHOLD'),
    ('FIELDS','M7_3_NEG_050_OTP_PIN_TREATED_AS_GENERIC_TEXT_INPUT'),
    ('FORCED_COLORS_CONTRAST','M7_3_NEG_053_FORCED_COLORS_GAP_AS_STORY_P0'),
    ('FRESHNESS_INVALIDATION','M7_3_NEG_007_STALE_EVIDENCE'),
    ('I18N_FORMATS','M7_3_NEG_001_MISSING_SOURCE'),
    ('IDEMPOTENCY_CONCURRENCY','M7_3_NEG_054_IDEMPOTENCY_GAP_AS_STORY_P0'),
    ('LOADING_EMPTY_ERROR_STATES','M7_3_NEG_010_AMBIGUOUS_INPUT'),
    ('MFA_OTP_SSO','M7_3_NEG_072_OTP_SOURCE_EXISTS_BUT_MFA_OTP_SSO_NA'),
    ('NEGATIVE_REQUIREMENTS','M7_3_NEG_011_UNTESTABLE_REQUIREMENT'),
    ('OBJECTIVE_OUTCOMES','M7_3_NEG_001_MISSING_SOURCE'),
    ('OBSERVABILITY','M7_3_NEG_001_MISSING_SOURCE'),
    ('PERFORMANCE','M7_3_NEG_001_MISSING_SOURCE'),
    ('PERMISSIONS','M7_3_NEG_084_PERMISSIONS_EXCLUSION_RULE_MUST_BE_DECLARED_SOURCE'),
    ('PRIVACY_PII','M7_3_NEG_001_MISSING_SOURCE'),
    ('PROFILES','M7_3_NEG_013_MISSING_COMPONENT_BINDING'),
    ('RATE_LIMIT','M7_3_NEG_090_HARDCODED_CONFIGURABLE_THRESHOLD'),
    ('REDUCED_MOTION','M7_3_NEG_055_REDUCED_MOTION_GAP_AS_STORY_P0'),
    ('RESPONSIVE','M7_3_NEG_001_MISSING_SOURCE'),
    ('ROLLOUT_PRODUCTION_GATES','M7_3_NEG_080_V512_STAGE_BOUNDARY_GUARD_ACTIVE'),
    ('ROUTING_NAVIGATION','M7_3_NEG_029_SCREEN_SCOPED_REF_WITHOUT_ID'),
    ('RUNTIME_CONFIG','M7_3_NEG_090_HARDCODED_CONFIGURABLE_THRESHOLD'),
    ('SCREEN_IDENTITY','M7_3_NEG_029_SCREEN_SCOPED_REF_WITHOUT_ID'),
    ('SECURITY','M7_3_NEG_041_SECURITY_THREAT_OMITTED'),
    ('SESSION','M7_3_NEG_064_RECOVERY_OTP_CREATES_OPERATIONAL_SESSION'),
    ('SOURCE_AUTHORITY_PROVENANCE','M7_3_NEG_089_INDUSTRY_GUIDANCE_MISLABELED_AS_INTERNATIONAL_STANDARD'),
    ('STATES','M7_3_NEG_070_NA_WITH_EMPTY_STATE_SET'),
    ('TESTING_OBLIGATIONS','M7_3_NEG_056_TEST_CONTRACT_GAP_AS_STORY_P0'),
    ('THEME_LIGHT_DARK_SYSTEM','M7_3_NEG_057_THEME_GAP_AS_STORY_P0'),
    ('TIMEOUT_RETRY','M7_3_NEG_005_TIMEOUT_WITHOUT_SOURCE'),
    ('TRANSITIONS','M7_3_NEG_022_IMPLEMENTATION_READY_WHILE_STORY_NOT_READY'),
    ('UI_MESSAGES','M7_3_NEG_010_AMBIGUOUS_INPUT'),
    ('VALIDATIONS','M7_3_NEG_068_POSITIVE_RULE_ASSERTION_WITH_FALSE_MISSING_BLOCKER'),
    ('VISUAL_EVIDENCE','M7_3_NEG_032_DECLARED_STORAGE_VISUAL_MISSING')
),
types(seq,test_kind,default_test_code) AS (
  VALUES
    (1,'POSITIVO','M7_5_POSITIVE_FAMILY_GOVERNED_ACCEPTANCE'),
    (2,'NEGATIVO',NULL::text),
    (3,'FALTANTE','M7_3_NEG_001_MISSING_SOURCE'),
    (4,'STALE','M7_3_NEG_007_STALE_EVIDENCE'),
    (5,'CONTRADICCION','M7_3_NEG_002_CONTRADICTORY_SOURCE'),
    (6,'MUTACION','M7_3_NEG_042_SEMANTIC_DEPTH_MUTATION_AFTER_CURATOR')
),
matrix_resolved AS (
  SELECT
    f.family_code,
    t.seq,
    t.test_kind,
    CASE WHEN t.test_kind='NEGATIVO' THEN p.test_code ELSE t.default_test_code END AS test_code
  FROM families f
  CROSS JOIN types t
  LEFT JOIN primary_negative_map p ON p.family_code=f.family_code
),
matrix_enriched AS (
  SELECT
    m.family_code,m.seq,m.test_kind,m.test_code,
    c.metadata->>'q_class' AS q_class,
    c.metadata->>'dimension' AS dimension,
    c.metadata->>'property' AS property,
    c.metadata->>'oracle' AS oracle,
    c.metadata->>'expected' AS expected,
    c.metadata->'evidence' AS evidence
  FROM matrix_resolved m
  JOIN public.lf_test_suite_cases c
    ON c.suite_code='INPUT_GOVERNANCE_REGRESSION'
   AND c.test_code=m.test_code
),
matrix_json AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'family_code',family_code,
      'test_kind',test_kind,
      'resolution','TEST_CODE',
      'test_code',test_code,
      'q_class',q_class,
      'dimension',dimension,
      'property',property,
      'oracle',oracle,
      'expected',expected,
      'evidence',evidence
    )
    ORDER BY family_code,seq
  ) AS cells
  FROM matrix_enriched
),
negative_catalog AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'test_code',test_code,
      'contract_ordinal',(metadata->>'contract_ordinal')::integer,
      'contract_negative_test',metadata->>'contract_negative_test',
      'q_class',metadata->>'q_class',
      'dimension',metadata->>'dimension',
      'property',metadata->>'property',
      'oracle',metadata->>'oracle',
      'expected',metadata->>'expected',
      'evidence',metadata->'evidence',
      'reuse_role','M7_5_NEGATIVE_CATALOG_WHEN_APPLICABLE'
    )
    ORDER BY (metadata->>'contract_ordinal')::integer
  ) AS catalog
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND metadata->>'unit_code'='M7.3'
),
next_order AS (
  SELECT coalesce(max(test_order),0)+1 AS n
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
)
INSERT INTO public.lf_test_suite_cases (
  suite_code,test_code,test_order,story_code,rule_codes,title,test_type,
  execution_mode,severity,preconditions,input_payload,expected_output,
  prohibited_output,status,metadata,created_at,updated_at,
  created_by_execution_id,updated_by_execution_id
)
SELECT
  'INPUT_GOVERNANCE_REGRESSION',
  'M7_5_MATRIX_47X6_MANIFEST',
  o.n,
  NULL,
  ARRAY[]::text[],
  'M7.5 governed 47 families x 6 test types matrix manifest',
  'MATRIX_GOVERNANCE',
  'GOVERNANCE',
  'HIGH',
  jsonb_build_object(
    'canonical_family_count',47,
    'test_type_count',6,
    'expected_cell_count',282,
    'dependency','M7.3/PAULO-052 DONE',
    'taxonomy','M7.0/Q_TAXONOMY_V1'
  ),
  jsonb_build_object(
    'schema_version','M7_5_MATRIX_INPUT_V1',
    'family_authority','programacion.input_family_assessments',
    'suite_authority','INPUT_GOVERNANCE_REGRESSION'
  ),
  jsonb_build_object(
    'cells',282,
    'omitted_cells',0,
    'orphan_cells',0,
    'na_policy','EXPLICIT_REASON_AUTHORITY_EVIDENCE_REQUIRED'
  ),
  jsonb_build_object(
    'omitted_cell',true,
    'orphan_test_code',true,
    'implicit_na',true,
    'parallel_suite',true,
    'parallel_test_engine',true
  ),
  'CANDIDATO',
  jsonb_build_object(
    'unit_code','M7.5',
    'work_code','PAULO-086',
    'q_class','Q1',
    'dimension','STRUCTURAL',
    'property','MATRIX_CELL_COMPLETENESS_AND_TRACEABILITY',
    'oracle','SQL_READBACK_M7_5_MATRIX_V1',
    'expected','282_OF_282_CELLS_RECONCILED',
    'evidence',jsonb_build_object(
      'family_authority','programacion.input_family_assessments',
      'case_authority','public.lf_test_suite_cases',
      'm7_0_taxonomy','INPUT_GOVERNANCE_REGRESSION.metadata.m7_0_q_taxonomy',
      'm7_3_catalog','91 executable contract traces'
    ),
    'matrix_version','M7_5_MATRIX_47X6_V1',
    'family_count',47,
    'test_type_count',6,
    'cell_count',282,
    'na_count',0,
    'na_policy','N/A_REQUIRES_REASON_AUTHORITY_EVIDENCE',
    'all_latest_families_applicable',true,
    'positive_strategy','ONE_PARAMETERIZED_GOVERNED_CASE_REUSED_BY_47_CELLS',
    'missing_strategy','REUSE_M7_3_NEG_001',
    'stale_strategy','REUSE_M7_3_NEG_007',
    'contradiction_strategy','REUSE_M7_3_NEG_002',
    'mutation_strategy','REUSE_M7_3_NEG_042',
    'negative_strategy','PRIMARY_M7_3_CASE_PER_FAMILY_PLUS_FULL_91_CASE_REUSE_CATALOG',
    'matrix_cells',m.cells,
    'negative_reuse_catalog',n.catalog,
    'negative_reuse_catalog_count',91,
    'parity_equals_correctness',false,
    'semantic_equals_readiness',false,
    'structural_equals_semantic',false,
    'no_parallel_suite',true,
    'no_parallel_taxonomy',true,
    'no_parallel_test_engine',true
  ),
  now(),now(),
  'CHATGPT-IG-CV-M7-5-20261004',
  'CHATGPT-IG-CV-M7-5-20261004'
FROM matrix_json m
CROSS JOIN negative_catalog n
CROSS JOIN next_order o;

UPDATE public.lf_test_suites
SET metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'm7_5_family_test_matrix',jsonb_build_object(
        'version','M7_5_MATRIX_47X6_V1',
        'unit_code','M7.5',
        'work_code','PAULO-086',
        'manifest_test_code','M7_5_MATRIX_47X6_MANIFEST',
        'families',47,
        'test_types',6,
        'cells',282,
        'na_count',0,
        'm7_3_negative_catalog_reused',91,
        'parallel_suite_created',false,
        'parallel_taxonomy_created',false,
        'parallel_test_engine_created',false,
        'parity_equals_correctness',false
      )
    ),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-5-20261004'
WHERE suite_code='INPUT_GOVERNANCE_REGRESSION';

DO $m7_5_orphan_probe_and_readback$
DECLARE
  v_cells jsonb;
  v_catalog jsonb;
  v_total integer;
  v_family_count integer;
  v_type_count integer;
  v_missing integer;
  v_orphan integer;
  v_incomplete integer;
  v_invalid_q integer;
  v_na_invalid integer;
  v_negative_cells integer;
  v_negative_not_m7_3 integer;
  v_catalog_count integer;
  v_catalog_distinct integer;
  v_probe_missing integer;
BEGIN
  SELECT metadata->'matrix_cells',metadata->'negative_reuse_catalog'
    INTO v_cells,v_catalog
  FROM public.lf_test_suite_cases
  WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
    AND test_code='M7_5_MATRIX_47X6_MANIFEST';

  IF v_cells IS NULL OR v_catalog IS NULL THEN
    RAISE EXCEPTION 'M7_5_MANIFEST_METADATA_MISSING';
  END IF;

  v_total := jsonb_array_length(v_cells);
  v_catalog_count := jsonb_array_length(v_catalog);

  SELECT count(DISTINCT e->>'family_code'),
         count(DISTINCT e->>'test_kind'),
         count(*) FILTER (
           WHERE nullif(e->>'q_class','') IS NULL
              OR nullif(e->>'dimension','') IS NULL
              OR nullif(e->>'property','') IS NULL
              OR nullif(e->>'oracle','') IS NULL
              OR nullif(e->>'expected','') IS NULL
              OR NOT (e ? 'evidence')
              OR e->'evidence' IS NULL
              OR e->'evidence'='null'::jsonb
         ),
         count(*) FILTER (
           WHERE e->>'q_class' NOT IN ('Q0','Q1','Q2','Q3','Q4','Q5','Q6','Q7','Q8')
         ),
         count(*) FILTER (
           WHERE e->>'resolution'='N/A'
             AND (
               nullif(e->>'na_reason','') IS NULL
               OR nullif(e->>'na_authority','') IS NULL
               OR NOT (e ? 'evidence')
               OR e->'evidence' IS NULL
             )
         ),
         count(*) FILTER (WHERE e->>'test_kind'='NEGATIVO')
    INTO v_family_count,v_type_count,v_incomplete,v_invalid_q,v_na_invalid,v_negative_cells
  FROM jsonb_array_elements(v_cells) e;

  WITH expected AS (
    SELECT f.family_code,t.test_kind
    FROM (SELECT DISTINCT family_code FROM programacion.input_family_assessments) f
    CROSS JOIN (VALUES
      ('POSITIVO'),('NEGATIVO'),('FALTANTE'),('STALE'),('CONTRADICCION'),('MUTACION')
    ) t(test_kind)
  ),
  actual AS (
    SELECT e->>'family_code' family_code,e->>'test_kind' test_kind
    FROM jsonb_array_elements(v_cells) e
  )
  SELECT count(*) INTO v_missing
  FROM expected x
  LEFT JOIN actual a USING(family_code,test_kind)
  WHERE a.family_code IS NULL;

  SELECT count(*) INTO v_orphan
  FROM jsonb_array_elements(v_cells) e
  LEFT JOIN public.lf_test_suite_cases c
    ON c.suite_code='INPUT_GOVERNANCE_REGRESSION'
   AND c.test_code=e->>'test_code'
  WHERE e->>'resolution'='TEST_CODE'
    AND c.test_code IS NULL;

  SELECT count(*) INTO v_negative_not_m7_3
  FROM jsonb_array_elements(v_cells) e
  JOIN public.lf_test_suite_cases c
    ON c.suite_code='INPUT_GOVERNANCE_REGRESSION'
   AND c.test_code=e->>'test_code'
  WHERE e->>'test_kind'='NEGATIVO'
    AND c.metadata->>'unit_code'<>'M7.3';

  SELECT count(DISTINCT e->>'test_code')
    INTO v_catalog_distinct
  FROM jsonb_array_elements(v_catalog) e;

  WITH expected AS (
    SELECT f.family_code,t.test_kind
    FROM (SELECT DISTINCT family_code FROM programacion.input_family_assessments) f
    CROSS JOIN (VALUES
      ('POSITIVO'),('NEGATIVO'),('FALTANTE'),('STALE'),('CONTRADICCION'),('MUTACION')
    ) t(test_kind)
  ),
  probe_actual AS (
    SELECT e->>'family_code' family_code,e->>'test_kind' test_kind
    FROM jsonb_array_elements(v_cells) e
    WHERE NOT (
      e->>'family_code'='ACCESSIBILITY'
      AND e->>'test_kind'='POSITIVO'
    )
  )
  SELECT count(*) INTO v_probe_missing
  FROM expected x
  LEFT JOIN probe_actual a USING(family_code,test_kind)
  WHERE a.family_code IS NULL;

  IF v_total<>282
     OR v_family_count<>47
     OR v_type_count<>6
     OR v_missing<>0
     OR v_orphan<>0
     OR v_incomplete<>0
     OR v_invalid_q<>0
     OR v_na_invalid<>0
     OR v_negative_cells<>47
     OR v_negative_not_m7_3<>0
     OR v_catalog_count<>91
     OR v_catalog_distinct<>91
     OR v_probe_missing<>1 THEN
    RAISE EXCEPTION
      'M7_5_READBACK_FAILED:cells=% families=% types=% missing=% orphan=% incomplete=% invalid_q=% invalid_na=% negative_cells=% negative_not_m7_3=% catalog=% catalog_distinct=% probe_missing=%',
      v_total,v_family_count,v_type_count,v_missing,v_orphan,v_incomplete,v_invalid_q,v_na_invalid,
      v_negative_cells,v_negative_not_m7_3,v_catalog_count,v_catalog_distinct,v_probe_missing;
  END IF;
END
$m7_5_orphan_probe_and_readback$;

UPDATE programacion.engineering_work_checkpoints
SET status='DONE',
    evidence_ref='db://public.lf_test_suite_cases/INPUT_GOVERNANCE_REGRESSION/M7_5_MATRIX_47X6_MANIFEST',
    completed_at=now(),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-5-20261004'
WHERE work_item_id=(SELECT id FROM programacion.engineering_work_items WHERE work_code='PAULO-086')
  AND checkpoint_code IN (
    'MATRIX_ASIS','MATRIX_282_CELLS','NA_EXPLICIT_AUTHORITY',
    'OMITTED_CELL_NEGATIVE','REUSE_M7_3_NEGATIVES','MATRIX_READBACK'
  );

UPDATE programacion.engineering_plan_units
SET unit_metadata=coalesce(unit_metadata,'{}'::jsonb) || jsonb_build_object(
      'm7_5_terminal',jsonb_build_object(
        'status','DONE',
        'matrix_version','M7_5_MATRIX_47X6_V1',
        'families',47,
        'test_types',6,
        'cells',282,
        'omitted_cells',0,
        'orphan_cells',0,
        'na_count',0,
        'm7_3_negative_catalog_reused',91,
        'new_semantic_cases',1,
        'manifest_cases',1,
        'parallel_suite_created',false,
        'parallel_taxonomy_created',false,
        'parallel_test_engine_created',false,
        'runtime_modified',false,
        'negative_probe','DETECTED_ONE_OMITTED_CELL',
        'manifest_test_code','M7_5_MATRIX_47X6_MANIFEST'
      )
    )
WHERE plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2'
  AND unit_code='M7.5';

UPDATE programacion.engineering_work_items
SET status='DONE',
    started_at=coalesce(started_at,now()),
    completed_at=now(),
    updated_at=now(),
    updated_by_execution_id='CHATGPT-IG-CV-M7-5-20261004'
WHERE work_code='PAULO-086';

INSERT INTO public.lf_error_knowledge (
  codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,
  root_cause_family,detectability,source_context,source_ref
)
SELECT
  'IG-M7-5-MATRIX-47X6-001',
  'INPUT_GOVERNANCE_TESTS',
  'Family test coverage matrix must reuse governed semantics instead of cloning cases',
  'M7.5 materializes the 47x6 governance matrix as 282 traceable cells in the existing INPUT_GOVERNANCE_REGRESSION suite. One parameterized positive case was added; missing, stale, contradiction, mutation and negative paths reuse M7.3 cases. The complete 91-case M7.3 catalog remains referenced and unchanged.',
  'The suite already contained governed negative semantics but had no explicit 47-family x 6-type coverage binding; creating one case per cell would duplicate semantics and create maintenance drift.',
  '47_FAMILIES_X_6_TYPES -> MATRIX_CELL -> EXISTING_GOVERNED_TEST_CODE_OR_EXPLICIT_NA',
  'For coverage matrices, bind cells to existing governed test codes first. Add a new case only for a missing semantic property. N/A is valid only with reason, authority and evidence.',
  'PASS when manifest readback is 282/282, 47 families, 6 types, 0 omissions, 0 orphan codes, 91/91 M7.3 catalog reused, and the simulated one-cell omission is detected.',
  'HIGH',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M7.5',
  '1585',
  'activo',
  'M7_5_MATRIX_47X6_MANIFEST; 282/282 cells; 0 omitted; 0 orphan; M7.3 catalog 91/91 reused; one-cell negative probe detected; no parallel suite/taxonomy/engine; no runtime modification.',
  'TEST_GOVERNANCE',
  ARRAY['CURATOR','VALIDATOR','ASSURANCE']::text[],
  'TEST_COVERAGE_MATRIX_TRACEABILITY',
  'DETERMINISTIC_SQL_READBACK',
  'M7.5 / PAULO-086 governed family test matrix',
  'github://cristhianlujan/claude-persona-lf-patch@main/supabase/migrations/20261004070200_ig_cv_m7_5_family_test_matrix_v1.sql'
WHERE NOT EXISTS (
  SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M7-5-MATRIX-47X6-001'
);

COMMIT;
