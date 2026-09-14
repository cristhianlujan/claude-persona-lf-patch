-- S31 CURRENTNESS_AUTHORITY consumer cutover v1
-- Formalizes material-aware currentness semantics for Git Broker and Strategy Qualification.
-- No broker protected-path mutation, no qualification receipt mutation, no runtime/production/Golden activation.

DO $cutover$
DECLARE
  v_max_migration text;
  v_q_receipts_before bigint;
  v_q_receipts_after bigint;
  v_bindings_before text;
  v_bindings_after text;
  v_qual_def text;
  v_suite_fp_def text;
BEGIN
  SELECT max(version) INTO v_max_migration
  FROM supabase_migrations.schema_migrations;
  IF v_max_migration IS DISTINCT FROM '20260914170500' THEN
    RAISE EXCEPTION 'S31_CURRENTNESS_CUTOVER_LEDGER_DRIFT:%', v_max_migration;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_execution
    WHERE execution_id='EXEC-S31-CURRENTNESS-CONSUMER-CUTOVER-20260914-001'
      AND operation_code='ACTUALIZACION_DB_LF'
      AND target_type='MIGRATION'
      AND target_code='S31_CURRENTNESS_CONSUMER_CUTOVER_V1'
      AND target_repo='cristhianlujan/claude-persona-lf-patch'
      AND target_path='supabase/migrations/20260914183000_lf_s31_currentness_consumer_cutover_v1.sql'
      AND status='IN_PROGRESS'
  ) THEN
    RAISE EXCEPTION 'BLOCK_S31_CURRENTNESS_CUTOVER_EXECUTION_BINDING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_capability_current c
    JOIN public.lf_capability_version_registry v
      ON v.capability_code=c.capability_code
     AND v.version=c.version
     AND v.manifest_sha256=c.manifest_sha256
    WHERE c.capability_code='CURRENTNESS_AUTHORITY'
      AND c.version='1.0.0'
      AND c.manifest_sha256='9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'
      AND v.release_state='RELEASED'
  ) THEN
    RAISE EXCEPTION 'BLOCK_S31_CURRENTNESS_AUTHORITY_NOT_CURRENT';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM private.lf_evidence_ledger_v1
    WHERE receipt_id='7b7566c7-4495-499d-bebf-311e52890517'::uuid
      AND capability_code='CURRENTNESS_AUTHORITY'
      AND gate_code='CURRENTNESS_AUTHORITY_SOURCE_ATTESTATION'
      AND verification_state='VERIFIED'
      AND subject_sha256='db91be1d99bef57cbdc2a7d5c27690ee3eef93efa0f5c96443f5beed8a67cf35'
  ) THEN
    RAISE EXCEPTION 'BLOCK_S31_CURRENTNESS_DURABLE_EVIDENCE_MISSING';
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_contracts
      WHERE operation_code='GITHUB_CONTRACT_GATE_LF'
        AND status='ACTIVE_ENFORCEMENT') <> 1 THEN
    RAISE EXCEPTION 'BLOCK_S31_GITHUB_GATE_ACTIVE_CONTRACT_CARDINALITY';
  END IF;

  IF (SELECT count(*) FROM public.lf_operation_contracts
      WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
        AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
        AND status='ACTIVE_ENFORCEMENT') <> 1 THEN
    RAISE EXCEPTION 'BLOCK_S31_STRATEGY_EXEC_ACTIVE_CONTRACT_CARDINALITY';
  END IF;

  IF to_regprocedure('public.lf_qualification_current_v1(text,text,text)') IS NULL
     OR to_regprocedure('public.lf_required_test_suite_fingerprint_v1(text,text)') IS NULL
     OR to_regprocedure('public.lf_strategy_revision_sha256_v1(bigint)') IS NULL
     OR to_regprocedure('public.lf_operation_revision_sha256_v1(text)') IS NULL
     OR to_regprocedure('public.lf_test_suite_revision_sha256_v1(text)') IS NULL THEN
    RAISE EXCEPTION 'BLOCK_S31_QUALIFICATION_MATERIAL_CURRENTNESS_FUNCTION_MISSING';
  END IF;

  LOCK TABLE public.lf_qualification_receipts IN SHARE MODE;
  LOCK TABLE public.lf_test_requirement_bindings IN SHARE MODE;

  SELECT count(*) INTO v_q_receipts_before
  FROM public.lf_qualification_receipts;

  SELECT encode(extensions.digest(convert_to(coalesce(
      jsonb_agg(jsonb_build_array(
        binding_code,subject_type,subject_code,suite_code,currentness_mode,required,status,effective_from
      ) ORDER BY binding_code)::text,'[]'
    ),'UTF8'),'sha256'),'hex')
  INTO v_bindings_before
  FROM public.lf_test_requirement_bindings;

  UPDATE public.lf_operation_contracts
  SET
    allowed = allowed || jsonb_build_object(
      'currentness_authority_capability','CURRENTNESS_AUTHORITY',
      'currentness_authority_version','1.0.0',
      'currentness_policy_scope','MATERIAL_DEPENDENCY_AWARE',
      'broker_currentness_preflight_required',true,
      'legacy_exact_main_sha_guard_role','ATOMIC_DISPATCH_GUARD_ONLY',
      'current_rebound_requires_effective_base_equals_resolved_main',true,
      'current_rebound_requires_source_descendant_of_effective_base',true,
      'current_rebound_requires_receipt_rehydration',true,
      'currentness_decisions',jsonb_build_array('CURRENT','CURRENT_REBOUND','STALE_AFFECTED','UNKNOWN_FAIL_CLOSED')
    ),
    required_before_write = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          required_before_write || jsonb_build_array(
            'currentness_authority_read',
            'durable_currentness_receipt_readback',
            'source_descendant_of_effective_base',
            'prewrite_receipt_effective_base_binding'
          )
        )
      ) s
    ),
    blocked = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          blocked || jsonb_build_array(
            'broker_dispatch_without_currentness_authority',
            'broker_dispatch_on_stale_affected',
            'broker_dispatch_on_unknown_currentness',
            'current_rebound_without_effective_base_binding'
          )
        )
      ) s
    ),
    updated_by_execution_id='EXEC-S31-CURRENTNESS-CONSUMER-CUTOVER-20260914-001'
  WHERE operation_code='GITHUB_CONTRACT_GATE_LF'
    AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_contracts
  SET
    allowed = allowed || jsonb_build_object(
      'strategy_qualification_scope','SUBJECT_MATERIAL_REVISION_AND_REQUIRED_SUITE_SET',
      'global_main_sha_part_of_strategy_qualification',false,
      'currentness_authority_capability','CURRENTNESS_AUTHORITY',
      'currentness_authority_version','1.0.0',
      'qualification_cutover_mode','NO_MASS_INVALIDATION'
    ),
    required_before_write = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          required_before_write || jsonb_build_array(
            'CURRENT_STRATEGY_QUALIFICATION_BY_MATERIAL_REVISION'
          )
        )
      ) s
    ),
    blocked = (
      SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v),'[]'::jsonb)
      FROM (
        SELECT DISTINCT value AS v
        FROM jsonb_array_elements_text(
          blocked || jsonb_build_array(
            'GLOBAL_MAIN_SHA_AS_STRATEGY_QUALIFICATION_REVISION',
            'MASS_QUALIFICATION_INVALIDATION_FOR_UNRELATED_REPO_DRIFT'
          )
        )
      ) s
    ),
    updated_by_execution_id='EXEC-S31-CURRENTNESS-CONSUMER-CUTOVER-20260914-001'
  WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
    AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
    AND status='ACTIVE_ENFORCEMENT';

  UPDATE public.lf_operation_contracts
  SET
    contract_sha=encode(extensions.digest(convert_to(jsonb_build_object(
      'operation_code',operation_code,
      'contract_code',contract_code,
      'contract_path',contract_path,
      'required_before_write',required_before_write,
      'allowed',allowed,
      'blocked',blocked,
      'required_after_write',required_after_write
    )::text,'UTF8'),'sha256'),'hex'),
    updated_by_execution_id='EXEC-S31-CURRENTNESS-CONSUMER-CUTOVER-20260914-001'
  WHERE status='ACTIVE_ENFORCEMENT'
    AND (
      operation_code='GITHUB_CONTRACT_GATE_LF'
      OR (operation_code='EJECUCION_ESTRATEGIA_LF' AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1')
    );

  SELECT pg_get_functiondef(to_regprocedure('public.lf_qualification_current_v1(text,text,text)'))
    INTO v_qual_def;
  SELECT pg_get_functiondef(to_regprocedure('public.lf_required_test_suite_fingerprint_v1(text,text)'))
    INTO v_suite_fp_def;

  IF v_qual_def NOT ILIKE '%revision_sha256%'
     OR v_qual_def NOT ILIKE '%lf_required_test_suite_fingerprint_v1%'
     OR v_qual_def ILIKE '%refs/heads/main%'
     OR v_qual_def ILIKE '%head_sha%' THEN
    RAISE EXCEPTION 'BLOCK_S31_QUALIFICATION_CURRENTNESS_NOT_MATERIAL_SCOPED';
  END IF;

  IF v_suite_fp_def NOT ILIKE '%lf_test_suite_revision_sha256_v1%' THEN
    RAISE EXCEPTION 'BLOCK_S31_QUALIFICATION_SUITE_FINGERPRINT_NOT_REVISION_BOUND';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='GITHUB_CONTRACT_GATE_LF'
      AND status='ACTIVE_ENFORCEMENT'
      AND allowed->>'currentness_authority_capability'='CURRENTNESS_AUTHORITY'
      AND allowed->>'currentness_authority_version'='1.0.0'
      AND allowed->>'currentness_policy_scope'='MATERIAL_DEPENDENCY_AWARE'
      AND allowed->>'legacy_exact_main_sha_guard_role'='ATOMIC_DISPATCH_GUARD_ONLY'
      AND allowed->>'broker_currentness_preflight_required'='true'
      AND allowed->>'current_rebound_requires_source_descendant_of_effective_base'='true'
      AND allowed->>'current_rebound_requires_receipt_rehydration'='true'
      AND contract_sha ~ '^[0-9a-f]{64}$'
  ) THEN
    RAISE EXCEPTION 'BLOCK_S31_GITHUB_GATE_CUTOVER_READBACK';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_operation_contracts
    WHERE operation_code='EJECUCION_ESTRATEGIA_LF'
      AND contract_code='CONTRACT-EJECUCION-ESTRATEGIA-LF-v1'
      AND status='ACTIVE_ENFORCEMENT'
      AND allowed->>'strategy_qualification_currentness'='EXACT_REVISION'
      AND allowed->>'strategy_qualification_scope'='SUBJECT_MATERIAL_REVISION_AND_REQUIRED_SUITE_SET'
      AND allowed->>'global_main_sha_part_of_strategy_qualification'='false'
      AND allowed->>'qualification_cutover_mode'='NO_MASS_INVALIDATION'
      AND allowed->>'currentness_authority_capability'='CURRENTNESS_AUTHORITY'
      AND contract_sha ~ '^[0-9a-f]{64}$'
  ) THEN
    RAISE EXCEPTION 'BLOCK_S31_STRATEGY_QUALIFICATION_CUTOVER_READBACK';
  END IF;

  SELECT count(*) INTO v_q_receipts_after
  FROM public.lf_qualification_receipts;
  IF v_q_receipts_after IS DISTINCT FROM v_q_receipts_before THEN
    RAISE EXCEPTION 'BLOCK_S31_QUALIFICATION_RECEIPTS_MUTATED:before=% after=%',
      v_q_receipts_before,v_q_receipts_after;
  END IF;

  SELECT encode(extensions.digest(convert_to(coalesce(
      jsonb_agg(jsonb_build_array(
        binding_code,subject_type,subject_code,suite_code,currentness_mode,required,status,effective_from
      ) ORDER BY binding_code)::text,'[]'
    ),'UTF8'),'sha256'),'hex')
  INTO v_bindings_after
  FROM public.lf_test_requirement_bindings;

  IF v_bindings_after IS DISTINCT FROM v_bindings_before THEN
    RAISE EXCEPTION 'BLOCK_S31_QUALIFICATION_BINDINGS_MUTATED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='CURRENTNESS_AUTHORITY'
      AND version='1.0.0'
      AND manifest_sha256='9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09'
  ) THEN
    RAISE EXCEPTION 'BLOCK_S31_CURRENTNESS_POINTER_CHANGED_DURING_CUTOVER';
  END IF;
END
$cutover$;
