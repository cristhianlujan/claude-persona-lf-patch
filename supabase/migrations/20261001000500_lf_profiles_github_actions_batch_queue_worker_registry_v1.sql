-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · N-1 (PAULO-014)
-- Complete the deferred Profiles batch-worker registration after M0.2-M0.4 closure.
-- Registry-only: no runtime binding, deploy, promotion or production activation.

begin;

do $n1_worker$
declare
  v_batch constant uuid := 'e14f1d14-5d36-4f6c-a01e-1a0f01400002'::uuid;
  v_exec constant text := 'IG-CV-V2-L1-N1-BATCH-WORKER-20261001';
  v_source constant text := 'supabase/migrations/20261001000500_lf_profiles_github_actions_batch_queue_worker_registry_v1.sql';
  v_worker constant text := 'PROFILES_GITHUB_ACTIONS_BATCH_QUEUE_WORKER_V1';
  v_parent constant text := 'PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1';
  v_path constant text := 'sandbox/lf_contract_gate_test/profile_execution_runtime/github_actions_batch_queue_worker.py';
  v_blob constant text := '5f9b94fbb420f06a635b1a142f18096be8f5ec0d';
begin
  if exists (
    select 1 from public.lf_activos
    where codigo_activo=v_worker and archived_at is null
  ) then
    raise exception 'N1_WORKER_ASSET_ALREADY_EXISTS:%',v_worker;
  end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo=v_parent
      and archived_at is null
      and tipo_activo='CAPABILITY'
      and subtipo_activo='DB_FUNCTION'
  ) then
    raise exception 'N1_WORKER_PARENT_ASSET_MISSING:%',v_parent;
  end if;

  if exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo=v_worker
      and relacionado_codigo=v_parent
      and relacion_tipo='DEPENDE_DE'
  ) then
    raise exception 'N1_WORKER_RELATION_ALREADY_EXISTS';
  end if;

  insert into public.lf_activos(
    codigo_activo,nombre_canonico,tipo_activo,subtipo_activo,
    estado_documental,estado_operativo,nivel_control,runtime_estado,impacto_automatico,
    accion_migracion,version,ruta_esperada,owner_name,rol_arquitectura,
    source_spreadsheet_id,source_spreadsheet_title,source_sheet_name,source_row_number,
    migration_batch_id,raw_payload,metadata,created_by_execution_id,updated_by_execution_id
  ) values (
    v_worker,
    'github_actions_batch_queue_worker',
    'CAPABILITY','WORKER',
    'CANDIDATO','READ_ONLY','CONTROLADO','CANDIDATE_READ_ONLY','BLOQUEADO',
    'REGISTER_WORKER_CANDIDATE','v1',v_path,'LF_GOVERNANCE',
    'Profiles GitHub Actions batch queue worker. Directly consumes the canonical Input Governance router resolver; registry candidate only and blocked from automatic impact.',
    'GITHUB_MAIN_CONTROLLED_ENTRY','LF_OPERATION_CONTROLLED_CANDIDATES',
    'INPUT_GOVERNANCE_CONSUMER_REGISTRY_20261001',1,
    v_batch,
    jsonb_build_object(
      'repository','cristhianlujan/claude-persona-lf-patch',
      'path',v_path,
      'blob_sha',v_blob,
      'source_line',76
    ),
    jsonb_build_object(
      'dominio','INPUT_GOVERNANCE',
      'consumer_domain','PROFILES',
      'source_ref',v_path||'#L76',
      'source_blob_sha',v_blob,
      'direct_dependency',v_parent,
      'registration_reason','N-1 deferred consumer registration after M0.2-M0.4 closure',
      'runtime_change',false,
      'production_authorized',false
    ),
    v_exec,v_exec
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  ) values (
    v_worker,v_parent,'DEPENDE_DE',
    'github_actions_batch_queue_worker.py line 76 calls programacion.fn_lf_router_input_governance_resolve_v1(...).',
    v_source,v_batch,v_exec,v_exec
  );

  if (
    select count(*) from public.lf_activos
    where codigo_activo=v_worker
      and archived_at is null
      and tipo_activo='CAPABILITY'
      and subtipo_activo='WORKER'
      and estado_documental='CANDIDATO'
      and estado_operativo='READ_ONLY'
      and nivel_control='CONTROLADO'
      and runtime_estado='CANDIDATE_READ_ONLY'
      and impacto_automatico='BLOQUEADO'
      and ruta_esperada=v_path
      and raw_payload->>'blob_sha'=v_blob
  ) <> 1 then
    raise exception 'N1_WORKER_POSTCONDITION_ASSET_MISMATCH';
  end if;

  if (
    select count(*) from public.lf_activo_relaciones
    where codigo_activo=v_worker
      and relacionado_codigo=v_parent
      and relacion_tipo='DEPENDE_DE'
      and migration_batch_id=v_batch
  ) <> 1 then
    raise exception 'N1_WORKER_POSTCONDITION_RELATION_MISMATCH';
  end if;

  if exists (
    select 1
    from public.lf_activo_relaciones r
    left join public.lf_activos a
      on a.codigo_activo=r.relacionado_codigo and a.archived_at is null
    where r.migration_batch_id=v_batch
      and a.codigo_activo is null
  ) then
    raise exception 'N1_WORKER_POSTCONDITION_ORPHAN_TARGET';
  end if;
end
$n1_worker$;

commit;
