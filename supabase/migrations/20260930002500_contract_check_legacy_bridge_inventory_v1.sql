-- Contract Check legacy-path bridge inventory transition.
--
-- This migration does NOT create a second Contract Check asset or operation.
-- It records that the historical path scripts/lf_contract_check.py is now a
-- temporary compatibility bridge to the new Final Thin Carrier, and that the
-- bridge must be removed after callers are migrated.
--
-- No activation, ruleset change, runtime enablement, or new router binding is
-- performed here.

do $migration$
begin
  update public.lf_activos
     set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
           'contract_check_bridge_transition',
           jsonb_build_object(
             'schema_version', 'LF_CONTRACT_CHECK_BRIDGE_TRANSITION_V1',
             'status', 'TEMPORARY_COMPATIBILITY_BRIDGE',
             'bridge_path', 'scripts/lf_contract_check.py',
             'canonical_entrypoint', 'sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py',
             'semantic_integration', 'sandbox/lf_contract_gate_test/contract_check_semantic_integration/contract_check_semantic_integration_v1.py',
             'retired_implementation', 'LF_CONTRACT_CHECK_V0_21',
             'retired_implementation_executable', false,
             'cleanup_required', true,
             'new_consumers_allowed', false,
             'sunset_condition', 'REMOVE_BRIDGE_AFTER_ZERO_ACTIVE_CALLERS_AND_ZERO_ACTIVE_AUTHORITY_DEPENDENCIES',
             'source_inventory', 'sandbox/lf_contract_gate_test/contract_check_responsibility_inventory/contract_check_legacy_bridge_inventory_v1.json'
           )
         ),
         updated_at = now()
   where codigo_activo = 'GITHUB_CONTRACT_GATE_LF'
     and archived_at is null;

  if not found then
    raise exception 'CONTRACT_CHECK_BRIDGE_ASSET_NOT_FOUND';
  end if;

  update public.lf_operation_registry
     set source_paths = array[
           '.github/workflows/lf-contract-check.yml',
           'scripts/lf_contract_check.py',
           'sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py',
           'sandbox/lf_contract_gate_test/contract_check_semantic_integration/contract_check_semantic_integration_v1.py'
         ]::text[],
         notes = concat_ws(E'\n',
           nullif(notes, ''),
           '2026-09-29: scripts/lf_contract_check.py reclassified as TEMPORARY_COMPATIBILITY_BRIDGE. The retired v0.21 implementation must not execute. Canonical Contract Check execution delegates to contract_check_carrier_v1.py -> semantic integration. cleanup_required=true; new_consumers_allowed=false. No new router binding or runtime activation is introduced by this transition.'
         ),
         updated_at = now()
   where operation_code = 'GITHUB_CONTRACT_GATE_LF';

  if not found then
    raise exception 'CONTRACT_CHECK_BRIDGE_OPERATION_NOT_FOUND';
  end if;
end
$migration$;
