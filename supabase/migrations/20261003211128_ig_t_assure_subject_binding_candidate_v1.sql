-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-ASSURE / PAULO-033
-- Checkpoint SUBJECT_BINDING candidate preparation.
-- Adds only a CANDIDATO exact binding for EJECUCION_INPUT_GOVERNANCE_LF.
-- It MUST NOT activate ASSURANCE_EVALUATOR, create a current pointer, execute
-- Assurance, or change runtime/production behavior. D-V2.3 remains required
-- for any future activation.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_assurance_claim_catalog
    WHERE claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND version=1
      AND subject_type='OPERATION'
      AND subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND status='CANDIDATO'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_PARENT_CLAIM_NOT_CANDIDATE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_test_suites
    WHERE suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND version='v1'
      AND status='CANDIDATO'
      AND execution_policy->>'semantic_pass_implied'='false'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_REGRESSION_SUITE_NOT_CANDIDATE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_registry
    WHERE capability_code='ASSURANCE_EVALUATOR'
      AND owner_scope='SUPER_ADMIN'
      AND status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_ASSURANCE_EVALUATOR_REGISTRY_NOT_ACTIVE';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='ASSURANCE_EVALUATOR'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_UNEXPECTED_ASSURANCE_EVALUATOR_CURRENT_POINTER';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_assurance_subject_bindings
    WHERE subject_type='OPERATION'
      AND subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_UNEXPECTED_ACTIVE_IG_BINDING';
  END IF;
END
$pre$;

INSERT INTO public.lf_assurance_subject_bindings(
  binding_code,subject_type,subject_code,standard_claim_code,standard_claim_version,
  benchmark_suite_code,activation_condition,required,status,source_ref,created_by_execution_id
)
VALUES (
  'BIND-INPUT-GOVERNANCE-CONTRACT-5_13-ASSURANCE-V1',
  'OPERATION',
  'EJECUCION_INPUT_GOVERNANCE_LF',
  'INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1',
  1,
  'INPUT_GOVERNANCE_REGRESSION',
  jsonb_build_object(
    'mode','CANDIDATE_ONLY_UNTIL_D_V2_3',
    'activation_decision','D-V2.3',
    'capability_code','ASSURANCE_EVALUATOR',
    'current_pointer_required',true,
    'exact_subject_required',true,
    'applicability_authority','CHANGESET_GOVERNANCE_LF_V1',
    'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
    'canonical_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
    'semantic_pass_implied',false,
    'no_parallel_engine',true
  ),
  true,
  'CANDIDATO',
  'supabase://public/lf_assurance_claim_catalog/INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1@1',
  'CHATGPT-IG-CV-T-ASSURE-SUBJECT-BINDING-20261003-001'
)
ON CONFLICT (binding_code) DO NOTHING;

DO $post$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_assurance_subject_bindings
    WHERE binding_code='BIND-INPUT-GOVERNANCE-CONTRACT-5_13-ASSURANCE-V1'
      AND subject_type='OPERATION'
      AND subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND standard_claim_code='INPUT_GOVERNANCE_CONTRACT_5_13_ASSURANCE_V1'
      AND standard_claim_version=1
      AND benchmark_suite_code='INPUT_GOVERNANCE_REGRESSION'
      AND required=true
      AND status='CANDIDATO'
      AND activation_condition->>'mode'='CANDIDATE_ONLY_UNTIL_D_V2_3'
      AND activation_condition->>'activation_decision'='D-V2.3'
      AND activation_condition->>'canonical_entrypoint'='public.fn_lf_capability_bind_from_orchestrator_v1'
      AND activation_condition->>'entry_guard_code'='ORCHESTRATOR_EXECUTION_GUARD_V1'
      AND activation_condition->>'semantic_pass_implied'='false'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_CANDIDATE_BINDING_CONFLICT';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_assurance_subject_bindings
    WHERE subject_type='OPERATION'
      AND subject_code='EJECUCION_INPUT_GOVERNANCE_LF'
      AND status='ACTIVE'
  ) THEN
    RAISE EXCEPTION 'T_ASSURE_IG_CANDIDATE_MUST_NOT_ACTIVATE';
  END IF;
END
$post$;
