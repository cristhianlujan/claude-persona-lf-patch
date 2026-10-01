-- LF_ASSURANCE_EVALUATOR_INVENTORY_WIRING_V1
-- Discoverability/call-contract projection only.
-- No capability version/current promotion, no subject-binding activation, no evaluator execution,
-- no runtime/deploy/production activation.

do $lf_assurance_evaluator_inventory_wiring$
declare
  v_execution_id constant text := 'EXEC-SADM-ASSURANCE-EVALUATOR-INVENTORY-WIRING-20260930-001';
  v_capability_code constant text := 'ASSURANCE_EVALUATOR';
  v_target_path constant text := 'supabase/migrations/20260930203100_lf_assurance_evaluator_inventory_wiring_v1.sql';
  v_call_contract_ref constant text := 'sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_call_contract_v1.json';
  v_call_contract_sha constant text := '181a1da4553dce73e42a911216c2f3932406be833ec128df3be2f797deb3e305';
  v_inventory_batch uuid := gen_random_uuid();
  v_count integer;
begin
  if not exists (
    select 1 from public.lf_operation_execution
    where execution_id=v_execution_id
      and operation_code='ACTUALIZACION_DB_LF'
      and target_type='MIGRATION'
      and target_code='ASSURANCE_EVALUATOR_INVENTORY_WIRING_V1'
      and target_repo='cristhianlujan/claude-persona-lf-patch'
      and target_path=v_target_path
      and status='IN_PROGRESS'
  ) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_INVENTORY_EXECUTION_BINDING';
  end if;

  if not exists (
    select 1 from public.lf_capability_registry
    where capability_code=v_capability_code
      and capability_kind='TRANSVERSAL'
      and owner_scope='SUPER_ADMIN'
      and status='ACTIVE'
      and entry_guard_required is true
      and entry_guard_code='ORCHESTRATOR_EXECUTION_GUARD_V1'
  ) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_REGISTRY_PRESTATE';
  end if;

  select count(*) into v_count from public.lf_capability_version_registry where capability_code=v_capability_code;
  if v_count <> 0 then raise exception 'BLOCK_ASSURANCE_EVALUATOR_PREMATURE_VERSION:%',v_count; end if;
  select count(*) into v_count from public.lf_capability_current where capability_code=v_capability_code;
  if v_count <> 0 then raise exception 'BLOCK_ASSURANCE_EVALUATOR_PREMATURE_CURRENT:%',v_count; end if;
  select count(*) into v_count from public.lf_assurance_subject_bindings where status='ACTIVE';
  if v_count <> 0 then raise exception 'BLOCK_ASSURANCE_EVALUATOR_ACTIVE_SUBJECT_BINDINGS:%',v_count; end if;

  if not exists (select 1 from public.lf_activos where codigo_activo='ACT-0001' and archived_at is null) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_ROUTER_ASSET_MISSING';
  end if;
  if not exists (select 1 from public.lf_activos where codigo_activo='CURRENTNESS_AUTHORITY' and archived_at is null) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_CURRENTNESS_ASSET_MISSING';
  end if;
  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ASSURANCE_COMPLETENESS'
      and estado_documental='LEGACY'
      and estado_operativo='READ_ONLY'
      and metadata#>>'{transversal_inventory,inventory_status}'='RETIRED_LEGACY_LINEAGE'
      and archived_at is null
  ) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_LEGACY_PREDECESSOR_NOT_RETIRED';
  end if;

  if exists (select 1 from public.lf_activos where codigo_activo=v_capability_code and archived_at is null) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_ASSET_ALREADY_PRESENT';
  end if;
  if exists (select 1 from public.lf_activo_relaciones where codigo_activo=v_capability_code) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_RELATIONS_ALREADY_PRESENT';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    version,ruta_esperada,url,owner_name,ultima_revision,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_capability_code,'TRANSVERSAL_ASSURANCE_EVALUATOR','CAPABILITY','TRANSVERSAL_EVIDENCE_SUFFICIENCY_EVALUATOR',
    'VIGENTE','READ_ONLY','FAIL_CLOSED','NO_HABILITADO','BLOQUEADO',
    null,'sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_runner_v1.py',
    'supabase://public/lf_capability_registry/ASSURANCE_EVALUATOR','SUPER_ADMIN',v_call_contract_sha,
    'TRANSVERSAL_ASSURANCE_EVIDENCE_SUFFICIENCY_EVALUATOR',
    'NATIVE_SUPABASE','LF_TRANSVERSAL_CAPABILITY_INVENTORY','ASSURANCE_EVALUATOR_20260930',1,
    v_inventory_batch,
    jsonb_build_object(
      'key',v_capability_code,
      'class','EVIDENCE_SUFFICIENCY_EVALUATOR',
      'status','CANDIDATE_DORMANT_NO_ACTIVE_BINDING',
      'current_pointer_present',false,
      'active_subject_bindings',0,
      'runtime_authorized',false,
      'production_authorized',false
    ),
    jsonb_build_object(
      'source_kind','GITHUB_SOURCE_PLUS_SUPABASE_REGISTRY',
      'inventory_status','CANDIDATE_DORMANT_NO_ACTIVE_BINDING',
      'owner','SUPER_ADMIN',
      'no_duplicate_engine',true,
      'physical_assets',jsonb_build_array(
        'public.lf_capability_registry:ASSURANCE_EVALUATOR',
        'sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_core_v1.py',
        'sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_runner_v1.py',
        v_call_contract_ref
      ),
      'entry_contract',jsonb_build_object(
        'schema_version','LF_CAPABILITY_ENTRY_CONTRACT_V1',
        'required',true,
        'owner','SUPER_ADMIN',
        'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1',
        'required_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'required_entrypoint_signature','public.fn_lf_capability_bind_from_orchestrator_v1(text,text,text,text,uuid,text)',
        'direct_new_binding_policy','BLOCK',
        'enforcement_state','ENFORCED_DORMANT_NO_CURRENT'
      ),
      'call_contract',jsonb_build_object(
        'schema_version','lf-assurance-evaluator-call-contract/v1',
        'ref',v_call_contract_ref,
        'sha256',v_call_contract_sha,
        'dispatch_entrypoint','public.fn_lf_orchestrator_dispatch_receipt_v1',
        'bind_entrypoint','public.fn_lf_capability_bind_from_orchestrator_v1',
        'activation_gate','ASSURANCE_ACTIVATION_GATE_V1',
        'runner','sandbox/lf_contract_gate_test/assurance_evaluator_boundary/assurance_evaluator_runner_v1.py',
        'expected_before_promotion','BLOCK_NO_CURRENT_CAPABILITY'
      ),
      'lookup_rule','ASSET_INVENTORY_FIRST_THEN_CURRENTNESS_THEN_EXPAND_SEARCH',
      'legacy_predecessor','ASSURANCE_COMPLETENESS',
      'inventory_execution_id',v_execution_id
    ),
    v_execution_id,v_execution_id
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values
    (v_capability_code,'ACT-0001','GOBERNADO_POR','ROUTER_CHANGESET_GOVERNANCE',v_target_path,v_inventory_batch,v_execution_id,v_execution_id),
    (v_capability_code,'CURRENTNESS_AUTHORITY','DEPENDE_DE','CURRENTNESS_AUTHORITY',v_target_path,v_inventory_batch,v_execution_id,v_execution_id),
    (v_capability_code,'ASSURANCE_COMPLETENESS','RELACIONADO_CAPACIDADES','LEGACY_PREDECESSOR_RETIRED',v_target_path,v_inventory_batch,v_execution_id,v_execution_id);

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo=v_capability_code
      and nombre_canonico='TRANSVERSAL_ASSURANCE_EVALUATOR'
      and tipo_activo='CAPABILITY'
      and estado_documental='VIGENTE'
      and estado_operativo='READ_ONLY'
      and nivel_control='FAIL_CLOSED'
      and runtime_estado='NO_HABILITADO'
      and impacto_automatico='BLOQUEADO'
      and owner_name='SUPER_ADMIN'
      and version is null
      and metadata#>>'{entry_contract,required_entrypoint}'='public.fn_lf_capability_bind_from_orchestrator_v1'
      and metadata#>>'{call_contract,sha256}'=v_call_contract_sha
      and archived_at is null
  ) then
    raise exception 'BLOCK_ASSURANCE_EVALUATOR_ASSET_READBACK';
  end if;

  select count(*) into v_count
  from public.lf_activo_relaciones
  where codigo_activo=v_capability_code
    and (
      (relacionado_codigo='ACT-0001' and relacion_tipo='GOBERNADO_POR')
      or (relacionado_codigo='CURRENTNESS_AUTHORITY' and relacion_tipo='DEPENDE_DE')
      or (relacionado_codigo='ASSURANCE_COMPLETENESS' and relacion_tipo='RELACIONADO_CAPACIDADES')
    );
  if v_count <> 3 then raise exception 'BLOCK_ASSURANCE_EVALUATOR_RELATION_READBACK:%',v_count; end if;

  select count(*) into v_count from public.lf_capability_current where capability_code=v_capability_code;
  if v_count <> 0 then raise exception 'BLOCK_ASSURANCE_EVALUATOR_UNAUTHORIZED_CURRENT_AFTER_PROJECTION:%',v_count; end if;
  select count(*) into v_count from public.lf_assurance_subject_bindings where status='ACTIVE';
  if v_count <> 0 then raise exception 'BLOCK_ASSURANCE_EVALUATOR_UNAUTHORIZED_BINDING_AFTER_PROJECTION:%',v_count; end if;
end
$lf_assurance_evaluator_inventory_wiring$;
