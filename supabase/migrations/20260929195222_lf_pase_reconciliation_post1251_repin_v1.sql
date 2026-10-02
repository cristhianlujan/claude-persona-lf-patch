-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260929195222-20261001-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260929195222
-- source_name=lf_pase_reconciliation_post1251_repin_v1

-- Post-PR1251 governance repin for .github/workflows/lf-github-reconcile-v3.yml.
-- Advances only the canonical governance fingerprint to exact main
-- dbc07b79563e16095c04821a8f05edce21bada88 bytes.
-- No workflow behavior, ruleset, PASE trigger, or legacy retirement is changed here.

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
     ('ba3332ae25bb403cc58080c1b17a63db9bcd14f9d94e5ced09817f27c005845a',
      '0bfdc24e265bcbc2dd320c10d333fa12e8b68b51') then
    null;
  elsif (v_sha256,v_git_blob) is not distinct from
        ('db3ba61a75130207c9528a4393edff3794299097d2e4563a3e8292902321a1b5',
         '95751ee25c3db4d19e68680d24350e3954c96b32') then
    insert into private.lf_repository_governance_bundle_v4(
      path,expected_sha256,expected_git_blob,control_kind,active,
      approved_commit_sha,approved_by_execution_id,approved_at
    ) values (
      '.github/workflows/lf-github-reconcile-v3.yml',
      'ba3332ae25bb403cc58080c1b17a63db9bcd14f9d94e5ced09817f27c005845a',
      '0bfdc24e265bcbc2dd320c10d333fa12e8b68b51',
      'RECONCILIATION_WORKFLOW',
      true,
      'dbc07b79563e16095c04821a8f05edce21bada88',
      'EXEC-PASE-RECONCILIATION-POST1251-REPIN-20260929-001',
      clock_timestamp()
    );
  else
    raise exception
      'PASE_RECONCILIATION_POST1251_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'),
      coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*)
    into v_count
  from public.get_lf_repository_governance_bundle_v4();

  if v_count<>7 then
    raise exception
      'PASE_RECONCILIATION_POST1251_GOVERNANCE_COUNT expected=7 observed=%',
      v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-github-reconcile-v3.yml'
      and expected_sha256='ba3332ae25bb403cc58080c1b17a63db9bcd14f9d94e5ced09817f27c005845a'
      and expected_git_blob='0bfdc24e265bcbc2dd320c10d333fa12e8b68b51'
      and control_kind='RECONCILIATION_WORKFLOW'
  ) then
    raise exception 'PASE_RECONCILIATION_POST1251_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
