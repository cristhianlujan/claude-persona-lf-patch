
insert into private.lf_repository_governance_bundle_v4(
  path,expected_sha256,expected_git_blob,control_kind,active,
  approved_commit_sha,approved_by_execution_id
)
values (
  'scripts/lf_contract_check.py',
  '75efc0adb24a1c8f1a48fbb4aff5950e6484b86c42797fdade31cb501bf374a6',
  '2eee5f6742c9b167c3403fe8c308bee6da19e10d',
  'VALIDATOR',
  true,
  '26817c67362cebbb7de63611d68c8b41b4fdbdbe',
  'WORK-PR93-POSTMERGE-PIN-REPAIR-20260809'
);

do $assertions$
declare
  governance_count bigint;
  drift_count bigint;
begin
  select count(*) into governance_count
  from public.get_lf_repository_governance_bundle_v4();
  if governance_count <> 7 then
    raise exception 'governance bundle count mismatch expected 7, got %', governance_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path='scripts/lf_contract_check.py'
      and expected_sha256='75efc0adb24a1c8f1a48fbb4aff5950e6484b86c42797fdade31cb501bf374a6'
      and expected_git_blob='2eee5f6742c9b167c3403fe8c308bee6da19e10d'
      and control_kind='VALIDATOR'
  ) then
    raise exception 'validator governance revision missing';
  end if;

  select count(*) into drift_count
  from public.v_lf_schema_fingerprint_drift_v13
  where drifted or missing;
  if drift_count <> 0 then
    raise exception 'baseline v13 unexpected drift count %', drift_count;
  end if;
end;
$assertions$;
