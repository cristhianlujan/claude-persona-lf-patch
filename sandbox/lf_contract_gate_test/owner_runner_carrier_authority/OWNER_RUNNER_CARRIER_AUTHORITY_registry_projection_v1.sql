do $$
declare
  v_execution_id constant text := 'EXEC-OWNER-RUNNER-CARRIER-AUTHORITY-REGISTRY-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d1d-008000000001'::uuid;
  v_readme constant text := 'sandbox/lf_contract_gate_test/owner_runner_carrier_authority/README.md';
  v_contract constant text := 'sandbox/lf_contract_gate_test/owner_runner_carrier_authority/owner_runner_carrier_authority_contract_v1.json';
begin
  if exists (
    select 1 from public.lf_capability_registry
    where capability_code='OWNER_RUNNER_CARRIER_AUTHORITY'
  ) then
    raise exception 'BLOCK_OWNER_RUNNER_CARRIER_CAPABILITY_ALREADY_REGISTERED';
  end if;

  insert into public.lf_activos(
    codigo_activo,
    nombre_canonico,
    tipo_activo,
    subtipo_activo,
    formato_nativo,
    estado_original,
    estado_documental,
    estado_operativo,
    impacto_automatico,
    version,
    ruta_esperada,
    owner_name,
    source_spreadsheet_id,
    source_spreadsheet_title,
    source_sheet_name,
    source_row_number,
    raw_payload,
    metadata,
    migration_batch_id,
    created_by_execution_id,
    updated_by_execution_id
  ) values (
    'OWNER_RUNNER_CARRIER_AUTHORITY',
    'TRANSVERSAL_OWNER_RUNNER_CARRIER_AUTHORITY',
    'CAPABILITY',
    'TRANSVERSAL_GOVERNANCE_READ_MODEL',
    'GITHUB_CONTRACT',
    'CANDIDATE_READ_ONLY',
    'CANDIDATO',
    'READ_ONLY',
    'BLOQUEADO',
    '1.0.0-candidate',
    v_readme,
    'SUPER_ADMIN',
    'NATIVE_SUPABASE',
    'LF_TRANSVERSAL_CAPABILITY_INVENTORY',
    'OWNER_RUNNER_CARRIER_AUTHORITY_20260930',
    1,
    jsonb_build_object(
      'solution_code','OWNER_RUNNER_CARRIER_AUTHORITY_V1',
      'work_code','SADM-PP-L1-008',
      'contract_ref',v_contract,
      'readme_ref',v_readme,
      'mode','DERIVED_READ_MODEL_ONLY',
      'persistent_binding_catalog_created',false,
      'capability_registry_projection_deferred',true,
      'supabase_applied',false,
      'cutover_authorized',false,
      'runtime_authorized',false,
      'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','OWNER_RUNNER_CARRIER_AUTHORITY_ASSET_METADATA_V1',
      'purpose','Resolve control, super admin, capability/runner, carrier, state and source revision from existing authorities without becoming a second authority.',
      'entry_contract',jsonb_build_object(
        'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1',
        'required',true,
        'owner','SUPER_ADMIN',
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'guard_function','public.fn_lf_capability_orchestrator_entry_guard_v1',
        'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'direct_new_binding_policy','BLOCK',
        'enforcement_state','SOURCE_READY_NOT_REGISTERED'
      ),
      'authority_boundary',jsonb_build_object(
        'administrative_owner','LF_GOVERNANCE',
        'carrier_authority','sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_control_impact_registry_v2.json',
        'classification_evidence','sandbox/lf_contract_gate_test/pase_control_binding_inventory/pase_control_binding_inventory_v1.json',
        'classification_evidence_is_authority',false,
        'asset_authority','public.lf_activos',
        'relation_authority','public.lf_activo_relaciones',
        'persistent_binding_catalog_forbidden',true
      ),
      'transversal_inventory',jsonb_build_object(
        'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
        'logical_key','OWNER_RUNNER_CARRIER_AUTHORITY',
        'class','GOVERNANCE_READ_MODEL',
        'inventory_status','CANDIDATE_READ_ONLY_SOURCE_READY_NOT_APPLIED',
        'no_duplicate_engine',true,
        'physical_assets',jsonb_build_array(v_contract,v_readme)
      )
    ),
    v_batch,
    v_execution_id,
    v_execution_id
  )
  on conflict(codigo_activo) do update set
    nombre_canonico=excluded.nombre_canonico,
    tipo_activo=excluded.tipo_activo,
    subtipo_activo=excluded.subtipo_activo,
    formato_nativo=excluded.formato_nativo,
    estado_original=excluded.estado_original,
    estado_documental=excluded.estado_documental,
    estado_operativo=excluded.estado_operativo,
    impacto_automatico=excluded.impacto_automatico,
    version=excluded.version,
    ruta_esperada=excluded.ruta_esperada,
    owner_name=excluded.owner_name,
    source_spreadsheet_id=excluded.source_spreadsheet_id,
    source_spreadsheet_title=excluded.source_spreadsheet_title,
    source_sheet_name=excluded.source_sheet_name,
    source_row_number=excluded.source_row_number,
    raw_payload=excluded.raw_payload,
    metadata=excluded.metadata,
    updated_at=now(),
    updated_by_execution_id=excluded.updated_by_execution_id;

  insert into public.lf_activo_relaciones(
    codigo_activo,
    relacionado_codigo,
    relacion_tipo,
    valor_original,
    fuente,
    migration_batch_id,
    created_by_execution_id,
    updated_by_execution_id
  ) values
    (
      'OWNER_RUNNER_CARRIER_AUTHORITY',
      'CURRENTNESS_AUTHORITY',
      'DEPENDE_DE',
      'currentness/read-model revision only',
      v_contract,
      v_batch,
      v_execution_id,
      v_execution_id
    ),
    (
      'OWNER_RUNNER_CARRIER_AUTHORITY',
      'LF_GOVERNANCE',
      'RELACIONADO_CAPACIDADES',
      'administrative discoverability only; ownership remains contract-derived',
      v_contract,
      v_batch,
      v_execution_id,
      v_execution_id
    )
  on conflict do nothing;
end $$;
