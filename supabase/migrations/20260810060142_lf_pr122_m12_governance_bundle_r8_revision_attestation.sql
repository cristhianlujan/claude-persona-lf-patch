begin;

do $assertions$
declare
  governance_count bigint;
  selected_revision_count bigint;
begin
  select count(*) into governance_count
  from public.get_lf_repository_governance_bundle_v4();

  if governance_count<>7 then
    raise exception 'governance bundle count mismatch expected 7, got %',governance_count;
  end if;

  select count(*) into selected_revision_count
  from public.get_lf_repository_governance_bundle_v4()
  where path='sandbox/lf_contract_gate_test/r8_continuous_audit.py'
    and expected_sha256='bed17e3e4f89dd68ba93872a03123236eef9d101b5c8ead85ff1dfa8193c1973'
    and expected_git_blob='3e8a5bc0ce6dd9851591fa63378cdb104e4f9a2e'
    and control_kind='VALIDATOR';

  if selected_revision_count<>1 then
    raise exception 'merged R8 governance revision was not selected';
  end if;

  if not exists (
    select 1
    from private.lf_repository_governance_bundle_v4
    where path='sandbox/lf_contract_gate_test/r8_continuous_audit.py'
      and expected_sha256='bed17e3e4f89dd68ba93872a03123236eef9d101b5c8ead85ff1dfa8193c1973'
      and expected_git_blob='3e8a5bc0ce6dd9851591fa63378cdb104e4f9a2e'
      and approved_commit_sha='0deeb8f918a4bdde5e09bc24624e91e2d61008e3'
      and approved_by_execution_id='WORK-PR122-M12-POSTMERGE-GOVERNANCE-20260810'
      and active
  ) then
    raise exception 'merged R8 append-only governance evidence missing';
  end if;
end;
$assertions$;

commit;
