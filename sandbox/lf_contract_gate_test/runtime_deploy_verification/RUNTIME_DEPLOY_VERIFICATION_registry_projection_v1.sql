do $$
declare
  v_execution_id constant text := 'EXEC-RUNTIME-DEPLOY-VERIFICATION-REGISTRY-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d2d-014000000001'::uuid;
  v_readme constant text := 'sandbox/lf_contract_gate_test/runtime_deploy_verification/README.md';
  v_contract constant text := 'sandbox/lf_contract_gate_test/runtime_deploy_verification/runtime_deploy_verification_v1.json';
  v_inventory constant text := 'sandbox/lf_contract_gate_test/runtime_deploy_verification/runtime_deploy_verification_inventory_v1.json';
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE') then
    raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT') then
    raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_EXECUTION_CONTRACT_NOT_MATERIALIZED';
  end if;
  if exists(select 1 from public.lf_capability_registry where capability_code='RUNTIME_DEPLOY_VERIFICATION') then
    raise exception 'BLOCK_RUNTIME_DEPLOY_VERIFICATION_PREMATURE_EXECUTABLE_REGISTRATION';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,
    estado_original,estado_documental,estado_operativo,impacto_automatico,version,
    ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
    source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'RUNTIME_DEPLOY_VERIFICATION','TRANSVERSAL_RUNTIME_DEPLOY_VERIFICATION','CAPABILITY',
    'TRANSVERSAL_READ_ONLY_RUNTIME_DEPLOY_VERIFICATION','GITHUB_CONTRACT','CANDIDATE_READ_ONLY',
    'CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',v_readme,'SUPER_ADMIN',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','RUNTIME_DEPLOY_VERIFICATION_20261001',1,
    jsonb_build_object(
      'solution_code','RUNTIME_DEPLOY_VERIFICATION_V1','work_code','SADM-PP-L2-014',
      'contract_ref',v_contract,'inventory_ref',v_inventory,'readme_ref',v_readme,
      'mode','BOUNDED_DETERMINISTIC_RUNTIME_DEPLOY_READBACK',
      'initial_effect_source','REFRESCO_RUNTIME_PERFIL_LF',
      'legacy_installer','services/profile_runtime_api/scripts/install.sh',
      'capability_registry_projection_forbidden',true,'supabase_applied',false,
      'cutover_authorized',false,'runtime_authorized',false,'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','RUNTIME_DEPLOY_VERIFICATION_ASSET_METADATA_V1',
      'purpose','Read-only deterministic verification of an exact deployment receipt, declared release files, health/source and preserved state.',
      'entry_contract',jsonb_build_object(
        'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'owner','SUPER_ADMIN',
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'guard_function','public.fn_lf_capability_orchestrator_entry_guard_v1',
        'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'direct_new_binding_policy','BLOCK','enforcement_state','SOURCE_READY_NOT_REGISTERED'
      ),
      'boundary',jsonb_build_object(
        'applicability_owner','POST_PASE_ROUTER_V1',
        'deploy_effect_owner','EXPLICIT_GOVERNED_DEPLOY_OPERATION',
        'next_gate_owner','POST_PASE_ROUTER_OR_ORCHESTRATOR',
        'exact_required_file_manifest',true,
        'deploy_forbidden',true,'restart_forbidden',true,'asset_mutation_forbidden',true,
        'promotion_forbidden',true
      )
    ),
    v_batch,v_execution_id,v_execution_id
  )
  on conflict(codigo_activo) do update set
    nombre_canonico=excluded.nombre_canonico,tipo_activo=excluded.tipo_activo,
    subtipo_activo=excluded.subtipo_activo,formato_nativo=excluded.formato_nativo,
    estado_original=excluded.estado_original,estado_documental=excluded.estado_documental,
    estado_operativo=excluded.estado_operativo,impacto_automatico=excluded.impacto_automatico,
    version=excluded.version,ruta_esperada=excluded.ruta_esperada,owner_name=excluded.owner_name,
    source_spreadsheet_id=excluded.source_spreadsheet_id,source_spreadsheet_title=excluded.source_spreadsheet_title,
    source_sheet_name=excluded.source_sheet_name,source_row_number=excluded.source_row_number,
    raw_payload=excluded.raw_payload,metadata=excluded.metadata,updated_at=now(),
    updated_by_execution_id=excluded.updated_by_execution_id;

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values
    ('RUNTIME_DEPLOY_VERIFICATION','CAPABILITY_EXECUTION_CONTRACT','DEPENDE_DE','orchestrated request/receipt envelope',v_contract,v_batch,v_execution_id,v_execution_id),
    ('RUNTIME_DEPLOY_VERIFICATION','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative discoverability only',v_contract,v_batch,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
