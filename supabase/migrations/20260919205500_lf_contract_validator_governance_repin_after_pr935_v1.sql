do $migration$
declare
  v_sha256 text;
  v_git_blob text;
  v_count bigint;
begin
  select expected_sha256, expected_git_blob
    into v_sha256, v_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path = 'scripts/lf_contract_check.py';

  if (v_sha256, v_git_blob) is not distinct from
     ('4bf79ae543049dc39bcc5b112ff8c7aee8c4408798d80080aaf7d952c8489c24','30752959ecade60664b4d50351a8e6106f5f972c') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('6eafe5b33055748e1c271dfe9f958b07720e387bf4987c19179aacd17c59434d','57fdc46d1c12f445bd33cbb58a713bf040fc6682') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      'scripts/lf_contract_check.py',
      '4bf79ae543049dc39bcc5b112ff8c7aee8c4408798d80080aaf7d952c8489c24',
      '30752959ecade60664b4d50351a8e6106f5f972c',
      'VALIDATOR', true,
      '670ce759c3d15c37ba2585cca866683646248d79',
      'EXEC-LF-CONTRACT-VALIDATOR-GOVERNANCE-REPIN-20260919-002',
      clock_timestamp()
    );
  else
    raise exception 'LF_CONTRACT_VALIDATOR_GOVERNANCE_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'), coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception 'LF_CONTRACT_VALIDATOR_GOVERNANCE_REPIN_COUNT expected=7 observed=%', v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = 'scripts/lf_contract_check.py'
      and expected_sha256 = '4bf79ae543049dc39bcc5b112ff8c7aee8c4408798d80080aaf7d952c8489c24'
      and expected_git_blob = '30752959ecade60664b4d50351a8e6106f5f972c'
      and control_kind = 'VALIDATOR'
  ) then
    raise exception 'LF_CONTRACT_VALIDATOR_GOVERNANCE_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
