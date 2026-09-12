-- CA-N25 remediation and V7 effective-evidence cutover.
-- Historical reconciliation rows remain immutable. Invalid compensating evidence is
-- excluded through an append-only quarantine registry and explicit V7 predicates.

begin;

create table if not exists private.lf_github_reconciliation_quarantine_v7 (
  reconciliation_run_id bigint primary key
    references private.lf_github_reconciliation_runs_v3(id),
  artifact_id bigint not null,
  quarantine_code text not null,
  quarantine_reason text not null,
  source_branch_protection_status text,
  source_writer_authentication text,
  quarantined_by_execution_id text not null,
  quarantined_at timestamptz not null default clock_timestamp()
);

-- Capture the known compromised/compensating population by invariant, not by IDs.
insert into private.lf_github_reconciliation_quarantine_v7(
  reconciliation_run_id,
  artifact_id,
  quarantine_code,
  quarantine_reason,
  source_branch_protection_status,
  source_writer_authentication,
  quarantined_by_execution_id
)
select
  g.id,
  g.artifact_id,
  'LEGACY_COMPENSATING_CONTROL_NOT_NATIVE',
  'Reconciliation used VERIFIED_COMPENSATING_CONTROLS and predates the keyed OIDC HMAC writer V7.',
  g.branch_protection_status,
  g.writer_authentication,
  'EXEC-ARCH-V7-QUARANTINE-COMPENSATING-EVIDENCE'
from private.lf_github_reconciliation_runs_v3 g
where g.branch_protection_status='VERIFIED_COMPENSATING_CONTROLS'
   or (
     g.result='PASS'
     and g.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
   )
on conflict (reconciliation_run_id) do nothing;

alter table private.lf_github_reconciliation_quarantine_v7
  owner to lf_governance_owner_v3;
alter table private.lf_github_reconciliation_quarantine_v7
  enable row level security;
alter table private.lf_github_reconciliation_quarantine_v7
  force row level security;

revoke all on private.lf_github_reconciliation_quarantine_v7
  from public,anon,authenticated,service_role;
grant select on private.lf_github_reconciliation_quarantine_v7
  to lf_governance_owner_v3;

drop policy if exists pol_lf_github_reconciliation_quarantine_v7_owner
  on private.lf_github_reconciliation_quarantine_v7;
create policy pol_lf_github_reconciliation_quarantine_v7_owner
  on private.lf_github_reconciliation_quarantine_v7
  for select
  to lf_governance_owner_v3
  using (true);

drop trigger if exists trg_00_guard_lf_github_reconciliation_quarantine_v7
  on private.lf_github_reconciliation_quarantine_v7;
create trigger trg_00_guard_lf_github_reconciliation_quarantine_v7
before insert or update or delete
on private.lf_github_reconciliation_quarantine_v7
for each row execute function private.fn_guard_governed_relation_v3('APPEND_ONLY');
alter table private.lf_github_reconciliation_quarantine_v7
  enable always trigger trg_00_guard_lf_github_reconciliation_quarantine_v7;

create or replace function private.fn_lf_artifact_v3_evidence_valid(p_artifact_id bigint)
returns boolean
language plpgsql
stable
set search_path to ''
as $function$
declare
  a private.lf_skill_artifacts%rowtype;
  e jsonb;
  g private.lf_github_reconciliation_runs_v3%rowtype;
  v_test_id bigint;
  v_test_count integer:=0;
  v_event public.lf_eventos%rowtype;
begin
  select * into a
  from private.lf_skill_artifacts
  where id=p_artifact_id;

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
     or e->>'writer_authentication'<>'GITHUB_OIDC_HMAC_NONCE_V7'
  then
    return false;
  end if;

  select * into g
  from private.lf_github_reconciliation_runs_v3 candidate
  where candidate.artifact_id=a.id
    and candidate.authoritative
    and candidate.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
    and not exists (
      select 1
      from private.lf_github_reconciliation_quarantine_v7 q
      where q.reconciliation_run_id=candidate.id
    )
  order by candidate.observed_at desc,candidate.id desc
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
     or not private.fn_reconciliation_nonce_v7_valid(g.id)
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
     or v_event.payload->>'writer_authentication'<>'GITHUB_OIDC_HMAC_NONCE_V7'
     or coalesce(v_event.payload->>'branch_protection_status','')<>'VERIFIED'
     or coalesce(v_event.payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
  then
    return false;
  end if;

  for v_test_id in
    select value::bigint
    from jsonb_array_elements_text(e->'gate_test_run_ids')
  loop
    v_test_count:=v_test_count+1;
    if not exists (
      select 1
      from private.lf_gate_test_runs_v3 t
      where t.id=v_test_id
        and t.artifact_id=a.id
        and t.passed
        and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
        and t.runner_type in ('GITHUB_ACTIONS_POST_MERGE','EXTERNAL_INDEPENDENT')
        and t.source_workflow_run_id=g.workflow_run_id
        and t.source_commit_sha=g.merge_commit_sha
        and t.executed_at>=g.observed_at-interval '10 minutes'
        and t.executed_at<=clock_timestamp()+interval '5 minutes'
        and private.fn_gate_nonce_v7_valid(t.id)
    ) then
      return false;
    end if;
  end loop;

  return v_test_count>0;
exception
  when invalid_text_representation
    or numeric_value_out_of_range
    or datetime_field_overflow then
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
set search_path to ''
as $function$
declare
  a private.lf_skill_artifacts%rowtype;
  g private.lf_github_reconciliation_runs_v3%rowtype;
  v_evidence jsonb;
  v_dependency_declaration jsonb;
  v_claims jsonb:='{}'::jsonb;
begin
  begin
    v_claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
  exception
    when invalid_text_representation then
      raise exception using errcode='42501',message='promotion JWT claims are malformed';
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
  from private.lf_github_reconciliation_runs_v3 candidate
  where candidate.id=p_reconciliation_run_id
    and candidate.artifact_id=p_artifact_id
    and candidate.authoritative
    and candidate.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
    and not exists (
      select 1
      from private.lf_github_reconciliation_quarantine_v7 q
      where q.reconciliation_run_id=candidate.id
    );

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
     or not private.fn_reconciliation_nonce_v7_valid(g.id)
     or g.reconciled_by_execution_id<>p_execution_id
     or g.observed_at<clock_timestamp()-interval '2 hours'
     or g.observed_at>clock_timestamp()+interval '5 minutes'
     or exists (
       select 1
       from private.lf_github_reconciliation_runs_v3 newer
       where newer.artifact_id=p_artifact_id
         and newer.authoritative
         and not exists (
           select 1
           from private.lf_github_reconciliation_quarantine_v7 q
           where q.reconciliation_run_id=newer.id
         )
         and (newer.observed_at,newer.id)>(g.observed_at,g.id)
     )
  then
    raise exception using
      errcode='23514',
      message='reconciliation is not native-protected, current, keyed-nonce-authenticated and promotable';
  end if;

  if p_gate_test_run_ids is null
     or cardinality(p_gate_test_run_ids)<1
     or cardinality(p_gate_test_run_ids)<>(select count(distinct x) from unnest(p_gate_test_run_ids) x)
     or exists (
       select 1
       from unnest(p_gate_test_run_ids) x(id)
       where not exists (
         select 1
         from private.lf_gate_test_runs_v3 t
         where t.id=x.id
           and t.artifact_id=a.id
           and t.passed
           and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
           and t.runner_type in ('GITHUB_ACTIONS_POST_MERGE','EXTERNAL_INDEPENDENT')
           and t.source_workflow_run_id=g.workflow_run_id
           and t.source_commit_sha=g.merge_commit_sha
           and t.executed_by_execution_id=p_execution_id
           and t.executed_at>=g.observed_at-interval '10 minutes'
           and t.executed_at<=clock_timestamp()+interval '5 minutes'
           and private.fn_gate_nonce_v7_valid(t.id)
       )
     )
  then
    raise exception using
      errcode='23514',
      message='keyed-nonce-authenticated gate test set is not current and promotable';
  end if;

  v_evidence:=coalesce(a.validation_evidence,'{}'::jsonb);
  if jsonb_array_length(private.fn_lf_dependency_array(a.dependencies))=0 then
    v_dependency_declaration:=jsonb_build_object(
      'schema_version','dependency-declaration/v1',
      'mode','NO_DEPENDENCIES',
      'rationale','No internal dependencies are declared; repository, native protection, OIDC HMAC nonce and gate evidence were independently verified.',
      'evidence_refs',jsonb_build_array(
        jsonb_build_object('type','COMMIT','ref',g.merge_commit_sha,'sha256',a.content_sha256)
      ),
      'declared_by_execution_id',p_execution_id,
      'declared_at',clock_timestamp()
    );
    v_evidence:=v_evidence||jsonb_build_object('dependency_declaration',v_dependency_declaration);
  end if;

  v_evidence:=v_evidence||jsonb_build_object(
    'artifact_evidence_v3',jsonb_build_object(
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
      'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
      'dependencies_passed',true,
      'verified_at',clock_timestamp()
    )
  );

  update private.lf_skill_artifacts
  set validation_status='PASS_WITH_EVIDENCE',
      validation_evidence=v_evidence,
      updated_by_execution_id=p_execution_id,
      updated_at=clock_timestamp()
  where id=a.id;

  return true;
end;
$function$;

revoke all on function public.promote_lf_artifact_pass_v3(bigint,bigint,bigint[],text)
  from public,anon,authenticated;
grant execute on function public.promote_lf_artifact_pass_v3(bigint,bigint,bigint[],text)
  to service_role;

-- Keep V8 as the public closure contract while replacing its evidence semantics.
create or replace view public.v_lf_architecture_closure_v8
with (security_invoker=true)
as
with base as (
  select * from public.v_lf_architecture_closure_v7
), latest_g as (
  select distinct on (g.artifact_id) g.*
  from private.lf_github_reconciliation_runs_v3 g
  where g.authoritative
    and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
    and not exists (
      select 1
      from private.lf_github_reconciliation_quarantine_v7 q
      where q.reconciliation_run_id=g.id
    )
  order by g.artifact_id,g.observed_at desc,g.id desc
), reconciliation_metrics as (
  select
    count(g.id) as reconciliation_count,
    count(*) filter (
      where g.result='PASS'
        and g.branch_protection_status='VERIFIED'
        and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
        and private.fn_reconciliation_nonce_v7_valid(g.id)
    ) as github_pass_count
  from private.lf_artifact_inventory_baseline_v3 i
  left join latest_g g on g.artifact_id=i.artifact_id
  where i.required_for_closure
), latest_gate as (
  select distinct on (t.artifact_id) t.*
  from private.lf_gate_test_runs_v3 t
  where t.test_code='POST_MERGE-LF-CONTRACT-CHECK-V3'
    and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
  order by t.artifact_id,t.executed_at desc,t.id desc
), gate_metrics as (
  select
    count(t.id) as latest_gate_tests,
    count(*) filter (
      where t.passed and private.fn_gate_nonce_v7_valid(t.id)
    ) as passed_gate_tests,
    count(*) filter (
      where t.id is null or not t.passed or not private.fn_gate_nonce_v7_valid(t.id)
    ) as failed_gate_tests
  from private.lf_artifact_inventory_baseline_v3 i
  left join latest_gate t on t.artifact_id=i.artifact_id
  where i.required_for_closure
), edge_state as (
  select exists (
    select 1
    from private.lf_edge_function_deployment_evidence_v6 e
    where e.function_slug='lf-github-reconcile-v3'
      and e.deployed_version>=7
      and e.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
      and e.verification_source='SUPABASE_CONTROL_PLANE_READBACK'
  ) as edge_reconciler_v7_ready
), quarantine_state as (
  select count(*) as quarantined_reconciliations
  from private.lf_github_reconciliation_quarantine_v7
), strict as (
  select
    b.*,
    r.reconciliation_count as strict_reconciliation_count,
    r.github_pass_count as strict_github_pass_count,
    g.latest_gate_tests as strict_latest_gate_tests,
    g.passed_gate_tests as strict_passed_gate_tests,
    g.failed_gate_tests as strict_failed_gate_tests,
    e.edge_reconciler_v7_ready,
    q.quarantined_reconciliations,
    (
      b.internal_control_ready
      and r.github_pass_count=b.artifact_count
      and g.passed_gate_tests=b.artifact_count
      and g.failed_gate_tests=0
      and e.edge_reconciler_v7_ready
    ) as keyed_internal_control_ready
  from base b
  cross join reconciliation_metrics r
  cross join gate_metrics g
  cross join edge_state e
  cross join quarantine_state q
)
select
  computed_at,
  artifact_count,
  pass_v3_count,
  inventory_integrity_gaps,
  judge_count,
  judges_pass_v3,
  strict_reconciliation_count as reconciliation_count,
  ci_artifacts_exercised,
  branch_protection_gaps,
  strict_github_pass_count as github_pass_count,
  strict_latest_gate_tests as latest_gate_tests,
  strict_passed_gate_tests as passed_gate_tests,
  strict_failed_gate_tests as failed_gate_tests,
  provenance_gaps,
  nonconforming_events,
  quarantined_events,
  quarantined_acceptance_references,
  quarantine_control_complete,
  baseline_objects,
  schema_drift_gaps,
  external_notifications,
  delivered_notifications,
  unresolved_notifications,
  unmigrated_legacy_notifications,
  latest_monitor_status,
  latest_monitor_at,
  active_exemptions,
  typed_schema_registry_gaps,
  open_findings,
  unresolved_internal_findings,
  blocking_capabilities,
  keyed_internal_control_ready as internal_control_ready,
  external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)||jsonb_build_object(
    'writer_v7',jsonb_build_object(
      'state',case
        when edge_reconciler_v7_ready then 'DEPLOYED_WAITING_FOR_NATIVE_RECONCILIATION'
        else 'NOT_DEPLOYED_OR_NOT_INDEPENDENTLY_READ_BACK'
      end,
      'authentication_mode','GITHUB_OIDC_HMAC_NONCE_V7',
      'v7_reconciliation_count',strict_reconciliation_count,
      'v7_pass_count',strict_github_pass_count,
      'v7_gate_test_count',strict_passed_gate_tests,
      'edge_reconciler_v7_ready',edge_reconciler_v7_ready,
      'quarantined_reconciliations',quarantined_reconciliations
    )
  ) as residual_observations,
  (
    keyed_internal_control_ready
    and branch_protection_gaps=0
    and schema_drift_gaps=0
    and unresolved_notifications=0
  ) as closure_ready,
  case
    when keyed_internal_control_ready
      and branch_protection_gaps=0
      and schema_drift_gaps=0
      and unresolved_notifications=0
      then 'PASS_V8'
    when keyed_internal_control_ready
      and branch_protection_gaps>0
      and schema_drift_gaps=0
      and unresolved_notifications=0
      then 'READY_INTERNAL_BLOCKED_EXTERNAL'
    else 'NOT_READY'
  end as computed_closure_status
from strict;

create or replace view public.v_lf_architecture_closure_current
with (security_invoker=true)
as
select * from public.v_lf_architecture_closure_v8;

commit;
