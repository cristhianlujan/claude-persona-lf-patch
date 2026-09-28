-- Governance repin for .github/workflows/lf-github-reconcile-v3.yml
-- Approves the already-merged independent Contract Check self-change admission change
-- introduced by commit 48c35eaaa11b0a7bd2dd10fbcc268df81f60eadf.
-- No workflow behavior is changed here; only the canonical governance fingerprint is advanced.

do $migration$
declare
  v_sha256 text;
  v_git_blob text;
  v_count bigint;
begin
  select expected_sha256,expected_git_blob
    into v_sha256,v_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path='.github/workflows/lf-github-reconcile-v3.yml';

  if (v_sha256,v_git_blob) is not distinct from
     ('db3ba61a75130207c9528a4393edff3794299097d2e4563a3e8292902321a1b5',
      '95751ee25c3db4d19e68680d24350e3954c96b32') then
    null;
  elsif (v_sha256,v_git_blob) is not distinct from
        ('dd3febd8a6de892fcffc52deee8c4479cb01dd4e701607427a9696d6594b952a',
         '8d1b2a025a3a3334817d6ea548c32c0b6c41bc36') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-github-reconcile-v3.yml',
      'db3ba61a75130207c9528a4393edff3794299097d2e4563a3e8292902321a1b5',
      '95751ee25c3db4d19e68680d24350e3954c96b32',
      'RECONCILIATION_WORKFLOW',
      true,
      '48c35eaaa11b0a7bd2dd10fbcc268df81f60eadf',
      'EXEC-CHANGE-ADMISSION-GOVERNANCE-REPIN-20260928-001',
      clock_timestamp()
    );
  else
    raise exception
      'RECONCILE_CHANGE_ADMISSION_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'),
      coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*)
    into v_count
  from public.get_lf_repository_governance_bundle_v4();

  if v_count<>7 then
    raise exception
      'RECONCILE_CHANGE_ADMISSION_GOVERNANCE_COUNT expected=7 observed=%',
      v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-github-reconcile-v3.yml'
      and expected_sha256='db3ba61a75130207c9528a4393edff3794299097d2e4563a3e8292902321a1b5'
      and expected_git_blob='95751ee25c3db4d19e68680d24350e3954c96b32'
      and control_kind='RECONCILIATION_WORKFLOW'
  ) then
    raise exception 'RECONCILE_CHANGE_ADMISSION_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
