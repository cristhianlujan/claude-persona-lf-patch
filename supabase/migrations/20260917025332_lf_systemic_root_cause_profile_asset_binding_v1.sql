insert into public.lf_activos (
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,
  estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
  raw_payload,metadata,created_by_execution_id,updated_by_execution_id
)
select
  'PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF','PERFIL_SYSTEMIC_ROOT_CAUSE_REPAIR_LF','PERFIL','Systemic Root Cause Repair LF','PROFILE_PACK','MARKDOWN_PROFILE_PACK',
  'CANDIDATO','CANDIDATO','READ_ONLY','PROFILE_REGISTRY','NO_HABILITADO','BLOQUEADO',
  'INVENTARIADO_SUPABASE','v0.1','profiles/systemic_root_cause_repair_lf','supabase://public/lf_activos/PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF',null,'2026-09-17','Systemic root-cause analysis and repair specification',
  'SUPABASE_DIRECT_INVENTORY','LF_SUPABASE_SANDBOX','public.lf_activos',0,'86700000-0000-4000-8000-202609170001'::uuid,
  jsonb_build_object(
    'path','profiles/systemic_root_cause_repair_lf/SKILL.md',
    'repo','cristhianlujan/claude-persona-lf-patch',
    'skill_sha','89485c60c971c0645850ced577609c8b9f13f84c',
    'profile_pack_id','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_1',
    'registration_reason','governed_post_merge_profile_binding_for_first_runtime_canary'
  ),
  jsonb_build_object(
    'repo','cristhianlujan/claude-persona-lf-patch',
    'repo_path','profiles/systemic_root_cause_repair_lf',
    'display_name','Systemic Root Cause Repair LF',
    'profile_slug','systemic_root_cause_repair_lf',
    'entrypoint_sha','89485c60c971c0645850ced577609c8b9f13f84c',
    'entrypoint_path','profiles/systemic_root_cause_repair_lf/SKILL.md',
    'profile_pack_id','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_1',
    'registry_source','SUPABASE',
    'runtime_enabled',false,
    'last_governed_pr',867,
    'last_governed_merge_sha','6c7adf72851d459acb5156924a52f05f186c65cb',
    'manifest_sha','dba0ae1c0bc8e7a276ca4bdadcf5a4a91fb4d81c',
    'creation_execution_id','EXEC-S30-A2R-PROFILE-SYSTEMIC-ROOT-CAUSE-20260916-001',
    'creation_receipt_path','sandbox/lf_contract_gate_test/receipts/receipt_systemic_root_cause_repair_creation_20260916.json',
    'creation_receipt_sha','382f15cc02b2e22c59571f2c9d154737e13a64ac',
    'canonical_profile_key','systemic_root_cause_repair_lf',
    'legacy_registry_source','GITHUB_MAIN',
    'automatic_impact_enabled',false,
    'aliases',jsonb_build_array('systemic_root_cause_repair_lf','Systemic Root Cause Repair LF','SYSTEMIC_ROOT_CAUSE_REPAIR_LF_V0_1'),
    'keywords',jsonb_build_array('root cause','causa raiz','recurrence','recurrent failure','systemic repair','migration parity','source parity','replay','partial failure'),
    'source_governance',jsonb_build_object(
      'operational_authority','SUPABASE',
      'github_role','TECHNICAL_IMPLEMENTATION_ARTIFACT',
      'github_is_authority',false,
      'operational_source_ref','supabase://public/lf_activos/PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
    )
  ),
  'EXEC-S30-A2R-PROFILE-SYSTEMIC-ROOT-CAUSE-20260916-001','EXEC-S30-A2R-PROFILE-SYSTEMIC-ROOT-CAUSE-20260916-001'
where not exists (
  select 1 from public.lf_activos where codigo_activo='PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF'
)
on conflict (codigo_activo) do nothing;