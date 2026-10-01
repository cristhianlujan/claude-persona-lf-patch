do $$
declare
  v_execution_id constant text := 'EXEC-GITHUB-RECONCILIATION-REGISTRY-PROJECTION-V1';
  v_batch constant uuid := '8c1d2f6c-4a1c-4f80-9d2d-012000000001'::uuid;
  v_readme constant text := 'sandbox/lf_contract_gate_test/github_reconciliation/README.md';
  v_contract constant text := 'sandbox/lf_contract_gate_test/github_reconciliation/github_reconciliation_v1.json';
  v_inventory constant text := 'sandbox/lf_contract_gate_test/github_reconciliation/github_reconciliation_inventory_v1.json';
begin
  if not exists(select 1 from public.lf_activos where codigo_activo='LF_GOVERNANCE') then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_LF_GOVERNANCE_NOT_MATERIALIZED';
  end if;
  if not exists(select 1 from public.lf_activos where codigo_activo='CAPABILITY_EXECUTION_CONTRACT') then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_EXECUTION_CONTRACT_NOT_MATERIALIZED';
  end if;
  if exists(select 1 from public.lf_capability_registry where capability_code='GITHUB_RECONCILIATION') then
    raise exception 'BLOCK_GITHUB_RECONCILIATION_PREMATURE_EXECUTABLE_REGISTRATION';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,formato_nativo,
    estado_original,estado_documental,estado_operativo,impacto_automatico,version,
    ruta_esperada,owner_name,source_spreadsheet_id,source_spreadsheet_title,
    source_sheet_name,source_row_number,raw_payload,metadata,migration_batch_id,
    created_by_execution_id,updated_by_execution_id
  ) values (
    'GITHUB_RECONCILIATION','TRANSVERSAL_GITHUB_RECONCILIATION','CAPABILITY',
    'TRANSVERSAL_READ_ONLY_RECONCILIATION','GITHUB_CONTRACT','CANDIDATE_READ_ONLY',
    'CANDIDATO','READ_ONLY','BLOQUEADO','1.0.0-candidate',v_readme,'SUPER_ADMIN',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','GITHUB_RECONCILIATION_20261001',1,
    jsonb_build_object(
      'solution_code','GITHUB_RECONCILIATION_V1','work_code','SADM-PP-L2-012',
      'contract_ref',v_contract,'inventory_ref',v_inventory,'readme_ref',v_readme,
      'mode','BOUNDED_DETERMINISTIC_POST_MERGE_READBACK',
      'legacy_workflow','.github/workflows/lf-github-reconcile-v3.yml',
      'legacy_edge_function','supabase/functions/lf-github-reconcile-v3/index.ts',
      'capability_registry_projection_forbidden',true,'supabase_applied',false,
      'cutover_authorized',false,'runtime_authorized',false,'production_authorized',false
    ),
    jsonb_build_object(
      'schema_version','GITHUB_RECONCILIATION_ASSET_METADATA_V1',
      'purpose','Bounded deterministic post-merge GitHub readback over declared paths and anchors only.',
      'entry_contract',jsonb_build_object(
        'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1','required',true,'owner','SUPER_ADMIN',
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'guard_function','public.fn_lf_capability_orchestrator_entry_guard_v1',
        'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'direct_new_binding_policy','BLOCK','enforcement_state','SOURCE_READY_NOT_REGISTERED'
      ),
      'boundary',jsonb_build_object(
        'applicability_owner','POST_PASE_ROUTER_V1','pre_merge_admission_owner','CONTRACT_CHECK_SELF_CHANGE_ADMISSION',
        'persistence_owner','EVIDENCE_LEDGER_OR_CALLER','promotion_owner','ARTIFACT_LIFECYCLE',
        'global_inventory_forbidden',true,'promotion_forbidden',true
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
    ('GITHUB_RECONCILIATION','CAPABILITY_EXECUTION_CONTRACT','DEPENDE_DE','orchestrated request/receipt envelope',v_contract,v_batch,v_execution_id,v_execution_id),
    ('GITHUB_RECONCILIATION','LF_GOVERNANCE','RELACIONADO_CAPACIDADES','administrative discoverability only',v_contract,v_batch,v_execution_id,v_execution_id)
  on conflict do nothing;
end $$;
