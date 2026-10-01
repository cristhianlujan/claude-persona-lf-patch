-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · N-2 / PAULO-015
-- Governed binding for Input Governance recuration.
-- Canonical operation authority remains public.lf_operation_registry.
-- The material asset graph must only point to registered lf_activos nodes, so the
-- Agent binds to the canonical Router resolver asset; the operation row is checked
-- separately and remains the authority for EJECUCION_INPUT_GOVERNANCE_LF.
-- Runtime deployment and workflow execution are deliberately excluded.

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
    from public.lf_activos
    where codigo_activo='PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'
      and archived_at is null
  ) then
    raise exception 'N2_ROUTER_RESOLVER_ASSET_MISSING';
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

  -- Repair the first applied form of this exact N-2 migration. It incorrectly
  -- treated an operation_registry code as an lf_activos target and created
  -- relation #405 with a non-existent relacionado_codigo.
  delete from public.lf_activo_relaciones
  where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and relacionado_codigo='EJECUCION_INPUT_GOVERNANCE_LF'
    and relacion_tipo='DEPENDE_DE'
    and fuente='IG_CURATOR_VALIDATOR_REFACTOR_V2_N2';

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
    'PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1',
    'DEPENDE_DE',
    'Governed execution binding: Input Governance Agent is reached through the canonical Router resolver, which resolves operation EJECUCION_INPUT_GOVERNANCE_LF from public.lf_operation_registry; no production or runtime activation is implied.',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2_N2',
    v_batch,
    v_exec,
    v_exec
  where not exists (
    select 1
    from public.lf_activo_relaciones
    where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacionado_codigo='PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'
      and relacion_tipo='DEPENDE_DE'
  );

  select count(*) into v_count
  from public.lf_activo_relaciones r
  join public.lf_activos a
    on a.codigo_activo=r.relacionado_codigo
   and a.archived_at is null
  where r.codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
    and r.relacionado_codigo='PROGRAMACION_FN_LF_ROUTER_INPUT_GOVERNANCE_RESOLVE_V1'
    and r.relacion_tipo='DEPENDE_DE';

  if v_count <> 1 then
    raise exception 'N2_AGENT_ROUTER_RELATION_COUNT:%',v_count;
  end if;

  if exists (
    select 1
    from public.lf_activo_relaciones r
    left join public.lf_activos a
      on a.codigo_activo=r.relacionado_codigo
     and a.archived_at is null
    where r.fuente='IG_CURATOR_VALIDATOR_REFACTOR_V2_N2'
      and a.codigo_activo is null
  ) then
    raise exception 'N2_ORPHAN_RELATION_REMAINS';
  end if;
end
$n2$;

commit;
