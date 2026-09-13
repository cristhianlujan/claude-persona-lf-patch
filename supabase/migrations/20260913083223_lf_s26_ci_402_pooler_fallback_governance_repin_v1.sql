do $migration$
declare
  v_workflow_sha text;
  v_workflow_blob text;
  v_count bigint;
begin
  select expected_sha256,expected_git_blob
    into v_workflow_sha,v_workflow_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='.github/workflows/lf-github-reconcile-v3.yml';

  if (v_workflow_sha,v_workflow_blob) is not distinct from
     ('dd3febd8a6de892fcffc52deee8c4479cb01dd4e701607427a9696d6594b952a','8d1b2a025a3a3334817d6ea548c32c0b6c41bc36') then
    null;
  elsif (v_workflow_sha,v_workflow_blob) is not distinct from
     ('d038c4e78e2b9c37b3a31bab74c56b1215acd8e93a5fe60fc0a94826acfd771c','ae4130e5a6c79a0a257708db9435e5acdcfeeb83') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-github-reconcile-v3.yml',
      'dd3febd8a6de892fcffc52deee8c4479cb01dd4e701607427a9696d6594b952a',
      '8d1b2a025a3a3334817d6ea548c32c0b6c41bc36',
      'RECONCILIATION_WORKFLOW',true,
      'a8273e6331fbb738a3e2fcf9bb5e9b6c6c6b25cd',
      'EXEC-S26-CI-402-POOLER-FALLBACK-20260913-001',
      clock_timestamp()
    );
  else
    raise exception 'S26_CI_402_RECONCILIATION_REPIN_STATE_MISMATCH workflow_sha=% workflow_blob=%',
      coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>');
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'S26_CI_402_RECONCILIATION_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;

  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-github-reconcile-v3.yml'
      and expected_sha256='dd3febd8a6de892fcffc52deee8c4479cb01dd4e701607427a9696d6594b952a'
      and expected_git_blob='8d1b2a025a3a3334817d6ea548c32c0b6c41bc36'
  ) then
    raise exception 'S26_CI_402_RECONCILIATION_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
