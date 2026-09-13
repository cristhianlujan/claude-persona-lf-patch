do $migration$
declare
  v_sha256 text;
  v_git_blob text;
  v_count bigint;
begin
  select expected_sha256, expected_git_blob
    into v_sha256, v_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path = '.github/workflows/lf-contract-check.yml';

  if (v_sha256, v_git_blob) is not distinct from
     ('a82a42f3dd1314f83e0d784c2b98c33057c48a4261575b435f3405511b96a0d1','58dbf14df29524b6f85fa04213377c8657df4bb3') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('bf05a8ca4347b9827ad2876563f02b4f68f8a6f711412cdbc08449f151d5960a','cdda00f6c6cc1a35cd6118190a783b0c30382d09') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      'a82a42f3dd1314f83e0d784c2b98c33057c48a4261575b435f3405511b96a0d1',
      '58dbf14df29524b6f85fa04213377c8657df4bb3',
      'SOURCE_WORKFLOW', true,
      '40c0314598be7bc40f19d7786868ffd17364537d',
      'EXEC-S26-CI-402-POOLER-FALLBACK-20260913-001',
      clock_timestamp()
    );
  else
    raise exception 'S26_CI_402_SOURCE_WORKFLOW_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'), coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception 'S26_CI_402_SOURCE_WORKFLOW_GOVERNANCE_COUNT expected=7 observed=%', v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = '.github/workflows/lf-contract-check.yml'
      and expected_sha256 = 'a82a42f3dd1314f83e0d784c2b98c33057c48a4261575b435f3405511b96a0d1'
      and expected_git_blob = '58dbf14df29524b6f85fa04213377c8657df4bb3'
      and control_kind = 'SOURCE_WORKFLOW'
  ) then
    raise exception 'S26_CI_402_SOURCE_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
