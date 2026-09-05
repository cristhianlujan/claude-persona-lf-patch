do $migration$
declare
  v_workflow_sha text;
  v_workflow_blob text;
  v_count bigint;
begin
  select expected_sha256,expected_git_blob
    into v_workflow_sha,v_workflow_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='.github/workflows/lf-contract-check.yml';

  if (v_workflow_sha,v_workflow_blob) is not distinct from
     ('97f2f206a875e908d4abb684620bfdf8a51d445d47add319ba04dc1e6c5fd40d','36cd77165647e2801fb2495dcd4a244132a35247') then
    null;
  elsif (v_workflow_sha,v_workflow_blob) is not distinct from
     ('35975321cd44995d45d369ad186db6afd4199dbcd4944b06d18c4a78a2ece3e1','699f5f10e742393f6fc3f8f207d51046f27b7dc2') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      '97f2f206a875e908d4abb684620bfdf8a51d445d47add319ba04dc1e6c5fd40d',
      '36cd77165647e2801fb2495dcd4a244132a35247',
      'SOURCE_WORKFLOW',true,
      'db4064755e0137b7e5d7d653761a102e2bdee13b',
      'GOV-S28-MIGRATION-LEDGER-FOCAL-REPIN-20260905-001',
      clock_timestamp()
    );
  else
    raise exception 'S28_MIGRATION_LEDGER_REPIN_STATE_MISMATCH workflow_sha=% workflow_blob=%',
      coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>');
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'S28_MIGRATION_LEDGER_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-contract-check.yml'
      and expected_sha256='97f2f206a875e908d4abb684620bfdf8a51d445d47add319ba04dc1e6c5fd40d'
      and expected_git_blob='36cd77165647e2801fb2495dcd4a244132a35247'
  ) then
    raise exception 'S28_MIGRATION_LEDGER_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
