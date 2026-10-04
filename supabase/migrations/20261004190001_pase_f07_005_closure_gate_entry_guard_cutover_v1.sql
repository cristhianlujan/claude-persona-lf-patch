-- PASE-ATOM-F07-005 control-scoped cutover 2/5.
-- No runtime/deploy/production activation and no current-pointer change.
do $$
declare
  v_exec constant text := 'CHATGPT-PASE-F07-005-CLOSURE-GATE-CUTOVER-20261004';
  v_manifest constant text := '55b4e8f8d40d6af594f724674a403fde4efee4d3c55389e87158a23fd0ed2f96';
begin
  if not exists(select 1 from public.lf_capability_current where capability_code='CLOSURE_GATE' and version='1.0.0' and manifest_sha256=v_manifest) then raise exception 'BLOCK_F07_005_CLOSURE_GATE_CURRENT_DRIFT'; end if;
  if not exists(select 1 from public.lf_capability_registry where capability_code='CLOSURE_GATE' and status='ACTIVE' and entry_guard_required=false and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1') then raise exception 'BLOCK_F07_005_CLOSURE_GATE_EXPECTED_OLD_REGISTRY_DRIFT'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CLOSURE_GATE' and archived_at is null and metadata->'entry_contract' is null) then raise exception 'BLOCK_F07_005_CLOSURE_GATE_EXPECTED_OLD_ASSET_DRIFT'; end if;
  update public.lf_capability_registry set entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_exec where capability_code='CLOSURE_GATE' and status='ACTIVE' and entry_guard_required=false;
  if not found then raise exception 'BLOCK_F07_005_CLOSURE_GATE_REGISTRY_UPDATE'; end if;
  update public.lf_activos set metadata=jsonb_set(coalesce(metadata,'{}'::jsonb),'{entry_contract}',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'owner',coalesce(owner_name,'LF_GOVERNANCE'),'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','direct_new_binding_policy','BLOCK','enforcement_state','ENFORCED'),true),updated_at=now(),updated_by_execution_id=v_exec where codigo_activo='CLOSURE_GATE' and archived_at is null;
  if not found then raise exception 'BLOCK_F07_005_CLOSURE_GATE_ASSET_UPDATE'; end if;
  if not exists(select 1 from public.lf_capability_registry r join public.lf_capability_current c using(capability_code) join public.lf_activos a on a.codigo_activo=r.capability_code and a.archived_at is null where r.capability_code='CLOSURE_GATE' and r.status='ACTIVE' and r.entry_guard_required=true and r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1' and c.version='1.0.0' and c.manifest_sha256=v_manifest and (a.metadata#>>'{entry_contract,required}')::boolean=true and a.metadata#>>'{entry_contract,enforcement_state}'='ENFORCED') then raise exception 'BLOCK_F07_005_CLOSURE_GATE_POSTCHECK'; end if;
end $$;
