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
     ('6eafe5b33055748e1c271dfe9f958b07720e387bf4987c19179aacd17c59434d','57fdc46d1c12f445bd33cbb58a713bf040fc6682') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('ed6cdba7db6db43d3906be48abda82b4328aa8b0d5a865543ea57721160cabde','d9e9d1f4955229f97b8f60aaa0eeedb0d0827cdf') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      'scripts/lf_contract_check.py',
      '6eafe5b33055748e1c271dfe9f958b07720e387bf4987c19179aacd17c59434d',
      '57fdc46d1c12f445bd33cbb58a713bf040fc6682',
      'VALIDATOR', true,
      'd3281cc531353cf52e56619c14da5230d7ead5f0',
      'EXEC-LF-CONTRACT-VALIDATOR-GOVERNANCE-REPIN-20260918-001',
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
      and expected_sha256 = '6eafe5b33055748e1c271dfe9f958b07720e387bf4987c19179aacd17c59434d'
      and expected_git_blob = '57fdc46d1c12f445bd33cbb58a713bf040fc6682'
      and control_kind = 'VALIDATOR'
  ) then
    raise exception 'LF_CONTRACT_VALIDATOR_GOVERNANCE_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
