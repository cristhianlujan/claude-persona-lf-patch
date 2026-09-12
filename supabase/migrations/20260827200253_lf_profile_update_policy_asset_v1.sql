insert into public.lf_activos (
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,
  estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
  raw_payload,metadata,created_by_execution_id,updated_by_execution_id
)
select
  'POL-PROFILE-UPDATE-PASS','POL_PROFILE_UPDATE_PASS_LF','REGLA','POLICY_TRANSVERSAL_GOV','POLICY','SUPABASE_JSONB',
  'NUEVO_CANONICO','VIGENTE','ACTIVO','GOVERNANCE_ENFORCED','NO_APLICA','BLOQUEADO','INVENTARIADO_SUPABASE','v1.0',
  'Supabase/public/lf_policy_versions/POL-PROFILE-UPDATE-PASS','LF_GOVERNANCE','2026-08-27',
  'Policy transversal para pase gobernado de actualización de perfiles',
  'SUPABASE_DIRECT_INVENTORY','LF_SUPABASE_SANDBOX','public.lf_activos',0,
  '11111111-1111-4111-8111-000000000002'::uuid,'{}'::jsonb,
  jsonb_build_object(
    'inventory_source','SUPABASE_DIRECT_INVENTORY','policy_kind','PROFILE_UPDATE_PASS_POLICY',
    'canonical_policy_store','public.lf_policy_versions','operation_binding_store','public.lf_operation_policy_bindings',
    'snapshot_view','public.v_lf_operation_policy_snapshot','applies_to_operations',jsonb_build_array('ACTUALIZACION_PERFIL_LF'),
    'distribution_modes',jsonb_build_array('ROUTER','DIRECT'),'governance_issue','GOV-036','precedents_are_authority',false
  ),
  'EXEC-GOV-036-POLICY-INVENTORY-20260827-001','EXEC-GOV-036-POLICY-INVENTORY-20260827-001'
where not exists (select 1 from public.lf_activos where codigo_activo='POL-PROFILE-UPDATE-PASS');

with p as (
  select jsonb_build_object(
    'policy_id','POL-PROFILE-UPDATE-PASS','policy_kind','PROFILE_UPDATE_PASS_POLICY','authority','SUPABASE',
    'applies_to_operation_code','ACTUALIZACION_PERFIL_LF',
    'distribution_contract',jsonb_build_object(
      'modes',jsonb_build_array('ROUTER','DIRECT'),'snapshot_view','public.v_lf_operation_policy_snapshot',
      'required_fields',jsonb_build_array('policy_code','policy_version','policy_sha','policy_payload'),
      'precedent_usage','EVIDENCE_ONLY_NOT_AUTHORITY'
    ),
    'required_steps',jsonb_build_array(
      'init_execution','router','profile_resolve','baseline_read','change_scope','regression_plan','pre_write_execution_binding_gate',
      'github_write','github_readback','deterministic_validation','semantic_judge','regression_after','close','report_output'
    ),
    'required_behaviors',jsonb_build_object(
      'ekb_first',true,'policy_snapshot_before_write',true,'execution_binding_before_write',true,'branch_from_exact_main',true,
      'minimal_patch',true,'github_readback_exact_head',true,'deterministic_validation',true,'semantic_judge',true,
      'adversarial_and_holdout',true,'router_direct_consistency',true,'all_required_ci_success_exact_head',true,
      'pre_merge_main_reread',true,'pre_merge_policy_reread',true,'force_push_for_base_drift_forbidden',true,
      'post_merge_readback',true,'ekb_close',true,'automatic_runtime_promotion',false
    ),
    'blocking_rules',jsonb_build_array(
      'BLOCK_PROFILE_UPDATE_POLICY_MISSING','BLOCK_PROFILE_UPDATE_POLICY_SHA_MISMATCH','BLOCK_STALE_PROFILE_UPDATE_POLICY',
      'BLOCK_WRITE_BEFORE_BINDING','BLOCK_INCOMPLETE_EVIDENCE','BLOCK_SEMANTIC_REGRESSION','BLOCK_ROUTER_DIRECT_DIVERGENCE'
    ),
    'stale_policy_action','BLOCK_STALE_PROFILE_UPDATE_POLICY',
    'precedent_rule','PRs are historical evidence only; never an operational source of truth'
  ) as payload
)
insert into public.lf_policy_versions (
  policy_code,policy_version,policy_payload,policy_sha,status,effective_at,source_ref,created_by_execution_id,updated_by_execution_id
)
select 'POL-PROFILE-UPDATE-PASS','v1.0',payload,
  encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),'ACTIVE',now(),'GOV-036',
  'EXEC-GOV-036-POLICY-INVENTORY-20260827-001','EXEC-GOV-036-POLICY-INVENTORY-20260827-001'
from p
where not exists (select 1 from public.lf_policy_versions where policy_code='POL-PROFILE-UPDATE-PASS' and policy_version='v1.0');

insert into public.lf_operation_policy_bindings (
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,created_by_execution_id,updated_by_execution_id
)
values ('ACTUALIZACION_PERFIL_LF','POL-PROFILE-UPDATE-PASS','PASS_POLICY',true,array['ROUTER','DIRECT']::text[],'ACTIVE',
  'EXEC-GOV-036-POLICY-INVENTORY-20260827-001','EXEC-GOV-036-POLICY-INVENTORY-20260827-001')
on conflict (operation_code,policy_code,policy_role) do update set
  required=excluded.required,distribution_modes=excluded.distribution_modes,binding_status=excluded.binding_status,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=now();

insert into public.lf_activo_relaciones (
  codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,migration_batch_id,created_by_execution_id,updated_by_execution_id,updated_at
)
select 'ACT-0001','POL-PROFILE-UPDATE-PASS','DISTRIBUYE_POLICY','ACTUALIZACION_PERFIL_LF','SUPABASE_DIRECT_INVENTORY',
  '11111111-1111-4111-8111-000000000002'::uuid,'EXEC-GOV-036-POLICY-INVENTORY-20260827-001',
  'EXEC-GOV-036-POLICY-INVENTORY-20260827-001',now()
where not exists (select 1 from public.lf_activo_relaciones where codigo_activo='ACT-0001' and relacionado_codigo='POL-PROFILE-UPDATE-PASS' and relacion_tipo='DISTRIBUYE_POLICY');

update public.lf_activos
set metadata = metadata || jsonb_build_object(
  'operation_policy_resolution',jsonb_build_object(
    'snapshot_view','public.v_lf_operation_policy_snapshot','required_for_profile_update',true,
    'policy_code','POL-PROFILE-UPDATE-PASS','distribution_modes',jsonb_build_array('ROUTER','DIRECT'),
    'precedents_are_authority',false,'missing_policy_action','BLOCK_PROFILE_UPDATE_POLICY_MISSING',
    'stale_policy_action','BLOCK_STALE_PROFILE_UPDATE_POLICY'
  )
), updated_by_execution_id='EXEC-GOV-036-POLICY-INVENTORY-20260827-001', updated_at=now()
where codigo_activo='ACT-0001';

update public.lf_operation_registry
set source_paths = case
    when not (coalesce(source_paths,'[]'::jsonb) @> '["public.v_lf_operation_policy_snapshot"]'::jsonb)
      then coalesce(source_paths,'[]'::jsonb) || '"public.v_lf_operation_policy_snapshot"'::jsonb
    else source_paths
  end,
  notes = case when coalesce(notes,'') not like '%GOV-036: policy de pase versionada%'
    then coalesce(notes,'') || ' | GOV-036: policy de pase versionada se resuelve desde public.v_lf_operation_policy_snapshot; PRs son evidencia, no autoridad.'
    else notes end,
  updated_by_execution_id='EXEC-GOV-036-POLICY-INVENTORY-20260827-001',updated_at=now()
where operation_code='ACTUALIZACION_PERFIL_LF';
