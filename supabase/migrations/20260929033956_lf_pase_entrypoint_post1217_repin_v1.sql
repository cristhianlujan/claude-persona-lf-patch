-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260929033956-20261001-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260929033956
-- source_name=lf_pase_entrypoint_post1217_repin_v1

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
     ('9aef8fb4bc631d89753b8eb7e687c41f7d317bbe747baeab49a1c29c29b5989e',
      'b1b49516bfc29a07d223fa23b8bf4d1d91c248bb') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('19cfcbb225d6e6fed6b39ec9264c7792cc453b45f8d268ef273b06c56337e383',
         '9239331863126cbd1fd4dcee6cbf355fba868c26') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      '9aef8fb4bc631d89753b8eb7e687c41f7d317bbe747baeab49a1c29c29b5989e',
      'b1b49516bfc29a07d223fa23b8bf4d1d91c248bb',
      'SOURCE_WORKFLOW', true,
      '12ba6410e17b69dbc11a292fcd00b23d69ca16fb',
      'EXEC-PASE-GITHUB-ENTRYPOINT-PR1217-20260928-001',
      clock_timestamp()
    );
  else
    raise exception 'LF_PASE_ENTRYPOINT_POST1217_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'), coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception 'LF_PASE_ENTRYPOINT_POST1217_REPIN_COUNT expected=7 observed=%', v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = '.github/workflows/lf-contract-check.yml'
      and expected_sha256 = '9aef8fb4bc631d89753b8eb7e687c41f7d317bbe747baeab49a1c29c29b5989e'
      and expected_git_blob = 'b1b49516bfc29a07d223fa23b8bf4d1d91c248bb'
      and control_kind = 'SOURCE_WORKFLOW'
  ) then
    raise exception 'LF_PASE_ENTRYPOINT_POST1217_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
