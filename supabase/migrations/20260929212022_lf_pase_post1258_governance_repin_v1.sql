-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260929212022-20261001-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260929212022
-- source_name=lf_pase_post1258_governance_repin_v1

-- Repin only the two governed workflow fingerprints changed by the PASE cutover.
-- Exact-main evidence comes from source run 36631790668 at
-- 0edb84e8eaf5f6e167e0f33f6559922a31ef3bfb.
-- No SOURCE_WORKFLOW path switch, ruleset activation, or legacy retirement occurs here.

do $migration$
declare
  v_source_sha256 text;
  v_source_git_blob text;
  v_reconcile_sha256 text;
  v_reconcile_git_blob text;
  v_count bigint;
begin
  select expected_sha256, expected_git_blob
    into v_source_sha256, v_source_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path = '.github/workflows/lf-contract-check.yml';

  if (v_source_sha256, v_source_git_blob) is not distinct from
     ('74f8011df5b1d3d5fe452ee2a8c1d14db1e9be316f8b271985c8850c970f078c',
      '4355bee301e90d494298cbf1e735868a86833d74') then
    null;
  elsif (v_source_sha256, v_source_git_blob) is not distinct from
        ('bc7a0b29e9505837e48c815497d44ebf3fd3617d458a70aa36dd071918f7c82b',
         '163323bc2fdbffaabe8d5b06585cf71c79ded4ef') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      '.github/workflows/lf-contract-check.yml',
      '74f8011df5b1d3d5fe452ee2a8c1d14db1e9be316f8b271985c8850c970f078c',
      '4355bee301e90d494298cbf1e735868a86833d74',
      'SOURCE_WORKFLOW', true,
      'b89e50680275c4423ac19c35adf37155877627b8',
      'EXEC-PASE-POST1258-SOURCE-REPIN-20260929-001',
      clock_timestamp()
    );
  else
    raise exception
      'LF_PASE_POST1258_SOURCE_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_source_sha256,'<NULL>'),
      coalesce(v_source_git_blob,'<NULL>');
  end if;

  select expected_sha256, expected_git_blob
    into v_reconcile_sha256, v_reconcile_git_blob
  from public.get_lf_repository_governance_bundle_v4()
  where path = '.github/workflows/lf-github-reconcile-v3.yml';

  if (v_reconcile_sha256, v_reconcile_git_blob) is not distinct from
     ('213dfe5f5b8393508958110f8eccdc7935b6491bb29bd34ca010625e13eee808',
      '07da24909acac57b2183b473dadbb79c13967ca5') then
    null;
  elsif (v_reconcile_sha256, v_reconcile_git_blob) is not distinct from
        ('ba3332ae25bb403cc58080c1b17a63db9bcd14f9d94e5ced09817f27c005845a',
         '0bfdc24e265bcbc2dd320c10d333fa12e8b68b51') then
    insert into private.lf_repository_governance_bundle_v4(
      path, expected_sha256, expected_git_blob, control_kind, active,
      approved_commit_sha, approved_by_execution_id, approved_at
    ) values (
      '.github/workflows/lf-github-reconcile-v3.yml',
      '213dfe5f5b8393508958110f8eccdc7935b6491bb29bd34ca010625e13eee808',
      '07da24909acac57b2183b473dadbb79c13967ca5',
      'RECONCILIATION_WORKFLOW', true,
      '0edb84e8eaf5f6e167e0f33f6559922a31ef3bfb',
      'EXEC-PASE-POST1258-RECONCILIATION-REPIN-20260929-001',
      clock_timestamp()
    );
  else
    raise exception
      'LF_PASE_POST1258_RECONCILIATION_REPIN_STATE_MISMATCH sha256=% git_blob=%',
      coalesce(v_reconcile_sha256,'<NULL>'),
      coalesce(v_reconcile_git_blob,'<NULL>');
  end if;

  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 7 then
    raise exception
      'LF_PASE_POST1258_GOVERNANCE_COUNT expected=7 observed=%',
      v_count;
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = '.github/workflows/lf-contract-check.yml'
      and expected_sha256 = '74f8011df5b1d3d5fe452ee2a8c1d14db1e9be316f8b271985c8850c970f078c'
      and expected_git_blob = '4355bee301e90d494298cbf1e735868a86833d74'
      and control_kind = 'SOURCE_WORKFLOW'
  ) then
    raise exception 'LF_PASE_POST1258_SOURCE_REPIN_ASSERTION_FAILED';
  end if;

  if not exists (
    select 1
    from public.get_lf_repository_governance_bundle_v4()
    where path = '.github/workflows/lf-github-reconcile-v3.yml'
      and expected_sha256 = '213dfe5f5b8393508958110f8eccdc7935b6491bb29bd34ca010625e13eee808'
      and expected_git_blob = '07da24909acac57b2183b473dadbb79c13967ca5'
      and control_kind = 'RECONCILIATION_WORKFLOW'
  ) then
    raise exception 'LF_PASE_POST1258_RECONCILIATION_REPIN_ASSERTION_FAILED';
  end if;
end;
$migration$;
