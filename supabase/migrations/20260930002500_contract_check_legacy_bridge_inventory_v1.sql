-- Contract Check legacy-path bridge inventory transition.
--
-- This migration does NOT create a second Contract Check asset or operation.
-- It records that the historical path scripts/lf_contract_check.py is now a
-- temporary compatibility bridge to the new Final Thin Carrier, and repins the
-- existing repository-governance path to the bridge bytes so v0.21 cannot remain
-- the approved executable content.
--
-- No activation, ruleset change, runtime enablement, or new router binding is
-- performed here.

do $migration$
declare
  v_sha256 text;
  v_git_blob text;
  v_bundle_count bigint;
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
     set source_paths = jsonb_build_array(
           '.github/workflows/lf-contract-check.yml',
           'scripts/lf_contract_check.py',
           'sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py',
           'sandbox/lf_contract_gate_test/contract_check_semantic_integration/contract_check_semantic_integration_v1.py'
         ),
         notes = concat_ws(E'\n',
           nullif(notes, ''),
           '2026-09-29: scripts/lf_contract_check.py reclassified as TEMPORARY_COMPATIBILITY_BRIDGE. The retired v0.21 implementation must not execute. Canonical Contract Check execution delegates to contract_check_carrier_v1.py -> semantic integration. cleanup_required=true; new_consumers_allowed=false. No new router binding or runtime activation is introduced by this transition.'
         ),
         updated_at = now()
   where operation_code = 'GITHUB_CONTRACT_GATE_LF';

  if not found then
    raise exception 'CONTRACT_CHECK_BRIDGE_OPERATION_NOT_FOUND';
  end if;

  select expected_sha256, expected_git_blob
    into v_sha256, v_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path = 'scripts/lf_contract_check.py';

  if (v_sha256, v_git_blob) is not distinct from
     ('91490d410062ecb9d08fe68e7d6cfcfac4632e57e722bceb3cf8cd5ebab2c83a',
      '5db1c733a001465c6d6a9b8d4c96d0bec48445ca') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('21311317378e295c1f3c6eda0ae4845343e73758575ec364aa7cb4ac0dbe665c',
         'e623e64d966fc58d4731f2584c90ae9f98d653ae') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      'scripts/lf_contract_check.py',
      '91490d410062ecb9d08fe68e7d6cfcfac4632e57e722bceb3cf8cd5ebab2c83a',
      '5db1c733a001465c6d6a9b8d4c96d0bec48445ca',
      'VALIDATOR',
      true,
      'd7adf137f9602fdcdd15dada55755a1a2cd43645',
      'EXEC-CONTRACT-CHECK-LEGACY-BRIDGE-REPIN-20260929-001',
      clock_timestamp()
    );
  else
    raise exception
      'CONTRACT_CHECK_BRIDGE_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256, '<NULL>'),
      coalesce(v_git_blob, '<NULL>');
  end if;

  select count(*)
    into v_bundle_count
  from public.get_lf_repository_governance_bundle_v4();

  if v_bundle_count <> 7 then
    raise exception 'CONTRACT_CHECK_BRIDGE_GOVERNANCE_COUNT expected=7 observed=%', v_bundle_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = 'scripts/lf_contract_check.py'
      and expected_sha256 = '91490d410062ecb9d08fe68e7d6cfcfac4632e57e722bceb3cf8cd5ebab2c83a'
      and expected_git_blob = '5db1c733a001465c6d6a9b8d4c96d0bec48445ca'
      and control_kind = 'VALIDATOR'
  ) then
    raise exception 'CONTRACT_CHECK_BRIDGE_REPIN_ASSERTION_FAILED';
  end if;
end
$migration$;
