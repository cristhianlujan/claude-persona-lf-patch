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
     ('d038c4e78e2b9c37b3a31bab74c56b1215acd8e93a5fe60fc0a94826acfd771c','ae4130e5a6c79a0a257708db9435e5acdcfeeb83') then
    null;
  elsif (v_workflow_sha,v_workflow_blob) is not distinct from
     ('0821aec5d5935f350185f68fddc0ec5d42b5bf024b6f62af8104ed322ee0ebb8','2da6838b1f541facff4c9cad5ca61ebfbfaa12cc') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-github-reconcile-v3.yml',
      'd038c4e78e2b9c37b3a31bab74c56b1215acd8e93a5fe60fc0a94826acfd771c',
      'ae4130e5a6c79a0a257708db9435e5acdcfeeb83',
      'RECONCILIATION_WORKFLOW',true,
      '060511c8a2c4ae9ab517ea1a0b8829e2ee8b85a6',
      'GOV-PR706-RECONCILIATION-APPLICABILITY-20260912-001',
      clock_timestamp()
    );
  else
    raise exception 'PR706_RECONCILIATION_REPIN_STATE_MISMATCH workflow_sha=% workflow_blob=%',
      coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>');
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'PR706_RECONCILIATION_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;

  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-github-reconcile-v3.yml'
      and expected_sha256='d038c4e78e2b9c37b3a31bab74c56b1215acd8e93a5fe60fc0a94826acfd771c'
      and expected_git_blob='ae4130e5a6c79a0a257708db9435e5acdcfeeb83'
  ) then
    raise exception 'PR706_RECONCILIATION_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;