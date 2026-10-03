-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-ASSURE / PAULO-033
-- Checkpoint IG_OBLIGATIONS.
-- Materializes the existing 60-row M1.A6 traceability matrix as candidate
-- ASSURANCE_EVALUATOR obligations. No capability activation, subject binding,
-- runtime mutation, production change, or ASSURANCE_COMPLETENESS usage.

DO $pre$
DECLARE
  v_matrix_id bigint;
  v_clause_count integer;
  v_distinct_count integer;
  v_contract_revision text;
  v_contract_md5 text;
  v_matrix_sha text;
  v_matrix_status text;
BEGIN
  SELECT id, clause_count, contract_revision, contract_spec_md5, matrix_sha256, status
    INTO v_matrix_id, v_clause_count, v_contract_revision, v_contract_md5, v_matrix_sha, v_matrix_status
  FROM programacion.contract_traceability_matrices
  WHERE matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
    AND matrix_revision=1
    AND contract_id=37;

  IF v_matrix_id IS NULL THEN
    RAISE EXCEPTION 'T_ASSURE_IG_TRACEABILITY_MATRIX_MISSING';
  END IF;
  IF v_clause_count<>60
     OR v_contract_revision<>'5.13'
     OR v_contract_md5<>'1d9709b94d20ee8036ad985edffaaf01'
     OR v_matrix_sha<>'9ccf8537bd96de7d30e05d5493711a1b99b7858fa573bf7541ebf456f12e30b4'
     OR v_matrix_status<>'DEFINED' THEN
    RAISE EXCEPTION 'T_ASSURE_IG_TRACEABILITY_MATRIX_DRIFT';
  END IF;

  SELECT count(*), count(distinct clause_key)
    INTO v_clause_count, v_distinct_count
  FROM programacion.contract_traceability_rows
  WHERE matrix_id=v_matrix_id;

  IF v_clause_count<>60 OR v_distinct_count<>60 THEN
    RAISE EXCEPTION 'T_ASSURE_IG_TRACEABILITY_ROWS_NOT_60:%:%',v_clause_count,v_distinct_count;
  END IF;
  IF EXISTS (
    SELECT 1
    FROM programacion.contract_traceability_rows
    WHERE matrix_id=v_matrix_id
      AND (row_status<>'DEFINED' OR clause_key IS NULL OR btrim(clause_key)='')
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_TRACEABILITY_ROW_INVALID';
  END IF;
END
$pre$;

INSERT INTO public.lf_assurance_claim_catalog(
  claim_code,version,parent_claim_code,parent_claim_version,
  subject_type,subject_code,claim_class,claim_text,criticality,
  applicability,closure_rule,methodology_version,status,source_ref,created_by_execution_id
)
VALUES (
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',1,NULL,NULL,
  'OPERATION','EJECUCION_INPUT_GOVERNANCE_LF','CLOSURE',
  'Input Governance contract 5.13 is materially assured only when all 60 traced clauses are individually evaluated with governed evidence and no required clause is silently omitted.',
  'CRITICAL',
  jsonb_build_object(
    'contract_id',37,
    'contract_revision','5.13',
    'traceability_matrix','INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@1',
    'mode','CANDIDATE_ONLY_UNTIL_D_V2_3',
    'assurance_capability','ASSURANCE_EVALUATOR',
    'assurance_completeness','RETIRED_NOT_USED'
  ),
  jsonb_build_object(
    'required_obligation_count',60,
    'all_required_obligations_must_be_resolved',true,
    'material_pass_forbidden_on_missing_obligation',true,
    'activation_requires','D-V2.3',
    'no_parallel_assurance_engine',true
  ),
  'LF_ASSURANCE_METHOD_V1','CANDIDATO',
  'supabase://programacion.contract_traceability_matrices/INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@1',
  'CHATGPT-IG-CV-T-ASSURE-OBLIGATIONS-20261003-001'
)
ON CONFLICT (claim_code,version) DO NOTHING;

DO $claim_guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_assurance_claim_catalog
    WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND version=1
      AND subject_type='OPERATION'
      AND subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND claim_class='CLOSURE'
      AND criticality='CRITICAL'
      AND methodology_version='LF_ASSURANCE_METHOD_V1'
      AND status='CANDIDATO'
      AND applicability->>'contract_revision'='5.13'
      AND applicability->>'mode'='CANDIDATE_ONLY_UNTIL_D_V2_3'
      AND applicability->>'assurance_capability'='ASSURANCE_EVALUATOR'
      AND applicability->>'assurance_completeness'='RETIRED_NOT_USED'
      AND (closure_rule->>'required_obligation_count')::integer=60
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_PARENT_CLAIM_CONFLICT';
  END IF;
END
$claim_guard$;

WITH matrix AS (
  SELECT m.id
  FROM programacion.contract_traceability_matrices m
  WHERE m.matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
    AND m.matrix_revision=1
    AND m.contract_id=37
), source_rows AS (
  SELECT r.*
  FROM programacion.contract_traceability_rows r
  JOIN matrix m ON m.id=r.matrix_id
)
INSERT INTO public.lf_assurance_obligation_catalog(
  obligation_code,version,claim_code,claim_version,
  requirement_ref,implementation_ref,condition_ref,verification_method,
  positive_test_ref,negative_test_ref,adversarial_test_ref,
  structural_coverage_mode,evidence_contract,failure_taxonomy_code,
  required,status,source_ref,created_by_execution_id
)
SELECT
  'IG-C5_13-' || upper(r.clause_key),
  1,
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',
  1,
  'supabase://programacion.contratos/37#5.13/' || r.clause_key,
  'supabase://programacion.contract_traceability_matrices/INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@1/' || r.clause_key,
  concat_ws('|',r.target_layer,r.target_owner,r.target_enforcement),
  CASE
    WHEN r.target_layer='SEMANTIC' THEN 'ANALYSIS'
    WHEN r.target_layer='EVIDENCE' THEN 'INSPECTION'
    ELSE 'TEST'
  END,
  NULL,
  NULL,
  NULL,
  'NONE',
  jsonb_build_object(
    'schema_version','IG_ASSURANCE_OBLIGATION_V1',
    'contract_id',37,
    'contract_revision','5.13',
    'clause_key',r.clause_key,
    'traceability_matrix','INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@1',
    'target_layer',r.target_layer,
    'target_owner',r.target_owner,
    'target_enforcement',r.target_enforcement,
    'current_enforcement_status',r.current_enforcement_status,
    'current_function_refs',to_jsonb(coalesce(r.current_function_refs,ARRAY[]::text[])),
    'current_trigger_refs',to_jsonb(coalesce(r.current_trigger_refs,ARRAY[]::text[])),
    'integrity_test_refs',to_jsonb(coalesce(r.integrity_test_refs,ARRAY[]::text[])),
    'semantic_test_status',r.semantic_test_status,
    'semantic_pass_requires_governed_evidence',true,
    'traceability_source','M1.A6'
  ),
  'TRACEABILITY_BROKEN',
  true,
  'CANDIDATO',
  'supabase://programacion.contract_traceability_matrices/INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@1#' || r.clause_key,
  'CHATGPT-IG-CV-T-ASSURE-OBLIGATIONS-20261003-001'
FROM source_rows r
ON CONFLICT (obligation_code,version) DO NOTHING;

DO $post$
DECLARE
  v_matrix_id bigint;
  v_obligations integer;
  v_clause_refs integer;
BEGIN
  SELECT id INTO v_matrix_id
  FROM programacion.contract_traceability_matrices
  WHERE matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
    AND matrix_revision=1
    AND contract_id=37;

  SELECT count(*),count(distinct evidence_contract->>'clause_key')
    INTO v_obligations,v_clause_refs
  FROM public.lf_assurance_obligation_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
    AND claim_version=1
    AND version=1;

  IF v_obligations<>60 OR v_clause_refs<>60 THEN
    RAISE EXCEPTION 'T_ASSURE_IG_OBLIGATION_COUNT_INVALID:%:%',v_obligations,v_clause_refs;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM programacion.contract_traceability_rows r
    WHERE r.matrix_id=v_matrix_id
      AND NOT EXISTS (
        SELECT 1
        FROM public.lf_assurance_obligation_catalog o
        WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
          AND o.claim_version=1
          AND o.version=1
          AND o.evidence_contract->>'clause_key'=r.clause_key
          AND o.required=true
          AND o.status='CANDIDATO'
      )
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_CLAUSE_WITHOUT_OBLIGATION';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_assurance_obligation_catalog o
    WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND o.claim_version=1
      AND o.version=1
      AND (
        o.required IS NOT TRUE
        OR o.status<>'CANDIDATO'
        OR o.evidence_contract->>'traceability_matrix'<>'INPUT_READINESS_CONTRACT_5_13_TRACEABILITY@1'
      )
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_OBLIGATION_SHAPE_INVALID';
  END IF;
END
$post$;