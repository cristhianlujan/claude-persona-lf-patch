-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · N-2 / PAULO-015
-- Material relation only: EDGE_FN_INPUT_GOVERNANCE_AGENT_V1 -> EJECUCION_INPUT_GOVERNANCE_LF.
-- Runtime deployment and workflow execution are deliberately excluded and require explicit owner authorization.

begin;

do $n2$
declare
  v_batch constant uuid := '7a720002-2026-4000-8000-000000000015'::uuid;
  v_exec constant text := 'CHATGPT-IG-CV-L1-N2-BINDING-20261001';
  v_count integer;
begin
  if not exists (
    select 1
    from public.lf_activos
    where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and archived_at is null
  ) then
    raise exception 'N2_AGENT_ASSET_MISSING';
  end if;

  if not exists (
    select 1
    from public.lf_activos
    where codigo_activo='EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
      and archived_at is null
      and estado_operativo='READ_ONLY'
      and runtime_estado='CANDIDATE_READ_ONLY'
  ) then
    raise exception 'N2_CALLER_ASSET_NOT_READ_ONLY_CANDIDATE';
  end if;

  if not exists (
    select 1
    from public.lf_operation_registry
    where operation_code='EJECUCION_INPUT_GOVERNANCE_LF'
      and status='SANDBOX_ACTIVE'
      and lifecycle_state_code='OP_CANDIDATE'
      and source_paths ? 'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'
  ) then
    raise exception 'N2_OPERATION_REGISTRY_BINDING_MISSING_OR_DRIFTED';
  end if;

  insert into public.lf_activo_relaciones(
    codigo_activo,
    relacionado_codigo,
    relacion_tipo,
    valor_original,
    fuente,
    migration_batch_id,
    created_by_execution_id,
    updated_by_execution_id
  )
  select
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'EJECUCION_INPUT_GOVERNANCE_LF',
    'DEPENDE_DE',
    'Governed execution binding: Input Governance Agent is invoked for recuration through operation EJECUCION_INPUT_GOVERNANCE_LF; no production or runtime activation is implied.',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2_N2',
    v_batch,
    v_exec,
    v_exec
  where not exists (
    select 1
    from public.lf_activo_relaciones
    where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacionado_codigo='EJECUCION_INPUT_GOVERNANCE_LF'
      and relacion_tipo='DEPENDE_DE'
  );

  select count(*) into v_count
  from public.lf_activo_relaciones
  where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and relacionado_codigo='EJECUCION_INPUT_GOVERNANCE_LF'
    and relacion_tipo='DEPENDE_DE';

  if v_count <> 1 then
    raise exception 'N2_AGENT_OPERATION_RELATION_COUNT:%',v_count;
  end if;
end
$n2$;

commit;
