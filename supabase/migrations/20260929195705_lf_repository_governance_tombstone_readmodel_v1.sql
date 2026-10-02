-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-20260929195705-20261001-001
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- source_version=20260929195705
-- source_name=lf_repository_governance_tombstone_readmodel_v1

-- Make append-only repository-governance tombstones effective.
-- The latest revision per path is resolved first; only then is active=true exposed.
-- This enables a later PASE source-workflow identity cutover without UPDATE/DELETE
-- and without keeping two active SOURCE_WORKFLOW paths in the canonical read model.

create or replace function public.get_lf_repository_governance_bundle_v4()
returns table(path text, expected_sha256 text, expected_git_blob text, control_kind text)
language sql
stable
security definer
set search_path='pg_catalog','private'
as $function$
  select latest.path,latest.expected_sha256,latest.expected_git_blob,latest.control_kind
  from (
    select distinct on (b.path)
           b.path,b.expected_sha256,b.expected_git_blob,b.control_kind,b.active
    from private.lf_repository_governance_bundle_v4 b
    order by b.path,b.revision_id desc
  ) latest
  where latest.active
$function$;

do $assertions$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from public.get_lf_repository_governance_bundle_v4();
  if v_count<>7 then
    raise exception 'LF_REPOSITORY_GOVERNANCE_TOMBSTONE_READMODEL_COUNT expected=7 observed=%',v_count;
  end if;

  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-contract-check.yml'
      and expected_sha256='bc7a0b29e9505837e48c815497d44ebf3fd3617d458a70aa36dd071918f7c82b'
      and expected_git_blob='163323bc2fdbffaabe8d5b06585cf71c79ded4ef'
      and control_kind='SOURCE_WORKFLOW'
  ) then
    raise exception 'LF_REPOSITORY_GOVERNANCE_TOMBSTONE_SOURCE_WORKFLOW_DRIFT';
  end if;

  if not exists (
    select 1 from public.get_lf_repository_governance_bundle_v4()
    where path='.github/workflows/lf-github-reconcile-v3.yml'
      and expected_sha256='ba3332ae25bb403cc58080c1b17a63db9bcd14f9d94e5ced09817f27c005845a'
      and expected_git_blob='0bfdc24e265bcbc2dd320c10d333fa12e8b68b51'
      and control_kind='RECONCILIATION_WORKFLOW'
  ) then
    raise exception 'LF_REPOSITORY_GOVERNANCE_TOMBSTONE_RECONCILIATION_DRIFT';
  end if;

  if exists (
    select 1 from private.lf_repository_governance_bundle_v4
    where path='sandbox/__pase_governance_tombstone_probe__'
  ) then
    raise exception 'LF_REPOSITORY_GOVERNANCE_TOMBSTONE_PROBE_RESIDUE';
  end if;
end;
$assertions$;
