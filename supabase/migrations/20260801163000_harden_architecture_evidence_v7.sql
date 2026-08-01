-- Architecture V7 hardening.
-- Applied to Supabase project mhwmirqcgxxukpctffuv on 2026-08-01.
-- Removes anonymous promotion/sync/inventory execution and requires native
-- GitHub branch protection for effective PASS and promotion.

begin;

grant lf_governance_owner_v3 to postgres with set true;
grant create on schema private, public to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

revoke execute on function public.promote_lf_artifact_pass_v3(bigint,bigint,bigint[],text)
  from public, anon, authenticated;
revoke execute on function public.sync_lf_artifact_content_from_repository_v3(bigint,bigint,text,text)
  from public, anon, authenticated;
revoke execute on function public.get_lf_github_reconciliation_inventory_v3()
  from public, anon, authenticated;
revoke execute on function private.fn_baseline_architecture_schema_v3(text)
  from public, anon, authenticated, service_role;

grant execute on function public.promote_lf_artifact_pass_v3(bigint,bigint,bigint[],text)
  to service_role;
grant execute on function public.sync_lf_artifact_content_from_repository_v3(bigint,bigint,text,text)
  to service_role;
grant execute on function public.get_lf_github_reconciliation_inventory_v3()
  to service_role;

create or replace function private.fn_lf_artifact_v3_evidence_valid(p_artifact_id bigint)
returns boolean
language plpgsql
stable
set search_path to 'pg_catalog','public','private'
as $function$
declare
  a private.lf_skill_artifacts%rowtype;
  e jsonb;
  g private.lf_github_reconciliation_runs_v3%rowtype;
  v_test_id bigint;
  v_test_count integer:=0;
  v_event public.lf_eventos%rowtype;
begin
  select * into a from private.lf_skill_artifacts where id=p_artifact_id;
  if not found or not a.is_current or a.validation_status<>'PASS_WITH_EVIDENCE' then
    return false;
  end if;

  e:=a.validation_evidence->'artifact_evidence_v3';
  if jsonb_typeof(e)<>'object'
     or e->>'evidence_schema_version'<>'artifact-evidence/v3'
     or e->>'result'<>'PASS_WITH_EVIDENCE'
     or e->>'test_evidence_mode'<>'TEST_EVIDENCE_V3'
     or e->>'artifact_sha256' is distinct from a.content_sha256
     or e->>'relative_path' is distinct from a.relative_path
     or coalesce(e->>'artifact_git_blob','') !~ '^[0-9a-f]{40}$'
     or coalesce(e->>'merge_commit_sha','') !~ '^[0-9a-f]{40}$'
     or jsonb_typeof(e->'workflow_run_id')<>'number'
     or jsonb_typeof(e->'github_reconciliation_run_id')<>'number'
     or jsonb_typeof(e->'external_verification_event_id')<>'number'
     or jsonb_typeof(e->'gate_test_run_ids')<>'array'
     or jsonb_array_length(e->'gate_test_run_ids')<1
     or jsonb_typeof(e->'dependencies_passed')<>'boolean'
     or not (e->>'dependencies_passed')::boolean
     or private.fn_lf_try_timestamptz(e->>'verified_at') is null
  then
    return false;
  end if;

  select * into g
  from private.lf_github_reconciliation_runs_v3
  where artifact_id=a.id and authoritative
  order by observed_at desc,id desc
  limit 1;

  if not found
     or g.id<>(e->>'github_reconciliation_run_id')::bigint
     or g.result<>'PASS'
     or g.target_branch<>'main'
     or not g.merged
     or g.pr_state<>'MERGED'
     or g.reconciled_at<clock_timestamp()-interval '24 hours'
     or g.observed_at>clock_timestamp()+interval '5 minutes'
     or g.branch_protection_status<>'VERIFIED'
     or coalesce(g.details->>'actual_branch_protection_status','')<>'VERIFIED'
     or g.merge_commit_sha is distinct from e->>'merge_commit_sha'
     or g.workflow_run_id<>(e->>'workflow_run_id')::bigint
     or g.artifact_git_blob is distinct from e->>'artifact_git_blob'
     or g.artifact_sha256 is distinct from a.content_sha256
     or not g.artifact_exercised_by_workflow
     or g.audit_manifest_sha256 is null
     or g.workflow_event<>'push'
     or g.workflow_head_sha<>g.merge_commit_sha
     or g.workflow_conclusion<>'success'
     or g.writer_authentication<>'HMAC_TOKEN_V5'
     or coalesce(g.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$'
  then
    return false;
  end if;

  select * into v_event
  from public.lf_eventos
  where id=(e->>'external_verification_event_id')::bigint;

  if not found
     or v_event.id<>g.evidence_event_id
     or v_event.evento_tipo<>'EXTERNAL_CI_VERIFICATION_COMPLETED'
     or v_event.payload->>'evidence_schema_version'<>'external-ci-verification/v3'
     or v_event.payload->>'result'<>'PASS'
     or v_event.payload->>'verification_payload_sha256' is distinct from g.verification_payload_sha256
     or v_event.payload->>'writer_authentication'<>'HMAC_TOKEN_V5'
     or coalesce(v_event.payload->>'branch_protection_status','')<>'VERIFIED'
     or coalesce(v_event.payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
  then
    return false;
  end if;

  for v_test_id in
    select value::bigint from jsonb_array_elements_text(e->'gate_test_run_ids')
  loop
    v_test_count:=v_test_count+1;
    if not exists(
      select 1
      from private.lf_gate_test_runs_v3 t
      where t.id=v_test_id
        and t.artifact_id=a.id
        and t.passed
        and t.runner_type in ('GITHUB_ACTIONS_POST_MERGE','EXTERNAL_INDEPENDENT')
        and t.source_workflow_run_id=g.workflow_run_id
        and t.source_commit_sha=g.merge_commit_sha
        and t.executed_at>=g.observed_at-interval '10 minutes'
        and t.executed_at<=clock_timestamp()+interval '5 minutes'
        and t.writer_authentication='HMAC_TOKEN_V5'
        and t.writer_signature_sha256 ~ '^[0-9a-f]{64}$'
    ) then
      return false;
    end if;
  end loop;

  return v_test_count>0;
exception when others then
  return false;
end;
$function$;

create or replace function public.promote_lf_artifact_pass_v3(
  p_artifact_id bigint,
  p_reconciliation_run_id bigint,
  p_gate_test_run_ids bigint[],
  p_execution_id text
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  a private.lf_skill_artifacts%rowtype;
  g private.lf_github_reconciliation_runs_v3%rowtype;
  v_evidence jsonb;
  v_dependency_declaration jsonb;
  v_claims jsonb := '{}'::jsonb;
begin
  begin
    v_claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
  exception when others then
    v_claims:='{}'::jsonb;
  end;

  if coalesce(v_claims->>'role','')<>'service_role' then
    raise exception using errcode='42501',message='promotion requires service_role request context';
  end if;
  if nullif(btrim(coalesce(p_execution_id,'')),'') is null then
    raise exception using errcode='23514',message='promotion execution_id is required';
  end if;

  select * into a
  from private.lf_skill_artifacts
  where id=p_artifact_id and is_current
  for update;
  if not found then
    raise exception using errcode='P0002',message='current artifact not found';
  end if;

  select * into g
  from private.lf_github_reconciliation_runs_v3
  where id=p_reconciliation_run_id
    and artifact_id=p_artifact_id
    and authoritative;

  if not found
     or g.result<>'PASS'
     or g.target_branch<>'main'
     or not g.merged
     or g.pr_state<>'MERGED'
     or g.branch_protection_status<>'VERIFIED'
     or coalesce(g.details->>'actual_branch_protection_status','')<>'VERIFIED'
     or not g.artifact_exercised_by_workflow
     or g.workflow_event<>'push'
     or g.workflow_conclusion<>'success'
     or g.workflow_head_sha<>g.merge_commit_sha
     or g.artifact_sha256 is distinct from a.content_sha256
     or g.writer_authentication<>'HMAC_TOKEN_V5'
     or coalesce(g.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$'
     or g.reconciled_by_execution_id<>p_execution_id
     or g.observed_at<clock_timestamp()-interval '2 hours'
     or g.observed_at>clock_timestamp()+interval '5 minutes'
     or exists(
       select 1
       from private.lf_github_reconciliation_runs_v3 newer
       where newer.artifact_id=p_artifact_id
         and newer.authoritative
         and (newer.observed_at,newer.id)>(g.observed_at,g.id)
     )
  then
    raise exception using errcode='23514',message='reconciliation run is not natively protected, current and promotable';
  end if;

  if p_gate_test_run_ids is null
     or cardinality(p_gate_test_run_ids)<1
     or cardinality(p_gate_test_run_ids)<>(select count(distinct x) from unnest(p_gate_test_run_ids) x)
     or exists(
       select 1
       from unnest(p_gate_test_run_ids) x(id)
       where not exists(
         select 1
         from private.lf_gate_test_runs_v3 t
         where t.id=x.id
           and t.artifact_id=a.id
           and t.passed
           and t.runner_type in ('GITHUB_ACTIONS_POST_MERGE','EXTERNAL_INDEPENDENT')
           and t.source_workflow_run_id=g.workflow_run_id
           and t.source_commit_sha=g.merge_commit_sha
           and t.executed_by_execution_id=p_execution_id
           and t.executed_at>=g.observed_at-interval '10 minutes'
           and t.executed_at<=clock_timestamp()+interval '5 minutes'
           and t.writer_authentication='HMAC_TOKEN_V5'
           and t.writer_signature_sha256 ~ '^[0-9a-f]{64}$'
       )
     )
  then
    raise exception using errcode='23514',message='signed gate test set is not current and promotable';
  end if;

  v_evidence:=coalesce(a.validation_evidence,'{}'::jsonb);
  if jsonb_array_length(private.fn_lf_dependency_array(a.dependencies))=0 then
    v_dependency_declaration:=jsonb_build_object(
      'schema_version','dependency-declaration/v1',
      'mode','NO_DEPENDENCIES',
      'rationale','No internal artifact dependencies are declared; repository content, commit, workflow and signed gate evidence were independently verified.',
      'evidence_refs',jsonb_build_array(jsonb_build_object('type','COMMIT','ref',g.merge_commit_sha,'sha256',a.content_sha256)),
      'declared_by_execution_id',p_execution_id,
      'declared_at',clock_timestamp()
    );
    v_evidence:=v_evidence||jsonb_build_object('dependency_declaration',v_dependency_declaration);
  end if;

  v_evidence:=v_evidence||jsonb_build_object('artifact_evidence_v3',jsonb_build_object(
    'evidence_schema_version','artifact-evidence/v3',
    'result','PASS_WITH_EVIDENCE',
    'test_evidence_mode','TEST_EVIDENCE_V3',
    'artifact_sha256',a.content_sha256,
    'relative_path',a.relative_path,
    'artifact_git_blob',g.artifact_git_blob,
    'merge_commit_sha',g.merge_commit_sha,
    'workflow_run_id',g.workflow_run_id,
    'github_reconciliation_run_id',g.id,
    'external_verification_event_id',g.evidence_event_id,
    'gate_test_run_ids',to_jsonb(p_gate_test_run_ids),
    'repository_change_control_status','VERIFIED',
    'writer_authentication','HMAC_TOKEN_V5',
    'dependencies_passed',true,
    'verified_at',clock_timestamp()
  ));

  update private.lf_skill_artifacts
  set validation_status='PASS_WITH_EVIDENCE',
      validation_evidence=v_evidence,
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where id=a.id;

  return true;
end;
$function$;

revoke execute on function public.promote_lf_artifact_pass_v3(bigint,bigint,bigint[],text)
  from public, anon, authenticated;
grant execute on function public.promote_lf_artifact_pass_v3(bigint,bigint,bigint[],text)
  to service_role;

reset role;
revoke create on schema private, public from lf_governance_owner_v3;
revoke set option for lf_governance_owner_v3 from postgres;

commit;
