-- SADM-PP-L2-011 source-only normalization for the existing CURRENTNESS_AUTHORITY.
-- This file does not create a capability/version, move lf_capability_current, cut over runtime, deploy or activate production.
-- It is intentionally fail-closed while LF_GOVERNANCE is not materialized live.

do $$
declare
  v_execution_id constant text := 'EXEC-CURRENTNESS-AUTHORITY-SCOPED-READER-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d2d-011000000001'::uuid;
  v_inventory constant text := 'sandbox/lf_contract_gate_test/material_currentness/currentness_authority_scoped_reader_inventory_v1.json';
  v_contract constant text := 'sandbox/lf_contract_gate_test/material_currentness/LF_MATERIAL_CURRENTNESS_CONTRACT_V1.json';
  v_reader constant text := 'sandbox/lf_contract_gate_test/material_currentness/lf_material_currentness_v1.py';
  v_status text;
  v_owner_scope text;
  v_current_version text;
  v_current_manifest text;
begin
  select status, owner_scope
    into v_status, v_owner_scope
  from public.lf_capability_registry
  where capability_code='CURRENTNESS_AUTHORITY';

  if v_status is distinct from 'ACTIVE' then
    raise exception 'BLOCK_CURRENTNESS_SCOPED_READER_CAPABILITY_NOT_ACTIVE';
  end if;
  if v_owner_scope not in ('LF_GOVERNANCE_S31','LF_GOVERNANCE') then
    raise exception 'BLOCK_CURRENTNESS_SCOPED_READER_OWNER_SCOPE_UNEXPECTED:%',v_owner_scope;
  end if;

  select version, manifest_sha256
    into v_current_version, v_current_manifest
  from public.lf_capability_current
  where capability_code='CURRENTNESS_AUTHORITY';

  if v_current_version is distinct from '1.0.0'
     or v_current_manifest is distinct from '9f715dc226fd55a60c4002fa1960f848c4bf39e80b8863792eeef451073fce09' then
    raise exception 'BLOCK_CURRENTNESS_SCOPED_READER_CURRENT_POINTER_DRIFT';
  end if;

  if not exists(select 1 from public.lf_activos where codigo_activo='CURRENTNESS_AUTHORITY' and archived_at is null) then
    raise exception 'BLOCK_CURRENTNESS_SCOPED_READER_ASSET_MISSING';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE' and archived_at is null) then
    raise exception 'BLOCK_CURRENTNESS_SCOPED_READER_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;

  update public.lf_capability_registry
  set owner_scope='LF_GOVERNANCE',
      description='Material/dependency-aware currentness authority with bounded declared-path Git tree reads. Registration does not authorize runtime, production, cutover or current-pointer promotion.',
      updated_at=now(),
      updated_by_execution_id=v_execution_id
  where capability_code='CURRENTNESS_AUTHORITY';

  update public.lf_activos
  set owner_name='LF_GOVERNANCE',
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'administrative_owner','LF_GOVERNANCE',
        'scoped_reader_mode','DECLARED_BOUNDED_PATHSPECS_ONLY',
        'full_repository_tree_enumeration_forbidden',true,
        'unbounded_selector_policy','UNKNOWN_FAIL_CLOSED',
        'reader_ref',v_reader,
        'contract_ref',v_contract,
        'inventory_ref',v_inventory,
        'source_solution','CURRENTNESS_AUTHORITY_SCOPED_READER_V1',
        'work_code','SADM-PP-L2-011',
        'current_pointer_changed',false,
        'runtime_cutover',false
      ),
      updated_at=now(),
      updated_by_execution_id=v_execution_id
  where codigo_activo='CURRENTNESS_AUTHORITY' and archived_at is null;

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    'CURRENTNESS_AUTHORITY','LF_GOVERNANCE','RELACIONADO_CAPACIDADES',
    'administrative ownership/discoverability only; CURRENTNESS_AUTHORITY remains the single engine',
    v_inventory,v_batch,v_execution_id,v_execution_id
  ) on conflict do nothing;
end $$;
