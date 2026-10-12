-- S30_MIGRATION_SOURCE_FIRST_PREWRITE_GUARD_V1
-- Owner: S30 migration lifecycle.
-- Purpose: prevent DB-first migration application from creating remote-only drift.
-- Scope: governance metadata only. No business/runtime/Golden activation.

DO $pre$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code = 'ACTUALIZACION_DB_LF'
  ) THEN
    RAISE EXCEPTION 'S30_MIGRATION_GUARD_OPERATION_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_contracts
    WHERE operation_code = 'ACTUALIZACION_DB_LF'
      AND contract_code = 'CONTRACT-ACTUALIZACION-DB-LF-v0.1'
      AND status = 'ACTIVE_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'S30_MIGRATION_GUARD_BASE_CONTRACT_NOT_ACTIVE';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_router_action_registry
    WHERE asset_type = 'MIGRATION'
      AND action_code = 'UPDATE'
      AND operation_code = 'ACTUALIZACION_DB_LF'
      AND status = 'ACTIVE'
      AND write_allowed IS TRUE
  ) THEN
    RAISE EXCEPTION 'S30_MIGRATION_GUARD_ROUTER_BINDING_INVALID';
  END IF;
END
$pre$;

UPDATE public.lf_operation_contracts
SET status = 'SUPERSEDED',
    updated_at = now()
WHERE operation_code = 'ACTUALIZACION_DB_LF'
  AND contract_code = 'CONTRACT-ACTUALIZACION-DB-LF-v0.1'
  AND status = 'ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_operation_contracts(
  operation_code,
  contract_code,
  contract_path,
  contract_sha,
  required_before_write,
  allowed,
  blocked,
  required_after_write,
  status,
  created_by_execution_id,
  updated_by_execution_id
) VALUES (
  'ACTUALIZACION_DB_LF',
  'CONTRACT-ACTUALIZACION-DB-LF-v0.2',
  'supabase://public/lf_operation_contracts/ACTUALIZACION_DB_LF/v0.2',
  NULL,
  '["router_read","ekb_read","schema_source_read","exact_target_bound","rollback_or_fail_forward_plan","migration_parity_precheck_if_applicable","migration_canonical_main_sha_if_target_migration","migration_canonical_source_path_if_target_migration","migration_canonical_source_sha256_if_target_migration","migration_source_merged_to_main_if_target_migration","migration_remote_only_zero_if_target_migration","migration_exact_version_name_if_target_migration"]'::jsonb,
  '{"sandbox_only_non_migration_repairs":true,"minimal_reversible_patch":true,"migration_reconciliation":true,"migration_source_first_only":true,"migration_exact_version_transport_only":true,"migration_apply_only_after_main_merge":true,"function_trigger_repair":true,"schema_or_contract_repair":true,"manual_hash_patch":false,"bypass_allowed":false}'::jsonb,
  '["direct_hash_patch","parity_bypass","unscoped_ddl","write_without_exact_target","write_without_readback","migration_db_first_apply","migration_source_pending_github_branch","migration_source_not_on_main","migration_remote_only_present","migration_version_name_mismatch","migration_source_hash_mismatch","migration_generated_version_transport"]'::jsonb,
  '["exact_target_readback","regression_or_parity_retest","no_unscoped_changes","ekb_closeout","migration_exact_ledger_readback_if_target_migration","migration_full_source_parity_if_target_migration","migration_remote_only_zero_after_write_if_target_migration"]'::jsonb,
  'ACTIVE_ENFORCEMENT',
  'EXEC-S30-MIGRATION-SOURCE-PARITY-20260914-001',
  'EXEC-S30-MIGRATION-SOURCE-PARITY-20260914-001'
)
ON CONFLICT (operation_code, contract_code) DO UPDATE SET
  contract_path = EXCLUDED.contract_path,
  contract_sha = EXCLUDED.contract_sha,
  required_before_write = EXCLUDED.required_before_write,
  allowed = EXCLUDED.allowed,
  blocked = EXCLUDED.blocked,
  required_after_write = EXCLUDED.required_after_write,
  status = EXCLUDED.status,
  updated_by_execution_id = EXCLUDED.updated_by_execution_id,
  updated_at = now();

UPDATE public.lf_operation_registry
SET version = 'v0.2',
    notes = 'Ruta gobernada para DB/FUNCTION/TRIGGER y MIGRATION. Para target MIGRATION es obligatorio source-first: fuente exacta ya fusionada en main, path/SHA/version/name ligados, remote_only=0 antes del write, transporte de version exacta y readback de paridad completo. DB-first y PENDING_GITHUB_BRANCH quedan bloqueados.',
    updated_by_execution_id = 'EXEC-S30-MIGRATION-SOURCE-PARITY-20260914-001',
    updated_at = now()
WHERE operation_code = 'ACTUALIZACION_DB_LF';

UPDATE public.lf_operation_steps
SET evidence_required = CASE step_id
      WHEN 'preflight' THEN 'router_binding; ekb_refs; schema_source_readback; exact_target; rollback_or_fail_forward_plan; migration_main_source_attestation_if_applicable; migration_ledger_precheck_if_applicable'
      WHEN 'patch' THEN 'minimal_diff; write_receipt; target_binding; exact_version_transport_if_migration'
      WHEN 'verify' THEN 'readback; regression_or_parity; ekb_closeout; migration_full_source_parity_if_applicable'
      ELSE evidence_required
    END,
    updated_by_execution_id = 'EXEC-S30-MIGRATION-SOURCE-PARITY-20260914-001',
    updated_at = now()
WHERE operation_code = 'ACTUALIZACION_DB_LF'
  AND step_id IN ('preflight','patch','verify');

UPDATE public.lf_operation_step_contracts
SET contract_code = 'CONTRACT-ACTUALIZACION-DB-LF-v0.2',
    purpose = CASE step_id
      WHEN 'preflight' THEN 'Validar Router, EKB, schema/source, target exacto y rollback/fail-forward. Para MIGRATION, probar fuente exacta ya fusionada en main y remote_only=0 antes de cualquier write.'
      WHEN 'patch' THEN 'Aplicar únicamente el delta mínimo al target exacto. Para MIGRATION, ejecutar solo la fuente canónica de main con versión/nombre exactos; DB-first o timestamp regenerado están bloqueados.'
      WHEN 'verify' THEN 'Verificar readback exacto, regresión/paridad y cierre EKB. Para MIGRATION, exigir ledger exacto y full source parity sin local_only/remote_only.'
      ELSE purpose
    END,
    input_required = CASE step_id
      WHEN 'preflight' THEN '["router_binding","ekb_refs","schema_source","exact_target","rollback_or_fail_forward_plan","migration_main_source_attestation_if_applicable","migration_ledger_precheck_if_applicable"]'::jsonb
      WHEN 'patch' THEN '["minimal_diff","exact_target","rollback_or_fail_forward_plan","exact_version_transport_if_migration"]'::jsonb
      WHEN 'verify' THEN '["readback","regression_or_parity","ekb_closeout","migration_full_source_parity_if_applicable"]'::jsonb
      ELSE input_required
    END,
    pass_condition = CASE step_id
      WHEN 'preflight' THEN '{"preflight_pass":true,"migration_source_first_if_applicable":true,"migration_remote_only_zero_if_applicable":true}'::jsonb
      WHEN 'patch' THEN '{"minimal_patch":true,"migration_exact_version_transport_if_applicable":true}'::jsonb
      WHEN 'verify' THEN '{"verified":true,"migration_full_source_parity_if_applicable":true}'::jsonb
      ELSE pass_condition
    END,
    block_condition = CASE step_id
      WHEN 'preflight' THEN '{"preflight_pass":false,"migration_source_not_on_main_if_applicable":true,"migration_remote_only_if_applicable":true}'::jsonb
      WHEN 'patch' THEN '{"unscoped_or_irreversible":true,"migration_db_first_or_generated_version_if_applicable":true}'::jsonb
      WHEN 'verify' THEN '{"verified":false,"migration_source_parity_failed_if_applicable":true}'::jsonb
      ELSE block_condition
    END,
    blocking_code = CASE step_id
      WHEN 'preflight' THEN 'BLOCK_DB_MIGRATION_SOURCE_FIRST_PREFLIGHT'
      WHEN 'patch' THEN 'BLOCK_DB_MIGRATION_PATCH_SCOPE'
      WHEN 'verify' THEN 'BLOCK_DB_MIGRATION_VERIFY_FAILED'
      ELSE blocking_code
    END,
    required_evidence_keys = CASE step_id
      WHEN 'preflight' THEN '["router_binding","ekb_refs","schema_source_readback","exact_target","rollback_or_fail_forward_plan","migration_main_source_attestation_if_applicable","migration_ledger_precheck_if_applicable"]'::jsonb
      WHEN 'patch' THEN '["minimal_diff","write_receipt","target_binding","exact_version_transport_if_migration"]'::jsonb
      WHEN 'verify' THEN '["readback","regression_or_parity","ekb_closeout","migration_full_source_parity_if_applicable"]'::jsonb
      ELSE required_evidence_keys
    END,
    notes = CASE step_id
      WHEN 'preflight' THEN 'Fail closed. MIGRATION no puede entrar con source_parity_state=PENDING_GITHUB_BRANCH ni con remote_only>0.'
      WHEN 'patch' THEN 'No parity bypass, no direct hash patch, no DB-first migration apply, no regenerated migration version.'
      WHEN 'verify' THEN 'PASS solo con readback exacto; MIGRATION requiere full source parity reproducible.'
      ELSE notes
    END,
    updated_by_execution_id = 'EXEC-S30-MIGRATION-SOURCE-PARITY-20260914-001',
    updated_at = now()
WHERE operation_code = 'ACTUALIZACION_DB_LF'
  AND step_id IN ('preflight','patch','verify');

UPDATE public.lf_router_action_registry
SET notes = 'Canonical DB mutation route. MIGRATION/UPDATE is source-first only: exact source must already exist on main with bound path/SHA/version/name, remote_only must be zero before write, exact-version transport is mandatory, and parity readback is required. DB-first is blocked.',
    updated_by_execution_id = 'EXEC-S30-MIGRATION-SOURCE-PARITY-20260914-001',
    updated_at = now()
WHERE asset_type = 'MIGRATION'
  AND action_code = 'UPDATE'
  AND operation_code = 'ACTUALIZACION_DB_LF';

DO $post$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_registry
    WHERE operation_code = 'ACTUALIZACION_DB_LF'
      AND version = 'v0.2'
  ) THEN
    RAISE EXCEPTION 'S30_MIGRATION_GUARD_OPERATION_VERSION_READBACK_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.lf_operation_contracts
    WHERE operation_code = 'ACTUALIZACION_DB_LF'
      AND contract_code = 'CONTRACT-ACTUALIZACION-DB-LF-v0.2'
      AND status = 'ACTIVE_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'S30_MIGRATION_GUARD_CONTRACT_READBACK_FAILED';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lf_operation_contracts
    WHERE operation_code = 'ACTUALIZACION_DB_LF'
      AND contract_code = 'CONTRACT-ACTUALIZACION-DB-LF-v0.1'
      AND status = 'ACTIVE_ENFORCEMENT'
  ) THEN
    RAISE EXCEPTION 'S30_MIGRATION_GUARD_OLD_CONTRACT_STILL_ACTIVE';
  END IF;
END
$post$;
