-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260929155733-20261001-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260929155733
-- source_name=lf_pase_entrypoint_post1236_repin_v1

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
     ('bc7a0b29e9505837e48c815497d44ebf3fd3617d458a70aa36dd071918f7c82b',
      '163323bc2fdbffaabe8d5b06585cf71c79ded4ef') then
    null;
  elsif (v_sha256, v_git_blob) is not distinct from
        ('fa62639b157e8346b65525c42894358e96e95241455f136acc242140b9bd8fca',
         '27c8418f2f382e5b2b305e7f4791c5848c6eff9f') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      'bc7a0b29e9505837e48c815497d44ebf3fd3617d458a70aa36dd071918f7c82b',
      '163323bc2fdbffaabe8d5b06585cf71c79ded4ef',
      'SOURCE_WORKFLOW', true,
      '5742e46133aae85df90c40a266dd430d7ef4e237',
      'EXEC-PASE-ENTRYPOINT-PREEMPTION-PR1236-20260929-001',
      clock_timestamp()
    );
  else
    raise exception 'LF_PASE_ENTRYPOINT_POST1236_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_sha256,'<NULL>'), coalesce(v_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception 'LF_PASE_ENTRYPOINT_POST1236_REPIN_COUNT expected=7 observed=%', v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = '.github/workflows/lf-contract-check.yml'
      and expected_sha256 = 'bc7a0b29e9505837e48c815497d44ebf3fd3617d458a70aa36dd071918f7c82b'
      and expected_git_blob = '163323bc2fdbffaabe8d5b06585cf71c79ded4ef'
      and control_kind = 'SOURCE_WORKFLOW'
  ) then
    raise exception 'LF_PASE_ENTRYPOINT_POST1236_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
