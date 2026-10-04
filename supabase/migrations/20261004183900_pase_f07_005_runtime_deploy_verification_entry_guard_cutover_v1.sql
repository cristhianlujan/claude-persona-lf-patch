-- PASE-ATOM-F07-005 control-scoped cutover 5/5: RUNTIME_DEPLOY_VERIFICATION.
-- No runtime/deploy/production activation and no current-pointer change.
do $$
declare
  v_exec constant text := 'CHATGPT-PASE-F07-005-RUNTIME-DEPLOY-VERIFICATION-CUTOVER-20261004';
  v_manifest constant text := 'ee733461092d956da32ccd27607c0600a8d954a820a05feeae8a0e4fa3b779b9';
begin
  if not exists(select 1 from public.lf_capability_current where capability_code='RUNTIME_DEPLOY_VERIFICATION' and version='1.0.0' and manifest_sha256=v_manifest) then raise exception 'BLOCK_F07_005_RUNTIME_DEPLOY_VERIFICATION_CURRENT_DRIFT'; end if;
  if not exists(select 1 from public.lf_capability_registry where capability_code='RUNTIME_DEPLOY_VERIFICATION' and status='ACTIVE' and entry_guard_required=false and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1') then raise exception 'BLOCK_F07_005_RUNTIME_DEPLOY_VERIFICATION_EXPECTED_OLD_REGISTRY_DRIFT'; end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='RUNTIME_DEPLOY_VERIFICATION' and archived_at is null and coalesce((metadata#>>'{entry_contract,required}')::boolean,false)=false and metadata#>>'{entry_contract,guard_code}'='ORCHESTRATOR_EXECUTION_GUARD_V1' and metadata#>>'{entry_contract,enforcement_state}'='ENTRY_GUARD_REQUIREMENT_DEFERRED_ONLY') then raise exception 'BLOCK_F07_005_RUNTIME_DEPLOY_VERIFICATION_EXPECTED_OLD_ASSET_DRIFT'; end if;
  update public.lf_capability_registry set entry_guard_required=true,entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1',updated_at=now(),updated_by_execution_id=v_exec where capability_code='RUNTIME_DEPLOY_VERIFICATION' and status='ACTIVE' and entry_guard_required=false;
  if not found then raise exception 'BLOCK_F07_005_RUNTIME_DEPLOY_VERIFICATION_REGISTRY_UPDATE'; end if;
  update public.lf_activos set metadata=jsonb_set(metadata,'{entry_contract}',jsonb_build_object('schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'owner',coalesce(metadata#>>'{entry_contract,owner}',owner_name,'LF_GOVERNANCE'),'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1','required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1','direct_new_binding_policy','BLOCK','enforcement_state','ENFORCED'),true),updated_at=now(),updated_by_execution_id=v_exec where codigo_activo='RUNTIME_DEPLOY_VERIFICATION' and archived_at is null;
  if not found then raise exception 'BLOCK_F07_005_RUNTIME_DEPLOY_VERIFICATION_ASSET_UPDATE'; end if;
  if not exists(select 1 from public.lf_capability_registry r join public.lf_capability_current c using(capability_code) join public.lf_activos a on a.codigo_activo=r.capability_code and a.archived_at is null where r.capability_code='RUNTIME_DEPLOY_VERIFICATION' and r.status='ACTIVE' and r.entry_guard_required=true and r.entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1' and c.version='1.0.0' and c.manifest_sha256=v_manifest and (a.metadata#>>'{entry_contract,required}')::boolean=true and a.metadata#>>'{entry_contract,enforcement_state}'='ENFORCED') then raise exception 'BLOCK_F07_005_RUNTIME_DEPLOY_VERIFICATION_POSTCHECK'; end if;
end $$;
