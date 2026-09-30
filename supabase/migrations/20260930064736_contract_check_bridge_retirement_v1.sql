-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260930064736-20260930-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260930064736
-- source_name=contract_check_bridge_retirement_v1

-- Retire the historical Contract Check compatibility bridge after zero functional consumers.
-- Source-first: apply only after the GitHub retirement PR is merged and read back.
-- No runtime, production, carrier activation, ruleset change, or automatic impact is enabled here.
-- Provenance note: this migration does not invent/update *_by_execution_id on guarded operational rows;
-- durable traceability is provided by the merged source, migration ledger, authority readback and closure event.

do $migration$
declare
  v_bridge_sha text;
  v_bridge_blob text;
  v_carrier_sha text;
  v_carrier_blob text;
  v_bundle_count bigint;
  v_exec constant text := 'EXEC-CONTRACT-CHECK-BRIDGE-RETIREMENT-20260930-001';
  v_carrier constant text := 'sandbox/lf_contract_gate_test/contract_check_carrier/contract_check_carrier_v1.py';
begin
  select expected_sha256, expected_git_blob
    into v_bridge_sha, v_bridge_blob
    from public.get_lf_repository_governance_bundle_v4()
   where path = 'scripts/lf_contract_check.py';

  if (v_bridge_sha, v_bridge_blob) is distinct from
     ('91490d410062ecb9d08fe68e7d6cfcfac4632e57e722bceb3cf8cd5ebab2c83a',
      '5db1c733a001465c6d6a9b8d4c96d0bec48445ca') then
    raise exception 'CONTRACT_CHECK_BRIDGE_RETIREMENT_BASE_MISMATCH sha256=% git_blob=%',
      coalesce(v_bridge_sha,'<NULL>'),coalesce(v_bridge_blob,'<NULL>');
  end if;

  select expected_sha256, expected_git_blob
    into v_carrier_sha, v_carrier_blob
    from public.get_lf_repository_governance_bundle_v4()
   where path = v_carrier;

  if v_carrier_sha is null and v_carrier_blob is null then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      v_carrier,
      '8358a14daaa9560d09ae1cfe1c4da54e86b29ded6739c95be33d760d60215b06',
      'ee5473e265bec09e7df8b9283c7e8daec918473e',
      'VALIDATOR', true,
      '89264951f250d697c13c7ef19298e65a45affc16', v_exec, clock_timestamp()
    );
  elsif (v_carrier_sha, v_carrier_blob) is distinct from
        ('8358a14daaa9560d09ae1cfe1c4da54e86b29ded6739c95be33d760d60215b06',
         'ee5473e265bec09e7df8b9283c7e8daec918473e') then
    raise exception 'CONTRACT_CHECK_CARRIER_AUTHORITY_MISMATCH sha256=% git_blob=%',
      v_carrier_sha,v_carrier_blob;
  end if;

  insert into private.lf_repository_governance_bundle_v4(
    path, expected_sha256, expected_git_blob, control_kind, active,
    approved_commit_sha, approved_by_execution_id, approved_at
  ) values (
    'scripts/lf_contract_check.py',
    '91490d410062ecb9d08fe68e7d6cfcfac4632e57e722bceb3cf8cd5ebab2c83a',
    '5db1c733a001465c6d6a9b8d4c96d0bec48445ca',
    'VALIDATOR', false,
    '89264951f250d697c13c7ef19298e65a45affc16', v_exec, clock_timestamp()
  );

  update public.lf_operation_registry
     set source_paths = jsonb_build_array(
           '.github/workflows/lf-contract-check.yml',
           v_carrier,
           'sandbox/lf_contract_gate_test/contract_check_semantic_integration/contract_check_semantic_integration_v1.py'
         ),
         notes = concat_ws(E'\n', nullif(notes,''),
           '2026-09-30: temporary scripts/lf_contract_check.py bridge retired after zero functional consumers and live-authority E2E closure. Canonical Contract Check source is the Final Thin Carrier -> semantic integration. Runtime/production/automatic impact remain unchanged.'),
         updated_at = clock_timestamp()
   where operation_code = 'GITHUB_CONTRACT_GATE_LF';
  if not found then raise exception 'CONTRACT_CHECK_BRIDGE_RETIREMENT_OPERATION_NOT_FOUND'; end if;

  update public.lf_activos
     set metadata = jsonb_set(
           (coalesce(metadata,'{}'::jsonb) - 'contract_check_bridge_transition') || jsonb_build_object(
             'contract_check_bridge_transition',
             (coalesce(metadata->'contract_check_bridge_transition','{}'::jsonb) - 'bridge_path') || jsonb_build_object(
               'status','RETIRED',
               'cleanup_required',false,
               'retired_bridge_path','scripts/lf_contract_check.py',
               'canonical_entrypoint',v_carrier,
               'retired_at',clock_timestamp(),
               'retired_by_execution_id',v_exec
             )
           ),
           '{transversal_inventory,physical_assets}',
           coalesce((select jsonb_agg(to_jsonb(value) order by value)
                     from jsonb_array_elements_text(coalesce(metadata#>'{transversal_inventory,physical_assets}','[]'::jsonb)) as e(value)
                     where value <> 'scripts/lf_contract_check.py'),'[]'::jsonb),
           true
         ),
         updated_at=clock_timestamp()
   where codigo_activo='GITHUB_CONTRACT_GATE_LF' and archived_at is null;
  if not found then raise exception 'CONTRACT_CHECK_BRIDGE_RETIREMENT_ASSET_NOT_FOUND'; end if;

  update public.lf_activos
     set metadata = (coalesce(metadata,'{}'::jsonb) - 'legacy_bridge') || jsonb_build_object(
           'legacy_bridge_state','RETIRED',
           'legacy_bridge_retired_path','scripts/lf_contract_check.py',
           'legacy_bridge_retired_by_execution_id',v_exec
         ),
         updated_at=clock_timestamp()
   where codigo_activo='LF_CONTRACT_CHECK' and archived_at is null;
  if not found then raise exception 'LF_CONTRACT_CHECK_ASSET_NOT_FOUND'; end if;

  if exists (select 1 from public.get_lf_repository_governance_bundle_v4() where path='scripts/lf_contract_check.py') then
    raise exception 'CONTRACT_CHECK_BRIDGE_STILL_ACTIVE_IN_AUTHORITY';
  end if;

  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
     where path=v_carrier
       and expected_sha256='8358a14daaa9560d09ae1cfe1c4da54e86b29ded6739c95be33d760d60215b06'
       and expected_git_blob='ee5473e265bec09e7df8b9283c7e8daec918473e'
       and control_kind='VALIDATOR'
  ) then raise exception 'CONTRACT_CHECK_CARRIER_AUTHORITY_ASSERTION_FAILED'; end if;

  select count(*) into v_bundle_count from public.get_lf_repository_governance_bundle_v4();
  if v_bundle_count <> 7 then
    raise exception 'CONTRACT_CHECK_BRIDGE_RETIREMENT_BUNDLE_COUNT expected=7 observed=%',v_bundle_count;
  end if;

  if exists (
    select 1 from public.lf_operation_registry
     where operation_code='GITHUB_CONTRACT_GATE_LF'
       and source_paths ? 'scripts/lf_contract_check.py'
  ) then raise exception 'CONTRACT_CHECK_OPERATION_STILL_REFERENCES_BRIDGE'; end if;
end
$migration$;
