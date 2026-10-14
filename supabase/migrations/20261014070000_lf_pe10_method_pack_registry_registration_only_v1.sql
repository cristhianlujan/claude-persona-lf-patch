-- PE10_C3 / Profile Updater — registration only.
-- This is NOT a method release, qualification, version promotion or runtime cutover.
-- Submit through LF Migration Train. Never apply directly from chat.
-- Separate from the Profile Updater source PR #2579.
DO $guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code = 'METHOD_PACK_REGISTRY'
  ) OR EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code = 'METHOD_PACK_REGISTRY'
  ) OR EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code = 'METHOD_PACK_REGISTRY'
  ) THEN
    RAISE EXCEPTION 'BLOCK_PE10_METHOD_CATALOG_ALREADY_REGISTERED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry r
    JOIN public.lf_capability_current c ON c.capability_code = r.capability_code
    JOIN public.lf_capability_version_registry v
      ON v.capability_code = c.capability_code AND v.version = c.version
    WHERE r.capability_code = 'CAPABILITY_SELECTOR'
      AND r.status = 'ACTIVE' AND v.release_state = 'RELEASED'
      AND c.manifest_sha256 = v.manifest_sha256
  ) THEN
    RAISE EXCEPTION 'BLOCK_PE10_CANONICAL_SELECTOR_NOT_RELEASED';
  END IF;

  INSERT INTO public.lf_capability_registry
  (capability_code, capability_name, capability_kind, owner_scope, status,
   description, created_by_execution_id, updated_by_execution_id,
   entry_guard_required, entry_guard_code)
  VALUES
  ('METHOD_PACK_REGISTRY', 'Method Pack Registry', 'TRANSVERSAL',
   'SUPER_ADMIN', 'ACTIVE',
   'Registry identity only: NO released catalog version, NO method qualification, NO current pointer, NO runtime execution. Future release requires independent benchmark evidence, Train admission and exact source readback.',
   'PE10_C3_V2_METHOD_REGISTRY_TRAIN_V1',
   'PE10_C3_V2_METHOD_REGISTRY_TRAIN_V1',
   true, 'ORCHESTRATOR_EXECUTION_GUARD_V1');

  IF NOT EXISTS (
    SELECT 1 FROM public.lf_capability_registry
    WHERE capability_code = 'METHOD_PACK_REGISTRY'
      AND status = 'ACTIVE' AND owner_scope = 'SUPER_ADMIN'
      AND entry_guard_required IS TRUE
  ) OR EXISTS (
    SELECT 1 FROM public.lf_capability_version_registry
    WHERE capability_code = 'METHOD_PACK_REGISTRY'
  ) OR EXISTS (
    SELECT 1 FROM public.lf_capability_current
    WHERE capability_code = 'METHOD_PACK_REGISTRY'
  ) THEN
    RAISE EXCEPTION 'BLOCK_PE10_REGISTRATION_ONLY_READBACK';
  END IF;
END $guard$;
