-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / T-PARITY / PAULO-030
-- Registry/current reconciliation only. No runtime deployment.
DO $x$
DECLARE v_exec text:='CHATGPT-IG-CV-T-PARITY-CURRENTNESS-20261003';
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code='MIGRATION_SOURCE_RECONCILIATION_V1'
      AND version='1.0.0' AND release_state='RELEASED'
      AND manifest_sha256='a35e2ece439071ee56168be17b404541a58b08465c7f9333f6de878588108f39'
  ) THEN RAISE EXCEPTION 'BLOCK_T_PARITY_RECONCILIATION_RELEASE_DRIFT'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='MIGRATION_SOURCE_RECONCILIATION_V1'
  ) THEN RAISE EXCEPTION 'BLOCK_T_PARITY_RECONCILIATION_CURRENT_ALREADY_EXISTS'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo='MIGRATION_SOURCE_PARITY' AND archived_at IS NULL
      AND metadata#>>'{entry_contract,enforcement_state}'='ENFORCED'
      AND coalesce((metadata#>>'{entry_contract,required}')::boolean,false)=true
      AND metadata#>>'{entry_contract,guard_code}'='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN RAISE EXCEPTION 'BLOCK_T_PARITY_ENTRY_CONTRACT_DRIFT'; END IF;

  INSERT INTO public.lf_capability_current(
    capability_code,version,manifest_sha256,previous_version,promoted_by_execution_id,promotion_reason
  ) VALUES (
    'MIGRATION_SOURCE_RECONCILIATION_V1','1.0.0',
    'a35e2ece439071ee56168be17b404541a58b08465c7f9333f6de878588108f39',
    null,v_exec,'T-PARITY projection of already RELEASED reconciliation capability; no runtime activation.'
  );

  UPDATE public.lf_capability_registry
  SET entry_guard_required=true,
      entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',
      updated_at=now(),updated_by_execution_id=v_exec
  WHERE capability_code='MIGRATION_SOURCE_PARITY';

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code='MIGRATION_SOURCE_RECONCILIATION_V1' AND version='1.0.0'
  ) THEN RAISE EXCEPTION 'T_PARITY_CURRENT_POSTCHECK_FAILED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code='MIGRATION_SOURCE_PARITY'
      AND entry_guard_required=true
      AND entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) THEN RAISE EXCEPTION 'T_PARITY_ENTRY_GUARD_POSTCHECK_FAILED'; END IF;
END $x$;
