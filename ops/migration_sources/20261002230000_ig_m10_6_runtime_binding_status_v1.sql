-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · M10.6 / PAULO-010
-- Materialize the already-governed runtime bindings in the canonical asset inventory.
-- Metadata only: no Edge deploy, no runtime activation, no promotion, no production change.
-- `BOUND_RUNTIME` is the existing INPUT_GOVERNANCE_WORKER_SPEC_V1 vocabulary.

do $m10_6$
declare
  v_preimage_count integer;
  v_post_count integer;
begin
  select count(*)
    into v_preimage_count
  from public.lf_activos
  where codigo_activo in (
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
    'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1',
    'EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
  )
    and archived_at is null
    and metadata->'runtime_binding_status' is null;

  if v_preimage_count <> 4 then
    raise exception 'M10_6_RUNTIME_BINDING_PREIMAGE_DRIFT:%', v_preimage_count;
  end if;

  update public.lf_activos
  set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'runtime_binding_status', 'BOUND_RUNTIME',
      'runtime_binding_provider', 'SUPABASE_EDGE_FUNCTION',
      'runtime_binding_ref', case codigo_activo
        when 'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1' then 'SUPABASE_EDGE_FUNCTION:input-governance-agent-v1'
        when 'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1' then 'SUPABASE_EDGE_FUNCTION:input-governance-curator-v1'
        when 'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1' then 'SUPABASE_EDGE_FUNCTION:input-governance-validator-v1'
        when 'EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1' then 'SUPABASE_EDGE_FUNCTION:lf-profiles-governance-caller-v1'
      end,
      'runtime_binding_authority', 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_AND_MATERIAL_RELATIONS',
      'runtime_binding_source_unit', 'M10.6'
    ),
    updated_at = now(),
    updated_by_execution_id = 'IG-CV-M10-6-RUNTIME-BINDING-20261002'
  where codigo_activo in (
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
    'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1',
    'EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
  )
    and archived_at is null;

  select count(*)
    into v_post_count
  from public.lf_activos
  where codigo_activo in (
    'EDGE_FN_INPUT_GOVERNANCE_AGENT_V1',
    'EDGE_FN_INPUT_GOVERNANCE_CURATOR_V1',
    'EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1',
    'EDGE_FN_LF_PROFILES_GOVERNANCE_CALLER_V1'
  )
    and archived_at is null
    and metadata->>'runtime_binding_status' = 'BOUND_RUNTIME'
    and metadata->>'runtime_binding_provider' = 'SUPABASE_EDGE_FUNCTION'
    and metadata->>'runtime_binding_source_unit' = 'M10.6'
    and metadata->>'runtime_binding_ref' is not null;

  if v_post_count <> 4 then
    raise exception 'M10_6_RUNTIME_BINDING_POSTCONDITION:%', v_post_count;
  end if;
end
$m10_6$;
