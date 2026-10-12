begin;

-- PACK_VALIDATION_HARNESS v1 registration + versioned external floor.
-- Stage boundary:
--   * registers the already-merged deterministic capability;
--   * materializes POL-PACK-VALIDATION-FLOOR v1.0;
--   * DOES NOT bind the policy to profile operations;
--   * DOES NOT enforce any profile;
--   * DOES NOT authorize runtime or automatic impact.
--
-- Source capability authority:
-- main@718dad1e30c12f6f39745fcf71d72dbd4f6e6880
-- PR #918, exact source already merged and 3/3 CI green.

do $execution_guard$
declare
  v_execution_id constant text := 'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001';
  v_preflight jsonb;
begin
  if not exists (
    select 1
    from public.lf_operation_execution e
    where e.execution_id=v_execution_id
      and e.operation_code='ACTUALIZACION_DB_LF'
      and e.target_type='MIGRATION'
      and e.target_code='PACK_VALIDATION_HARNESS_REGISTRY_POLICY_V1'
      and e.target_repo='cristhianlujan/claude-persona-lf-patch'
      and e.target_path='supabase/migrations/20260919001718_lf_pack_validation_harness_registry_policy_v1.sql'
      and e.status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_GOVERNED_EXECUTION_BINDING:%',v_execution_id;
  end if;

  if not exists (
    select 1
    from public.lf_capability_binding b
    where b.execution_id=v_execution_id
      and b.capability_code='DB_WRITE_TRANSPORT'
      and b.bound_version='1.0.0'
      and b.bound_manifest_sha256='f791ab6d602810bdb534355c754f4b2be79e9985e9d4e721eb2dc987748ba0cd'
      and b.binding_state in ('BOUND','PINNED')
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_DB_WRITE_TRANSPORT_BINDING_MISSING';
  end if;

  v_preflight := public.fn_lf_capability_preflight_v1(v_execution_id,'DB_WRITE_TRANSPORT');
  if coalesce((v_preflight->>'ready')::boolean,false) is not true
     or v_preflight->>'current_version' is distinct from '1.0.0'
     or v_preflight->>'current_manifest_sha256'
          is distinct from 'f791ab6d602810bdb534355c754f4b2be79e9985e9d4e721eb2dc987748ba0cd' then
    raise exception 'BLOCK_PACK_VALIDATION_DB_WRITE_TRANSPORT_PREFLIGHT:%',v_preflight;
  end if;

  if exists (
    select 1 from public.lf_capability_registry
    where capability_code='PACK_VALIDATION_HARNESS'
  ) or exists (
    select 1 from public.lf_capability_version_registry
    where capability_code='PACK_VALIDATION_HARNESS'
  ) or exists (
    select 1 from public.lf_capability_current
    where capability_code='PACK_VALIDATION_HARNESS'
  ) or exists (
    select 1 from public.lf_activos
    where codigo_activo in ('PACK_VALIDATION_HARNESS','POL-PACK-VALIDATION-FLOOR')
      and archived_at is null
  ) or exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-PACK-VALIDATION-FLOOR'
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_PREEXISTING_REGISTRY_STATE';
  end if;
end
$execution_guard$;

insert into public.lf_capability_registry(
  capability_code,
  capability_name,
  capability_kind,
  owner_scope,
  status,
  description,
  created_by_execution_id,
  updated_by_execution_id
) values (
  'PACK_VALIDATION_HARNESS',
  'LF Pack Validation Harness',
  'TRANSVERSAL',
  'LF_GOVERNANCE_S26_PROFILE_VALIDATION',
  'ACTIVE',
  'Deterministic externally-governed profile-pack validation harness. Registration does not imply profile cutover, runtime authorization, semantic promotion, or automatic impact.',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001'
);

with m as (
  select $manifest$
  {
    "schema_version":"LF_CAPABILITY_MANIFEST_V1",
    "capability_code":"PACK_VALIDATION_HARNESS",
    "version":"1.0.0",
    "contract":{
      "input":"LF_PACK_VALIDATION_INPUT_V1",
      "output":"LF_PACK_VALIDATION_RESULT_V1",
      "authority":"DETERMINISTIC_VALIDATION_ONLY_NO_PROFILE_PROMOTION"
    },
    "delivery":{
      "mode":"VERSIONED_REPOSITORY_CAPABILITY",
      "runner":"sandbox/lf_contract_gate_test/pack_validation_harness/pack_validation_harness_v1.py",
      "consumer_state":"REGISTERED_NOT_CUTOVER"
    },
    "installation":{
      "required":false,
      "reinstall_required":false,
      "package_update_mode":"REPOSITORY_BOUND"
    },
    "dependencies":{
      "packages":["python>=3.11"],
      "governance":["ACT-0001","POL-PACK-VALIDATION-FLOOR"],
      "capabilities":[]
    },
    "compatibility":{
      "supported_target_types":["PERFIL"],
      "unknown_target":"FAIL_CLOSED",
      "profile_operation_bindings":"PENDING_CUTOVER"
    },
    "migration":{
      "mode":"REGISTRY_ONLY_NO_RUNTIME_CUTOVER",
      "registration_source":"supabase/migrations/20260919001718_lf_pack_validation_harness_registry_policy_v1.sql"
    },
    "rollback":{
      "supported":true,
      "source_preserved":true,
      "rule":"SEPARATELY_GOVERNED_REGISTRY_POLICY_REVERSAL;NO_PROFILE_RUNTIME_CHANGE"
    },
    "usage":{
      "docs":"sandbox/lf_contract_gate_test/pack_validation_harness/README.md",
      "runner":"sandbox/lf_contract_gate_test/pack_validation_harness/pack_validation_harness_v1.py",
      "self_test":"python sandbox/lf_contract_gate_test/pack_validation_harness/test_pack_validation_harness_v1.py",
      "floor_schema":"sandbox/lf_contract_gate_test/pack_validation_harness/schemas/pack_validation_floor.schema.json",
      "result_schema":"sandbox/lf_contract_gate_test/pack_validation_harness/schemas/pack_validation_result.schema.json"
    },
    "currentness":{
      "authority_ref":"github://cristhianlujan/claude-persona-lf-patch@718dad1e30c12f6f39745fcf71d72dbd4f6e6880",
      "source_revision_immutable":true,
      "policy_authority":"SUPABASE_VERSIONED_POLICY",
      "runtime_authorized":false,
      "automatic_impact_authorized":false,
      "profile_cutover_authorized":false
    }
  }
  $manifest$::jsonb as manifest
)
insert into public.lf_capability_version_registry(
  capability_code,
  version,
  version_major,
  version_minor,
  version_patch,
  release_state,
  supersedes_version,
  manifest,
  manifest_sha256,
  source_ref,
  docs_ref,
  validator_ref,
  created_by_execution_id
)
select
  'PACK_VALIDATION_HARNESS',
  '1.0.0',
  1,0,0,
  'RELEASED',
  null,
  manifest,
  encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex'),
  'github://cristhianlujan/claude-persona-lf-patch@718dad1e30c12f6f39745fcf71d72dbd4f6e6880/sandbox/lf_contract_gate_test/pack_validation_harness/pack_validation_harness_v1.py',
  'github://cristhianlujan/claude-persona-lf-patch@718dad1e30c12f6f39745fcf71d72dbd4f6e6880/sandbox/lf_contract_gate_test/pack_validation_harness/README.md',
  'github://cristhianlujan/claude-persona-lf-patch@718dad1e30c12f6f39745fcf71d72dbd4f6e6880/sandbox/lf_contract_gate_test/pack_validation_harness/test_pack_validation_harness_v1.py',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001'
from m;

do $promote$
declare
  v_result jsonb;
begin
  v_result := public.fn_lf_capability_promote_v1(
    'PACK_VALIDATION_HARNESS',
    '1.0.0',
    null,
    'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001',
    'Register merged source-only harness as current deterministic capability; profile cutover remains blocked.'
  );
  if coalesce((v_result->>'ready')::boolean,false) is not true
     or v_result->>'version' is distinct from '1.0.0' then
    raise exception 'BLOCK_PACK_VALIDATION_CAPABILITY_PROMOTION:%',v_result;
  end if;
end
$promote$;

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,
  estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
  raw_payload,metadata,created_by_execution_id,updated_by_execution_id
) values (
  'PACK_VALIDATION_HARNESS',
  'TRANSVERSAL_PACK_VALIDATION_HARNESS',
  'CAPABILITY',
  'TRANSVERSAL_CAPABILITY_INFRASTRUCTURE',
  'CAPABILITY',
  'PYTHON_JSON_SCHEMA',
  'NUEVO_CANONICO',
  'VIGENTE',
  'READ_ONLY',
  'FAIL_CLOSED',
  'NO_HABILITADO',
  'BLOQUEADO',
  'INVENTARIADO_SUPABASE',
  '1.0.0',
  'sandbox/lf_contract_gate_test/pack_validation_harness/pack_validation_harness_v1.py',
  'supabase://public/lf_capability_registry/PACK_VALIDATION_HARNESS/1.0.0',
  'LF_GOVERNANCE_S26_PROFILE_VALIDATION',
  '2026-09-18',
  'TRANSVERSAL_PACK_VALIDATION_HARNESS',
  'SUPABASE_DIRECT_INVENTORY',
  'LF_SUPABASE_SANDBOX',
  'public.lf_activos',
  0,
  '4414397d-c232-40c5-bffe-fdd829ec7cb8'::uuid,
  jsonb_build_object(
    'key','PACK_VALIDATION_HARNESS',
    'class','CAPABILITY_INFRASTRUCTURE',
    'status','FORMAL_TRANSVERSAL_REGISTERED_NOT_CUTOVER',
    'source_pr',918,
    'source_main_sha','718dad1e30c12f6f39745fcf71d72dbd4f6e6880',
    'runtime_authorized',false,
    'automatic_impact_authorized',false,
    'profile_cutover_authorized',false
  ),
  jsonb_build_object(
    'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
    'transversal_inventory',jsonb_build_object(
      'class','CAPABILITY_INFRASTRUCTURE',
      'schema_version','TRANSVERSAL_ASSET_INDEX_V1',
      'logical_key','PACK_VALIDATION_HARNESS',
      'source_pr',918,
      'source_main_sha','718dad1e30c12f6f39745fcf71d72dbd4f6e6880',
      'inventory_status','FORMAL_TRANSVERSAL_REGISTERED_NOT_CUTOVER',
      'no_duplicate_engine',true,
      'consumers_known',jsonb_build_array('Validate LF Packs self-test only'),
      'consumers_intended',jsonb_build_array('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF'),
      'physical_assets',jsonb_build_array(
        'public.lf_capability_registry:PACK_VALIDATION_HARNESS',
        'public.lf_capability_current:PACK_VALIDATION_HARNESS@1.0.0',
        'sandbox/lf_contract_gate_test/pack_validation_harness/pack_validation_harness_v1.py',
        'sandbox/lf_contract_gate_test/pack_validation_harness/README.md'
      ),
      'inventory_execution_id','EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001'
    )
  ),
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001'
);

insert into public.lf_activos(
  codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,tipo_original,formato_nativo,
  estado_original,estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
  accion_migracion,version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
  source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,migration_batch_id,
  raw_payload,metadata,created_by_execution_id,updated_by_execution_id
) values (
  'POL-PACK-VALIDATION-FLOOR',
  'POL_PACK_VALIDATION_FLOOR_LF',
  'REGLA',
  'POLICY_TRANSVERSAL_GOV',
  'POLICY',
  'SUPABASE_JSONB',
  'NUEVO_CANONICO',
  'VIGENTE',
  'READ_ONLY',
  'GOVERNANCE_ENFORCED',
  'NO_APLICA',
  'BLOQUEADO',
  'INVENTARIADO_SUPABASE',
  'v1.0',
  'Supabase/public/lf_policy_versions/POL-PACK-VALIDATION-FLOOR',
  'supabase://public/lf_policy_versions/POL-PACK-VALIDATION-FLOOR/v1.0',
  'LF_GOVERNANCE_S26_PROFILE_VALIDATION',
  '2026-09-18',
  'External non-producer-controlled validation floor for profile packs',
  'SUPABASE_DIRECT_INVENTORY',
  'LF_SUPABASE_SANDBOX',
  'public.lf_activos',
  0,
  '4414397d-c232-40c5-bffe-fdd829ec7cb8'::uuid,
  jsonb_build_object(
    'key','POL-PACK-VALIDATION-FLOOR',
    'class','POLICY',
    'binding_state','PENDING_CUTOVER',
    'runtime_authorized',false,
    'automatic_impact_authorized',false,
    'profile_cutover_authorized',false
  ),
  jsonb_build_object(
    'policy_kind','PACK_VALIDATION_FLOOR_POLICY',
    'canonical_policy_store','public.lf_policy_versions',
    'operation_binding_store','public.lf_operation_policy_bindings',
    'snapshot_view','public.v_lf_operation_policy_snapshot',
    'harness_capability','PACK_VALIDATION_HARNESS',
    'intended_operations',jsonb_build_array('CREACION_PERFIL_LF','ACTUALIZACION_PERFIL_LF'),
    'binding_state','PENDING_CUTOVER',
    'cutover_authorized',false,
    'transversal',false,
    'router_required',false,
    'source_pr',918,
    'source_main_sha','718dad1e30c12f6f39745fcf71d72dbd4f6e6880',
    'precedents_are_authority',false
  ),
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001'
);

with p as (
  select $policy$
  {
    "schema":"LF_PACK_VALIDATION_FLOOR_V1",
    "requirements":{
      "inventory_reconciliation_required":true,
      "direct_suite_execution_required":true,
      "external_holdout_required_for_enforced":true,
      "hashes_computed_by_harness":true,
      "producer_self_exclusion_forbidden":true,
      "runtime_authorized_false":true,
      "automatic_impact_authorized_false":true
    },
    "profiles":{
      "ACT-0051":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout debt: inventory profile is not materialized on current main; certification cutover not authorized",
        "allow_missing_materialization":true
      },
      "PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-GAMIFICATION-SYSTEM-ARCHITECT":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-PRODUCT-DIRECTOR-LF":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-QUALITY-PACK":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; active profile remediation remains isolated from this registration",
        "allow_missing_materialization":false
      },
      "PERFIL-UI-ARCHITECT":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout: capability and floor registered; profile certification cutover not yet authorized",
        "allow_missing_materialization":false
      },
      "PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531":{
        "enforcement_state":"NOT_ENFORCED",
        "reason":"governed rollout debt: inventory profile is not materialized on current main; certification cutover not authorized",
        "allow_missing_materialization":true
      }
    }
  }
  $policy$::jsonb as payload
)
insert into public.lf_policy_versions(
  policy_code,
  policy_version,
  policy_payload,
  policy_sha,
  status,
  effective_at,
  source_ref,
  created_by_execution_id,
  updated_by_execution_id
)
select
  'POL-PACK-VALIDATION-FLOOR',
  'v1.0',
  payload,
  encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
  'ACTIVE',
  clock_timestamp(),
  'supabase/migrations/20260919001718_lf_pack_validation_harness_registry_policy_v1.sql',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001',
  'EXEC-S26-PACK-VALIDATION-HARNESS-REGISTER-20260918-001'
from p;

-- Stage boundary is fail-closed: this migration MUST NOT distribute the
-- policy to profile operations. Distribution is a later cutover.
do $readback$
declare
  v_manifest_sha text;
  v_policy public.lf_policy_versions%rowtype;
  v_profile_count integer;
  v_enforced_count integer;
  v_missing_allowed text[];
begin
  select c.manifest_sha256
  into v_manifest_sha
  from public.lf_capability_current c
  join public.lf_capability_version_registry v
    on v.capability_code=c.capability_code
   and v.version=c.version
   and v.manifest_sha256=c.manifest_sha256
  where c.capability_code='PACK_VALIDATION_HARNESS'
    and c.version='1.0.0'
    and v.release_state='RELEASED';

  if v_manifest_sha is null then
    raise exception 'BLOCK_PACK_VALIDATION_CAPABILITY_CURRENT_READBACK';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='PACK_VALIDATION_HARNESS'
      and estado_documental='VIGENTE'
      and estado_operativo='READ_ONLY'
      and runtime_estado='NO_HABILITADO'
      and impacto_automatico='BLOQUEADO'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_CAPABILITY_ASSET_READBACK';
  end if;

  select * into v_policy
  from public.lf_policy_versions
  where policy_code='POL-PACK-VALIDATION-FLOOR'
    and policy_version='v1.0'
    and status='ACTIVE';

  if not found
     or v_policy.policy_sha is distinct from
       encode(extensions.digest(convert_to(v_policy.policy_payload::text,'UTF8'),'sha256'),'hex')
     or v_policy.policy_payload->>'schema' is distinct from 'LF_PACK_VALIDATION_FLOOR_V1'
     or v_policy.policy_payload #>> '{requirements,inventory_reconciliation_required}' is distinct from 'true'
     or v_policy.policy_payload #>> '{requirements,direct_suite_execution_required}' is distinct from 'true'
     or v_policy.policy_payload #>> '{requirements,external_holdout_required_for_enforced}' is distinct from 'true'
     or v_policy.policy_payload #>> '{requirements,hashes_computed_by_harness}' is distinct from 'true'
     or v_policy.policy_payload #>> '{requirements,producer_self_exclusion_forbidden}' is distinct from 'true'
     or v_policy.policy_payload #>> '{requirements,runtime_authorized_false}' is distinct from 'true'
     or v_policy.policy_payload #>> '{requirements,automatic_impact_authorized_false}' is distinct from 'true' then
    raise exception 'BLOCK_PACK_VALIDATION_POLICY_READBACK';
  end if;

  select count(*),
         count(*) filter (where value->>'enforcement_state'='ENFORCED')
  into v_profile_count,v_enforced_count
  from jsonb_each(v_policy.policy_payload->'profiles');

  if v_profile_count<>10 or v_enforced_count<>0 then
    raise exception 'BLOCK_PACK_VALIDATION_ROLLOUT_STATE profile_count=% enforced=%',
      v_profile_count,v_enforced_count;
  end if;

  select array_agg(key order by key)
  into v_missing_allowed
  from jsonb_each(v_policy.policy_payload->'profiles')
  where coalesce((value->>'allow_missing_materialization')::boolean,false);

  if v_missing_allowed is distinct from array[
    'PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531',
    'PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531'
  ]::text[] then
    raise exception 'BLOCK_PACK_VALIDATION_MISSING_MATERIALIZATION_DEBT:%',v_missing_allowed;
  end if;

  if exists (
    select 1
    from public.lf_operation_policy_bindings
    where policy_code='POL-PACK-VALIDATION-FLOOR'
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_PREMATURE_OPERATION_BINDING';
  end if;

  if exists (
    select 1
    from public.v_lf_operation_policy_snapshot
    where policy_code='POL-PACK-VALIDATION-FLOOR'
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_PREMATURE_POLICY_DISTRIBUTION';
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='POL-PACK-VALIDATION-FLOOR'
      and estado_documental='VIGENTE'
      and estado_operativo='READ_ONLY'
      and runtime_estado='NO_APLICA'
      and impacto_automatico='BLOQUEADO'
      and metadata->>'binding_state'='PENDING_CUTOVER'
      and archived_at is null
  ) then
    raise exception 'BLOCK_PACK_VALIDATION_POLICY_ASSET_READBACK';
  end if;
end
$readback$;

commit;
