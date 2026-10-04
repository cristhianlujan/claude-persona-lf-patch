-- PLAN_AUTHORITY_DRIFT_GUARD source lifecycle projection.
-- Mutable lifecycle is canonical in Supabase and must not be replayed from source.
-- This file is verification-only: no asset/registry/current mutation.

do $$
declare
  v_asset_state text;
  v_registry_state text;
  v_current_version text;
  v_current_manifest text;
begin
  select estado_operativo
    into v_asset_state
  from public.lf_activos
  where codigo_activo='PLAN_AUTHORITY_DRIFT_GUARD'
    and archived_at is null;

  if v_asset_state is distinct from 'ACTIVO' then
    raise exception 'BLOCK_PLAN_AUTHORITY_CANONICAL_ASSET_NOT_ACTIVE:%',coalesce(v_asset_state,'<missing>');
  end if;

  select status
    into v_registry_state
  from public.lf_capability_registry
  where capability_code='PLAN_AUTHORITY_DRIFT_GUARD';

  if v_registry_state is distinct from 'ACTIVE' then
    raise exception 'BLOCK_PLAN_AUTHORITY_CANONICAL_REGISTRY_NOT_ACTIVE:%',coalesce(v_registry_state,'<missing>');
  end if;

  select version,manifest_sha256
    into v_current_version,v_current_manifest
  from public.lf_capability_current
  where capability_code='PLAN_AUTHORITY_DRIFT_GUARD';

  if v_current_version is null or v_current_manifest is null then
    raise exception 'BLOCK_PLAN_AUTHORITY_CANONICAL_CURRENT_MISSING';
  end if;

  if v_current_version is distinct from '1.0.0'
     or v_current_manifest is distinct from '1cacbd3f235723406e1d85457c8474b540be703bf127a35ff0fc41223cf47272' then
    raise exception 'BLOCK_PLAN_AUTHORITY_CANONICAL_CURRENT_DRIFT:%:%',coalesce(v_current_version,'<missing>'),coalesce(v_current_manifest,'<missing>');
  end if;

  -- Source contract remains functional only. Mutable lifecycle is read from the
  -- three canonical authorities above and is never reconstructed from this file.
end $$;
