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
     ('35975321cd44995d45d369ad186db6afd4199dbcd4944b06d18c4a78a2ece3e1','699f5f10e742393f6fc3f8f207d51046f27b7dc2') then
    null;
  elsif (v_workflow_sha,v_workflow_blob) is not distinct from
     ('498a0693b2d042157460c5cedfcfc946517d97233e0ce41c7e792d525400aba4','302dafc0f045b81ce7c583c6425ed20bc34e1b3b') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      '35975321cd44995d45d369ad186db6afd4199dbcd4944b06d18c4a78a2ece3e1',
      '699f5f10e742393f6fc3f8f207d51046f27b7dc2',
      'SOURCE_WORKFLOW',true,
      '95a403d6cdd2e80964bb74ad4ea6815a43b1c824',
      'GOV-S28-C7-READY-REVIEW-DEDUPE-CANARY-20260905-001',
      clock_timestamp()
    );
  else
    raise exception 'S28_C7_REPIN_STATE_MISMATCH workflow_sha=% workflow_blob=%',
      coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>');
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'S28_C7_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-contract-check.yml'
      and expected_sha256='35975321cd44995d45d369ad186db6afd4199dbcd4944b06d18c4a78a2ece3e1'
      and expected_git_blob='699f5f10e742393f6fc3f8f207d51046f27b7dc2'
  ) then
    raise exception 'S28_C7_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
