-- PASE F04 Q02 — PACK_VALIDATION_HARNESS owner/relationship normalization.
-- Data-only governance projection. No current-pointer, guard, runtime, policy, or harness change.
DO $$
DECLARE
  v_execution_id constant text := 'PASE-F04-Q02-PACK-OWNER-REHOME-V1';
  v_batch_id uuid := gen_random_uuid();
  v_old_registry_owner text;
  v_old_asset_owner text;
BEGIN
  SELECT owner_scope INTO v_old_registry_owner
  FROM public.lf_capability_registry
  WHERE capability_code = 'PACK_VALIDATION_HARNESS'
  FOR UPDATE;

  IF v_old_registry_owner IS NULL THEN
    RAISE EXCEPTION 'PACK_VALIDATION_HARNESS_REGISTRY_MISSING';
  END IF;

  SELECT owner_name INTO v_old_asset_owner
  FROM public.lf_activos
  WHERE codigo_activo = 'PACK_VALIDATION_HARNESS'
    AND archived_at IS NULL
  FOR UPDATE;

  IF v_old_asset_owner IS NULL THEN
    RAISE EXCEPTION 'PACK_VALIDATION_HARNESS_ASSET_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo = 'LF_GOVERNANCE' AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'LF_GOVERNANCE_AUTHORITY_MISSING';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activos
    WHERE codigo_activo = 'OWNER_RUNNER_CARRIER_AUTHORITY' AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'OWNER_RUNNER_CARRIER_AUTHORITY_MISSING';
  END IF;

  UPDATE public.lf_capability_registry
  SET owner_scope = 'LF_GOVERNANCE',
      updated_at = now(),
      updated_by_execution_id = v_execution_id
  WHERE capability_code = 'PACK_VALIDATION_HARNESS';

  UPDATE public.lf_activos
  SET owner_name = 'LF_GOVERNANCE',
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'legacy_owner_name', coalesce(metadata->>'legacy_owner_name', v_old_asset_owner),
        'owner_authority_code', 'LF_GOVERNANCE',
        'owner_runner_carrier_authority', 'OWNER_RUNNER_CARRIER_AUTHORITY',
        'owner_rehome_execution_id', v_execution_id
      ),
      updated_at = now(),
      updated_by_execution_id = v_execution_id
  WHERE codigo_activo = 'PACK_VALIDATION_HARNESS'
    AND archived_at IS NULL;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo = 'PACK_VALIDATION_HARNESS'
      AND relacionado_codigo = 'LF_GOVERNANCE'
      AND relacion_tipo = 'RELACIONADO_CAPACIDADES'
  ) THEN
    INSERT INTO public.lf_activo_relaciones(
      codigo_activo, relacionado_codigo, relacion_tipo, valor_original,
      fuente, migration_batch_id, created_by_execution_id
    ) VALUES (
      'PACK_VALIDATION_HARNESS', 'LF_GOVERNANCE', 'RELACIONADO_CAPACIDADES',
      v_old_registry_owner,
      'supabase/migrations/20261002015500_pack_validation_harness_owner_rehome_v1.sql',
      v_batch_id, v_execution_id
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_activo_relaciones
    WHERE codigo_activo = 'PACK_VALIDATION_HARNESS'
      AND relacionado_codigo = 'OWNER_RUNNER_CARRIER_AUTHORITY'
      AND relacion_tipo = 'DEPENDE_DE'
  ) THEN
    INSERT INTO public.lf_activo_relaciones(
      codigo_activo, relacionado_codigo, relacion_tipo, valor_original,
      fuente, migration_batch_id, created_by_execution_id
    ) VALUES (
      'PACK_VALIDATION_HARNESS', 'OWNER_RUNNER_CARRIER_AUTHORITY', 'DEPENDE_DE',
      null,
      'supabase/migrations/20261002015500_pack_validation_harness_owner_rehome_v1.sql',
      v_batch_id, v_execution_id
    );
  END IF;

  IF (SELECT owner_scope FROM public.lf_capability_registry WHERE capability_code='PACK_VALIDATION_HARNESS') <> 'LF_GOVERNANCE' THEN
    RAISE EXCEPTION 'PACK_VALIDATION_HARNESS_REGISTRY_OWNER_READBACK_FAILED';
  END IF;

  IF (SELECT owner_name FROM public.lf_activos WHERE codigo_activo='PACK_VALIDATION_HARNESS' AND archived_at IS NULL) <> 'LF_GOVERNANCE' THEN
    RAISE EXCEPTION 'PACK_VALIDATION_HARNESS_ASSET_OWNER_READBACK_FAILED';
  END IF;
END $$;
