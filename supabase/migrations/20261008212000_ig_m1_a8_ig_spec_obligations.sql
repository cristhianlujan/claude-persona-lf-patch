-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M1.A8 / IG_SPEC_OBLIGATIONS
-- Canonical append-only reconciliation of the EXACT 60 INPUT_READINESS 5.13
-- clause obligations. Reuse V2 (from T-ASSURE) as immutable authority;
-- V3 only records classification evidence, it is NOT a fresh obligation universe.
-- This is not readiness/semantic certification, capability activation or PASE.
DO $ig_m1_a8$
DECLARE
  v_v2_count integer;
  v_v3_count integer;
  v_locator_count integer;
  v_missing_count integer;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE evidence_contract->>'current_enforcement_status'
             ='CURRENT_LOCATOR_OBSERVED_NOT_SEMANTIC_PROOF'),
         count(*) FILTER (WHERE evidence_contract->>'current_enforcement_status'
             ='NO_DIRECT_LOCATOR_OBSERVED')
    INTO v_v2_count,v_locator_count,v_missing_count
  FROM public.lf_assurance_obligation_catalog
  WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
    AND claim_version=2 AND version=2 AND status='CANDIDATO'
    AND evidence_contract->>'contract_revision'='5.13'
    AND evidence_contract->>'semantic_test_status'='PENDING_CLAUSE_SEMANTIC_TEST'
    AND nullif(evidence_contract->>'clause_key','') IS NOT NULL;

  IF v_v2_count<>60 OR v_locator_count+v_missing_count<>60
     OR v_locator_count<>18 OR v_missing_count<>42 THEN
    RAISE EXCEPTION
      'IG_M1_A8_CANONICAL_OBLIGATION_BASELINE_DRIFT:total=%:located=%:missing=%',
      v_v2_count,v_locator_count,v_missing_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.contract_traceability_matrices m
    WHERE m.matrix_code='INPUT_READINESS_CONTRACT_5_13_TRACEABILITY'
      AND m.matrix_revision=1 AND m.contract_revision='5.13'
      AND m.clause_count=60
  ) THEN
    RAISE EXCEPTION 'IG_M1_A8_EXACT_5_13_TRACEABILITY_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_assurance_obligation_catalog o
    WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND o.version=3
  ) THEN
    RAISE EXCEPTION 'IG_M1_A8_V3_ALREADY_PRESENT_RECONCILE_INSTEAD_OF_REPLAY';
  END IF;

  -- The subject already has a governed version-2 binding. Never create
  -- a second binding or extend it to a wildcard.
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_assurance_subject_bindings b
    WHERE b.subject_type='OPERATION'
      AND b.subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND b.standard_claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND b.standard_claim_version=2
      AND b.status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'IG_M1_A8_EXISTING_EXACT_SUBJECT_BINDING_NOT_ACTIVE';
  END IF;

  INSERT INTO public.lf_assurance_obligation_catalog (
    obligation_code,version,claim_code,claim_version,requirement_ref,
    implementation_ref,condition_ref,verification_method,positive_test_ref,
    negative_test_ref,adversarial_test_ref,structural_coverage_mode,
    evidence_contract,failure_taxonomy_code,required,status,
    source_ref,created_by_execution_id
  )
  SELECT
    o.obligation_code,
    3,
    o.claim_code,
    o.claim_version,
    o.requirement_ref,
    o.implementation_ref,
    o.condition_ref,
    o.verification_method,
    o.positive_test_ref,
    o.negative_test_ref,
    o.adversarial_test_ref,
    o.structural_coverage_mode,
    o.evidence_contract || jsonb_build_object(
      'spec_traversal',jsonb_build_object(
        'schema_version','IG_SPEC_TRAVERSAL_OBLIGATION_V1',
        'run_scope','EXACT_INPUT_READINESS_CONTRACT_5_13',
        'source_obligation_version',2,
        'classification','BLOCKED',
        'reason',CASE
          WHEN o.evidence_contract->>'current_enforcement_status'
                 ='CURRENT_LOCATOR_OBSERVED_NOT_SEMANTIC_PROOF'
            THEN 'LOCATOR_PRESENT_SEMANTIC_TEST_NOT_PROVEN'
          ELSE 'CANONICAL_ENFORCEMENT_LOCATOR_NOT_OBSERVED'
        END,
        'independent_semantic_receipt_verified',false,
        'eligible_for_applied',false,
        'not_applicable_positive_authority_verified',false,
        'requires_evidence_before_requalification',true,
        'no_parallel_assurance_engine',true
      )
    ),
    o.failure_taxonomy_code,
    o.required,
    'CANDIDATO',
    o.source_ref || '#ig-m1-a8-spec-traversal-v3',
    'CHATGPT-IG-M1A8-SPEC-OBLIGATIONS-20261008'
  FROM public.lf_assurance_obligation_catalog o
  WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
    AND o.version=2 AND o.claim_version=2
  ORDER BY o.obligation_code;

  SELECT count(*) INTO v_v3_count
  FROM public.lf_assurance_obligation_catalog o
  WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
    AND o.version=3;
  IF v_v3_count<>60 THEN
    RAISE EXCEPTION 'IG_M1_A8_SPEC_TRAVERSAL_CARDINALITY_MISMATCH:%',v_v3_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_assurance_obligation_catalog o
    WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND o.version=3
      AND (o.status<>'CANDIDATO'
        OR o.evidence_contract#>>'{spec_traversal,classification}'<>'BLOCKED'
        OR coalesce((o.evidence_contract#>>'{spec_traversal,independent_semantic_receipt_verified}')::boolean,true)
        OR coalesce((o.evidence_contract#>>'{spec_traversal,not_applicable_positive_authority_verified}')::boolean,true)
      )
  ) THEN
    RAISE EXCEPTION 'IG_M1_A8_UNGROUNDED_CLAUSE_VERDICT';
  END IF;

  -- The original two generations remain immutable and discoverable.
  IF (SELECT count(*) FROM public.lf_assurance_obligation_catalog o
      WHERE o.claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
        AND o.version IN (1,2))<>120 THEN
    RAISE EXCEPTION 'IG_M1_A8_HISTORICAL_OBLIGATION_DRIFT';
  END IF;
END
$ig_m1_a8$;

-- Readback query (no assertion of semantic or production readiness):
-- SELECT version, count(*) n,
--        count(*) FILTER(WHERE evidence_contract#>>'{spec_traversal,classification}'='BLOCKED') blocked
-- FROM public.lf_assurance_obligation_catalog
-- WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
-- GROUP BY version ORDER BY version;
