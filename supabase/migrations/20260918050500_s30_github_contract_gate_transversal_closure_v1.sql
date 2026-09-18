-- S30 transversal operational closure contract v1.
-- Makes GITHUB_CONTRACT_GATE_LF / lf-contract-check a current shared asset and
-- strengthens the existing OPERATION_LIFECYCLE policy so PASS_CLOSED cannot be
-- claimed without active inventory + indexed README + readback.
--
-- Reuses:
--   public.lf_activos
--   public.lf_policy_versions
--   public.v_lf_operation_policy_snapshot
--   existing Validate LF Packs / lf-contract-check validators.
-- No new policy engine, close engine, registry, or Router is introduced.

begin;

do $migration$
declare
  v_execution_id text := 'EXEC-S30-GITHUB-CONTRACT-GATE-TRANSVERSAL-CLOSURE-20260918-001';
  v_inventory_batch uuid := '9f3fc914-8dbe-4eab-a87b-6ffcb0b0ec51'::uuid;
  v_policy jsonb;
  v_policy_sha text;
  v_old_count integer;
  v_old_version text;
  v_snapshot_count integer;
begin
  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='GITHUB_CONTRACT_GATE_LF'
      and lifecycle_state_code='OP_OPERATIONAL'
  ) then
    raise exception 'BLOCK_GITHUB_CONTRACT_GATE_OPERATION_NOT_OPERATIONAL';
  end if;

  select count(*), min(policy_version)
    into v_old_count,v_old_version
  from public.lf_policy_versions
  where policy_code='POL-LF-OPERATION-LIFECYCLE'
    and status='ACTIVE';

  if v_old_count<>1 or v_old_version<>'v1.0' then
    raise exception 'BLOCK_OPERATION_LIFECYCLE_POLICY_PRESTATE expected=v1.0 count=% actual=%',
      v_old_count,v_old_version;
  end if;

  if exists (
    select 1
    from public.lf_policy_versions
    where policy_code='POL-LF-OPERATION-LIFECYCLE'
      and policy_version='v1.1-operational-closure'
  ) then
    raise exception 'BLOCK_OPERATION_LIFECYCLE_POLICY_V11_ALREADY_EXISTS';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    formato_nativo,linea_codigo,estado_original,estado_documental,estado_operativo,
    nivel_control,runtime_estado,impacto_automatico,accion_migracion,version,
    ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    'GITHUB_CONTRACT_GATE_LF',
    'TRANSVERSAL_GITHUB_CONTRACT_GATE_LF',
    'CAPABILITY',
    'TRANSVERSAL_ORCHESTRATOR',
    'YAML+PYTHON+JSON',
    'LF',
    'ACTIVE_SHARED_ENFORCEMENT',
    'VIGENTE',
    'ACTIVO',
    'TRANSVERSAL',
    'REPOSITORY_BOUND',
    'BLOQUEADO',
    'REGISTER_TRANSVERSAL_CONSUMER',
    'v0.4',
    '.github/workflows/lf-contract-check.yml',
    'github://cristhianlujan/claude-persona-lf-patch/.github/workflows/lf-contract-check.yml',
    'LF_GOVERNANCE_S30',
    '2026-09-18',
    'Consumer/orchestrator transversal de contract-check; delega ejecución a engines compartidos y no duplica gates.',
    'NATIVE_SUPABASE',
    'LF_TRANSVERSAL_CAPABILITY_INVENTORY',
    'S30_GITHUB_CONTRACT_GATE_20260918',
    1,
    v_inventory_batch,
    jsonb_build_object(
      'aliases',jsonb_build_array('LF_CONTRACT_CHECK','lf-contract-check'),
      'operation_code','GITHUB_CONTRACT_GATE_LF',
      'consumer_manifest','sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_contract_check_control_manifest_v1.json'
    ),
    jsonb_build_object(
      'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
      'aliases',jsonb_build_array('LF_CONTRACT_CHECK','lf-contract-check'),
      'transversal_inventory',jsonb_build_object(
        'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
        'logical_key','GITHUB_CONTRACT_GATE_LF',
        'class','ORCHESTRATOR_CONSUMER',
        'inventory_status','ACTIVE_SHARED_ENFORCEMENT',
        'lookup_rule','ASSET_INVENTORY_FIRST_THEN_CURRENTNESS_THEN_EXPAND_SEARCH',
        'documentation',jsonb_build_object(
          'status','SOURCE_FIRST_BOUND',
          'repo','cristhianlujan/claude-persona-lf-patch',
          'readme_ref','sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md',
          'contract_version','lf-transversal-readme-contract/v2'
        ),
        'physical_assets',jsonb_build_array(
          '.github/workflows/lf-contract-check.yml',
          'scripts/lf_contract_check.py',
          'sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_ci_lane_router.py',
          'sandbox/lf_contract_gate_test/s28_ci_lane_router/lf_contract_check_control_manifest_v1.json',
          'sandbox/lf_contract_gate_test/gate_check_observability/run_gate_groups_v1.py',
          'sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md'
        ),
        'consumers_known',jsonb_build_array('GITHUB_PULL_REQUEST_CI'),
        'no_duplicate_engine',true,
        'inventory_execution_id',v_execution_id
      )
    ),
    v_execution_id,
    v_execution_id
  )
  on conflict (codigo_activo) do update
  set
    nombre_canonico=excluded.nombre_canonico,
    tipo_activo=excluded.tipo_activo,
    subtipo_activo=excluded.subtipo_activo,
    formato_nativo=excluded.formato_nativo,
    linea_codigo=excluded.linea_codigo,
    estado_original=excluded.estado_original,
    estado_documental=excluded.estado_documental,
    estado_operativo=excluded.estado_operativo,
    nivel_control=excluded.nivel_control,
    runtime_estado=excluded.runtime_estado,
    impacto_automatico=excluded.impacto_automatico,
    accion_migracion=excluded.accion_migracion,
    version=excluded.version,
    ruta_esperada=excluded.ruta_esperada,
    url=excluded.url,
    owner_name=excluded.owner_name,
    ultima_revision=excluded.ultima_revision,
    rol_arquitectura=excluded.rol_arquitectura,
    raw_payload=excluded.raw_payload,
    metadata=excluded.metadata,
    archived_at=null,
    archived_reason=null,
    updated_by_execution_id=v_execution_id;

  update public.lf_policy_versions
  set
    status='SUPERSEDED',
    superseded_at=clock_timestamp(),
    updated_at=clock_timestamp(),
    updated_by_execution_id=v_execution_id
  where policy_code='POL-LF-OPERATION-LIFECYCLE'
    and status='ACTIVE';

  v_policy:=jsonb_build_object(
    'rules',jsonb_build_array(
      'FAIL_CLOSED_IF_ANY_REQUIRED_LIFECYCLE_LAYER_MISSING',
      'NO_AUTHORITY_INFERENCE_FROM_SINGLE_STATE_DIMENSION',
      'CANONICAL_OPERATION_CODE_BEFORE_FREE_SEARCH',
      'READBACK_REQUIRED_BEFORE_CLOSE',
      'NO_BINDING_OR_MASSIFICATION_WITHOUT_QUALITY_PERFORMANCE_GOVERNANCE_PASS',
      'TRANSVERSAL_ASSET_MUST_BE_ACTIVE_BEFORE_PASS_CLOSED',
      'TRANSVERSAL_README_MUST_BE_INDEXED_BEFORE_PASS_CLOSED',
      'BIDIRECTIONAL_ASSET_README_READBACK_REQUIRED_BEFORE_CLOSE'
    ),
    'scope','TRANSVERSAL_LF_GOVERNANCE',
    'version','v1.1-operational-closure',
    'authority','ACT-0001_SUPABASE',
    'principle','DETERMINISTIC_FIRST_LLM_LAST',
    'policy_kind','OPERATION_LIFECYCLE_POLICY',
    'minimum_lifecycle',jsonb_build_array(
      'CURRENT_OPERATION_REGISTRY',
      'ACTIVE_ROUTER_MAPPING',
      'ACTIVE_ENFORCEMENT_CONTRACT',
      'ACTIVE_STEP_CONTRACT'
    ),
    'closure_requirements',jsonb_build_object(
      'asset_registry','public.lf_activos',
      'required_asset_state','ACTIVO',
      'transversal_inventory_status','ACTIVE_SHARED_ENFORCEMENT',
      'readme_contract','lf-transversal-readme-contract/v2',
      'readme_index','sandbox/lf_contract_gate_test/transversal_assets/README.md',
      'validator','sandbox/lf_contract_gate_test/transversal_asset_readme/validate_active_shared_readmes_v1.py',
      'required_readback',true
    )
  );
  v_policy_sha:=encode(
    extensions.digest(convert_to(v_policy::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into public.lf_policy_versions(
    policy_code,policy_version,policy_payload,policy_sha,status,effective_at,
    source_ref,created_by_execution_id,updated_by_execution_id
  ) values (
    'POL-LF-OPERATION-LIFECYCLE',
    'v1.1-operational-closure',
    v_policy,
    v_policy_sha,
    'ACTIVE',
    clock_timestamp(),
    'supabase/migrations/20260918050500_s30_github_contract_gate_transversal_closure_v1.sql',
    v_execution_id,
    v_execution_id
  );

  update public.lf_activos
  set
    version='v1.1-operational-closure',
    metadata=jsonb_set(
      metadata,
      '{transversal_inventory,physical_assets}',
      jsonb_build_array(
        'POL-LF-OPERATION-LIFECYCLE:v1.1-operational-closure',
        'public.v_lf_operation_policy_snapshot',
        'sandbox/lf_contract_gate_test/transversal_asset_readme/validate_active_shared_readmes_v1.py'
      ),
      true
    ),
    updated_by_execution_id=v_execution_id
  where codigo_activo='POL-LF-OPERATION-LIFECYCLE';

  if not exists (
    select 1
    from public.lf_activos
    where codigo_activo='GITHUB_CONTRACT_GATE_LF'
      and archived_at is null
      and estado_operativo='ACTIVO'
      and metadata #>> '{transversal_inventory,inventory_status}'='ACTIVE_SHARED_ENFORCEMENT'
      and metadata #>> '{transversal_inventory,documentation,readme_ref}'=
          'sandbox/lf_contract_gate_test/transversal_assets/github_contract_gate_lf/README.md'
  ) then
    raise exception 'BLOCK_GITHUB_CONTRACT_GATE_ACTIVE_ASSET_READBACK';
  end if;

  if (
    select count(*)
    from public.lf_policy_versions
    where policy_code='POL-LF-OPERATION-LIFECYCLE'
      and status='ACTIVE'
      and policy_version='v1.1-operational-closure'
      and policy_sha=v_policy_sha
  )<>1 then
    raise exception 'BLOCK_OPERATION_LIFECYCLE_POLICY_V11_READBACK';
  end if;

  select count(*)
    into v_snapshot_count
  from public.v_lf_operation_policy_snapshot
  where operation_code='GITHUB_CONTRACT_GATE_LF'
    and policy_code='POL-LF-OPERATION-LIFECYCLE'
    and policy_version='v1.1-operational-closure'
    and policy_sha=v_policy_sha
    and required=true;

  if v_snapshot_count<>1 then
    raise exception 'BLOCK_GITHUB_CONTRACT_GATE_POLICY_SNAPSHOT_READBACK count=%',
      v_snapshot_count;
  end if;
end
$migration$;

commit;
