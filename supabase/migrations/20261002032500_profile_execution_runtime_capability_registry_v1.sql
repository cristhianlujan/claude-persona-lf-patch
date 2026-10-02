-- PROFILE_EXECUTION_RUNTIME capability registry projection.
-- Registry/currentness identity only. No runtime, carrier, production or queue cutover.

do $profile_runtime_capability$
declare
  v_execution_id constant text := 'EXEC-PROFILE-EXECUTION-RUNTIME-CAPABILITY-REGISTER-20261002-001';
  v_capability_code constant text := 'PROFILE_EXECUTION_RUNTIME';
  v_version constant text := '1.0.0';
  v_source_sha constant text := '3fc0626396b64e1aac6375534b1cb3cadda1e4db';
  v_target_path constant text := 'supabase/migrations/20261002032500_profile_execution_runtime_capability_registry_v1.sql';
  v_batch uuid := gen_random_uuid();
  v_manifest jsonb := $manifest${
    "schema_version":"LF_CAPABILITY_MANIFEST_V1",
    "capability_code":"PROFILE_EXECUTION_RUNTIME",
    "version":"1.0.0",
    "contract":{
      "authority":"LOGICAL_CAPABILITY_IDENTITY_OVER_EXISTING_EJECUCION_PERFIL_LF_RUNTIME_LANE",
      "entry_guard":"ORCHESTRATOR_EXECUTION_GUARD_V1",
      "direct_or_unorchestrated_new_binding_policy":"BLOCK"
    },
    "implementation":{
      "operation_code":"EJECUCION_PERFIL_LF",
      "begin_rpc":"public.lf_profile_execution_begin_v1",
      "queue":"private.lf_profile_runtime_queue_v1",
      "runtime_source":"services/profile_runtime_api",
      "new_runtime_engine":false,
      "new_queue":false,
      "new_operation":false
    },
    "dependencies":{
      "capabilities":["CURRENTNESS_AUTHORITY"],
      "governance":["ACT-0001","ORCHESTRATOR_EXECUTION_GUARD_V1"],
      "operation":"EJECUCION_PERFIL_LF"
    },
    "source_contract":{
      "ref":"sandbox/lf_contract_gate_test/profile_execution_runtime_capability/profile_execution_runtime_capability_v1.json",
      "docs":"sandbox/lf_contract_gate_test/profile_execution_runtime_capability/README.md",
      "validator":"sandbox/lf_contract_gate_test/profile_execution_runtime_capability/validate_profile_execution_runtime_capability_v1.py"
    },
    "currentness":{
      "authority_capability":"CURRENTNESS_AUTHORITY",
      "authority_ref":"github://cristhianlujan/claude-persona-lf-patch@3fc0626396b64e1aac6375534b1cb3cadda1e4db",
      "source_revision_immutable":true,
      "runtime_activation_authorized":false,
      "production_authorized":false,
      "automatic_impact_authorized":false,
      "task_bound_story_cutover_authorized":false
    },
    "known_blockers_before_story_cutover":[
      "Story embedded Profile asset/currentness bindings",
      "PROFILE_TASK_RUNTIME_BINDING_V1 materialization",
      "PROFILE_RUNTIME_ORCHESTRATED_ATTACH_V1 worker wiring",
      "ORQUESTACION_SKILL_LF qualification"
    ]
  }$manifest$::jsonb;
  v_manifest_sha text;
  v_promotion jsonb;
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='PROFILE_EXECUTION_RUNTIME_CAPABILITY_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path=v_target_path
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_EXECUTION_BINDING';
  end if;

  if to_regprocedure('public.fn_lf_capability_promote_v1(text,text,text,text,text)') is null then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_PROMOTER_MISSING';
  end if;
  if to_regprocedure('public.lf_profile_execution_begin_v1(text,text,text,text,text,text,text,jsonb)') is null then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_BEGIN_RPC_MISSING';
  end if;
  if to_regclass('private.lf_profile_runtime_queue_v1') is null then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_QUEUE_MISSING';
  end if;
  if not exists (
    select 1 from public.lf_operation_registry
    where operation_code='EJECUCION_PERFIL_LF'
      and status in ('CANDIDATO_READ_ONLY','ACTIVE','VIGENTE','APROBADO_PRODUCCION_CONTROLADA','APROBADO_PRODUCCION_CONTROLADA_READ_ONLY')
  ) then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_OPERATION_MISSING';
  end if;
  if not exists (
    select 1
    from public.lf_capability_registry r
    join public.lf_capability_current c using (capability_code)
    join public.lf_capability_version_registry v
      on v.capability_code=c.capability_code and v.version=c.version
    where r.capability_code='CURRENTNESS_AUTHORITY'
      and r.status='ACTIVE'
      and v.release_state='RELEASED'
      and v.manifest_sha256=c.manifest_sha256
  ) then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_CURRENTNESS_NOT_CURRENT';
  end if;

  if exists(select 1 from public.lf_capability_registry where capability_code=v_capability_code)
     or exists(select 1 from public.lf_capability_version_registry where capability_code=v_capability_code)
     or exists(select 1 from public.lf_capability_current where capability_code=v_capability_code)
     or exists(select 1 from public.lf_activos where codigo_activo=v_capability_code and archived_at is null) then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_PREEXISTING_STATE';
  end if;

  insert into public.lf_capability_registry(
    capability_code,capability_name,capability_kind,owner_scope,status,description,
    created_by_execution_id,updated_by_execution_id,entry_guard_required,entry_guard_code
  ) values (
    v_capability_code,'Profile Execution Runtime','TRANSVERSAL_RUNTIME_LANE','LF_GOVERNANCE','ACTIVE',
    'Logical governed capability identity for the existing EJECUCION_PERFIL_LF runtime lane. Registration does not activate runtime, production, automatic impact or Story task-bound cutover.',
    v_execution_id,v_execution_id,true,'ORCHESTRATOR_EXECUTION_GUARD_V1'
  );

  v_manifest_sha := encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');

  insert into public.lf_capability_version_registry(
    capability_code,version,version_major,version_minor,version_patch,release_state,
    supersedes_version,manifest,manifest_sha256,source_ref,docs_ref,validator_ref,created_by_execution_id
  ) values (
    v_capability_code,v_version,1,0,0,'RELEASED',null,v_manifest,v_manifest_sha,
    'github://cristhianlujan/claude-persona-lf-patch@3fc0626396b64e1aac6375534b1cb3cadda1e4db/sandbox/lf_contract_gate_test/profile_execution_runtime_capability/profile_execution_runtime_capability_v1.json',
    'github://cristhianlujan/claude-persona-lf-patch@3fc0626396b64e1aac6375534b1cb3cadda1e4db/sandbox/lf_contract_gate_test/profile_execution_runtime_capability/README.md',
    'github://cristhianlujan/claude-persona-lf-patch@3fc0626396b64e1aac6375534b1cb3cadda1e4db/sandbox/lf_contract_gate_test/profile_execution_runtime_capability/validate_profile_execution_runtime_capability_v1.py',
    v_execution_id
  );

  v_promotion := public.fn_lf_capability_promote_v1(
    v_capability_code,v_version,null,v_execution_id,
    'Register logical current PROFILE_EXECUTION_RUNTIME identity over existing runtime lane; no task-bound cutover'
  );
  if coalesce((v_promotion->>'ready')::boolean,false) is not true then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_CURRENT_PROMOTION:%',v_promotion::text;
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_capability_code,'TRANSVERSAL_PROFILE_EXECUTION_RUNTIME','CAPABILITY','TRANSVERSAL_RUNTIME_LANE',
    'VIGENTE','READ_ONLY','FAIL_CLOSED','NO_HABILITADO','BLOQUEADO',
    v_version,'services/profile_runtime_api',
    'supabase://public/lf_capability_registry/PROFILE_EXECUTION_RUNTIME/1.0.0','LF_GOVERNANCE',
    v_source_sha,'TRANSVERSAL_PROFILE_EXECUTION_RUNTIME',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','PROFILE_EXECUTION_RUNTIME_20261002',1,
    v_batch,
    jsonb_build_object(
      'key',v_capability_code,
      'class','TRANSVERSAL_RUNTIME_LANE',
      'implementation_operation','EJECUCION_PERFIL_LF',
      'source_main_sha',v_source_sha,
      'runtime_activation_authorized',false,
      'production_authorized',false,
      'automatic_impact_authorized',false,
      'story_task_bound_cutover_authorized',false
    ),
    jsonb_build_object(
      'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
      'current_pointer_semantics','CAPABILITY_IDENTITY_ONLY',
      'runtime_lane','EJECUCION_PERFIL_LF',
      'entry_guard_required',true,
      'entry_guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
      'runtime_enabled',false,
      'automatic_impact_enabled',false,
      'inventory_execution_id',v_execution_id
    ),
    v_execution_id,v_execution_id
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    v_capability_code,'CURRENTNESS_AUTHORITY','DEPENDE_DE','CURRENTNESS_AUTHORITY',
    v_target_path,v_batch,v_execution_id,v_execution_id
  );

  if not exists(
    select 1 from public.lf_capability_registry
    where capability_code=v_capability_code and status='ACTIVE'
      and capability_kind='TRANSVERSAL_RUNTIME_LANE'
      and entry_guard_required=true
      and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) then raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_REGISTRY_READBACK'; end if;

  if not exists(
    select 1 from public.lf_capability_current
    where capability_code=v_capability_code and version=v_version and manifest_sha256=v_manifest_sha
  ) then raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_CURRENT_READBACK'; end if;

  if not exists(
    select 1 from public.lf_activos
    where codigo_activo=v_capability_code and archived_at is null
      and estado_operativo='READ_ONLY'
      and runtime_estado='NO_HABILITADO'
      and impacto_automatico='BLOQUEADO'
      and coalesce((metadata->>'runtime_enabled')::boolean,false)=false
  ) then raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_ASSET_READBACK'; end if;

  if (v_manifest #>> '{currentness,runtime_activation_authorized}')::boolean
     or (v_manifest #>> '{currentness,production_authorized}')::boolean
     or (v_manifest #>> '{currentness,automatic_impact_authorized}')::boolean
     or (v_manifest #>> '{currentness,task_bound_story_cutover_authorized}')::boolean then
    raise exception 'BLOCK_PROFILE_EXECUTION_RUNTIME_UNAUTHORIZED_ACTIVATION';
  end if;
end
$profile_runtime_capability$;
