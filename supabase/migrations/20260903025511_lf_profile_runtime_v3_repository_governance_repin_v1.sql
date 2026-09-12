do $migration$
declare
  v_workflow_sha text;
  v_workflow_blob text;
  v_validator_sha text;
  v_validator_blob text;
  v_count bigint;
begin
  select expected_sha256,expected_git_blob
    into v_workflow_sha,v_workflow_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='.github/workflows/lf-contract-check.yml';

  select expected_sha256,expected_git_blob
    into v_validator_sha,v_validator_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='scripts/lf_contract_check.py';

  if (v_workflow_sha,v_workflow_blob) is distinct from
     ('7b86ee4785b41369d23feefcfe228180d8e77b9401be86a76daad0f58de4bd05','9aea9597253780d6f22292663442e7d2b2002249') then
    raise exception 'PROFILE_RUNTIME_V3_WORKFLOW_PIN_RACE sha=% blob=%',coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>');
  end if;
  if (v_validator_sha,v_validator_blob) is distinct from
     ('5800cb1844297d4eb488c3a585326fc43a94ff7112858b85c9a996ce3d1db100','427902456b1b6abadd0eeea833733458be233491') then
    raise exception 'PROFILE_RUNTIME_V3_VALIDATOR_PIN_RACE sha=% blob=%',coalesce(v_validator_sha,'<NULL>'),coalesce(v_validator_blob,'<NULL>');
  end if;

  insert into private.lf_repository_governance_bundle_v4(
    path,expected_sha256,expected_git_blob,control_kind,active,
    approved_commit_sha,approved_by_execution_id,approved_at
  ) values
  (
    '.github/workflows/lf-contract-check.yml',
    'd71862e5c8eabbb2c996e5a230802a2e1143cf5fa733298c19160ac927369ede',
    '5b183387ac60589ac716a3ebb59a39195969df49',
    'SOURCE_WORKFLOW',true,
    'bcec64b5eb00180f82d6c6c8f12f973e4bde1927',
    'EXEC-ACTUALIZACION-PROFILE-RUNTIME-V3-GOVERNANCE-REPIN-20260903-001',
    clock_timestamp()
  ),
  (
    'scripts/lf_contract_check.py',
    '96a7ff7d2ea0d9b977cb2192b5febc048a6276cc86beb498aa8263308235b517',
    '0a09f6fc482f9c2e878806e6711b1cb2a19a6535',
    'VALIDATOR',true,
    'bcec64b5eb00180f82d6c6c8f12f973e4bde1927',
    'EXEC-ACTUALIZACION-PROFILE-RUNTIME-V3-GOVERNANCE-REPIN-20260903-001',
    clock_timestamp()
  );

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'PROFILE_RUNTIME_V3_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-contract-check.yml'
      and expected_sha256='d71862e5c8eabbb2c996e5a230802a2e1143cf5fa733298c19160ac927369ede'
      and expected_git_blob='5b183387ac60589ac716a3ebb59a39195969df49'
  ) then
    raise exception 'PROFILE_RUNTIME_V3_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='scripts/lf_contract_check.py'
      and expected_sha256='96a7ff7d2ea0d9b977cb2192b5febc048a6276cc86beb498aa8263308235b517'
      and expected_git_blob='0a09f6fc482f9c2e878806e6711b1cb2a19a6535'
  ) then
    raise exception 'PROFILE_RUNTIME_V3_VALIDATOR_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
