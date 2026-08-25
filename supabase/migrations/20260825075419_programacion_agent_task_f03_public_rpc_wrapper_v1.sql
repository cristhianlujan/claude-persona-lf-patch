create or replace function public.fn_record_f03_oidc_audit_verdict_v1(
  p_task_id bigint,
  p_task_sha256 text,
  p_generation_source_sha256 text,
  p_job_workflow_ref text,
  p_job_workflow_sha text,
  p_github_repository text,
  p_github_repository_id text,
  p_github_ref text,
  p_github_workflow text,
  p_github_workflow_ref text,
  p_github_workflow_sha text,
  p_run_id bigint,
  p_run_attempt integer,
  p_event_name text,
  p_selftest_result_sha256 text,
  p_seed_commitment text,
  p_case_manifest_sha256 text,
  p_mutation_count integer,
  p_killed_count integer
) returns jsonb
language sql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.fn_record_f03_oidc_audit_verdict_v1(
    p_task_id,p_task_sha256,p_generation_source_sha256,p_job_workflow_ref,p_job_workflow_sha,
    p_github_repository,p_github_repository_id,p_github_ref,p_github_workflow,p_github_workflow_ref,
    p_github_workflow_sha,p_run_id,p_run_attempt,p_event_name,p_selftest_result_sha256,p_seed_commitment,
    p_case_manifest_sha256,p_mutation_count,p_killed_count
  );
$function$;
revoke all on function public.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer) to service_role;
comment on function public.fn_record_f03_oidc_audit_verdict_v1(bigint,text,text,text,text,text,text,text,text,text,text,bigint,integer,text,text,text,text,integer,integer)
is 'PostgREST service_role-only wrapper for GitHub OIDC F03 attestation. No hidden challenge payload is accepted or returned.';
