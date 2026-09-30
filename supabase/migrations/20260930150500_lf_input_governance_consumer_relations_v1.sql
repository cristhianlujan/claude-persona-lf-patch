-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · L1 · N-1 (PAULO-014)
-- Register omitted Input Governance consumers in public.lf_activo_relaciones.
-- Scope: registry relations only. No runtime binding, no deploy, no production promotion.
-- Profiles batch-worker dependency is intentionally deferred to M0.2–M0.4.
-- github_actions_batch_queue_worker.py directly calls programacion.fn_lf_router_input_governance_resolve_v1,
-- but that worker/function pair is not yet registered as canonical assets. N-1 must not misattribute it.

begin;

do $n1$
declare
  v_batch constant uuid := 'e14f1d14-5d36-4f6c-a01e-1a0f01400001'::uuid;
  v_exec constant text := 'IG-CV-V2-L1-N1-CONSUMERS-20260930';
begin
  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1' and archived_at is null
  ) then raise exception 'N1_SOURCE_ASSET_MISSING:EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'; end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1' and archived_at is null
  ) then raise exception 'N1_TARGET_ASSET_MISSING:EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'; end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ADAPTER-LF-SHELL-PROFILE-20260827'
      and archived_at is null
      and metadata->>'input_governance_binding_contract'='gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md'
      and coalesce((metadata->>'input_governance_receipt_required')::boolean,false)
  ) then raise exception 'N1_SOURCE_BINDING_MISSING:ADAPTER-LF-SHELL-PROFILE-20260827'; end if;

  if not exists (
    select 1 from public.lf_activos
    where codigo_activo='ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827'
      and archived_at is null
      and metadata->>'input_governance_binding_contract'='gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md'
      and coalesce((metadata->>'input_governance_receipt_required')::boolean,false)
  ) then raise exception 'N1_SOURCE_BINDING_MISSING:ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827'; end if;

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  )
  select
    'EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1',
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'DEPENDE_DE',
    'Direct runtime consumer: supabase/functions/lf-profiles-governance-caller-v1/index.ts calls input-governance-agent-v1 via callRuntime().',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2_N1',
    v_batch,v_exec,v_exec
  where not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacion_tipo='DEPENDE_DE'
  );

  -- Adapters consume Input Governance through the canonical adapter binding contract and receipt.
  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  )
  select
    'ADAPTER-LF-SHELL-PROFILE-20260827',
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'CONSUME_TRANSITIVAMENTE',
    'Adapter requires an Input Governance receipt through gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md; relation is transitive and does not claim a direct Agent call.',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2_N1',
    v_batch,v_exec,v_exec
  where not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='ADAPTER-LF-SHELL-PROFILE-20260827'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacion_tipo='CONSUME_TRANSITIVAMENTE'
  );

  insert into public.lf_activo_relaciones(
    codigo_activo,relacionado_codigo,relacion_tipo,valor_original,fuente,
    migration_batch_id,created_by_execution_id,updated_by_execution_id
  )
  select
    'ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827',
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'CONSUME_TRANSITIVAMENTE',
    'Adapter requires an Input Governance receipt through gobernanza/contratos/ADAPTER_INPUT_GOVERNANCE_BINDING_v1.md; relation is transitive and does not claim a direct Agent call.',
    'IG_CURATOR_VALIDATOR_REFACTOR_V2_N1',
    v_batch,v_exec,v_exec
  where not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacion_tipo='CONSUME_TRANSITIVAMENTE'
  );

  if not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacion_tipo='DEPENDE_DE'
  ) then raise exception 'N1_POSTCONDITION_MISSING:DIRECT_PROFILES_CALLER'; end if;

  if not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='ADAPTER-LF-SHELL-PROFILE-20260827'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacion_tipo='CONSUME_TRANSITIVAMENTE'
  ) then raise exception 'N1_POSTCONDITION_MISSING:SHELL_ADAPTER_TRANSITIVE'; end if;

  if not exists (
    select 1 from public.lf_activo_relaciones
    where codigo_activo='ADAPTER-PROJECT-BRAND-MOCKUP-RENDER-LF-20260827'
      and relacionado_codigo='EDGE_FN_INPUT_GOVERNANCE_AGENT_V1'
      and relacion_tipo='CONSUME_TRANSITIVAMENTE'
  ) then raise exception 'N1_POSTCONDITION_MISSING:BRAND_ADAPTER_TRANSITIVE'; end if;

  -- N-1 must not introduce relation targets that are not canonical assets.
  if exists (
    select 1
    from public.lf_activo_relaciones r
    left join public.lf_activos a on a.codigo_activo=r.relacionado_codigo
    where r.fuente='IG_CURATOR_VALIDATOR_REFACTOR_V2_N1'
      and a.codigo_activo is null
  ) then
    raise exception 'N1_POSTCONDITION_ORPHAN_TARGET';
  end if;
end
$n1$;

commit;
