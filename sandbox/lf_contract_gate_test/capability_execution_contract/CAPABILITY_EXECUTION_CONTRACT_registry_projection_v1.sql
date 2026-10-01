do $$
declare
  v_execution_id constant text := 'EXEC-CAPABILITY-EXECUTION-CONTRACT-REGISTRY-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d1d-009000000001'::uuid;
  v_readme constant text := 'sandbox/lf_contract_gate_test/capability_execution_contract/README.md';
  v_contract constant text := 'sandbox/lf_contract_gate_test/capability_execution_contract/capability_execution_contract_v1.json';
  v_inventory constant text := 'sandbox/lf_contract_gate_test/capability_execution_contract/capability_execution_contract_inventory_v1.json';
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE') then
    raise exception 'BLOCK_CAPABILITY_EXECUTION_CONTRACT_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='OWNER_RUNNER_CARRIER_AUTHORITY') then
    raise exception 'BLOCK_CAPABILITY_EXECUTION_CONTRACT_OWNER_RUNNER_CARRIER_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='EVIDENCE_LEDGER') then
    raise exception 'BLOCK_CAPABILITY_EXECUTION_CONTRACT_EVIDENCE_LEDGER_NOT_MATERIALIZED';
  end if;
  if exists(select 1 from public.lf_capability_registry where capability_code='CAPABILITY_EXECUTION_CONTRACT') then
    raise exception 'BLOCK_CAPABILITY_EXECUTION_CONTRACT_EXECUTABLE_REGISTRATION_FORBIDDEN';
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
    'CAPABILITY_EXECUTION_CONTRACT',
    'TRANSVERSAL_CAPABILITY_EXECUTION_CONTRACT',
    'CAPABILITY',
    'TRANSVERSAL_RUNTIME_CONTRACT',
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
    'CAPABILITY_EXECUTION_CONTRACT_20260930',
    1,
    jsonb_build_object(
      'solution_code','CAPABILITY_EXECUTION_CONTRACT_V1',
      'work_code','SADM-PP-L1-009',
      'contract_ref',v_contract,
      'inventory_ref',v_inventory,
      'readme_ref',v_readme,
      'mode','SHARED_ENVELOPE_DEFINITION_ONLY',
      'new_table_created',false,
      'new_rpc_created',false,
      'new_ledger_created',false,
      'capability_registry_projection_forbidden',true,
      'supabase_applied',false,
      'cutover_authorized',false,
      'runtime_authorized',false,
      'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','CAPABILITY_EXECUTION_CONTRACT_ASSET_METADATA_V1',
      'purpose','Normalize orchestrated capability request/receipt envelopes while reusing live dispatch, guard, execution and evidence authorities.',
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
        'owner_runner_carrier','OWNER_RUNNER_CARRIER_AUTHORITY',
        'dispatch_receipt','private.lf_orchestrator_dispatch_receipts_v1',
        'evidence_ledger','private.lf_evidence_ledger_v1',
        'no_parallel_receipt_store',true,
        'no_parallel_evidence_ledger',true
      ),
      'transversal_inventory',jsonb_build_object(
        'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
        'logical_key','CAPABILITY_EXECUTION_CONTRACT',
        'class','TRANSVERSAL_RUNTIME_CONTRACT',
        'inventory_status','CANDIDATE_READ_ONLY_SOURCE_READY_NOT_APPLIED',
        'no_duplicate_engine',true,
        'physical_assets',jsonb_build_array(v_contract,v_inventory,v_readme)
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
    ('CAPABILITY_EXECUTION_CONTRACT','OWNER_RUNNER_CARRIER_AUTHORITY','DEPENDE_DE','owner/runner/carrier derived read-model',v_contract,v_batch,v_execution_id,v_execution_id),
    ('CAPABILITY_EXECUTION_CONTRACT','EVIDENCE_LEDGER','DEPENDE_DE','provider-bound output/evidence composition',v_contract,v_batch,v_execution_id,v_execution_id),
    ('CAPABILITY_EXECUTION_CONTRACT','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative discoverability only',v_contract,v_batch,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
