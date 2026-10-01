do $$
declare
  v_execution_id constant text := 'EXEC-LF-GOVERNANCE-SUPER-ADMIN-REGISTRY-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d1d-007000000001'::uuid;
  v_contract_ref constant text := 'sandbox/lf_contract_gate_test/transversal_assets/lf_governance_super_admin/lf_governance_super_admin_contract_v1.json';
  v_readme_ref constant text := 'sandbox/lf_contract_gate_test/transversal_assets/lf_governance_super_admin/README.md';
begin
  if exists (
    select 1
    from public.lf_capability_registry
    where capability_code = 'LF_GOVERNANCE'
  ) then
    raise exception 'BLOCK_LF_GOVERNANCE_MUST_NOT_BE_CAPABILITY';
  end if;

  if exists (
    select 1
    from public.lf_operation_registry
    where operation_code = 'LF_GOVERNANCE'
  ) then
    raise exception 'BLOCK_LF_GOVERNANCE_MUST_NOT_BE_OPERATION';
  end if;

  if exists (
    select 1
    from public.lf_activos
    where codigo_activo = 'LF_GOVERNANCE'
      and archived_at is null
      and (
        tipo_activo is distinct from 'REGLA'
        or subtipo_activo is distinct from 'SUPER_ADMIN_GOVERNANCE_ROOT'
        or owner_name is distinct from 'LF_GOVERNANCE'
      )
  ) then
    raise exception 'BLOCK_LF_GOVERNANCE_CONFLICTING_ASSET_IDENTITY';
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
    'LF_GOVERNANCE',
    'LF_GOVERNANCE SUPER ADMIN',
    'REGLA',
    'SUPER_ADMIN_GOVERNANCE_ROOT',
    'GITHUB_CONTRACT',
    'CANDIDATE_READ_ONLY',
    'CANDIDATO',
    'READ_ONLY',
    'BLOQUEADO',
    '1.0.0-candidate',
    v_readme_ref,
    'LF_GOVERNANCE',
    'NATIVE_SUPABASE',
    'LF_TRANSVERSAL_CAPABILITY_INVENTORY',
    'LF_GOVERNANCE_20260930',
    1,
    jsonb_build_object(
      'solution_code','LF_GOVERNANCE_SUPER_ADMIN_REGISTRY_PROJECTION_V1',
      'role','SUPER_ADMIN_GOVERNANCE',
      'source_pr',1223,
      'contract_ref',v_contract_ref,
      'readme_ref',v_readme_ref,
      'source_state','CANDIDATE_READ_ONLY',
      'binding_materialized',false,
      'cutover_authorized',false,
      'runtime_authorized',false,
      'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','LF_GOVERNANCE_SUPER_ADMIN_ASSET_METADATA_V1',
      'purpose','Single administrative governance root for PASE control/capability ownership identity; never a carrier, runner, applicability engine or executable capability.',
      'classification',jsonb_build_object(
        'asset_class','GOVERNANCE_AUTHORITY_ROOT',
        'standalone_capability',false,
        'canonical_operation',false,
        'capability_registry_projection','FORBIDDEN_BY_CLASSIFICATION',
        'operation_registry_projection','FORBIDDEN_BY_CLASSIFICATION'
      ),
      'material_relations',jsonb_build_object(
        'state','NO_VERIFIED_EDGE_AT_L1_007',
        'readback_table','public.lf_activo_relaciones',
        'owner_runner_carrier_authority_work_code','SADM-PP-L1-008',
        'do_not_invent_relation_type',true,
        'reason','L1-007 defines the administrative identity only; executable owner/runner/carrier bindings belong to L1-008.'
      ),
      'transversal_inventory',jsonb_build_object(
        'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
        'logical_key','LF_GOVERNANCE',
        'class','GOVERNANCE_AUTHORITY_ROOT',
        'inventory_status','CANDIDATE_READ_ONLY_SOURCE_READY_NOT_APPLIED',
        'no_duplicate_engine',true,
        'lookup_rule','ASSET_INVENTORY_FIRST_THEN_CURRENTNESS_THEN_EXPAND_SEARCH',
        'physical_assets',jsonb_build_array(
          'public.lf_activos:LF_GOVERNANCE',
          v_contract_ref,
          v_readme_ref
        ),
        'documentation',jsonb_build_object(
          'contract_ref',v_contract_ref,
          'readme_ref',v_readme_ref,
          'source_pr',1223
        )
      ),
      'global_dod',jsonb_build_object(
        'phase','PASE-GLOBAL-03-TRANSVERSAL-FOUNDATION',
        'work_code','SADM-PP-L1-007',
        'one_solution_one_pr',true,
        'no_zip',true,
        'entry_guard_applicable',false,
        'entry_guard_reason','Non-executable governance identity; executable capabilities remain guarded independently.',
        'merge_authorized',false,
        'supabase_apply_authorized',false,
        'cutover_authorized',false,
        'runtime_authorized',false,
        'production_authorized',false
      )
    ),
    v_batch,
    v_execution_id,
    v_execution_id
  )
  on conflict(codigo_activo) do update set
    nombre_canonico = excluded.nombre_canonico,
    tipo_activo = excluded.tipo_activo,
    subtipo_activo = excluded.subtipo_activo,
    formato_nativo = excluded.formato_nativo,
    estado_original = excluded.estado_original,
    estado_documental = excluded.estado_documental,
    estado_operativo = excluded.estado_operativo,
    impacto_automatico = excluded.impacto_automatico,
    version = excluded.version,
    ruta_esperada = excluded.ruta_esperada,
    owner_name = excluded.owner_name,
    source_spreadsheet_id = excluded.source_spreadsheet_id,
    source_spreadsheet_title = excluded.source_spreadsheet_title,
    source_sheet_name = excluded.source_sheet_name,
    source_row_number = excluded.source_row_number,
    raw_payload = excluded.raw_payload,
    metadata = excluded.metadata,
    migration_batch_id = excluded.migration_batch_id,
    updated_at = now(),
    updated_by_execution_id = excluded.updated_by_execution_id;
end $$;
