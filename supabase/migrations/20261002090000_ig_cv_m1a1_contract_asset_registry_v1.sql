-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M1.A1 / PAULO-016
-- R16 Git-first candidate. Registers the three canonical Input Governance
-- contract snapshots already frozen in Git and materializes their governing
-- source relationship for the existing Input Governance Agent asset.
-- No runtime/deploy/production activation.

do $$
declare
  v_execution_id constant text := 'CHATGPT-IG-CV-M1A1-ASSET-REGISTRY-R16-20261002';
  v_batch constant uuid := '1b81352f-51b6-48d2-a52d-009d4e48d178'::uuid;
  v_readiness constant text := 'docs/input-governance/contracts/input_readiness_contract_v5_13.json';
  v_freshness constant text := 'docs/input-governance/contracts/input_freshness_delta_contract_v1_0.json';
  v_execution constant text := 'docs/input-governance/contracts/input_governance_execution_contract_v1_5.json';
  v_count integer;
begin
  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and archived_at is null
  ) then
    raise exception 'BLOCK_M1A1_INPUT_GOVERNANCE_AGENT_ASSET_MISSING';
  end if;

  if exists (
    select 1 from public.lf_activos
    where codigo_activo in (
      'INPUT_READINESS_CONTRACT',
      'INPUT_FRESHNESS_DELTA_CONTRACT',
      'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    )
      and archived_at is null
  ) then
    raise exception 'BLOCK_M1A1_CONTRACT_ASSET_ALREADY_EXISTS_REVALIDATE';
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
    rol_arquitectura,
    source_spreadsheet_id,
    source_spreadsheet_title,
    source_sheet_name,
    source_row_number,
    raw_payload,
    metadata,
    migration_batch_id,
    created_by_execution_id,
    updated_by_execution_id
  ) values
  (
    'INPUT_READINESS_CONTRACT',
    'INPUT_READINESS_CONTRACT',
    'CONTRACT',
    'GOVERNANCE',
    'GITHUB_CONTRACT',
    'CANDIDATE_READ_ONLY',
    'CANDIDATO',
    'READ_ONLY',
    'BLOQUEADO',
    '5.13',
    v_readiness,
    'LF_GOVERNANCE',
    'Canonical Input Governance readiness contract snapshot; authority remains programacion.contratos id=37/version_id=19.',
    'NATIVE_SUPABASE',
    'LF_INPUT_GOVERNANCE_CONTRACT_INVENTORY',
    'M1_A1_CONTRACT_FREEZE_20261002',
    1,
    jsonb_build_object(
      'source_contract_id',37,
      'source_version_id',19,
      'contract_revision','5.13',
      'canonical_authority','programacion.contratos',
      'db_sha256','95a6a97ae457c3a11f494f840770a00dfec3fc547c5e553f73d2c0d4292e9df3',
      'git_blob_sha','8531ae2dc9f5ed65ed5fea6fc27df01ff1f42bb7',
      'git_path',v_readiness
    ),
    jsonb_build_object(
      'schema_version','IG_M1A1_CONTRACT_ASSET_METADATA_V1',
      'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','M1.A1',
      'work_code','PAULO-016',
      'source_pack','SOURCE_PACK_LOOKUP_V2',
      'runtime_authorized',false,
      'production_authorized',false
    ),
    v_batch,
    v_execution_id,
    v_execution_id
  ),
  (
    'INPUT_FRESHNESS_DELTA_CONTRACT',
    'INPUT_FRESHNESS_DELTA_CONTRACT',
    'CONTRACT',
    'TRACEABILITY_PROJECTION',
    'GITHUB_CONTRACT',
    'CANDIDATE_READ_ONLY',
    'CANDIDATO',
    'READ_ONLY',
    'BLOQUEADO',
    '1.0',
    v_freshness,
    'LF_GOVERNANCE',
    'Canonical Input Governance freshness-delta contract snapshot; authority remains programacion.contratos id=39/version_id=19.',
    'NATIVE_SUPABASE',
    'LF_INPUT_GOVERNANCE_CONTRACT_INVENTORY',
    'M1_A1_CONTRACT_FREEZE_20261002',
    2,
    jsonb_build_object(
      'source_contract_id',39,
      'source_version_id',19,
      'contract_revision','1.0',
      'canonical_authority','programacion.contratos',
      'db_sha256','726fe44d0c205898614f9385ad18f7097efaceb217515e74cdafa31cc816d10b',
      'git_blob_sha','e57e2c4952129d70afb8764170b2f15ab2ba205b',
      'git_path',v_freshness
    ),
    jsonb_build_object(
      'schema_version','IG_M1A1_CONTRACT_ASSET_METADATA_V1',
      'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','M1.A1',
      'work_code','PAULO-016',
      'source_pack','SOURCE_PACK_LOOKUP_V2',
      'runtime_authorized',false,
      'production_authorized',false
    ),
    v_batch,
    v_execution_id,
    v_execution_id
  ),
  (
    'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
    'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
    'CONTRACT',
    'EXECUTION_INTERFACE',
    'GITHUB_CONTRACT',
    'CANDIDATE_READ_ONLY',
    'CANDIDATO',
    'READ_ONLY',
    'BLOQUEADO',
    '1.5',
    v_execution,
    'LF_GOVERNANCE',
    'Canonical Input Governance execution contract snapshot; authority remains programacion.contratos id=42/version_id=19.',
    'NATIVE_SUPABASE',
    'LF_INPUT_GOVERNANCE_CONTRACT_INVENTORY',
    'M1_A1_CONTRACT_FREEZE_20261002',
    3,
    jsonb_build_object(
      'source_contract_id',42,
      'source_version_id',19,
      'contract_revision','1.5',
      'canonical_authority','programacion.contratos',
      'db_sha256','ab7c197996dc3985a8214ac4a6c2a2ae825449dd57473754ceddcb15ce71049f',
      'git_blob_sha','3b43c6d979a53fb68914e7c0c6335bdc0f605387',
      'git_path',v_execution
    ),
    jsonb_build_object(
      'schema_version','IG_M1A1_CONTRACT_ASSET_METADATA_V1',
      'plan_id','IG_CURATOR_VALIDATOR_REFACTOR_V2',
      'unit_code','M1.A1',
      'work_code','PAULO-016',
      'source_pack','SOURCE_PACK_LOOKUP_V2',
      'runtime_authorized',false,
      'production_authorized',false
    ),
    v_batch,
    v_execution_id,
    v_execution_id
  );

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
      'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'INPUT_READINESS_CONTRACT',
      'FUENTE_RECTORA',
      'programacion.contratos id=37 version_id=19 revision=5.13; frozen Git snapshot for governed consumption',
      v_readiness,
      v_batch,
      v_execution_id,
      v_execution_id
    ),
    (
      'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'INPUT_FRESHNESS_DELTA_CONTRACT',
      'FUENTE_RECTORA',
      'programacion.contratos id=39 version_id=19 revision=1.0; frozen Git snapshot for governed consumption',
      v_freshness,
      v_batch,
      v_execution_id,
      v_execution_id
    ),
    (
      'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
      'INPUT_GOVERNANCE_EXECUTION_CONTRACT',
      'FUENTE_RECTORA',
      'programacion.contratos id=42 version_id=19 revision=1.5; frozen Git snapshot for governed consumption',
      v_execution,
      v_batch,
      v_execution_id,
      v_execution_id
    );

  select count(*) into v_count
  from public.lf_activos
  where codigo_activo in (
    'INPUT_READINESS_CONTRACT',
    'INPUT_FRESHNESS_DELTA_CONTRACT',
    'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
  )
    and migration_batch_id=v_batch
    and archived_at is null;
  if v_count <> 3 then
    raise exception 'BLOCK_M1A1_CONTRACT_ASSET_COUNT:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_activo_relaciones
  where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and relacionado_codigo in (
      'INPUT_READINESS_CONTRACT',
      'INPUT_FRESHNESS_DELTA_CONTRACT',
      'INPUT_GOVERNANCE_EXECUTION_CONTRACT'
    )
    and relacion_tipo='FUENTE_RECTORA'
    and migration_batch_id=v_batch;
  if v_count <> 3 then
    raise exception 'BLOCK_M1A1_CONTRACT_RELATION_COUNT:%', v_count;
  end if;
end $$;
