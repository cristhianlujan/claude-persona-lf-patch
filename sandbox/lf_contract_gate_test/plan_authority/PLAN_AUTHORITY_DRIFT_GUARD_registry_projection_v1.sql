do $$
declare
  v_execution_id constant text := 'EXEC-PLAN-AUTHORITY-DRIFT-GUARD-REGISTRY-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d1d-010000000001'::uuid;
  v_readme constant text := 'sandbox/lf_contract_gate_test/plan_authority/README.md';
  v_contract constant text := 'sandbox/lf_contract_gate_test/plan_authority/plan_authority_drift_guard_v1.json';
  v_inventory constant text := 'sandbox/lf_contract_gate_test/plan_authority/plan_authority_drift_guard_inventory_v1.json';
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE') then
    raise exception 'BLOCK_PLAN_AUTHORITY_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT') then
    raise exception 'BLOCK_PLAN_AUTHORITY_EXECUTION_CONTRACT_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CURRENTNESS_AUTHORITY') then
    raise exception 'BLOCK_PLAN_AUTHORITY_CURRENTNESS_AUTHORITY_NOT_MATERIALIZED';
  end if;
  if exists(select 1 from public.lf_capability_registry where capability_code='PLAN_AUTHORITY_DRIFT_GUARD') then
    raise exception 'BLOCK_PLAN_AUTHORITY_PREMATURE_EXECUTABLE_REGISTRATION';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,
    estado_original,estado_documental,estado_operativo,impacto_automatico,version,
    ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
    source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'PLAN_AUTHORITY_DRIFT_GUARD',
    'TRANSVERSAL_PLAN_AUTHORITY_DRIFT_GUARD',
    'CAPABILITY',
    'TRANSVERSAL_READ_ONLY_GUARD',
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
    'PLAN_AUTHORITY_DRIFT_GUARD_20261001',
    1,
    jsonb_build_object(
      'solution_code','PLAN_AUTHORITY_DRIFT_GUARD_V1',
      'work_code','SADM-PP-L1-010',
      'contract_ref',v_contract,
      'inventory_ref',v_inventory,
      'readme_ref',v_readme,
      'anchor_event_id',19435,
      'anchor_plan_digest','9b234da6cdec56c141cc452e3997650c93cdf3a27f64d9b5858bea311476c648',
      'mode','PLAN_AUTHORITY_ADAPTER_OVER_CURRENTNESS_AUTHORITY',
      'capability_registry_projection_forbidden',true,
      'supabase_applied',false,
      'cutover_authorized',false,
      'runtime_authorized',false,
      'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','PLAN_AUTHORITY_DRIFT_GUARD_ASSET_METADATA_V1',
      'purpose','Fail-closed plan anchor and append-only delta reconciliation while reusing CURRENTNESS_AUTHORITY.',
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
        'source_currentness_engine','CURRENTNESS_AUTHORITY',
        'execution_envelope','CAPABILITY_EXECUTION_CONTRACT',
        'immutable_anchor_event_id',19435,
        'no_parallel_currentness_engine',true,
        'legacy_plan_digest_formula_invented',false
      ),
      'transversal_inventory',jsonb_build_object(
        'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
        'logical_key','PLAN_AUTHORITY_DRIFT_GUARD',
        'class','TRANSVERSAL_READ_ONLY_GUARD',
        'inventory_status','CANDIDATE_READ_ONLY_SOURCE_READY_NOT_APPLIED',
        'no_duplicate_engine',true,
        'physical_assets',jsonb_build_array(v_contract,v_inventory,v_readme)
      )
    ),
    v_batch,v_execution_id,v_execution_id
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
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values
    ('PLAN_AUTHORITY_DRIFT_GUARD','CURRENTNESS_AUTHORITY','DEPENDE_DE','single source/currentness engine',v_contract,v_batch,v_execution_id,v_execution_id),
    ('PLAN_AUTHORITY_DRIFT_GUARD','CAPABILITY_EXECUTION_CONTRACT','DEPENDE_DE','orchestrated request/receipt envelope',v_contract,v_batch,v_execution_id,v_execution_id),
    ('PLAN_AUTHORITY_DRIFT_GUARD','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative discoverability only',v_contract,v_batch,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
