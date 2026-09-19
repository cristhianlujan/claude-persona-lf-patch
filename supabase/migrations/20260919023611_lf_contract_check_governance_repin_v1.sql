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
     ('e3858ba3b627d9aeaccd72e803cf39ff68a341dd836ef557f38085fa6779eead','53bd414917e6522e42abf6cd6492f49a702e7fd9') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('2585742ce2427401004c0e191181c270b9f80fa0cad746d203480fe7ad3fe064','58dbf14df29524b6f85fa04213377c8657df4bb3') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      'e3858ba3b627d9aeaccd72e803cf39ff68a341dd836ef557f38085fa6779eead',
      '53bd414917e6522e42abf6cd6492f49a702e7fd9',
      'SOURCE_WORKFLOW', true,
      '8bfa1455e4294efa0b7afb2593daadac86c8abd6',
      'EXEC-LF-CONTRACT-CHECK-GOVERNANCE-REPIN-20260918-001',
      clock_timestamp()
    );
  else
    raise exception 'LF_CONTRACT_CHECK_GOVERNANCE_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'), coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception 'LF_CONTRACT_CHECK_GOVERNANCE_REPIN_COUNT expected=7 observed=%', v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = '.github/workflows/lf-contract-check.yml'
      and expected_sha256 = 'e3858ba3b627d9aeaccd72e803cf39ff68a341dd836ef557f38085fa6779eead'
      and expected_git_blob = '53bd414917e6522e42abf6cd6492f49a702e7fd9'
      and control_kind = 'SOURCE_WORKFLOW'
  ) then
    raise exception 'LF_CONTRACT_CHECK_GOVERNANCE_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
