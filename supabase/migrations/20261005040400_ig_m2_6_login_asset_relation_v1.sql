-- IG_CURATOR_VALIDATOR_REFACTOR_V2 / M2.6 / PAULO-039
-- LOGIN_ASSET_RELATION only. Registry-only; no runtime change.

begin;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
  estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,url,owner_name,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
  migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
)
select
  'LF_OPS_FN_B2B_BACKOFFICE_LOGIN_CONTRACT',
  'lf_ops.fn_b2b_backoffice_login_contract',
  'CAPABILITY','DB_FUNCTION',
  'CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
  'REGISTER_BOUNDARY_DB_FUNCTION','runtime-current',
  'supabase://lf_ops/fn_b2b_backoffice_login_contract',
  'SUPER_ADMIN',
  'Canonical B2B Backoffice login contract boundary consumed by Input Governance canonical context.',
  'SUPABASE_DIRECT_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
  'IG_CURATOR_VALIDATOR_REFACTOR_V2_M2_6',1,
  'e14f1d14-5d36-4f6c-a01e-1a0f20600001'::uuid,
  jsonb_build_object(
    'signature','lf_ops.fn_b2b_backoffice_login_contract(text,text,text)',
    'boundary_for','INPUT_GOVERNANCE'
  ),
  jsonb_build_object('domain','B2B_BACKOFFICE','unit_code','M2.6','no_duplicate_resolver',true),
  'CHATGPT-IG-CV-M2-6-LOGIN-ASSET-20261004',
  'CHATGPT-IG-CV-M2-6-LOGIN-ASSET-20261004'
where to_regprocedure('lf_ops.fn_b2b_backoffice_login_contract(text,text,text)') is not null
  and not exists (
    select 1 from public.lf_activos
    where codigo_activo='LF_OPS_FN_B2B_BACKOFFICE_LOGIN_CONTRACT'
      and archived_at is null
  );

insert into public.lf_activo_relaciones(
  codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
  migration_batch_id,created_by_execution_id,updated_by_execution_id
)
select
  'PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET',
  'LF_OPS_FN_B2B_BACKOFFICE_LOGIN_CONTRACT',
  'DEPENDE_DE',
  'programacion.fn_input_screen_canonical_graph -> lf_ops.fn_b2b_backoffice_login_contract(text,text,text)',
  'supabase/migrations/20261005040400_ig_m2_6_login_asset_relation_v1.sql',
  'e14f1d14-5d36-4f6c-a01e-1a0f20600001'::uuid,
  'CHATGPT-IG-CV-M2-6-LOGIN-ASSET-20261004',
  'CHATGPT-IG-CV-M2-6-LOGIN-ASSET-20261004'
where exists (
    select 1 from public.lf_activos
    where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
      and archived_at is null
  )
  and exists (
    select 1 from public.lf_activos
    where codigo_activo='LF_OPS_FN_B2B_BACKOFFICE_LOGIN_CONTRACT'
      and archived_at is null
  )
  and not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='PROGRAMACION_FN_INPUT_GOVERNANCE_CANONICAL_CONTEXT_SET'
      and relacionado_codigo='LF_OPS_FN_B2B_BACKOFFICE_LOGIN_CONTRACT'
      and relacion_tipo='DEPENDE_DE'
  );

commit;
