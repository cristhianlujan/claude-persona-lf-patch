-- Governance repin for scripts/lf_contract_check.py
-- Approves the current validator content whose repository-path admission responsibility
-- was delegated to Changeset Governance. No validator behavior is changed in this migration.

do $migration$
declare
  v_sha256 text;
  v_git_blob text;
  v_count bigint;
begin
  select expected_sha256,expected_git_blob
    into v_sha256,v_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='scripts/lf_contract_check.py';

  if (v_sha256,v_git_blob) is not distinct from
     ('21311317378e295c1f3c6eda0ae4845343e73758575ec364aa7cb4ac0dbe665c',
      'e623e64d966fc58d4731f2584c90ae9f98d653ae') then
    null;
  elsif (v_sha256,v_git_blob) is not distinct from
        ('befa5915e69d7d537e953d4a24d4d1a8c72c1c18b8daef0504845ad595ce2a0f',
         '5e6a1e9f0e0cd1dc6a92f4d3b4eac1425405b0c9') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      'scripts/lf_contract_check.py',
      '21311317378e295c1f3c6eda0ae4845343e73758575ec364aa7cb4ac0dbe665c',
      'e623e64d966fc58d4731f2584c90ae9f98d653ae',
      'VALIDATOR',
      true,
      '99a3b72a9d36be88b380b09da4c09aae577316bb',
      'EXEC-CONTRACT-CHECK-CHANGESET-DELEGATION-REPIN-20260928-001',
      clock_timestamp()
    );
  else
    raise exception
      'CONTRACT_CHECK_CHANGESET_DELEGATION_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'),
      coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*)
    into v_count
  from public.get_lf_repository_governance_bundle_v4();

  if v_count<>7 then
    raise exception
      'CONTRACT_CHECK_CHANGESET_DELEGATION_GOVERNANCE_COUNT expected=7 observed=%',
      v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path='scripts/lf_contract_check.py'
      and expected_sha256='21311317378e295c1f3c6eda0ae4845343e73758575ec364aa7cb4ac0dbe665c'
      and expected_git_blob='e623e64d966fc58d4731f2584c90ae9f98d653ae'
      and control_kind='VALIDATOR'
  ) then
    raise exception 'CONTRACT_CHECK_CHANGESET_DELEGATION_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
