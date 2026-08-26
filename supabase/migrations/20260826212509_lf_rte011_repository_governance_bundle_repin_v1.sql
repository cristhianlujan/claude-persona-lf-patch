do $migration$
declare
  v_workflow_blob text;
  v_validator_blob text;
begin
  select expected_git_blob into v_workflow_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='.github/workflows/lf-contract-check.yml';

  select expected_git_blob into v_validator_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='scripts/lf_contract_check.py';

  if v_workflow_blob is distinct from '3d579a2925652370926d1fcc08a20c58622e61ff' then
    raise exception 'RTE011_WORKFLOW_PIN_RACE:%',coalesce(v_workflow_blob,'<NULL>');
  end if;
  if v_validator_blob is distinct from 'a9d3056ec32954a61a427f8c93e02bb993d1b8cb' then
    raise exception 'RTE011_VALIDATOR_PIN_RACE:%',coalesce(v_validator_blob,'<NULL>');
  end if;

  insert into private.lf_repository_governance_bundle_v4(
    path,expected_sha256,expected_git_blob,control_kind,active,
    approved_commit_sha,approved_by_execution_id,approved_at
  ) values
  (
    '.github/workflows/lf-contract-check.yml',
    '7b86ee4785b41369d23feefcfe228180d8e77b9401be86a76daad0f58de4bd05',
    '9aea9597253780d6f22292663442e7d2b2002249',
    'SOURCE_WORKFLOW',true,
    'cc9e201960aa148c269616401b6fe9c15412c1da',
    'WORK-RTE011-PROD-GOVERNANCE-REPIN-20260826',clock_timestamp()
  ),
  (
    'scripts/lf_contract_check.py',
    '5800cb1844297d4eb488c3a585326fc43a94ff7112858b85c9a996ce3d1db100',
    '427902456b1b6abadd0eeea833733458be233491',
    'VALIDATOR',true,
    'cc9e201960aa148c269616401b6fe9c15412c1da',
    'WORK-RTE011-PROD-GOVERNANCE-REPIN-20260826',clock_timestamp()
  );
end;
$migration$;