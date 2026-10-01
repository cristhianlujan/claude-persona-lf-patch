-- SADM-PP-L5-023 / legacy GitHub reconciliation workflow retirement.
-- Source-first: apply only after PR #1378 is merged at eda30434f4117a7c1a038884173313e33373abe0.
-- No CASCADE, runtime/deploy, production activation, Edge Function undeploy or bulk retirement.

do $migration$
declare
  v_exec constant text := 'EXEC-L5-023-LEGACY-RECON-WORKFLOW-RETIREMENT-20261001';
  v_path constant text := '.github/workflows/lf-github-reconcile-v3.yml';
  v_expected_sha constant text := '213dfe5f5b8393508958110f8eccdc7935b6491bb29bd34ca010625e13eee808';
  v_expected_blob constant text := '07da24909acac57b2183b473dadbb79c13967ca5';
  v_merge_sha constant text := 'eda30434f4117a7c1a038884173313e33373abe0';
  v_count bigint;
begin
  if not exists (
    select 1
      from public.lf_capability_current
     where capability_code='GITHUB_RECONCILIATION'
       and version='1.0.0'
  ) then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_CANONICAL_REPLACEMENT_NOT_CURRENT';
  end if;

  if not exists (
    select 1
      from public.lf_capability_current
     where capability_code='POST_PASE_ORCHESTRATOR'
       and version='1.0.0'
  ) then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_ORCHESTRATOR_NOT_CURRENT';
  end if;

  if not exists (
    select 1
      from public.lf_activos
     where codigo_activo='CONSUMER_BINDINGS'
       and archived_at is null
       and estado_operativo='ACTIVO'
       and version='1.0.0'
  ) then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_BINDINGS_NOT_ACTIVE';
  end if;

  if not exists (
    select 1
      from public.get_lf_repository_governance_bundle_v4()
     where path=v_path
       and expected_sha256=v_expected_sha
       and expected_git_blob=v_expected_blob
       and control_kind='RECONCILIATION_WORKFLOW'
  ) then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_GOVERNANCE_AUTHORITY_MISMATCH';
  end if;

  insert into private.lf_repository_governance_bundle_v4(
    path,expected_sha256,expected_git_blob,control_kind,active,
    approved_commit_sha,approved_by_execution_id,approved_at
  ) values (
    v_path,v_expected_sha,v_expected_blob,'RECONCILIATION_WORKFLOW',false,
    v_merge_sha,v_exec,clock_timestamp()
  );

  update public.lf_activos
     set raw_payload=(coalesce(raw_payload,'{}'::jsonb)-'legacy_workflow') || jsonb_build_object(
           'legacy_workflow_state','RETIRED',
           'legacy_workflow_retired_path',v_path,
           'legacy_workflow_retired_merge_sha',v_merge_sha,
           'legacy_workflow_retired_by_execution_id',v_exec
         ),
         metadata=(coalesce(metadata,'{}'::jsonb)-'legacy_workflow_preserved') || jsonb_build_object(
           'legacy_workflow_preserved',false,
           'legacy_workflow_state','RETIRED',
           'legacy_workflow_retired_path',v_path,
           'legacy_workflow_retired_merge_sha',v_merge_sha,
           'legacy_workflow_retired_by_execution_id',v_exec,
           'legacy_edge_function_preserved',true
         ),
         updated_at=clock_timestamp(),
         updated_by_execution_id=v_exec
   where codigo_activo='GITHUB_RECONCILIATION' and archived_at is null;
  if not found then raise exception 'BLOCK_LEGACY_RECON_RETIRE_ASSET_NOT_FOUND'; end if;

  if exists (
    select 1 from public.get_lf_repository_governance_bundle_v4() where path=v_path
  ) then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_GOVERNANCE_TOMBSTONE_NOT_EFFECTIVE';
  end if;

  if not exists (
    select 1 from public.lf_activos
     where codigo_activo='GITHUB_RECONCILIATION' and archived_at is null
       and metadata->>'legacy_workflow_preserved'='false'
       and metadata->>'legacy_workflow_state'='RETIRED'
       and metadata->>'legacy_edge_function_preserved'='true'
  ) then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_ASSET_READBACK_FAILED';
  end if;

  select count(*) into v_count from public.get_lf_repository_governance_bundle_v4();
  if v_count <> 6 then
    raise exception 'BLOCK_LEGACY_RECON_RETIRE_BUNDLE_COUNT expected=6 observed=%',v_count;
  end if;
end
$migration$;
