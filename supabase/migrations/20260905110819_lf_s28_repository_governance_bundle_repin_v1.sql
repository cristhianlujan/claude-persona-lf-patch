do $migration$
declare
  v_workflow_sha text;
  v_workflow_blob text;
  v_validator_sha text;
  v_validator_blob text;
  v_count bigint;
begin
  select expected_sha256,expected_git_blob
    into v_workflow_sha,v_workflow_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='.github/workflows/lf-contract-check.yml';

  select expected_sha256,expected_git_blob
    into v_validator_sha,v_validator_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='scripts/lf_contract_check.py';

  if (v_workflow_sha,v_workflow_blob) is not distinct from
     ('498a0693b2d042157460c5cedfcfc946517d97233e0ce41c7e792d525400aba4','302dafc0f045b81ce7c583c6425ed20bc34e1b3b')
     and (v_validator_sha,v_validator_blob) is not distinct from
     ('73b333d996add245f5ac604c1d6103ed4e62227cee8ce21cc11b5c87599a04fb','ba6b0214bd6ca3fe88ce51a485a57fca30d8dc96') then
    null;
  elsif (v_workflow_sha,v_workflow_blob) is not distinct from
     ('d71862e5c8eabbb2c996e5a230802a2e1143cf5fa733298c19160ac927369ede','5b183387ac60589ac716a3ebb59a39195969df49')
     and (v_validator_sha,v_validator_blob) is not distinct from
     ('96a7ff7d2ea0d9b977cb2192b5febc048a6276cc86beb498aa8263308235b517','0a09f6fc482f9c2e878806e6711b1cb2a19a6535') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values
    (
      '.github/workflows/lf-contract-check.yml',
      '498a0693b2d042157460c5cedfcfc946517d97233e0ce41c7e792d525400aba4',
      '302dafc0f045b81ce7c583c6425ed20bc34e1b3b',
      'SOURCE_WORKFLOW',true,
      '97f717b596f324516c8ddb46871c094bf6ffd7f1',
      'GOV-S28-C5-GOVERNANCE-BUNDLE-REPIN-20260905-002',
      clock_timestamp()
    ),
    (
      'scripts/lf_contract_check.py',
      '73b333d996add245f5ac604c1d6103ed4e62227cee8ce21cc11b5c87599a04fb',
      'ba6b0214bd6ca3fe88ce51a485a57fca30d8dc96',
      'VALIDATOR',true,
      '97f717b596f324516c8ddb46871c094bf6ffd7f1',
      'GOV-S28-C5-GOVERNANCE-BUNDLE-REPIN-20260905-002',
      clock_timestamp()
    );
  else
    raise exception 'S28_C5_REPIN_STATE_MISMATCH workflow_sha=% workflow_blob=% validator_sha=% validator_blob=%',
      coalesce(v_workflow_sha,'<NULL>'),coalesce(v_workflow_blob,'<NULL>'),coalesce(v_validator_sha,'<NULL>'),coalesce(v_validator_blob,'<NULL>');
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'S28_C5_GOVERNANCE_COUNT expected=7 observed=%',v_count;
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-contract-check.yml'
      and expected_sha256='498a0693b2d042157460c5cedfcfc946517d97233e0ce41c7e792d525400aba4'
      and expected_git_blob='302dafc0f045b81ce7c583c6425ed20bc34e1b3b'
  ) then
    raise exception 'S28_C5_WORKFLOW_REPIN_ASSERTION_FAILED';
  end if;
  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='scripts/lf_contract_check.py'
      and expected_sha256='73b333d996add245f5ac604c1d6103ed4e62227cee8ce21cc11b5c87599a04fb'
      and expected_git_blob='ba6b0214bd6ca3fe88ce51a485a57fca30d8dc96'
  ) then
    raise exception 'S28_C5_VALIDATOR_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
