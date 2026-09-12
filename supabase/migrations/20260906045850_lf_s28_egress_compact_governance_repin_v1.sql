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
     ('bf05a8ca4347b9827ad2876563f02b4f68f8a6f711412cdbc08449f151d5960a','cdda00f6c6cc1a35cd6118190a783b0c30382d09') then
    null;
  elsif (v_workflow_sha,v_workflow_blob) is not distinct from
     ('97f2f206a875e908d4abb684620bfdf8a51d445d47add319ba04dc1e6c5fd40d','36cd77165647e2801fb2495dcd4a244132a35247') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      'bf05a8ca4347b9827ad2876563f02b4f68f8a6f711412cdbc08449f151d5960a',
      'cdda00f6c6cc1a35cd6118190a783b0c30382d09',
      'SOURCE_WORKFLOW',true,
      '0ebea11072d2ee9cd6d44f82d741ca2389940ee3',
      'GOV-S28-EGRESS-COMPACT-REPIN-20260906-001',
      clock_timestamp()
    );
  else
    raise exception 'S28_EGRESS_COMPACT_REPIN_STATE_MISMATCH workflow_sha=% workflow_blob=%',
      coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>');
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'S28_EGRESS_COMPACT_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-contract-check.yml'
      and expected_sha256='bf05a8ca4347b9827ad2876563f02b4f68f8a6f711412cdbc08449f151d5960a'
      and expected_git_blob='cdda00f6c6cc1a35cd6118190a783b0c30382d09'
  ) then
    raise exception 'S28_EGRESS_COMPACT_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
