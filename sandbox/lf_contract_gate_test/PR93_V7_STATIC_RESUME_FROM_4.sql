-- =============================================================================
-- PR #93 · V7 STATIC RESUME FROM 4 APPLIED MIGRATIONS
-- Generated deterministically from the repository source files.
-- No dynamic SQL download. No global transaction. No production authorization.
-- Existing sandbox state required: exactly 175950,175955,180000,180005 applied.
-- =============================================================================

do $preflight$
declare
  v_applied integer;
  v_pending integer;
  v_bad_applied integer;
begin
  if current_user <> 'postgres' then
    raise exception 'Expected current_user=postgres, got %',current_user;
  end if;

  select count(*) into v_applied
  from supabase_migrations.schema_migrations sm
  where sm.version in ('20260801175950','20260801175955','20260801180000','20260801180005');
  if v_applied <> 4 then
    raise exception 'Resume preflight requires exactly 4 applied V7 base migrations; found=%',v_applied;
  end if;

  with expected(version,blob) as (
    values
      ('20260801175950','484323bfe892cb1824320130203fd86d8aed69bf'),
      ('20260801175955','5a4586911376274efab625b54a5cd16ab6648798'),
      ('20260801180000','07f7258d43444f3d871257e9e7095edd0b4a41c7'),
      ('20260801180005','470739dac867faa82c25dce5ad17febfbcea422b')
  )
  select count(*) into v_bad_applied
  from expected e
  join supabase_migrations.schema_migrations sm using(version)
  where sm.idempotency_key is distinct from 'gitblob:'||e.blob;
  if v_bad_applied <> 0 then
    raise exception 'Applied V7 base ledger does not match immutable source blobs; mismatches=%',v_bad_applied;
  end if;

  with pending(version) as (
    values
      ('20260801180010'),
      ('20260801180100'),
      ('20260801180150'),
      ('20260801180200'),
      ('20260801180300'),
      ('20260801180305'),
      ('20260801180310'),
      ('20260801180315'),
      ('20260801180320'),
      ('20260801180400'),
      ('20260801180500'),
      ('20260801180510'),
      ('20260801180520'),
      ('20260801180530')
  )
  select count(*) into v_pending
  from pending p join supabase_migrations.schema_migrations sm using(version);
  if v_pending <> 0 then
    raise exception 'One or more resume migrations are already recorded; count=%',v_pending;
  end if;

  if to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'Expected nonce table from 180000 is missing';
  end if;
  if to_regclass('private.lf_github_reconciliation_quarantine_v7') is not null then
    raise exception 'Quarantine table already exists before resume';
  end if;
  if to_regclass('private.lf_writer_hmac_keys_v7') is not null then
    raise exception 'Writer key table already exists before resume';
  end if;
end
$preflight$;

-- -----------------------------------------------------------------------------
-- 05/18 · 20260801180010_prepare_quarantine_owner_context.sql
-- Git blob SHA-1: fb677bbd4002c53fa2b165ec4498059325271828
-- -----------------------------------------------------------------------------
-- Forward-only owner context for the quarantine cutover.
-- 180005 is already an immutable applied history point in the sandbox and correctly
-- removed schema CREATE. 180100 creates a new private relation and transfers it to
-- lf_governance_owner_v3, which PostgreSQL requires to have CREATE on the containing
-- schema at ownership-transfer time. 180150 removes this temporary CREATE again.

begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180010',
  array[$source_20260801180010$-- Forward-only owner context for the quarantine cutover.
-- 180005 is already an immutable applied history point in the sandbox and correctly
-- removed schema CREATE. 180100 creates a new private relation and transfers it to
-- lf_governance_owner_v3, which PostgreSQL requires to have CREATE on the containing
-- schema at ownership-transfer time. 180150 removes this temporary CREATE again.

begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;

commit;
$source_20260801180010$]::text[],
  'prepare_quarantine_owner_context',
  'pr93_v7_static_resume_from_4',
  'gitblob:fb677bbd4002c53fa2b165ec4498059325271828',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 06/18 · 20260801180100_quarantine_compensating_evidence_v7.sql
-- Git blob SHA-1: 38297c53f9670e13920b95e0d9b251f5cd2bf26d
-- -----------------------------------------------------------------------------
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

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180100',
  array[$source_20260801180100$-- CA-N25 remediation and V7 effective-evidence cutover.
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
$source_20260801180100$]::text[],
  'quarantine_compensating_evidence_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:38297c53f9670e13920b95e0d9b251f5cd2bf26d',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 07/18 · 20260801180150_trusted_v7_readback_grants.sql
-- Git blob SHA-1: e926158ba33b6fa70897ae5c30ba771c504930da
-- -----------------------------------------------------------------------------
-- Explicit read/test execution for the trusted PostgreSQL root.
-- No table access or operational API writer permission is granted here.
-- This migration also closes the temporary governance CREATE privilege that must
-- remain available through 20260801180100_quarantine_compensating_evidence_v7.sql.

begin;

set local role lf_writer_verifier_v7;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to postgres;
reset role;

set local role lf_governance_owner_v3;
grant execute on function private.fn_reconciliation_nonce_v7_valid(bigint)
  to postgres;
grant execute on function private.fn_gate_nonce_v7_valid(bigint)
  to postgres;
reset role;

revoke create on schema private from lf_governance_owner_v3;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180150',
  array[$source_20260801180150$-- Explicit read/test execution for the trusted PostgreSQL root.
-- No table access or operational API writer permission is granted here.
-- This migration also closes the temporary governance CREATE privilege that must
-- remain available through 20260801180100_quarantine_compensating_evidence_v7.sql.

begin;

set local role lf_writer_verifier_v7;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to postgres;
reset role;

set local role lf_governance_owner_v3;
grant execute on function private.fn_reconciliation_nonce_v7_valid(bigint)
  to postgres;
grant execute on function private.fn_gate_nonce_v7_valid(bigint)
  to postgres;
reset role;

revoke create on schema private from lf_governance_owner_v3;

commit;
$source_20260801180150$]::text[],
  'trusted_v7_readback_grants',
  'pr93_v7_static_resume_from_4',
  'gitblob:e926158ba33b6fa70897ae5c30ba771c504930da',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 08/18 · 20260801180200_governance_role_and_rls_v7.sql
-- Git blob SHA-1: 4bad5455752eaae48307bc75b63252758e605f7f
-- -----------------------------------------------------------------------------
-- CA-N05 / CA-N06 / CA-N28 remediation.
-- The Supabase-managed postgres role remains the trusted database root. Every V4
-- governance table becomes an RLS-protected internal relation. Temporary role
-- memberships used for ownership changes are removed at the end of this batch.

begin;

alter role lf_governance_owner_v3 nologin noinherit nobypassrls;
alter role lf_writer_verifier_v7 nologin noinherit nobypassrls;

-- Defense in depth for all V4 governance relations identified by the independent audit.
alter table private.lf_architecture_alerts_v4 enable row level security;
alter table private.lf_architecture_alerts_v4 force row level security;
alter table private.lf_architecture_delivery_secrets_v4 enable row level security;
alter table private.lf_architecture_delivery_secrets_v4 force row level security;
alter table private.lf_architecture_monitor_runs_v4 enable row level security;
alter table private.lf_architecture_monitor_runs_v4 force row level security;
alter table private.lf_architecture_notification_attempts_v4 enable row level security;
alter table private.lf_architecture_notification_attempts_v4 force row level security;
alter table private.lf_architecture_notification_outbox_v4 enable row level security;
alter table private.lf_architecture_notification_outbox_v4 force row level security;
alter table private.lf_architecture_notification_receipts_v4 enable row level security;
alter table private.lf_architecture_notification_receipts_v4 force row level security;
alter table private.lf_event_contract_provenance_overlay_v4 enable row level security;
alter table private.lf_event_contract_provenance_overlay_v4 force row level security;
alter table private.lf_legacy_event_quarantine_v4 enable row level security;
alter table private.lf_legacy_event_quarantine_v4 force row level security;
alter table private.lf_schema_fingerprint_baseline_v4 enable row level security;
alter table private.lf_schema_fingerprint_baseline_v4 force row level security;

-- The broken V6 nonce relation becomes historical-only. V7 uses a dedicated owner and
-- explicit RLS policies.
alter table private.lf_reconciliation_writer_nonces_v6 enable row level security;
alter table private.lf_reconciliation_writer_nonces_v6 force row level security;

revoke all on private.lf_architecture_alerts_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_delivery_secrets_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_monitor_runs_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_notification_attempts_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_notification_outbox_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_notification_receipts_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_event_contract_provenance_overlay_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_legacy_event_quarantine_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_schema_fingerprint_baseline_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_reconciliation_writer_nonces_v6 from public,anon,authenticated,service_role;

create or replace function private.fn_governance_role_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select not exists (
    select 1
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
  )
  and not exists (
    select 1
    from pg_roles r
    where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
      and (r.rolcanlogin or r.rolinherit or r.rolbypassrls)
  );
$function$;

-- This validator is intentionally postgres-owned from this point forward. The next
-- static-audit migration replaces it after the temporary owner memberships have been
-- removed; keeping the final owner here prevents a cross-migration ownership gap.
alter function private.fn_governance_role_separation_v7_valid()
  owner to postgres;
revoke all on function private.fn_governance_role_separation_v7_valid()
  from public,anon,authenticated,service_role;

-- Read-only validators are required by the trusted monitor/closure path. Granting
-- EXECUTE to postgres does not grant any writer or table privilege.
set local role lf_governance_owner_v3;
grant execute on function private.fn_reconciliation_nonce_v7_valid(bigint) to postgres;
grant execute on function private.fn_gate_nonce_v7_valid(bigint) to postgres;
reset role;

-- Preserve the V8 public shape while adding the real role-separation requirement to
-- the canonical view. Until supabase_admin removes its membership, closure stays false.
create or replace view public.v_lf_architecture_closure_current
with (security_invoker=true)
as
with source as (
  select * from public.v_lf_architecture_closure_v8
), separation as (
  select private.fn_governance_role_separation_v7_valid() as role_separation_ready
)
select
  computed_at,
  artifact_count,
  pass_v3_count,
  inventory_integrity_gaps,
  judge_count,
  judges_pass_v3,
  reconciliation_count,
  ci_artifacts_exercised,
  branch_protection_gaps,
  github_pass_count,
  latest_gate_tests,
  passed_gate_tests,
  failed_gate_tests,
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
  (internal_control_ready and role_separation_ready) as internal_control_ready,
  external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)||jsonb_build_object(
    'governance_role_separation',jsonb_build_object(
      'state',case when role_separation_ready then 'VERIFIED' else 'BLOCKED_BY_SUPABASE_ADMIN_MEMBERSHIP' end,
      'required_action','Remove every postgres membership/admin option on lf_governance_owner_v3 and lf_writer_verifier_v7 using the original grantor.'
    )
  ) as residual_observations,
  (closure_ready and role_separation_ready) as closure_ready,
  case
    when not role_separation_ready then 'NOT_READY'
    else computed_closure_status
  end as computed_closure_status
from source
cross join separation;

-- Remove both temporary memberships granted by postgres. Any membership granted by
-- supabase_admin remains visible to the closure predicate and must be removed externally.
revoke lf_writer_verifier_v7 from postgres granted by postgres;
revoke lf_governance_owner_v3 from postgres granted by postgres;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180200',
  array[$source_20260801180200$-- CA-N05 / CA-N06 / CA-N28 remediation.
-- The Supabase-managed postgres role remains the trusted database root. Every V4
-- governance table becomes an RLS-protected internal relation. Temporary role
-- memberships used for ownership changes are removed at the end of this batch.

begin;

alter role lf_governance_owner_v3 nologin noinherit nobypassrls;
alter role lf_writer_verifier_v7 nologin noinherit nobypassrls;

-- Defense in depth for all V4 governance relations identified by the independent audit.
alter table private.lf_architecture_alerts_v4 enable row level security;
alter table private.lf_architecture_alerts_v4 force row level security;
alter table private.lf_architecture_delivery_secrets_v4 enable row level security;
alter table private.lf_architecture_delivery_secrets_v4 force row level security;
alter table private.lf_architecture_monitor_runs_v4 enable row level security;
alter table private.lf_architecture_monitor_runs_v4 force row level security;
alter table private.lf_architecture_notification_attempts_v4 enable row level security;
alter table private.lf_architecture_notification_attempts_v4 force row level security;
alter table private.lf_architecture_notification_outbox_v4 enable row level security;
alter table private.lf_architecture_notification_outbox_v4 force row level security;
alter table private.lf_architecture_notification_receipts_v4 enable row level security;
alter table private.lf_architecture_notification_receipts_v4 force row level security;
alter table private.lf_event_contract_provenance_overlay_v4 enable row level security;
alter table private.lf_event_contract_provenance_overlay_v4 force row level security;
alter table private.lf_legacy_event_quarantine_v4 enable row level security;
alter table private.lf_legacy_event_quarantine_v4 force row level security;
alter table private.lf_schema_fingerprint_baseline_v4 enable row level security;
alter table private.lf_schema_fingerprint_baseline_v4 force row level security;

-- The broken V6 nonce relation becomes historical-only. V7 uses a dedicated owner and
-- explicit RLS policies.
alter table private.lf_reconciliation_writer_nonces_v6 enable row level security;
alter table private.lf_reconciliation_writer_nonces_v6 force row level security;

revoke all on private.lf_architecture_alerts_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_delivery_secrets_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_monitor_runs_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_notification_attempts_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_notification_outbox_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_architecture_notification_receipts_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_event_contract_provenance_overlay_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_legacy_event_quarantine_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_schema_fingerprint_baseline_v4 from public,anon,authenticated,service_role;
revoke all on private.lf_reconciliation_writer_nonces_v6 from public,anon,authenticated,service_role;

create or replace function private.fn_governance_role_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select not exists (
    select 1
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
  )
  and not exists (
    select 1
    from pg_roles r
    where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
      and (r.rolcanlogin or r.rolinherit or r.rolbypassrls)
  );
$function$;

-- This validator is intentionally postgres-owned from this point forward. The next
-- static-audit migration replaces it after the temporary owner memberships have been
-- removed; keeping the final owner here prevents a cross-migration ownership gap.
alter function private.fn_governance_role_separation_v7_valid()
  owner to postgres;
revoke all on function private.fn_governance_role_separation_v7_valid()
  from public,anon,authenticated,service_role;

-- Read-only validators are required by the trusted monitor/closure path. Granting
-- EXECUTE to postgres does not grant any writer or table privilege.
set local role lf_governance_owner_v3;
grant execute on function private.fn_reconciliation_nonce_v7_valid(bigint) to postgres;
grant execute on function private.fn_gate_nonce_v7_valid(bigint) to postgres;
reset role;

-- Preserve the V8 public shape while adding the real role-separation requirement to
-- the canonical view. Until supabase_admin removes its membership, closure stays false.
create or replace view public.v_lf_architecture_closure_current
with (security_invoker=true)
as
with source as (
  select * from public.v_lf_architecture_closure_v8
), separation as (
  select private.fn_governance_role_separation_v7_valid() as role_separation_ready
)
select
  computed_at,
  artifact_count,
  pass_v3_count,
  inventory_integrity_gaps,
  judge_count,
  judges_pass_v3,
  reconciliation_count,
  ci_artifacts_exercised,
  branch_protection_gaps,
  github_pass_count,
  latest_gate_tests,
  passed_gate_tests,
  failed_gate_tests,
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
  (internal_control_ready and role_separation_ready) as internal_control_ready,
  external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)||jsonb_build_object(
    'governance_role_separation',jsonb_build_object(
      'state',case when role_separation_ready then 'VERIFIED' else 'BLOCKED_BY_SUPABASE_ADMIN_MEMBERSHIP' end,
      'required_action','Remove every postgres membership/admin option on lf_governance_owner_v3 and lf_writer_verifier_v7 using the original grantor.'
    )
  ) as residual_observations,
  (closure_ready and role_separation_ready) as closure_ready,
  case
    when not role_separation_ready then 'NOT_READY'
    else computed_closure_status
  end as computed_closure_status
from source
cross join separation;

-- Remove both temporary memberships granted by postgres. Any membership granted by
-- supabase_admin remains visible to the closure predicate and must be removed externally.
revoke lf_writer_verifier_v7 from postgres granted by postgres;
revoke lf_governance_owner_v3 from postgres granted by postgres;

commit;
$source_20260801180200$]::text[],
  'governance_role_and_rls_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:4bad5455752eaae48307bc75b63252758e605f7f',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 09/18 · 20260801180300_static_audit_corrections_v7.sql
-- Git blob SHA-1: d23d0cd14459dacfeced2457ebebf35ebe098c04
-- -----------------------------------------------------------------------------
-- Static audit corrections for PR #93.
-- This migration supersedes the Vault-backed verifier and the inherited V6 closure
-- predicate introduced by earlier V7 draft migrations. It is intentionally not
-- deployed from the PR branch.

begin;

-- The database-side HMAC verifier key is provisioned out-of-band after merge.
-- It is deliberately stored in a postgres-owned private relation because the
-- Supabase-managed Vault currently grants service_role access to decrypted secrets.
-- The trusted PostgreSQL root is already capable of changing verifier code, so it is
-- the correct database trust boundary; API roles receive no privileges on this table.
create table if not exists private.lf_writer_hmac_keys_v7 (
  key_name text primary key
    check (key_name='lf_reconciliation_writer_hmac_v7'),
  key_material text not null
    check (length(key_material)>=32),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  rotated_at timestamptz,
  installed_by_execution_id text not null
);

alter table private.lf_writer_hmac_keys_v7 owner to postgres;
alter table private.lf_writer_hmac_keys_v7 enable row level security;
alter table private.lf_writer_hmac_keys_v7 force row level security;
revoke all on private.lf_writer_hmac_keys_v7
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_function_privilege(
      'service_role',
      'private.fn_writer_hmac_v7_valid(text,text,text)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'service_role',
      'private.fn_consume_writer_proof_v7(text,text,text)',
      'EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_key_ready_v7()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.fn_writer_key_separation_v7_valid()
    and (
      select count(*)=1
      from private.lf_writer_hmac_keys_v7 k
      where k.key_name='lf_reconciliation_writer_hmac_v7'
        and k.active
        and nullif(k.key_material,'') is not null
    );
$function$;

alter function private.fn_writer_key_ready_v7() owner to postgres;
revoke all on function private.fn_writer_key_ready_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_ready_v7()
  to postgres,service_role,lf_governance_owner_v3;

-- Replace the draft Vault implementation. The key is never returned and no API role
-- can execute this verifier directly.
create or replace function private.fn_writer_hmac_v7_valid(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_key text;
  v_count integer;
  v_expected text;
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception using
      errcode='42501',
      message='writer key separation is not valid';
  end if;

  select count(*),min(k.key_material)
    into v_count,v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_name='lf_reconciliation_writer_hmac_v7'
    and k.active;

  if v_count<>1 or nullif(v_key,'') is null then
    raise exception using
      errcode='55000',
      message='writer HMAC key is not configured exactly once';
  end if;

  v_expected:=encode(
    extensions.hmac(
      convert_to(p_preimage||':'||p_nonce,'UTF8'),
      convert_to(v_key,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  -- Compare fixed-size hashes rather than variable-length text values.
  return extensions.digest(convert_to(v_expected,'UTF8'),'sha256')
       = extensions.digest(convert_to(lower(p_signature),'UTF8'),'sha256');
end;
$function$;

alter function private.fn_writer_hmac_v7_valid(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_valid(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_valid(text,text,text)
  to lf_writer_verifier_v7;

-- Remove both temporary memberships created to transfer object ownership. Direct
-- function EXECUTE grants used for readback remain; postgres does not retain either
-- application role membership.
revoke lf_writer_verifier_v7 from postgres granted by postgres;
revoke lf_governance_owner_v3 from postgres granted by postgres;

create or replace function private.fn_governance_role_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select not exists (
    select 1
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
  )
  and not exists (
    select 1
    from pg_roles r
    where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
      and (r.rolcanlogin or r.rolinherit or r.rolbypassrls)
  );
$function$;

alter function private.fn_governance_role_separation_v7_valid() owner to postgres;
revoke all on function private.fn_governance_role_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_governance_role_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_net_api_exposure_v7_count()
returns bigint
language sql
stable
security definer
set search_path to ''
as $function$
  select count(*)
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='net'
    and (
      has_function_privilege('anon',p.oid,'EXECUTE')
      or has_function_privilege('authenticated',p.oid,'EXECUTE')
      or has_function_privilege('service_role',p.oid,'EXECUTE')
    );
$function$;

alter function private.fn_net_api_exposure_v7_count() owner to postgres;
revoke all on function private.fn_net_api_exposure_v7_count()
  from public,anon,authenticated;
grant execute on function private.fn_net_api_exposure_v7_count()
  to postgres,service_role,lf_governance_owner_v3;

-- Rebuild V8 solely from primary V7 evidence. No V5/V6 token-control boolean is
-- inherited. Historical/compensating reconciliations cannot satisfy any V7 metric.
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
      where g.id is not null and g.artifact_exercised_by_workflow
    ) as ci_artifacts_exercised,
    count(*) filter (
      where g.id is null
         or g.branch_protection_status<>'VERIFIED'
         or coalesce(g.details->>'actual_branch_protection_status','')<>'VERIFIED'
    ) as branch_protection_gaps,
    count(*) filter (
      where g.result='PASS'
        and g.target_branch='main'
        and g.merged
        and g.pr_state='MERGED'
        and g.workflow_event='push'
        and g.workflow_conclusion='success'
        and g.workflow_head_sha=g.merge_commit_sha
        and g.artifact_exercised_by_workflow
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
  select
    (select count(*) from private.lf_github_reconciliation_quarantine_v7)
      as quarantined_reconciliations,
    count(*) filter (
      where not exists (
        select 1
        from private.lf_github_reconciliation_quarantine_v7 q
        where q.reconciliation_run_id=g.id
      )
    ) as unquarantined_legacy_reconciliations
  from private.lf_github_reconciliation_runs_v3 g
  where g.branch_protection_status='VERIFIED_COMPENSATING_CONTROLS'
     or (
       g.result='PASS'
       and g.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
     )
), security_state as (
  select
    private.fn_writer_key_ready_v7() as writer_key_ready,
    private.fn_governance_role_separation_v7_valid() as role_separation_ready,
    private.fn_net_api_exposure_v7_count() as net_api_exposure_count
), strict as (
  select
    b.*,
    r.reconciliation_count as strict_reconciliation_count,
    r.ci_artifacts_exercised as strict_ci_artifacts_exercised,
    r.branch_protection_gaps as strict_branch_protection_gaps,
    r.github_pass_count as strict_github_pass_count,
    g.latest_gate_tests as strict_latest_gate_tests,
    g.passed_gate_tests as strict_passed_gate_tests,
    g.failed_gate_tests as strict_failed_gate_tests,
    e.edge_reconciler_v7_ready,
    q.quarantined_reconciliations,
    q.unquarantined_legacy_reconciliations,
    s.writer_key_ready,
    s.role_separation_ready,
    s.net_api_exposure_count,
    (
      b.artifact_count>0
      and b.pass_v3_count=b.artifact_count
      and b.judges_pass_v3=b.judge_count
      and b.inventory_integrity_gaps=0
      and r.reconciliation_count=b.artifact_count
      and r.ci_artifacts_exercised=b.artifact_count
      and r.github_pass_count=b.artifact_count
      and g.latest_gate_tests=b.artifact_count
      and g.passed_gate_tests=b.artifact_count
      and g.failed_gate_tests=0
      and b.provenance_gaps=0
      and b.quarantine_control_complete
      and q.unquarantined_legacy_reconciliations=0
      and b.schema_drift_gaps=0
      and b.unresolved_notifications=0
      and b.unmigrated_legacy_notifications=0
      and b.latest_monitor_status='SUCCEEDED'
      and b.active_exemptions=0
      and b.typed_schema_registry_gaps=0
      and b.unresolved_internal_findings=0
      and b.blocking_capabilities=0
      and e.edge_reconciler_v7_ready
      and s.writer_key_ready
      and s.role_separation_ready
    ) as v7_internal_control_ready
  from base b
  cross join reconciliation_metrics r
  cross join gate_metrics g
  cross join edge_state e
  cross join quarantine_state q
  cross join security_state s
)
select
  computed_at,
  artifact_count,
  pass_v3_count,
  inventory_integrity_gaps,
  judge_count,
  judges_pass_v3,
  strict_reconciliation_count as reconciliation_count,
  strict_ci_artifacts_exercised as ci_artifacts_exercised,
  strict_branch_protection_gaps as branch_protection_gaps,
  strict_github_pass_count as github_pass_count,
  strict_latest_gate_tests as latest_gate_tests,
  strict_passed_gate_tests as passed_gate_tests,
  strict_failed_gate_tests as failed_gate_tests,
  provenance_gaps,
  nonconforming_events,
  quarantined_events,
  quarantined_acceptance_references,
  (quarantine_control_complete and unquarantined_legacy_reconciliations=0)
    as quarantine_control_complete,
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
  v7_internal_control_ready as internal_control_ready,
  (
    case when strict_branch_protection_gaps>0 then 1 else 0 end
    + case when net_api_exposure_count>0 then 1 else 0 end
  ) as external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)||jsonb_build_object(
    'writer_v7',jsonb_build_object(
      'authentication_mode','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_key_ready',writer_key_ready,
      'role_separation_ready',role_separation_ready,
      'edge_reconciler_v7_ready',edge_reconciler_v7_ready,
      'v7_reconciliation_count',strict_reconciliation_count,
      'v7_pass_count',strict_github_pass_count,
      'v7_gate_test_count',strict_passed_gate_tests,
      'quarantined_reconciliations',quarantined_reconciliations,
      'unquarantined_legacy_reconciliations',unquarantined_legacy_reconciliations
    ),
    'admin_surfaces',jsonb_build_object(
      'net_api_exposure_count',net_api_exposure_count,
      'required_action',case
        when net_api_exposure_count>0
then 'supabase_admin must revoke API-role EXECUTE grants on net functions'
        else 'NONE'
      end
    )
  ) as residual_observations,
  (
    v7_internal_control_ready
    and strict_branch_protection_gaps=0
    and net_api_exposure_count=0
  ) as closure_ready,
  case
    when v7_internal_control_ready
      and strict_branch_protection_gaps=0
      and net_api_exposure_count=0
      then 'PASS_V8'
    when v7_internal_control_ready
      and (strict_branch_protection_gaps>0 or net_api_exposure_count>0)
      then 'READY_INTERNAL_BLOCKED_EXTERNAL'
    else 'NOT_READY'
  end as computed_closure_status
from strict;

create or replace view public.v_lf_architecture_closure_current
with (security_invoker=true)
as
select * from public.v_lf_architecture_closure_v8;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180300',
  array[$source_20260801180300$-- Static audit corrections for PR #93.
-- This migration supersedes the Vault-backed verifier and the inherited V6 closure
-- predicate introduced by earlier V7 draft migrations. It is intentionally not
-- deployed from the PR branch.

begin;

-- The database-side HMAC verifier key is provisioned out-of-band after merge.
-- It is deliberately stored in a postgres-owned private relation because the
-- Supabase-managed Vault currently grants service_role access to decrypted secrets.
-- The trusted PostgreSQL root is already capable of changing verifier code, so it is
-- the correct database trust boundary; API roles receive no privileges on this table.
create table if not exists private.lf_writer_hmac_keys_v7 (
  key_name text primary key
    check (key_name='lf_reconciliation_writer_hmac_v7'),
  key_material text not null
    check (length(key_material)>=32),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  rotated_at timestamptz,
  installed_by_execution_id text not null
);

alter table private.lf_writer_hmac_keys_v7 owner to postgres;
alter table private.lf_writer_hmac_keys_v7 enable row level security;
alter table private.lf_writer_hmac_keys_v7 force row level security;
revoke all on private.lf_writer_hmac_keys_v7
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_function_privilege(
      'service_role',
      'private.fn_writer_hmac_v7_valid(text,text,text)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'service_role',
      'private.fn_consume_writer_proof_v7(text,text,text)',
      'EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_key_ready_v7()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.fn_writer_key_separation_v7_valid()
    and (
      select count(*)=1
      from private.lf_writer_hmac_keys_v7 k
      where k.key_name='lf_reconciliation_writer_hmac_v7'
        and k.active
        and nullif(k.key_material,'') is not null
    );
$function$;

alter function private.fn_writer_key_ready_v7() owner to postgres;
revoke all on function private.fn_writer_key_ready_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_ready_v7()
  to postgres,service_role,lf_governance_owner_v3;

-- Replace the draft Vault implementation. The key is never returned and no API role
-- can execute this verifier directly.
create or replace function private.fn_writer_hmac_v7_valid(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_key text;
  v_count integer;
  v_expected text;
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception using
      errcode='42501',
      message='writer key separation is not valid';
  end if;

  select count(*),min(k.key_material)
    into v_count,v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_name='lf_reconciliation_writer_hmac_v7'
    and k.active;

  if v_count<>1 or nullif(v_key,'') is null then
    raise exception using
      errcode='55000',
      message='writer HMAC key is not configured exactly once';
  end if;

  v_expected:=encode(
    extensions.hmac(
      convert_to(p_preimage||':'||p_nonce,'UTF8'),
      convert_to(v_key,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  -- Compare fixed-size hashes rather than variable-length text values.
  return extensions.digest(convert_to(v_expected,'UTF8'),'sha256')
       = extensions.digest(convert_to(lower(p_signature),'UTF8'),'sha256');
end;
$function$;

alter function private.fn_writer_hmac_v7_valid(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_valid(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_valid(text,text,text)
  to lf_writer_verifier_v7;

-- Remove both temporary memberships created to transfer object ownership. Direct
-- function EXECUTE grants used for readback remain; postgres does not retain either
-- application role membership.
revoke lf_writer_verifier_v7 from postgres granted by postgres;
revoke lf_governance_owner_v3 from postgres granted by postgres;

create or replace function private.fn_governance_role_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select not exists (
    select 1
    from pg_auth_members m
    join pg_roles member_role on member_role.oid=m.member
    join pg_roles granted_role on granted_role.oid=m.roleid
    where member_role.rolname='postgres'
      and granted_role.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
  )
  and not exists (
    select 1
    from pg_roles r
    where r.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
      and (r.rolcanlogin or r.rolinherit or r.rolbypassrls)
  );
$function$;

alter function private.fn_governance_role_separation_v7_valid() owner to postgres;
revoke all on function private.fn_governance_role_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_governance_role_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_net_api_exposure_v7_count()
returns bigint
language sql
stable
security definer
set search_path to ''
as $function$
  select count(*)
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='net'
    and (
      has_function_privilege('anon',p.oid,'EXECUTE')
      or has_function_privilege('authenticated',p.oid,'EXECUTE')
      or has_function_privilege('service_role',p.oid,'EXECUTE')
    );
$function$;

alter function private.fn_net_api_exposure_v7_count() owner to postgres;
revoke all on function private.fn_net_api_exposure_v7_count()
  from public,anon,authenticated;
grant execute on function private.fn_net_api_exposure_v7_count()
  to postgres,service_role,lf_governance_owner_v3;

-- Rebuild V8 solely from primary V7 evidence. No V5/V6 token-control boolean is
-- inherited. Historical/compensating reconciliations cannot satisfy any V7 metric.
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
      where g.id is not null and g.artifact_exercised_by_workflow
    ) as ci_artifacts_exercised,
    count(*) filter (
      where g.id is null
         or g.branch_protection_status<>'VERIFIED'
         or coalesce(g.details->>'actual_branch_protection_status','')<>'VERIFIED'
    ) as branch_protection_gaps,
    count(*) filter (
      where g.result='PASS'
        and g.target_branch='main'
        and g.merged
        and g.pr_state='MERGED'
        and g.workflow_event='push'
        and g.workflow_conclusion='success'
        and g.workflow_head_sha=g.merge_commit_sha
        and g.artifact_exercised_by_workflow
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
  select
    (select count(*) from private.lf_github_reconciliation_quarantine_v7)
      as quarantined_reconciliations,
    count(*) filter (
      where not exists (
        select 1
        from private.lf_github_reconciliation_quarantine_v7 q
        where q.reconciliation_run_id=g.id
      )
    ) as unquarantined_legacy_reconciliations
  from private.lf_github_reconciliation_runs_v3 g
  where g.branch_protection_status='VERIFIED_COMPENSATING_CONTROLS'
     or (
       g.result='PASS'
       and g.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
     )
), security_state as (
  select
    private.fn_writer_key_ready_v7() as writer_key_ready,
    private.fn_governance_role_separation_v7_valid() as role_separation_ready,
    private.fn_net_api_exposure_v7_count() as net_api_exposure_count
), strict as (
  select
    b.*,
    r.reconciliation_count as strict_reconciliation_count,
    r.ci_artifacts_exercised as strict_ci_artifacts_exercised,
    r.branch_protection_gaps as strict_branch_protection_gaps,
    r.github_pass_count as strict_github_pass_count,
    g.latest_gate_tests as strict_latest_gate_tests,
    g.passed_gate_tests as strict_passed_gate_tests,
    g.failed_gate_tests as strict_failed_gate_tests,
    e.edge_reconciler_v7_ready,
    q.quarantined_reconciliations,
    q.unquarantined_legacy_reconciliations,
    s.writer_key_ready,
    s.role_separation_ready,
    s.net_api_exposure_count,
    (
      b.artifact_count>0
      and b.pass_v3_count=b.artifact_count
      and b.judges_pass_v3=b.judge_count
      and b.inventory_integrity_gaps=0
      and r.reconciliation_count=b.artifact_count
      and r.ci_artifacts_exercised=b.artifact_count
      and r.github_pass_count=b.artifact_count
      and g.latest_gate_tests=b.artifact_count
      and g.passed_gate_tests=b.artifact_count
      and g.failed_gate_tests=0
      and b.provenance_gaps=0
      and b.quarantine_control_complete
      and q.unquarantined_legacy_reconciliations=0
      and b.schema_drift_gaps=0
      and b.unresolved_notifications=0
      and b.unmigrated_legacy_notifications=0
      and b.latest_monitor_status='SUCCEEDED'
      and b.active_exemptions=0
      and b.typed_schema_registry_gaps=0
      and b.unresolved_internal_findings=0
      and b.blocking_capabilities=0
      and e.edge_reconciler_v7_ready
      and s.writer_key_ready
      and s.role_separation_ready
    ) as v7_internal_control_ready
  from base b
  cross join reconciliation_metrics r
  cross join gate_metrics g
  cross join edge_state e
  cross join quarantine_state q
  cross join security_state s
)
select
  computed_at,
  artifact_count,
  pass_v3_count,
  inventory_integrity_gaps,
  judge_count,
  judges_pass_v3,
  strict_reconciliation_count as reconciliation_count,
  strict_ci_artifacts_exercised as ci_artifacts_exercised,
  strict_branch_protection_gaps as branch_protection_gaps,
  strict_github_pass_count as github_pass_count,
  strict_latest_gate_tests as latest_gate_tests,
  strict_passed_gate_tests as passed_gate_tests,
  strict_failed_gate_tests as failed_gate_tests,
  provenance_gaps,
  nonconforming_events,
  quarantined_events,
  quarantined_acceptance_references,
  (quarantine_control_complete and unquarantined_legacy_reconciliations=0)
    as quarantine_control_complete,
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
  v7_internal_control_ready as internal_control_ready,
  (
    case when strict_branch_protection_gaps>0 then 1 else 0 end
    + case when net_api_exposure_count>0 then 1 else 0 end
  ) as external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)||jsonb_build_object(
    'writer_v7',jsonb_build_object(
      'authentication_mode','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_key_ready',writer_key_ready,
      'role_separation_ready',role_separation_ready,
      'edge_reconciler_v7_ready',edge_reconciler_v7_ready,
      'v7_reconciliation_count',strict_reconciliation_count,
      'v7_pass_count',strict_github_pass_count,
      'v7_gate_test_count',strict_passed_gate_tests,
      'quarantined_reconciliations',quarantined_reconciliations,
      'unquarantined_legacy_reconciliations',unquarantined_legacy_reconciliations
    ),
    'admin_surfaces',jsonb_build_object(
      'net_api_exposure_count',net_api_exposure_count,
      'required_action',case
        when net_api_exposure_count>0
then 'supabase_admin must revoke API-role EXECUTE grants on net functions'
        else 'NONE'
      end
    )
  ) as residual_observations,
  (
    v7_internal_control_ready
    and strict_branch_protection_gaps=0
    and net_api_exposure_count=0
  ) as closure_ready,
  case
    when v7_internal_control_ready
      and strict_branch_protection_gaps=0
      and net_api_exposure_count=0
      then 'PASS_V8'
    when v7_internal_control_ready
      and (strict_branch_protection_gaps>0 or net_api_exposure_count>0)
      then 'READY_INTERNAL_BLOCKED_EXTERNAL'
    else 'NOT_READY'
  end as computed_closure_status
from strict;

create or replace view public.v_lf_architecture_closure_current
with (security_invoker=true)
as
select * from public.v_lf_architecture_closure_v8;

commit;
$source_20260801180300$]::text[],
  'static_audit_corrections_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:d23d0cd14459dacfeced2457ebebf35ebe098c04',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 10/18 · 20260801180305_prepare_idempotency_owner_context.sql
-- Git blob SHA-1: 1ab7a093a4e1934f5319d0d7584a9aa7f8d3fa1c
-- -----------------------------------------------------------------------------
-- Temporary owner context for replacing governance-owned V7 writers.
-- These privileges are revoked by 20260801180320_cleanup_idempotency_owner_context.sql.

begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema public to lf_governance_owner_v3;
grant create on schema private to lf_governance_owner_v3;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180305',
  array[$source_20260801180305$-- Temporary owner context for replacing governance-owned V7 writers.
-- These privileges are revoked by 20260801180320_cleanup_idempotency_owner_context.sql.

begin;

grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema public to lf_governance_owner_v3;
grant create on schema private to lf_governance_owner_v3;

commit;
$source_20260801180305$]::text[],
  'prepare_idempotency_owner_context',
  'pr93_v7_static_resume_from_4',
  'gitblob:1ab7a093a4e1934f5319d0d7584a9aa7f8d3fa1c',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 11/18 · 20260801180310_v7_idempotency_guards.sql
-- Git blob SHA-1: f0461362480449a9039987c60bba6865c67d13fe
-- -----------------------------------------------------------------------------
-- Stable idempotency for V7 reconciliation and gate writers.
-- A nonce is still consumed for every authenticated request, but a retry for the same
-- immutable source workflow returns the existing row instead of creating new evidence.

begin;

create unique index if not exists uq_lf_github_reconciliation_v7_source
  on private.lf_github_reconciliation_runs_v3(
    artifact_id,workflow_run_id,merge_commit_sha,writer_authentication
  )
  where writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

create or replace function public.record_external_ci_verification_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_event_id bigint;
  v_run_id bigint;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload)<>'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_payload->'artifact_id')<>'number'
     or jsonb_typeof(p_payload->'workflow_run_id')<>'number'
     or coalesce(p_payload->>'merge_commit_sha','') !~ '^[0-9a-f]{40}$'
     or coalesce(p_payload->>'audit_manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or p_payload->>'result' not in ('PASS','FAIL') then
    raise exception using errcode='23514',message='external reconciliation payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  -- This ordering is shared with the Edge V7 implementation. Every PASS field is
  -- non-null; FAIL rows are evidence only and cannot satisfy promotion.
  v_preimage:=concat_ws(':',
    'reconciliation-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'workflow_run_id',
    p_payload->>'merge_commit_sha',p_payload->>'artifact_sha256',p_payload->>'branch_protection_status',
    p_payload->>'result',p_payload->>'audit_manifest_sha256'
  );
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce reconciliation writer failed';
  end if;

  if p_payload->>'target_branch'<>'main'
     or p_payload->>'workflow_event'<>'push'
     or p_payload->>'workflow_conclusion'<>'success'
     or p_payload->>'workflow_head_sha' is distinct from p_payload->>'merge_commit_sha'
     or coalesce((p_payload->>'merged')::boolean,false) is not true
     or p_payload->>'pr_state'<>'MERGED'
     or (p_payload->>'observed_at')::timestamptz<clock_timestamp()-interval '24 hours'
     or (p_payload->>'observed_at')::timestamptz>clock_timestamp()+interval '5 minutes' then
    raise exception using errcode='23514',message='external reconciliation source is not current post-merge evidence';
  end if;

  if p_payload->>'result'='PASS' and (
       p_payload->>'branch_protection_status'<>'VERIFIED'
       or coalesce(p_payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
       or not coalesce((p_payload->>'artifact_exercised_by_workflow')::boolean,false)
       or coalesce(p_payload->>'artifact_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(p_payload->>'artifact_git_blob','') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using errcode='23514',message='PASS requires native protection and complete workflow evidence';
  end if;

  if p_payload->>'artifact_path' is distinct from v_artifact.relative_path then
    raise exception using errcode='23514',message='external reconciliation artifact path mismatch';
  end if;
  if p_payload->>'result'='PASS' and (
    not v_artifact.is_current
    or p_payload->>'artifact_sha256' is distinct from v_artifact.content_sha256
  ) then
    raise exception using errcode='23514',message='external reconciliation PASS does not match current artifact content';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-github-v7:'||v_artifact.id::text,0));

  select g.id,g.details->>'signed_preimage_sha256'
    into v_run_id,v_existing_preimage_hash
  from private.lf_github_reconciliation_runs_v3 g
  where g.artifact_id=v_artifact.id
    and g.workflow_run_id=(p_payload->>'workflow_run_id')::bigint
    and g.merge_commit_sha=p_payload->>'merge_commit_sha'
    and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

  if found then
    if v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting V7 reconciliation already exists for source workflow';
    end if;
    return v_run_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_payload:=(p_payload-'verification_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','external-ci-verification/v3',
    'execution_id',p_execution_id,
    'verification_mode','GITHUB_ACTIONS_OIDC_HMAC_V7',
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('verification_payload_sha256',v_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'EXTERNAL_CI_VERIFICATION_COMPLETED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'Authoritative OIDC HMAC nonce post-merge GitHub reconciliation recorded',
    case when v_payload->>'result'='PASS' then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_github_reconciliation_runs_v3(
    artifact_id,repository,target_branch,artifact_path,pr_number,pr_state,merged,merge_commit_sha,
    workflow_run_id,workflow_name,workflow_event,workflow_head_sha,workflow_conclusion,
    artifact_git_blob,artifact_sha256,file_touched_by_merge,artifact_exercised_by_workflow,
    audit_artifact_name,audit_manifest_sha256,branch_protection_status,result,authoritative,
    failure_reasons,details,verification_payload_sha256,source_external_event_id,evidence_event_id,
    reconciled_by_execution_id,observed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_artifact.id,v_payload->>'repository',v_payload->>'target_branch',v_payload->>'artifact_path',
    case when v_payload->'pr_number'='null'::jsonb or not(v_payload?'pr_number')
      then null else (v_payload->>'pr_number')::integer end,
    v_payload->>'pr_state',(v_payload->>'merged')::boolean,v_payload->>'merge_commit_sha',
    (v_payload->>'workflow_run_id')::bigint,v_payload->>'workflow_name',v_payload->>'workflow_event',
    v_payload->>'workflow_head_sha',v_payload->>'workflow_conclusion',v_payload->>'artifact_git_blob',
    v_payload->>'artifact_sha256',(v_payload->>'file_touched_by_merge')::boolean,
    (v_payload->>'artifact_exercised_by_workflow')::boolean,v_payload->>'audit_artifact_name',
    v_payload->>'audit_manifest_sha256',v_payload->>'branch_protection_status',v_payload->>'result',true,
    v_payload->'failure_reasons',coalesce(v_payload->'details','{}'::jsonb)||jsonb_build_object(
      'writer_authentication_v7','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_nonce_sha256',v_nonce_hash,
      'writer_proof_expires_at',v_proof_expires_at,
      'signed_preimage_sha256',v_preimage_hash
    ),v_hash,v_event_id,v_event_id,p_execution_id,(v_payload->>'observed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_run_id;

  return v_run_id;
end;
$function$;

alter function public.record_external_ci_verification_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  to service_role;

create or replace function public.record_lf_gate_test_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_probe_hash text;
  v_effect_hash text;
  v_payload_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_persisted_effects jsonb;
  v_event_id bigint;
  v_id bigint;
  v_reconciliation_id bigint;
  v_existing_writer text;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(p_payload->'artifact_id')<>'number'
     or jsonb_typeof(p_payload->'source_workflow_run_id')<>'number'
     or coalesce(p_payload->>'source_commit_sha','') !~ '^[0-9a-f]{40}$'
     or nullif(p_payload->>'test_code','') is null then
    raise exception using errcode='23514',message='gate test payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=concat_ws(':',
    'gate-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'test_code',
    p_payload->>'source_workflow_run_id',p_payload->>'source_commit_sha',p_payload->>'passed',
    p_payload->>'target_relation',p_payload->>'gate_code',
    p_payload->'probe_preimage'->>'expected_sha256',
    p_payload->'observed_outcome'->>'artifact_sha256',
    p_payload->'observed_outcome'->>'audit_covered',
    p_payload->'persisted_effects'->>'github_reconciliation_run_id'
  );
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce gate writer failed';
  end if;

  v_reconciliation_id:=nullif(
    p_payload#>>'{persisted_effects,github_reconciliation_run_id}',''
  )::bigint;
  if coalesce((p_payload->>'passed')::boolean,false) and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=v_reconciliation_id
      and g.artifact_id=v_artifact.id
      and g.result='PASS'
      and g.authoritative
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and g.workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
      and g.merge_commit_sha=p_payload->>'source_commit_sha'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using errcode='23514',message='passing gate test requires matching V7 reconciliation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'lf-gate-v7:'||v_artifact.id::text||':'||coalesce(p_payload->>'test_code',''),0
  ));

  select t.id,t.writer_authentication,t.persisted_effects->>'signed_preimage_sha256'
    into v_id,v_existing_writer,v_existing_preimage_hash
  from private.lf_gate_test_runs_v3 t
  where t.test_code=p_payload->>'test_code'
    and t.artifact_id=v_artifact.id
    and t.source_workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
    and t.source_commit_sha=p_payload->>'source_commit_sha';

  if found then
    if v_existing_writer<>'GITHUB_OIDC_HMAC_NONCE_V7'
       or v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting gate evidence already exists for source workflow';
    end if;
    return v_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_probe_hash:=encode(
    extensions.digest(convert_to((p_payload->'probe_preimage')::text,'UTF8'),'sha256'),'hex'
  );
  v_persisted_effects:=coalesce(p_payload->'persisted_effects','{}'::jsonb)
    ||jsonb_build_object('signed_preimage_sha256',v_preimage_hash);
  v_effect_hash:=encode(
    extensions.digest(convert_to(v_persisted_effects::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=(p_payload-'evidence_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','gate-test-run/v3',
    'execution_id',p_execution_id,
    'probe_sha256',v_probe_hash,
    'persisted_effects',v_persisted_effects,
    'persisted_effects_sha256',v_effect_hash,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_payload_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('evidence_payload_sha256',v_payload_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'GATE_TEST_RUN_RECORDED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'OIDC HMAC nonce reproducible architecture gate test recorded',
    case when coalesce((v_payload->>'passed')::boolean,false) then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_gate_test_runs_v3(
    test_code,artifact_id,gate_code,test_kind,target_relation,probe_preimage,probe_sha256,
    expected_outcome,observed_outcome,persisted_effects,persisted_effects_sha256,passed,
    runner_type,runner_identity,source_workflow_run_id,source_commit_sha,evidence_event_id,
    executed_by_execution_id,executed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_payload->>'test_code',v_artifact.id,v_payload->>'gate_code',v_payload->>'test_kind',
    v_payload->>'target_relation',v_payload->'probe_preimage',v_probe_hash,
    v_payload->'expected_outcome',v_payload->'observed_outcome',
    v_persisted_effects,v_effect_hash,(v_payload->>'passed')::boolean,
    v_payload->>'runner_type',v_payload->>'runner_identity',
    (v_payload->>'source_workflow_run_id')::bigint,v_payload->>'source_commit_sha',
    v_event_id,p_execution_id,(v_payload->>'executed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.record_lf_gate_test_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  to service_role;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180310',
  array[$source_20260801180310$-- Stable idempotency for V7 reconciliation and gate writers.
-- A nonce is still consumed for every authenticated request, but a retry for the same
-- immutable source workflow returns the existing row instead of creating new evidence.

begin;

create unique index if not exists uq_lf_github_reconciliation_v7_source
  on private.lf_github_reconciliation_runs_v3(
    artifact_id,workflow_run_id,merge_commit_sha,writer_authentication
  )
  where writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

create or replace function public.record_external_ci_verification_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_event_id bigint;
  v_run_id bigint;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload)<>'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_payload->'artifact_id')<>'number'
     or jsonb_typeof(p_payload->'workflow_run_id')<>'number'
     or coalesce(p_payload->>'merge_commit_sha','') !~ '^[0-9a-f]{40}$'
     or coalesce(p_payload->>'audit_manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or p_payload->>'result' not in ('PASS','FAIL') then
    raise exception using errcode='23514',message='external reconciliation payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  -- This ordering is shared with the Edge V7 implementation. Every PASS field is
  -- non-null; FAIL rows are evidence only and cannot satisfy promotion.
  v_preimage:=concat_ws(':',
    'reconciliation-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'workflow_run_id',
    p_payload->>'merge_commit_sha',p_payload->>'artifact_sha256',p_payload->>'branch_protection_status',
    p_payload->>'result',p_payload->>'audit_manifest_sha256'
  );
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce reconciliation writer failed';
  end if;

  if p_payload->>'target_branch'<>'main'
     or p_payload->>'workflow_event'<>'push'
     or p_payload->>'workflow_conclusion'<>'success'
     or p_payload->>'workflow_head_sha' is distinct from p_payload->>'merge_commit_sha'
     or coalesce((p_payload->>'merged')::boolean,false) is not true
     or p_payload->>'pr_state'<>'MERGED'
     or (p_payload->>'observed_at')::timestamptz<clock_timestamp()-interval '24 hours'
     or (p_payload->>'observed_at')::timestamptz>clock_timestamp()+interval '5 minutes' then
    raise exception using errcode='23514',message='external reconciliation source is not current post-merge evidence';
  end if;

  if p_payload->>'result'='PASS' and (
       p_payload->>'branch_protection_status'<>'VERIFIED'
       or coalesce(p_payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
       or not coalesce((p_payload->>'artifact_exercised_by_workflow')::boolean,false)
       or coalesce(p_payload->>'artifact_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(p_payload->>'artifact_git_blob','') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using errcode='23514',message='PASS requires native protection and complete workflow evidence';
  end if;

  if p_payload->>'artifact_path' is distinct from v_artifact.relative_path then
    raise exception using errcode='23514',message='external reconciliation artifact path mismatch';
  end if;
  if p_payload->>'result'='PASS' and (
    not v_artifact.is_current
    or p_payload->>'artifact_sha256' is distinct from v_artifact.content_sha256
  ) then
    raise exception using errcode='23514',message='external reconciliation PASS does not match current artifact content';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-github-v7:'||v_artifact.id::text,0));

  select g.id,g.details->>'signed_preimage_sha256'
    into v_run_id,v_existing_preimage_hash
  from private.lf_github_reconciliation_runs_v3 g
  where g.artifact_id=v_artifact.id
    and g.workflow_run_id=(p_payload->>'workflow_run_id')::bigint
    and g.merge_commit_sha=p_payload->>'merge_commit_sha'
    and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

  if found then
    if v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting V7 reconciliation already exists for source workflow';
    end if;
    return v_run_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_payload:=(p_payload-'verification_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','external-ci-verification/v3',
    'execution_id',p_execution_id,
    'verification_mode','GITHUB_ACTIONS_OIDC_HMAC_V7',
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('verification_payload_sha256',v_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'EXTERNAL_CI_VERIFICATION_COMPLETED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'Authoritative OIDC HMAC nonce post-merge GitHub reconciliation recorded',
    case when v_payload->>'result'='PASS' then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_github_reconciliation_runs_v3(
    artifact_id,repository,target_branch,artifact_path,pr_number,pr_state,merged,merge_commit_sha,
    workflow_run_id,workflow_name,workflow_event,workflow_head_sha,workflow_conclusion,
    artifact_git_blob,artifact_sha256,file_touched_by_merge,artifact_exercised_by_workflow,
    audit_artifact_name,audit_manifest_sha256,branch_protection_status,result,authoritative,
    failure_reasons,details,verification_payload_sha256,source_external_event_id,evidence_event_id,
    reconciled_by_execution_id,observed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_artifact.id,v_payload->>'repository',v_payload->>'target_branch',v_payload->>'artifact_path',
    case when v_payload->'pr_number'='null'::jsonb or not(v_payload?'pr_number')
      then null else (v_payload->>'pr_number')::integer end,
    v_payload->>'pr_state',(v_payload->>'merged')::boolean,v_payload->>'merge_commit_sha',
    (v_payload->>'workflow_run_id')::bigint,v_payload->>'workflow_name',v_payload->>'workflow_event',
    v_payload->>'workflow_head_sha',v_payload->>'workflow_conclusion',v_payload->>'artifact_git_blob',
    v_payload->>'artifact_sha256',(v_payload->>'file_touched_by_merge')::boolean,
    (v_payload->>'artifact_exercised_by_workflow')::boolean,v_payload->>'audit_artifact_name',
    v_payload->>'audit_manifest_sha256',v_payload->>'branch_protection_status',v_payload->>'result',true,
    v_payload->'failure_reasons',coalesce(v_payload->'details','{}'::jsonb)||jsonb_build_object(
      'writer_authentication_v7','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_nonce_sha256',v_nonce_hash,
      'writer_proof_expires_at',v_proof_expires_at,
      'signed_preimage_sha256',v_preimage_hash
    ),v_hash,v_event_id,v_event_id,p_execution_id,(v_payload->>'observed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_run_id;

  return v_run_id;
end;
$function$;

alter function public.record_external_ci_verification_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  to service_role;

create or replace function public.record_lf_gate_test_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_probe_hash text;
  v_effect_hash text;
  v_payload_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_persisted_effects jsonb;
  v_event_id bigint;
  v_id bigint;
  v_reconciliation_id bigint;
  v_existing_writer text;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(p_payload->'artifact_id')<>'number'
     or jsonb_typeof(p_payload->'source_workflow_run_id')<>'number'
     or coalesce(p_payload->>'source_commit_sha','') !~ '^[0-9a-f]{40}$'
     or nullif(p_payload->>'test_code','') is null then
    raise exception using errcode='23514',message='gate test payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=concat_ws(':',
    'gate-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'test_code',
    p_payload->>'source_workflow_run_id',p_payload->>'source_commit_sha',p_payload->>'passed',
    p_payload->>'target_relation',p_payload->>'gate_code',
    p_payload->'probe_preimage'->>'expected_sha256',
    p_payload->'observed_outcome'->>'artifact_sha256',
    p_payload->'observed_outcome'->>'audit_covered',
    p_payload->'persisted_effects'->>'github_reconciliation_run_id'
  );
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce gate writer failed';
  end if;

  v_reconciliation_id:=nullif(
    p_payload#>>'{persisted_effects,github_reconciliation_run_id}',''
  )::bigint;
  if coalesce((p_payload->>'passed')::boolean,false) and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=v_reconciliation_id
      and g.artifact_id=v_artifact.id
      and g.result='PASS'
      and g.authoritative
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and g.workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
      and g.merge_commit_sha=p_payload->>'source_commit_sha'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using errcode='23514',message='passing gate test requires matching V7 reconciliation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'lf-gate-v7:'||v_artifact.id::text||':'||coalesce(p_payload->>'test_code',''),0
  ));

  select t.id,t.writer_authentication,t.persisted_effects->>'signed_preimage_sha256'
    into v_id,v_existing_writer,v_existing_preimage_hash
  from private.lf_gate_test_runs_v3 t
  where t.test_code=p_payload->>'test_code'
    and t.artifact_id=v_artifact.id
    and t.source_workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
    and t.source_commit_sha=p_payload->>'source_commit_sha';

  if found then
    if v_existing_writer<>'GITHUB_OIDC_HMAC_NONCE_V7'
       or v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting gate evidence already exists for source workflow';
    end if;
    return v_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_probe_hash:=encode(
    extensions.digest(convert_to((p_payload->'probe_preimage')::text,'UTF8'),'sha256'),'hex'
  );
  v_persisted_effects:=coalesce(p_payload->'persisted_effects','{}'::jsonb)
    ||jsonb_build_object('signed_preimage_sha256',v_preimage_hash);
  v_effect_hash:=encode(
    extensions.digest(convert_to(v_persisted_effects::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=(p_payload-'evidence_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','gate-test-run/v3',
    'execution_id',p_execution_id,
    'probe_sha256',v_probe_hash,
    'persisted_effects',v_persisted_effects,
    'persisted_effects_sha256',v_effect_hash,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_payload_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('evidence_payload_sha256',v_payload_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'GATE_TEST_RUN_RECORDED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'OIDC HMAC nonce reproducible architecture gate test recorded',
    case when coalesce((v_payload->>'passed')::boolean,false) then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_gate_test_runs_v3(
    test_code,artifact_id,gate_code,test_kind,target_relation,probe_preimage,probe_sha256,
    expected_outcome,observed_outcome,persisted_effects,persisted_effects_sha256,passed,
    runner_type,runner_identity,source_workflow_run_id,source_commit_sha,evidence_event_id,
    executed_by_execution_id,executed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_payload->>'test_code',v_artifact.id,v_payload->>'gate_code',v_payload->>'test_kind',
    v_payload->>'target_relation',v_payload->'probe_preimage',v_probe_hash,
    v_payload->'expected_outcome',v_payload->'observed_outcome',
    v_persisted_effects,v_effect_hash,(v_payload->>'passed')::boolean,
    v_payload->>'runner_type',v_payload->>'runner_identity',
    (v_payload->>'source_workflow_run_id')::bigint,v_payload->>'source_commit_sha',
    v_event_id,p_execution_id,(v_payload->>'executed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.record_lf_gate_test_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  to service_role;

commit;
$source_20260801180310$]::text[],
  'v7_idempotency_guards',
  'pr93_v7_static_resume_from_4',
  'gitblob:f0461362480449a9039987c60bba6865c67d13fe',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 12/18 · 20260801180315_v7_row_integrity_guards.sql
-- Git blob SHA-1: ace19fefd8b656b82a9b86639ef7abb567a04e58
-- -----------------------------------------------------------------------------
-- Storage-boundary validation for every V7 reconciliation and gate row.
-- This prevents SQL three-valued logic or a future writer implementation from
-- persisting incomplete evidence.

begin;

create or replace function private.fn_guard_v7_reconciliation_row()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if new.result not in ('PASS','FAIL')
     or new.target_branch is distinct from 'main'
     or new.merged is not true
     or new.pr_state is distinct from 'MERGED'
     or new.workflow_event is distinct from 'push'
     or new.workflow_conclusion is distinct from 'success'
     or new.workflow_head_sha is distinct from new.merge_commit_sha
     or coalesce(new.merge_commit_sha,'') !~ '^[0-9a-f]{40}$'
     or coalesce(new.audit_manifest_sha256,'') !~ '^[0-9a-f]{64}$'
     or new.observed_at is null
     or new.observed_at<clock_timestamp()-interval '24 hours'
     or new.observed_at>clock_timestamp()+interval '5 minutes'
     or coalesce(new.details->>'signed_preimage_sha256','') !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode='23514',
      message='V7 reconciliation row failed storage-boundary integrity checks';
  end if;

  if new.result='PASS' and (
       new.branch_protection_status is distinct from 'VERIFIED'
       or coalesce(new.details->>'actual_branch_protection_status','')<>'VERIFIED'
       or new.artifact_exercised_by_workflow is not true
       or coalesce(new.artifact_sha256,'') !~ '^[0-9a-f]{64}$'
       or coalesce(new.artifact_git_blob,'') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using
      errcode='23514',
      message='V7 PASS reconciliation lacks native protection or complete artifact evidence';
  end if;

  return new;
end;
$function$;

alter function private.fn_guard_v7_reconciliation_row()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_guard_v7_reconciliation_row()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_10_guard_v7_reconciliation_row
  on private.lf_github_reconciliation_runs_v3;
create trigger trg_10_guard_v7_reconciliation_row
before insert or update
on private.lf_github_reconciliation_runs_v3
for each row execute function private.fn_guard_v7_reconciliation_row();
alter table private.lf_github_reconciliation_runs_v3
  enable always trigger trg_10_guard_v7_reconciliation_row;

create or replace function private.fn_guard_v7_gate_row()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if nullif(new.test_code,'') is null
     or new.artifact_id is null
     or new.source_workflow_run_id is null
     or coalesce(new.source_commit_sha,'') !~ '^[0-9a-f]{40}$'
     or new.executed_at is null
     or new.executed_at<clock_timestamp()-interval '24 hours'
     or new.executed_at>clock_timestamp()+interval '5 minutes'
     or coalesce(new.persisted_effects->>'signed_preimage_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(new.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode='23514',
      message='V7 gate row failed storage-boundary integrity checks';
  end if;

  if new.passed and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=nullif(new.persisted_effects->>'github_reconciliation_run_id','')::bigint
      and g.artifact_id=new.artifact_id
      and g.workflow_run_id=new.source_workflow_run_id
      and g.merge_commit_sha=new.source_commit_sha
      and g.result='PASS'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using
      errcode='23514',
      message='V7 passing gate lacks its matching native-protected reconciliation';
  end if;

  return new;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode='23514',
      message='V7 gate contains a malformed reconciliation reference';
end;
$function$;

alter function private.fn_guard_v7_gate_row()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_guard_v7_gate_row()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_10_guard_v7_gate_row
  on private.lf_gate_test_runs_v3;
create trigger trg_10_guard_v7_gate_row
before insert or update
on private.lf_gate_test_runs_v3
for each row execute function private.fn_guard_v7_gate_row();
alter table private.lf_gate_test_runs_v3
  enable always trigger trg_10_guard_v7_gate_row;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180315',
  array[$source_20260801180315$-- Storage-boundary validation for every V7 reconciliation and gate row.
-- This prevents SQL three-valued logic or a future writer implementation from
-- persisting incomplete evidence.

begin;

create or replace function private.fn_guard_v7_reconciliation_row()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if new.result not in ('PASS','FAIL')
     or new.target_branch is distinct from 'main'
     or new.merged is not true
     or new.pr_state is distinct from 'MERGED'
     or new.workflow_event is distinct from 'push'
     or new.workflow_conclusion is distinct from 'success'
     or new.workflow_head_sha is distinct from new.merge_commit_sha
     or coalesce(new.merge_commit_sha,'') !~ '^[0-9a-f]{40}$'
     or coalesce(new.audit_manifest_sha256,'') !~ '^[0-9a-f]{64}$'
     or new.observed_at is null
     or new.observed_at<clock_timestamp()-interval '24 hours'
     or new.observed_at>clock_timestamp()+interval '5 minutes'
     or coalesce(new.details->>'signed_preimage_sha256','') !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode='23514',
      message='V7 reconciliation row failed storage-boundary integrity checks';
  end if;

  if new.result='PASS' and (
       new.branch_protection_status is distinct from 'VERIFIED'
       or coalesce(new.details->>'actual_branch_protection_status','')<>'VERIFIED'
       or new.artifact_exercised_by_workflow is not true
       or coalesce(new.artifact_sha256,'') !~ '^[0-9a-f]{64}$'
       or coalesce(new.artifact_git_blob,'') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using
      errcode='23514',
      message='V7 PASS reconciliation lacks native protection or complete artifact evidence';
  end if;

  return new;
end;
$function$;

alter function private.fn_guard_v7_reconciliation_row()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_guard_v7_reconciliation_row()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_10_guard_v7_reconciliation_row
  on private.lf_github_reconciliation_runs_v3;
create trigger trg_10_guard_v7_reconciliation_row
before insert or update
on private.lf_github_reconciliation_runs_v3
for each row execute function private.fn_guard_v7_reconciliation_row();
alter table private.lf_github_reconciliation_runs_v3
  enable always trigger trg_10_guard_v7_reconciliation_row;

create or replace function private.fn_guard_v7_gate_row()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if nullif(new.test_code,'') is null
     or new.artifact_id is null
     or new.source_workflow_run_id is null
     or coalesce(new.source_commit_sha,'') !~ '^[0-9a-f]{40}$'
     or new.executed_at is null
     or new.executed_at<clock_timestamp()-interval '24 hours'
     or new.executed_at>clock_timestamp()+interval '5 minutes'
     or coalesce(new.persisted_effects->>'signed_preimage_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(new.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$'
  then
    raise exception using
      errcode='23514',
      message='V7 gate row failed storage-boundary integrity checks';
  end if;

  if new.passed and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=nullif(new.persisted_effects->>'github_reconciliation_run_id','')::bigint
      and g.artifact_id=new.artifact_id
      and g.workflow_run_id=new.source_workflow_run_id
      and g.merge_commit_sha=new.source_commit_sha
      and g.result='PASS'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using
      errcode='23514',
      message='V7 passing gate lacks its matching native-protected reconciliation';
  end if;

  return new;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using
      errcode='23514',
      message='V7 gate contains a malformed reconciliation reference';
end;
$function$;

alter function private.fn_guard_v7_gate_row()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_guard_v7_gate_row()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_10_guard_v7_gate_row
  on private.lf_gate_test_runs_v3;
create trigger trg_10_guard_v7_gate_row
before insert or update
on private.lf_gate_test_runs_v3
for each row execute function private.fn_guard_v7_gate_row();
alter table private.lf_gate_test_runs_v3
  enable always trigger trg_10_guard_v7_gate_row;

commit;
$source_20260801180315$]::text[],
  'v7_row_integrity_guards',
  'pr93_v7_static_resume_from_4',
  'gitblob:ace19fefd8b656b82a9b86639ef7abb567a04e58',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 13/18 · 20260801180320_cleanup_idempotency_owner_context.sql
-- Git blob SHA-1: 5306c0136e59fe58f9217be7e0a4ed39f89dd3e2
-- -----------------------------------------------------------------------------
-- Remove every temporary privilege used by the idempotency replacement migration.
-- Then prepare the verifier-owner context required by the following key-rotation
-- migration, which alters the verifier-owned nonce relation and verifier-owned
-- consume function. The later canonicalization migration revokes this membership.

begin;

revoke create on schema public from lf_governance_owner_v3;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180320',
  array[$source_20260801180320$-- Remove every temporary privilege used by the idempotency replacement migration.
-- Then prepare the verifier-owner context required by the following key-rotation
-- migration, which alters the verifier-owned nonce relation and verifier-owned
-- consume function. The later canonicalization migration revokes this membership.

begin;

revoke create on schema public from lf_governance_owner_v3;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;

commit;
$source_20260801180320$]::text[],
  'cleanup_idempotency_owner_context',
  'pr93_v7_static_resume_from_4',
  'gitblob:5306c0136e59fe58f9217be7e0a4ed39f89dd3e2',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 14/18 · 20260801180400_writer_key_rotation_v7.sql
-- Git blob SHA-1: 3357696625dc05c951a937b1a05f1350e46fd320
-- -----------------------------------------------------------------------------
-- PR #93 / LOTE 1 / forward-only HMAC key rotation for the active V7 writer.
-- This migration extends the active V7 chain and preserves the existing Edge/RPC
-- contract: HMAC-SHA256(preimage || ':' || nonce).
-- Versioned only. Exercise in an isolated environment before any deployment.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null then
    raise exception 'private.lf_writer_hmac_keys_v7 must exist before rotation migration';
  end if;
  if to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'private.lf_reconciliation_writer_nonces_v7 must exist before rotation migration';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    raise exception 'lf_writer_verifier_v7 must exist before rotation migration';
  end if;
end
$preflight$;

alter table private.lf_writer_hmac_keys_v7
  add column if not exists key_id text,
  add column if not exists lifecycle_state text,
  add column if not exists activated_at timestamptz,
  add column if not exists retiring_at timestamptz,
  add column if not exists retiring_until timestamptz,
  add column if not exists retired_at timestamptz,
  add column if not exists last_transition_execution_id text;

-- Under the original fixed key_name primary key there can be at most one row.
-- Preserve it as the bootstrap generation when present.
update private.lf_writer_hmac_keys_v7
set key_id=coalesce(key_id,'lf-writer-2026-08-r00'),
    lifecycle_state=coalesce(
      lifecycle_state,
      case when active then 'ACTIVE' else 'RETIRED' end
    ),
    activated_at=coalesce(
      activated_at,
      case when active then created_at else coalesce(rotated_at,created_at) end
    ),
    retiring_at=coalesce(
      retiring_at,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    retiring_until=coalesce(
      retiring_until,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    retired_at=coalesce(
      retired_at,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    last_transition_execution_id=coalesce(
      last_transition_execution_id,
      installed_by_execution_id
    )
where key_id is null
   or lifecycle_state is null
   or last_transition_execution_id is null;

alter table private.lf_writer_hmac_keys_v7
  alter column key_id set not null,
  alter column lifecycle_state set not null,
  alter column last_transition_execution_id set not null;

-- Replace the fixed logical-name primary key with a public generation identifier.
do $primary_key$
declare
  v_pk_name text;
  v_pk_definition text;
begin
  select c.conname,pg_get_constraintdef(c.oid)
    into v_pk_name,v_pk_definition
  from pg_constraint c
  where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
    and c.contype='p';

  if v_pk_name is not null and v_pk_definition not like '%(key_id)%' then
    execute format(
      'alter table private.lf_writer_hmac_keys_v7 drop constraint %I',
      v_pk_name
    );
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and c.contype='p'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_pkey primary key (key_id);
  end if;
end
$primary_key$;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_key_id_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_key_id_ck
      check (key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_lifecycle_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_lifecycle_ck
      check (lifecycle_state in ('PREPARED','ACTIVE','RETIRING','RETIRED'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_active_lifecycle_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_active_lifecycle_ck
      check (active=(lifecycle_state='ACTIVE'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_state_times_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_state_times_ck
      check (
        (
lifecycle_state='PREPARED'
and activated_at is null
and retiring_at is null
and retiring_until is null
and retired_at is null
        )
        or (
lifecycle_state='ACTIVE'
and activated_at is not null
and retiring_at is null
and retiring_until is null
and retired_at is null
        )
        or (
lifecycle_state='RETIRING'
and activated_at is not null
and retiring_at is not null
and retiring_until is not null
and retiring_until>retiring_at
and retired_at is null
        )
        or (
lifecycle_state='RETIRED'
and activated_at is not null
and retiring_at is not null
and retiring_until is not null
and retired_at is not null
and retired_at>=retiring_at
        )
      );
  end if;
end
$constraints$;

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_active
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='ACTIVE';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_prepared
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='PREPARED';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_retiring
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='RETIRING';

-- Nullable for compatibility with nonce rows created before this migration.
alter table private.lf_reconciliation_writer_nonces_v7
  add column if not exists key_id text;

do $nonce_constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_reconciliation_writer_nonces_v7'::regclass
      and conname='lf_reconciliation_writer_nonces_v7_key_id_ck'
  ) then
    alter table private.lf_reconciliation_writer_nonces_v7
      add constraint lf_reconciliation_writer_nonces_v7_key_id_ck
      check (
        key_id is null
        or key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$'
      );
  end if;
end
$nonce_constraint$;

create or replace function private.fn_guard_lf_writer_hmac_keys_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='DELETE' then
    raise exception using
      errcode='55000',
      message='writer keys are append-and-transition only';
  end if;

  if new.key_id is distinct from old.key_id
     or new.key_name is distinct from old.key_name
     or new.key_material is distinct from old.key_material
     or new.created_at is distinct from old.created_at
     or new.installed_by_execution_id is distinct from old.installed_by_execution_id then
    raise exception using
      errcode='55000',
      message='writer key identity and material are immutable';
  end if;

  if not (
    (old.lifecycle_state='PREPARED' and new.lifecycle_state='ACTIVE')
    or (old.lifecycle_state='ACTIVE' and new.lifecycle_state='RETIRING')
    or (old.lifecycle_state='RETIRING' and new.lifecycle_state='RETIRED')
  ) then
    raise exception using
      errcode='55000',
      message='invalid writer key lifecycle transition';
  end if;

  if new.active is distinct from (new.lifecycle_state='ACTIVE') then
    raise exception using
      errcode='55000',
      message='writer key active flag does not match lifecycle state';
  end if;

  if old.lifecycle_state='RETIRING'
     and new.lifecycle_state='RETIRED'
     and clock_timestamp()<old.retiring_until then
    raise exception using
      errcode='55000',
      message='writer key overlap window is still open';
  end if;

  return new;
end;
$function$;

alter function private.fn_guard_lf_writer_hmac_keys_v7() owner to postgres;
revoke all on function private.fn_guard_lf_writer_hmac_keys_v7()
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

drop trigger if exists trg_guard_lf_writer_hmac_keys_v7
  on private.lf_writer_hmac_keys_v7;
create trigger trg_guard_lf_writer_hmac_keys_v7
before update or delete on private.lf_writer_hmac_keys_v7
for each row execute function private.fn_guard_lf_writer_hmac_keys_v7();

alter table private.lf_writer_hmac_keys_v7
  enable always trigger trg_guard_lf_writer_hmac_keys_v7;

create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_key_ready_v7()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.fn_writer_key_separation_v7_valid()
    and (
      select count(*)=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='ACTIVE'
        and k.active
        and nullif(k.key_material,'') is not null
    )
    and (
      select count(*)<=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='PREPARED'
    )
    and (
      select count(*)<=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='RETIRING'
    )
    and not exists (
      select 1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='RETIRING'
        and k.retiring_until<=clock_timestamp()
    );
$function$;

alter function private.fn_writer_key_ready_v7() owner to postgres;
revoke all on function private.fn_writer_key_ready_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_ready_v7()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_hmac_v7_match_key(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns text
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_active_count integer;
  v_key record;
  v_expected text;
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception using
      errcode='42501',
      message='writer key separation is not valid';
  end if;

  if nullif(p_preimage,'') is null
     or nullif(p_nonce,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select count(*)
    into v_active_count
  from private.lf_writer_hmac_keys_v7 k
  where k.lifecycle_state='ACTIVE'
    and k.active
    and nullif(k.key_material,'') is not null;

  if v_active_count<>1 then
    raise exception using
      errcode='55000',
      message='writer HMAC active key is not configured exactly once';
  end if;

  for v_key in
    select k.key_id,k.key_material
    from private.lf_writer_hmac_keys_v7 k
    where k.lifecycle_state='ACTIVE'
       or (
         k.lifecycle_state='RETIRING'
         and k.retiring_until>clock_timestamp()
       )
    order by case k.lifecycle_state when 'ACTIVE' then 0 else 1 end,k.created_at desc
  loop
    v_expected:=encode(
      extensions.hmac(
        convert_to(p_preimage||':'||p_nonce,'UTF8'),
        convert_to(v_key.key_material,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    if extensions.digest(convert_to(v_expected,'UTF8'),'sha256')
       = extensions.digest(convert_to(lower(p_signature),'UTF8'),'sha256') then
      return v_key.key_id;
    end if;
  end loop;

  return null;
end;
$function$;

alter function private.fn_writer_hmac_v7_match_key(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_match_key(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_match_key(text,text,text)
  to lf_writer_verifier_v7;

create or replace function private.fn_writer_hmac_v7_valid(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns boolean
language sql
volatile
security definer
set search_path to ''
as $function$
  select private.fn_writer_hmac_v7_match_key(
    p_preimage,p_nonce,lower(p_signature)
  ) is not null;
$function$;

alter function private.fn_writer_hmac_v7_valid(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_valid(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_valid(text,text,text)
  to lf_writer_verifier_v7;

create or replace function private.fn_consume_writer_proof_v7(
  p_preimage text,
  p_signature text,
  p_writer_nonce text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_claims jsonb:='{}'::jsonb;
  v_role text;
  v_exp timestamptz;
  v_scope text;
  v_key_id text;
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(
      nullif(current_setting('request.jwt.claims',true),'')::jsonb,
      '{}'::jsonb
    );
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then return false; end if;
  if nullif(p_preimage,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  if coalesce(p_writer_nonce,'') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range
      or datetime_field_overflow then
      return false;
  end;

  if v_exp<=clock_timestamp()-interval '5 seconds'
     or v_exp>clock_timestamp()+interval '6 minutes' then
    return false;
  end if;

  if p_preimage like 'reconciliation-v7:%' then
    v_scope:='RECONCILIATION';
  elsif p_preimage like 'gate-v7:%' then
    v_scope:='GATE';
  else
    return false;
  end if;

  v_key_id:=private.fn_writer_hmac_v7_match_key(
    p_preimage,p_writer_nonce,lower(p_signature)
  );
  if v_key_id is null then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role,key_id
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role,
    v_key_id
  ) on conflict do nothing;

  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

create or replace function private.fn_install_writer_hmac_key_v7(
  p_key_id text,
  p_key_material text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if coalesce(p_key_id,'') !~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$' then
    raise exception using errcode='22023',message='invalid key_id';
  end if;
  if length(coalesce(p_key_material,''))<32 then
    raise exception using errcode='22023',message='key material is too short';
  end if;
  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  insert into private.lf_writer_hmac_keys_v7(
    key_name,key_id,key_material,active,lifecycle_state,created_at,
    installed_by_execution_id,last_transition_execution_id
  ) values (
    'lf_reconciliation_writer_hmac_v7',
    p_key_id,
    p_key_material,
    false,
    'PREPARED',
    clock_timestamp(),
    p_execution_id,
    p_execution_id
  );
end;
$function$;

alter function private.fn_install_writer_hmac_key_v7(text,text,text)
  owner to postgres;
revoke all on function private.fn_install_writer_hmac_key_v7(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_install_writer_hmac_key_v7(text,text,text)
  to postgres;

create or replace function private.fn_writer_hmac_challenge_v7(
  p_key_id text,
  p_challenge text
)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_key text;
begin
  if coalesce(p_challenge,'') !~
    '^rotation-check-v7:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode='22023',message='invalid rotation challenge';
  end if;

  select k.key_material
    into strict v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_id=p_key_id
    and k.lifecycle_state in ('PREPARED','ACTIVE','RETIRING')
    and (
      k.lifecycle_state<>'RETIRING'
      or k.retiring_until>clock_timestamp()
    );

  return encode(
    extensions.hmac(
      convert_to(p_challenge,'UTF8'),
      convert_to(v_key,'UTF8'),
      'sha256'
    ),
    'hex'
  );
end;
$function$;

alter function private.fn_writer_hmac_challenge_v7(text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_challenge_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_writer_hmac_challenge_v7(text,text)
  to postgres;

create or replace function private.fn_promote_writer_hmac_key_v7(
  p_key_id text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_rows integer;
  v_now timestamptz:=clock_timestamp();
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7
    where lifecycle_state='RETIRING'
  ) then
    raise exception using
      errcode='55000',
      message='retiring writer key must be retired before another promotion';
  end if;

  update private.lf_writer_hmac_keys_v7
  set active=false,
      lifecycle_state='RETIRING',
      retiring_at=v_now,
      retiring_until=v_now+interval '10 minutes',
      last_transition_execution_id=p_execution_id
  where lifecycle_state='ACTIVE';

  update private.lf_writer_hmac_keys_v7
  set active=true,
      lifecycle_state='ACTIVE',
      activated_at=v_now,
      last_transition_execution_id=p_execution_id
  where key_id=p_key_id
    and lifecycle_state='PREPARED';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception using
      errcode='55000',
      message='exactly one prepared key must be promoted';
  end if;
end;
$function$;

alter function private.fn_promote_writer_hmac_key_v7(text,text) owner to postgres;
revoke all on function private.fn_promote_writer_hmac_key_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_promote_writer_hmac_key_v7(text,text)
  to postgres;

create or replace function private.fn_retire_writer_hmac_key_v7(
  p_key_id text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_rows integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7 k
    where k.key_id=p_key_id
      and k.lifecycle_state='RETIRING'
      and k.retiring_until>clock_timestamp()
  ) then
    raise exception using
      errcode='55000',
      message='writer key overlap window is still open';
  end if;

  if exists (
    select 1
    from private.lf_reconciliation_writer_nonces_v7 n
    where n.key_id=p_key_id
      and n.expires_at>=clock_timestamp()
  ) then
    raise exception using
      errcode='55000',
      message='unexpired nonces still reference this key';
  end if;

  update private.lf_writer_hmac_keys_v7
  set active=false,
      lifecycle_state='RETIRED',
      retired_at=clock_timestamp(),
      last_transition_execution_id=p_execution_id
  where key_id=p_key_id
    and lifecycle_state='RETIRING';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception using
      errcode='55000',
      message='exactly one retiring key must be retired';
  end if;
end;
$function$;

alter function private.fn_retire_writer_hmac_key_v7(text,text) owner to postgres;
revoke all on function private.fn_retire_writer_hmac_key_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_retire_writer_hmac_key_v7(text,text)
  to postgres;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180400',
  array[$source_20260801180400$-- PR #93 / LOTE 1 / forward-only HMAC key rotation for the active V7 writer.
-- This migration extends the active V7 chain and preserves the existing Edge/RPC
-- contract: HMAC-SHA256(preimage || ':' || nonce).
-- Versioned only. Exercise in an isolated environment before any deployment.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null then
    raise exception 'private.lf_writer_hmac_keys_v7 must exist before rotation migration';
  end if;
  if to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'private.lf_reconciliation_writer_nonces_v7 must exist before rotation migration';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    raise exception 'lf_writer_verifier_v7 must exist before rotation migration';
  end if;
end
$preflight$;

alter table private.lf_writer_hmac_keys_v7
  add column if not exists key_id text,
  add column if not exists lifecycle_state text,
  add column if not exists activated_at timestamptz,
  add column if not exists retiring_at timestamptz,
  add column if not exists retiring_until timestamptz,
  add column if not exists retired_at timestamptz,
  add column if not exists last_transition_execution_id text;

-- Under the original fixed key_name primary key there can be at most one row.
-- Preserve it as the bootstrap generation when present.
update private.lf_writer_hmac_keys_v7
set key_id=coalesce(key_id,'lf-writer-2026-08-r00'),
    lifecycle_state=coalesce(
      lifecycle_state,
      case when active then 'ACTIVE' else 'RETIRED' end
    ),
    activated_at=coalesce(
      activated_at,
      case when active then created_at else coalesce(rotated_at,created_at) end
    ),
    retiring_at=coalesce(
      retiring_at,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    retiring_until=coalesce(
      retiring_until,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    retired_at=coalesce(
      retired_at,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    last_transition_execution_id=coalesce(
      last_transition_execution_id,
      installed_by_execution_id
    )
where key_id is null
   or lifecycle_state is null
   or last_transition_execution_id is null;

alter table private.lf_writer_hmac_keys_v7
  alter column key_id set not null,
  alter column lifecycle_state set not null,
  alter column last_transition_execution_id set not null;

-- Replace the fixed logical-name primary key with a public generation identifier.
do $primary_key$
declare
  v_pk_name text;
  v_pk_definition text;
begin
  select c.conname,pg_get_constraintdef(c.oid)
    into v_pk_name,v_pk_definition
  from pg_constraint c
  where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
    and c.contype='p';

  if v_pk_name is not null and v_pk_definition not like '%(key_id)%' then
    execute format(
      'alter table private.lf_writer_hmac_keys_v7 drop constraint %I',
      v_pk_name
    );
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and c.contype='p'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_pkey primary key (key_id);
  end if;
end
$primary_key$;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_key_id_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_key_id_ck
      check (key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_lifecycle_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_lifecycle_ck
      check (lifecycle_state in ('PREPARED','ACTIVE','RETIRING','RETIRED'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_active_lifecycle_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_active_lifecycle_ck
      check (active=(lifecycle_state='ACTIVE'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_state_times_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_state_times_ck
      check (
        (
lifecycle_state='PREPARED'
and activated_at is null
and retiring_at is null
and retiring_until is null
and retired_at is null
        )
        or (
lifecycle_state='ACTIVE'
and activated_at is not null
and retiring_at is null
and retiring_until is null
and retired_at is null
        )
        or (
lifecycle_state='RETIRING'
and activated_at is not null
and retiring_at is not null
and retiring_until is not null
and retiring_until>retiring_at
and retired_at is null
        )
        or (
lifecycle_state='RETIRED'
and activated_at is not null
and retiring_at is not null
and retiring_until is not null
and retired_at is not null
and retired_at>=retiring_at
        )
      );
  end if;
end
$constraints$;

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_active
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='ACTIVE';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_prepared
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='PREPARED';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_retiring
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='RETIRING';

-- Nullable for compatibility with nonce rows created before this migration.
alter table private.lf_reconciliation_writer_nonces_v7
  add column if not exists key_id text;

do $nonce_constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_reconciliation_writer_nonces_v7'::regclass
      and conname='lf_reconciliation_writer_nonces_v7_key_id_ck'
  ) then
    alter table private.lf_reconciliation_writer_nonces_v7
      add constraint lf_reconciliation_writer_nonces_v7_key_id_ck
      check (
        key_id is null
        or key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$'
      );
  end if;
end
$nonce_constraint$;

create or replace function private.fn_guard_lf_writer_hmac_keys_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='DELETE' then
    raise exception using
      errcode='55000',
      message='writer keys are append-and-transition only';
  end if;

  if new.key_id is distinct from old.key_id
     or new.key_name is distinct from old.key_name
     or new.key_material is distinct from old.key_material
     or new.created_at is distinct from old.created_at
     or new.installed_by_execution_id is distinct from old.installed_by_execution_id then
    raise exception using
      errcode='55000',
      message='writer key identity and material are immutable';
  end if;

  if not (
    (old.lifecycle_state='PREPARED' and new.lifecycle_state='ACTIVE')
    or (old.lifecycle_state='ACTIVE' and new.lifecycle_state='RETIRING')
    or (old.lifecycle_state='RETIRING' and new.lifecycle_state='RETIRED')
  ) then
    raise exception using
      errcode='55000',
      message='invalid writer key lifecycle transition';
  end if;

  if new.active is distinct from (new.lifecycle_state='ACTIVE') then
    raise exception using
      errcode='55000',
      message='writer key active flag does not match lifecycle state';
  end if;

  if old.lifecycle_state='RETIRING'
     and new.lifecycle_state='RETIRED'
     and clock_timestamp()<old.retiring_until then
    raise exception using
      errcode='55000',
      message='writer key overlap window is still open';
  end if;

  return new;
end;
$function$;

alter function private.fn_guard_lf_writer_hmac_keys_v7() owner to postgres;
revoke all on function private.fn_guard_lf_writer_hmac_keys_v7()
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

drop trigger if exists trg_guard_lf_writer_hmac_keys_v7
  on private.lf_writer_hmac_keys_v7;
create trigger trg_guard_lf_writer_hmac_keys_v7
before update or delete on private.lf_writer_hmac_keys_v7
for each row execute function private.fn_guard_lf_writer_hmac_keys_v7();

alter table private.lf_writer_hmac_keys_v7
  enable always trigger trg_guard_lf_writer_hmac_keys_v7;

create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_key_ready_v7()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select private.fn_writer_key_separation_v7_valid()
    and (
      select count(*)=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='ACTIVE'
        and k.active
        and nullif(k.key_material,'') is not null
    )
    and (
      select count(*)<=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='PREPARED'
    )
    and (
      select count(*)<=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='RETIRING'
    )
    and not exists (
      select 1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='RETIRING'
        and k.retiring_until<=clock_timestamp()
    );
$function$;

alter function private.fn_writer_key_ready_v7() owner to postgres;
revoke all on function private.fn_writer_key_ready_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_ready_v7()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_hmac_v7_match_key(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns text
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_active_count integer;
  v_key record;
  v_expected text;
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception using
      errcode='42501',
      message='writer key separation is not valid';
  end if;

  if nullif(p_preimage,'') is null
     or nullif(p_nonce,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select count(*)
    into v_active_count
  from private.lf_writer_hmac_keys_v7 k
  where k.lifecycle_state='ACTIVE'
    and k.active
    and nullif(k.key_material,'') is not null;

  if v_active_count<>1 then
    raise exception using
      errcode='55000',
      message='writer HMAC active key is not configured exactly once';
  end if;

  for v_key in
    select k.key_id,k.key_material
    from private.lf_writer_hmac_keys_v7 k
    where k.lifecycle_state='ACTIVE'
       or (
         k.lifecycle_state='RETIRING'
         and k.retiring_until>clock_timestamp()
       )
    order by case k.lifecycle_state when 'ACTIVE' then 0 else 1 end,k.created_at desc
  loop
    v_expected:=encode(
      extensions.hmac(
        convert_to(p_preimage||':'||p_nonce,'UTF8'),
        convert_to(v_key.key_material,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    if extensions.digest(convert_to(v_expected,'UTF8'),'sha256')
       = extensions.digest(convert_to(lower(p_signature),'UTF8'),'sha256') then
      return v_key.key_id;
    end if;
  end loop;

  return null;
end;
$function$;

alter function private.fn_writer_hmac_v7_match_key(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_match_key(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_match_key(text,text,text)
  to lf_writer_verifier_v7;

create or replace function private.fn_writer_hmac_v7_valid(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns boolean
language sql
volatile
security definer
set search_path to ''
as $function$
  select private.fn_writer_hmac_v7_match_key(
    p_preimage,p_nonce,lower(p_signature)
  ) is not null;
$function$;

alter function private.fn_writer_hmac_v7_valid(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_valid(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_valid(text,text,text)
  to lf_writer_verifier_v7;

create or replace function private.fn_consume_writer_proof_v7(
  p_preimage text,
  p_signature text,
  p_writer_nonce text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_claims jsonb:='{}'::jsonb;
  v_role text;
  v_exp timestamptz;
  v_scope text;
  v_key_id text;
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(
      nullif(current_setting('request.jwt.claims',true),'')::jsonb,
      '{}'::jsonb
    );
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then return false; end if;
  if nullif(p_preimage,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  if coalesce(p_writer_nonce,'') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range
      or datetime_field_overflow then
      return false;
  end;

  if v_exp<=clock_timestamp()-interval '5 seconds'
     or v_exp>clock_timestamp()+interval '6 minutes' then
    return false;
  end if;

  if p_preimage like 'reconciliation-v7:%' then
    v_scope:='RECONCILIATION';
  elsif p_preimage like 'gate-v7:%' then
    v_scope:='GATE';
  else
    return false;
  end if;

  v_key_id:=private.fn_writer_hmac_v7_match_key(
    p_preimage,p_writer_nonce,lower(p_signature)
  );
  if v_key_id is null then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role,key_id
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role,
    v_key_id
  ) on conflict do nothing;

  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

create or replace function private.fn_install_writer_hmac_key_v7(
  p_key_id text,
  p_key_material text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if coalesce(p_key_id,'') !~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$' then
    raise exception using errcode='22023',message='invalid key_id';
  end if;
  if length(coalesce(p_key_material,''))<32 then
    raise exception using errcode='22023',message='key material is too short';
  end if;
  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  insert into private.lf_writer_hmac_keys_v7(
    key_name,key_id,key_material,active,lifecycle_state,created_at,
    installed_by_execution_id,last_transition_execution_id
  ) values (
    'lf_reconciliation_writer_hmac_v7',
    p_key_id,
    p_key_material,
    false,
    'PREPARED',
    clock_timestamp(),
    p_execution_id,
    p_execution_id
  );
end;
$function$;

alter function private.fn_install_writer_hmac_key_v7(text,text,text)
  owner to postgres;
revoke all on function private.fn_install_writer_hmac_key_v7(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_install_writer_hmac_key_v7(text,text,text)
  to postgres;

create or replace function private.fn_writer_hmac_challenge_v7(
  p_key_id text,
  p_challenge text
)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_key text;
begin
  if coalesce(p_challenge,'') !~
    '^rotation-check-v7:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode='22023',message='invalid rotation challenge';
  end if;

  select k.key_material
    into strict v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_id=p_key_id
    and k.lifecycle_state in ('PREPARED','ACTIVE','RETIRING')
    and (
      k.lifecycle_state<>'RETIRING'
      or k.retiring_until>clock_timestamp()
    );

  return encode(
    extensions.hmac(
      convert_to(p_challenge,'UTF8'),
      convert_to(v_key,'UTF8'),
      'sha256'
    ),
    'hex'
  );
end;
$function$;

alter function private.fn_writer_hmac_challenge_v7(text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_challenge_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_writer_hmac_challenge_v7(text,text)
  to postgres;

create or replace function private.fn_promote_writer_hmac_key_v7(
  p_key_id text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_rows integer;
  v_now timestamptz:=clock_timestamp();
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7
    where lifecycle_state='RETIRING'
  ) then
    raise exception using
      errcode='55000',
      message='retiring writer key must be retired before another promotion';
  end if;

  update private.lf_writer_hmac_keys_v7
  set active=false,
      lifecycle_state='RETIRING',
      retiring_at=v_now,
      retiring_until=v_now+interval '10 minutes',
      last_transition_execution_id=p_execution_id
  where lifecycle_state='ACTIVE';

  update private.lf_writer_hmac_keys_v7
  set active=true,
      lifecycle_state='ACTIVE',
      activated_at=v_now,
      last_transition_execution_id=p_execution_id
  where key_id=p_key_id
    and lifecycle_state='PREPARED';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception using
      errcode='55000',
      message='exactly one prepared key must be promoted';
  end if;
end;
$function$;

alter function private.fn_promote_writer_hmac_key_v7(text,text) owner to postgres;
revoke all on function private.fn_promote_writer_hmac_key_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_promote_writer_hmac_key_v7(text,text)
  to postgres;

create or replace function private.fn_retire_writer_hmac_key_v7(
  p_key_id text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_rows integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7 k
    where k.key_id=p_key_id
      and k.lifecycle_state='RETIRING'
      and k.retiring_until>clock_timestamp()
  ) then
    raise exception using
      errcode='55000',
      message='writer key overlap window is still open';
  end if;

  if exists (
    select 1
    from private.lf_reconciliation_writer_nonces_v7 n
    where n.key_id=p_key_id
      and n.expires_at>=clock_timestamp()
  ) then
    raise exception using
      errcode='55000',
      message='unexpired nonces still reference this key';
  end if;

  update private.lf_writer_hmac_keys_v7
  set active=false,
      lifecycle_state='RETIRED',
      retired_at=clock_timestamp(),
      last_transition_execution_id=p_execution_id
  where key_id=p_key_id
    and lifecycle_state='RETIRING';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception using
      errcode='55000',
      message='exactly one retiring key must be retired';
  end if;
end;
$function$;

alter function private.fn_retire_writer_hmac_key_v7(text,text) owner to postgres;
revoke all on function private.fn_retire_writer_hmac_key_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_retire_writer_hmac_key_v7(text,text)
  to postgres;

commit;
$source_20260801180400$]::text[],
  'writer_key_rotation_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:3357696625dc05c951a937b1a05f1350e46fd320',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 15/18 · 20260801180500_writer_canonicalization_rls_v7.sql
-- Git blob SHA-1: d41297db3d3bed95ba4f0a6286399dbee268570b
-- -----------------------------------------------------------------------------
-- PR #93 / CA-N30..CA-N35 hardening for the active V7 writer.
-- Versioned only. This migration must be exercised in an isolated environment.
-- It preserves the Edge/RPC contract HMAC-SHA256(preimage || ':' || nonce).
--
-- Canonicalization contract:
--   * fixed component count and fixed ':' separators;
--   * ordinary missing/JSON-null values become an empty component, matching JS Array.join;
--   * fields explicitly wrapped with JavaScript String() use its primitive semantics;
--   * the public gate writer accepts only booleans for those String() fields.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'V7 writer relations must exist before canonicalization hardening';
  end if;
  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('public.record_external_ci_verification_v7(jsonb,text,text,text)') is null
     or to_regprocedure('public.record_lf_gate_test_v7(jsonb,text,text,text)') is null then
    raise exception 'V7 writer functions must exist before canonicalization hardening';
  end if;
end
$preflight$;

-- Temporary owner context for replacing governance-owned functions and modifying the
-- verifier-owned nonce relation. Every grant is revoked before commit.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema public to lf_governance_owner_v3;
grant create on schema private to lf_governance_owner_v3;

-- CA-N31: the keystore must remain usable if postgres no longer has BYPASSRLS.
drop policy if exists pol_lf_writer_hmac_keys_v7_postgres
  on private.lf_writer_hmac_keys_v7;
create policy pol_lf_writer_hmac_keys_v7_postgres
  on private.lf_writer_hmac_keys_v7
  for all
  to postgres
  using (current_user='postgres')
  with check (current_user='postgres');

-- CA-N32: historical rows may have NULL key_id, but every new nonce must identify
-- the key generation that validated the HMAC.
drop policy if exists pol_lf_writer_nonce_v7_insert
  on private.lf_reconciliation_writer_nonces_v7;
create policy pol_lf_writer_nonce_v7_insert
  on private.lf_reconciliation_writer_nonces_v7
  for insert
  to lf_writer_verifier_v7
  with check (
    request_role='service_role'
    and key_id is not null
    and nonce_sha256 ~ '^[0-9a-f]{64}$'
    and preimage_sha256 ~ '^[0-9a-f]{64}$'
    and expires_at > consumed_at - interval '5 seconds'
    and expires_at <= consumed_at + interval '6 minutes'
  );

-- CA-N34: RETIRED history must be compatible with a valid or bootstrap overlap.
alter table private.lf_writer_hmac_keys_v7
  drop constraint if exists lf_writer_hmac_keys_v7_state_times_ck;
alter table private.lf_writer_hmac_keys_v7
  add constraint lf_writer_hmac_keys_v7_state_times_ck
  check (
    (
      lifecycle_state='PREPARED'
      and activated_at is null
      and retiring_at is null
      and retiring_until is null
      and retired_at is null
    )
    or (
      lifecycle_state='ACTIVE'
      and activated_at is not null
      and retiring_at is null
      and retiring_until is null
      and retired_at is null
    )
    or (
      lifecycle_state='RETIRING'
      and activated_at is not null
      and retiring_at is not null
      and retiring_until is not null
      and retiring_until>retiring_at
      and retired_at is null
    )
    or (
      lifecycle_state='RETIRED'
      and activated_at is not null
      and retiring_at is not null
      and retiring_until is not null
      and retiring_until>=retiring_at
      and retired_at is not null
      and retired_at>=retiring_at
    )
  );

-- CA-N35: row triggers do not fire for TRUNCATE.
create or replace function private.fn_block_writer_security_truncate_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using
    errcode='55000',
    message='writer security relations cannot be truncated';
end;
$function$;

alter function private.fn_block_writer_security_truncate_v7() owner to postgres;
revoke all on function private.fn_block_writer_security_truncate_v7()
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

drop trigger if exists trg_block_lf_writer_hmac_keys_v7_truncate
  on private.lf_writer_hmac_keys_v7;
create trigger trg_block_lf_writer_hmac_keys_v7_truncate
before truncate on private.lf_writer_hmac_keys_v7
for each statement execute function private.fn_block_writer_security_truncate_v7();
alter table private.lf_writer_hmac_keys_v7
  enable always trigger trg_block_lf_writer_hmac_keys_v7_truncate;

drop trigger if exists trg_block_lf_writer_nonces_v7_truncate
  on private.lf_reconciliation_writer_nonces_v7;
create trigger trg_block_lf_writer_nonces_v7_truncate
before truncate on private.lf_reconciliation_writer_nonces_v7
for each statement execute function private.fn_block_writer_security_truncate_v7();
alter table private.lf_reconciliation_writer_nonces_v7
  enable always trigger trg_block_lf_writer_nonces_v7_truncate;

-- Convert a JSON primitive to the representation produced by an ordinary element in
-- JavaScript Array.join(':'). Missing and JSON null values become an empty component.
create or replace function private.fn_json_join_component_v7(p_value jsonb)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_type text;
begin
  if p_value is null or p_value='null'::jsonb then
    return '';
  end if;

  v_type:=jsonb_typeof(p_value);
  if v_type not in ('string','number','boolean') then
    raise exception using
      errcode='22023',
      message='canonical preimage component must be a JSON primitive';
  end if;

  return jsonb_build_object('v',p_value)->>'v';
end;
$function$;

alter function private.fn_json_join_component_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_json_join_component_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_json_join_component_v7(jsonb)
  to lf_governance_owner_v3;

-- Reproduce JavaScript String(value) for the primitive values allowed by the writer.
create or replace function private.fn_json_js_string_v7(
  p_value jsonb,
  p_present boolean
)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_type text;
begin
  if not coalesce(p_present,false) then
    return 'undefined';
  end if;
  if p_value is null or p_value='null'::jsonb then
    return 'null';
  end if;

  v_type:=jsonb_typeof(p_value);
  if v_type not in ('string','number','boolean') then
    raise exception using
      errcode='22023',
      message='JavaScript String canonical component must be a JSON primitive';
  end if;

  return jsonb_build_object('v',p_value)->>'v';
end;
$function$;

alter function private.fn_json_js_string_v7(jsonb,boolean)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_json_js_string_v7(jsonb,boolean)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_json_js_string_v7(jsonb,boolean)
  to lf_governance_owner_v3;

create or replace function private.fn_reconciliation_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
set search_path to ''
as $function$
  select array_to_string(array[
    'reconciliation-v7',
    coalesce(p_execution_id,''),
    private.fn_json_join_component_v7(p_payload->'artifact_id'),
    private.fn_json_join_component_v7(p_payload->'workflow_run_id'),
    private.fn_json_join_component_v7(p_payload->'merge_commit_sha'),
    private.fn_json_join_component_v7(p_payload->'artifact_sha256'),
    private.fn_json_join_component_v7(p_payload->'branch_protection_status'),
    private.fn_json_join_component_v7(p_payload->'result'),
    private.fn_json_join_component_v7(p_payload->'audit_manifest_sha256')
  ],':','');
$function$;

alter function private.fn_reconciliation_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

create or replace function private.fn_gate_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
set search_path to ''
as $function$
  select array_to_string(array[
    'gate-v7',
    coalesce(p_execution_id,''),
    private.fn_json_join_component_v7(p_payload->'artifact_id'),
    private.fn_json_join_component_v7(p_payload->'test_code'),
    private.fn_json_join_component_v7(p_payload->'source_workflow_run_id'),
    private.fn_json_join_component_v7(p_payload->'source_commit_sha'),
    private.fn_json_js_string_v7(p_payload->'passed',p_payload?'passed'),
    private.fn_json_join_component_v7(p_payload->'target_relation'),
    private.fn_json_join_component_v7(p_payload->'gate_code'),
    private.fn_json_join_component_v7(p_payload#>'{probe_preimage,expected_sha256}'),
    private.fn_json_join_component_v7(p_payload#>'{observed_outcome,artifact_sha256}'),
    private.fn_json_js_string_v7(
      p_payload#>'{observed_outcome,audit_covered}',
      coalesce((p_payload->'observed_outcome')?'audit_covered',false)
    ),
    private.fn_json_join_component_v7(
      p_payload#>'{persisted_effects,github_reconciliation_run_id}'
    )
  ],':','');
$function$;

alter function private.fn_gate_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_gate_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

-- Recreate the reconciliation writer with fixed-position canonicalization.
create or replace function public.record_external_ci_verification_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_event_id bigint;
  v_run_id bigint;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_payload->'artifact_id') is distinct from 'number'
     or jsonb_typeof(p_payload->'workflow_run_id') is distinct from 'number'
     or coalesce(p_payload->>'merge_commit_sha','') !~ '^[0-9a-f]{40}$'
     or not (p_payload?'artifact_sha256')
     or jsonb_typeof(p_payload->'branch_protection_status') is distinct from 'string'
     or coalesce(p_payload->>'audit_manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_payload->>'result','') not in ('PASS','FAIL') then
    raise exception using errcode='23514',message='external reconciliation payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=private.fn_reconciliation_preimage_v7(p_payload,p_execution_id);
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce reconciliation writer failed';
  end if;

  if p_payload->>'target_branch'<>'main'
     or p_payload->>'workflow_event'<>'push'
     or p_payload->>'workflow_conclusion'<>'success'
     or p_payload->>'workflow_head_sha' is distinct from p_payload->>'merge_commit_sha'
     or coalesce((p_payload->>'merged')::boolean,false) is not true
     or p_payload->>'pr_state'<>'MERGED'
     or (p_payload->>'observed_at')::timestamptz<clock_timestamp()-interval '24 hours'
     or (p_payload->>'observed_at')::timestamptz>clock_timestamp()+interval '5 minutes' then
    raise exception using errcode='23514',message='external reconciliation source is not current post-merge evidence';
  end if;

  if p_payload->>'result'='PASS' and (
       p_payload->>'branch_protection_status'<>'VERIFIED'
       or coalesce(p_payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
       or not coalesce((p_payload->>'artifact_exercised_by_workflow')::boolean,false)
       or coalesce(p_payload->>'artifact_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(p_payload->>'artifact_git_blob','') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using errcode='23514',message='PASS requires native protection and complete workflow evidence';
  end if;

  if p_payload->>'artifact_path' is distinct from v_artifact.relative_path then
    raise exception using errcode='23514',message='external reconciliation artifact path mismatch';
  end if;
  if p_payload->>'result'='PASS' and (
    not v_artifact.is_current
    or p_payload->>'artifact_sha256' is distinct from v_artifact.content_sha256
  ) then
    raise exception using errcode='23514',message='external reconciliation PASS does not match current artifact content';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-github-v7:'||v_artifact.id::text,0));

  select g.id,g.details->>'signed_preimage_sha256'
    into v_run_id,v_existing_preimage_hash
  from private.lf_github_reconciliation_runs_v3 g
  where g.artifact_id=v_artifact.id
    and g.workflow_run_id=(p_payload->>'workflow_run_id')::bigint
    and g.merge_commit_sha=p_payload->>'merge_commit_sha'
    and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

  if found then
    if v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting V7 reconciliation already exists for source workflow';
    end if;
    return v_run_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_payload:=(p_payload-'verification_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','external-ci-verification/v3',
    'execution_id',p_execution_id,
    'verification_mode','GITHUB_ACTIONS_OIDC_HMAC_V7',
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('verification_payload_sha256',v_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'EXTERNAL_CI_VERIFICATION_COMPLETED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'Authoritative OIDC HMAC nonce post-merge GitHub reconciliation recorded',
    case when v_payload->>'result'='PASS' then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_github_reconciliation_runs_v3(
    artifact_id,repository,target_branch,artifact_path,pr_number,pr_state,merged,merge_commit_sha,
    workflow_run_id,workflow_name,workflow_event,workflow_head_sha,workflow_conclusion,
    artifact_git_blob,artifact_sha256,file_touched_by_merge,artifact_exercised_by_workflow,
    audit_artifact_name,audit_manifest_sha256,branch_protection_status,result,authoritative,
    failure_reasons,details,verification_payload_sha256,source_external_event_id,evidence_event_id,
    reconciled_by_execution_id,observed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_artifact.id,v_payload->>'repository',v_payload->>'target_branch',v_payload->>'artifact_path',
    case when v_payload->'pr_number'='null'::jsonb or not(v_payload?'pr_number')
      then null else (v_payload->>'pr_number')::integer end,
    v_payload->>'pr_state',(v_payload->>'merged')::boolean,v_payload->>'merge_commit_sha',
    (v_payload->>'workflow_run_id')::bigint,v_payload->>'workflow_name',v_payload->>'workflow_event',
    v_payload->>'workflow_head_sha',v_payload->>'workflow_conclusion',v_payload->>'artifact_git_blob',
    v_payload->>'artifact_sha256',(v_payload->>'file_touched_by_merge')::boolean,
    (v_payload->>'artifact_exercised_by_workflow')::boolean,v_payload->>'audit_artifact_name',
    v_payload->>'audit_manifest_sha256',v_payload->>'branch_protection_status',v_payload->>'result',true,
    v_payload->'failure_reasons',coalesce(v_payload->'details','{}'::jsonb)||jsonb_build_object(
      'writer_authentication_v7','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_nonce_sha256',v_nonce_hash,
      'writer_proof_expires_at',v_proof_expires_at,
      'signed_preimage_sha256',v_preimage_hash
    ),v_hash,v_event_id,v_event_id,p_execution_id,(v_payload->>'observed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_run_id;

  return v_run_id;
end;
$function$;

alter function public.record_external_ci_verification_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  to service_role;

-- Recreate the gate writer with the same fixed-position canonicalization contract.
create or replace function public.record_lf_gate_test_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_probe_hash text;
  v_effect_hash text;
  v_payload_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_persisted_effects jsonb;
  v_event_id bigint;
  v_id bigint;
  v_reconciliation_id bigint;
  v_existing_writer text;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object'
     or jsonb_typeof(p_payload->'artifact_id') is distinct from 'number'
     or jsonb_typeof(p_payload->'source_workflow_run_id') is distinct from 'number'
     or coalesce(p_payload->>'source_commit_sha','') !~ '^[0-9a-f]{40}$'
     or nullif(p_payload->>'test_code','') is null
     or nullif(p_payload->>'target_relation','') is null
     or nullif(p_payload->>'gate_code','') is null
     or jsonb_typeof(p_payload->'passed') is distinct from 'boolean'
     or jsonb_typeof(p_payload->'probe_preimage') is distinct from 'object'
     or jsonb_typeof(p_payload->'observed_outcome') is distinct from 'object'
     or jsonb_typeof(p_payload#>'{observed_outcome,audit_covered}') is distinct from 'boolean'
     or jsonb_typeof(p_payload->'persisted_effects') is distinct from 'object' then
    raise exception using errcode='23514',message='gate test payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=private.fn_gate_preimage_v7(p_payload,p_execution_id);
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce gate writer failed';
  end if;

  v_reconciliation_id:=nullif(
    p_payload#>>'{persisted_effects,github_reconciliation_run_id}',''
  )::bigint;
  if coalesce((p_payload->>'passed')::boolean,false) and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=v_reconciliation_id
      and g.artifact_id=v_artifact.id
      and g.result='PASS'
      and g.authoritative
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and g.workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
      and g.merge_commit_sha=p_payload->>'source_commit_sha'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using errcode='23514',message='passing gate test requires matching V7 reconciliation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'lf-gate-v7:'||v_artifact.id::text||':'||coalesce(p_payload->>'test_code',''),0
  ));

  select t.id,t.writer_authentication,t.persisted_effects->>'signed_preimage_sha256'
    into v_id,v_existing_writer,v_existing_preimage_hash
  from private.lf_gate_test_runs_v3 t
  where t.test_code=p_payload->>'test_code'
    and t.artifact_id=v_artifact.id
    and t.source_workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
    and t.source_commit_sha=p_payload->>'source_commit_sha';

  if found then
    if v_existing_writer<>'GITHUB_OIDC_HMAC_NONCE_V7'
       or v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting gate evidence already exists for source workflow';
    end if;
    return v_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_probe_hash:=encode(
    extensions.digest(convert_to((p_payload->'probe_preimage')::text,'UTF8'),'sha256'),'hex'
  );
  v_persisted_effects:=coalesce(p_payload->'persisted_effects','{}'::jsonb)
    ||jsonb_build_object('signed_preimage_sha256',v_preimage_hash);
  v_effect_hash:=encode(
    extensions.digest(convert_to(v_persisted_effects::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=(p_payload-'evidence_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','gate-test-run/v3',
    'execution_id',p_execution_id,
    'probe_sha256',v_probe_hash,
    'persisted_effects',v_persisted_effects,
    'persisted_effects_sha256',v_effect_hash,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_payload_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('evidence_payload_sha256',v_payload_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'GATE_TEST_RUN_RECORDED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'OIDC HMAC nonce reproducible architecture gate test recorded',
    case when coalesce((v_payload->>'passed')::boolean,false) then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_gate_test_runs_v3(
    test_code,artifact_id,gate_code,test_kind,target_relation,probe_preimage,probe_sha256,
    expected_outcome,observed_outcome,persisted_effects,persisted_effects_sha256,passed,
    runner_type,runner_identity,source_workflow_run_id,source_commit_sha,evidence_event_id,
    executed_by_execution_id,executed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_payload->>'test_code',v_artifact.id,v_payload->>'gate_code',v_payload->>'test_kind',
    v_payload->>'target_relation',v_payload->'probe_preimage',v_probe_hash,
    v_payload->'expected_outcome',v_payload->'observed_outcome',
    v_persisted_effects,v_effect_hash,(v_payload->>'passed')::boolean,
    v_payload->>'runner_type',v_payload->>'runner_identity',
    (v_payload->>'source_workflow_run_id')::bigint,v_payload->>'source_commit_sha',
    v_event_id,p_execution_id,(v_payload->>'executed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.record_lf_gate_test_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  to service_role;

-- Explicitly include the postgres RLS policy in the separation predicate.
create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    exists (
      select 1
      from pg_policies p
      where p.schemaname='private'
        and p.tablename='lf_writer_hmac_keys_v7'
        and p.policyname='pol_lf_writer_hmac_keys_v7_postgres'
        and p.cmd='ALL'
        and 'postgres'=any(p.roles)
    )
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

-- CA-N33: expose a non-secret reason when readiness is false after rotation.
create or replace function private.fn_writer_key_rotation_status_v7()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when not private.fn_writer_key_separation_v7_valid()
      then 'KEY_SEPARATION_INVALID'
    when (select count(*) from private.lf_writer_hmac_keys_v7
where lifecycle_state='ACTIVE' and active)<>1
      then 'ACTIVE_KEY_COUNT_INVALID'
    when exists (
      select 1 from private.lf_writer_hmac_keys_v7
      where lifecycle_state='RETIRING'
        and retiring_until<=clock_timestamp()
    )
      then 'RETIREMENT_DUE'
    when exists (
      select 1 from private.lf_writer_hmac_keys_v7
      where lifecycle_state='RETIRING'
    )
      then 'OVERLAP_ACTIVE'
    when exists (
      select 1 from private.lf_writer_hmac_keys_v7
      where lifecycle_state='PREPARED'
    )
      then 'PREPARED_PENDING'
    else 'READY'
  end;
$function$;

alter function private.fn_writer_key_rotation_status_v7() owner to postgres;
revoke all on function private.fn_writer_key_rotation_status_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_rotation_status_v7()
  to postgres,service_role,lf_governance_owner_v3;

-- Remove all temporary owner context created by this migration.
revoke create on schema public from lf_governance_owner_v3;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_writer_verifier_v7 from postgres granted by postgres;
revoke lf_governance_owner_v3 from postgres granted by postgres;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180500',
  array[$source_20260801180500$-- PR #93 / CA-N30..CA-N35 hardening for the active V7 writer.
-- Versioned only. This migration must be exercised in an isolated environment.
-- It preserves the Edge/RPC contract HMAC-SHA256(preimage || ':' || nonce).
--
-- Canonicalization contract:
--   * fixed component count and fixed ':' separators;
--   * ordinary missing/JSON-null values become an empty component, matching JS Array.join;
--   * fields explicitly wrapped with JavaScript String() use its primitive semantics;
--   * the public gate writer accepts only booleans for those String() fields.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'V7 writer relations must exist before canonicalization hardening';
  end if;
  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('public.record_external_ci_verification_v7(jsonb,text,text,text)') is null
     or to_regprocedure('public.record_lf_gate_test_v7(jsonb,text,text,text)') is null then
    raise exception 'V7 writer functions must exist before canonicalization hardening';
  end if;
end
$preflight$;

-- Temporary owner context for replacing governance-owned functions and modifying the
-- verifier-owned nonce relation. Every grant is revoked before commit.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema public to lf_governance_owner_v3;
grant create on schema private to lf_governance_owner_v3;

-- CA-N31: the keystore must remain usable if postgres no longer has BYPASSRLS.
drop policy if exists pol_lf_writer_hmac_keys_v7_postgres
  on private.lf_writer_hmac_keys_v7;
create policy pol_lf_writer_hmac_keys_v7_postgres
  on private.lf_writer_hmac_keys_v7
  for all
  to postgres
  using (current_user='postgres')
  with check (current_user='postgres');

-- CA-N32: historical rows may have NULL key_id, but every new nonce must identify
-- the key generation that validated the HMAC.
drop policy if exists pol_lf_writer_nonce_v7_insert
  on private.lf_reconciliation_writer_nonces_v7;
create policy pol_lf_writer_nonce_v7_insert
  on private.lf_reconciliation_writer_nonces_v7
  for insert
  to lf_writer_verifier_v7
  with check (
    request_role='service_role'
    and key_id is not null
    and nonce_sha256 ~ '^[0-9a-f]{64}$'
    and preimage_sha256 ~ '^[0-9a-f]{64}$'
    and expires_at > consumed_at - interval '5 seconds'
    and expires_at <= consumed_at + interval '6 minutes'
  );

-- CA-N34: RETIRED history must be compatible with a valid or bootstrap overlap.
alter table private.lf_writer_hmac_keys_v7
  drop constraint if exists lf_writer_hmac_keys_v7_state_times_ck;
alter table private.lf_writer_hmac_keys_v7
  add constraint lf_writer_hmac_keys_v7_state_times_ck
  check (
    (
      lifecycle_state='PREPARED'
      and activated_at is null
      and retiring_at is null
      and retiring_until is null
      and retired_at is null
    )
    or (
      lifecycle_state='ACTIVE'
      and activated_at is not null
      and retiring_at is null
      and retiring_until is null
      and retired_at is null
    )
    or (
      lifecycle_state='RETIRING'
      and activated_at is not null
      and retiring_at is not null
      and retiring_until is not null
      and retiring_until>retiring_at
      and retired_at is null
    )
    or (
      lifecycle_state='RETIRED'
      and activated_at is not null
      and retiring_at is not null
      and retiring_until is not null
      and retiring_until>=retiring_at
      and retired_at is not null
      and retired_at>=retiring_at
    )
  );

-- CA-N35: row triggers do not fire for TRUNCATE.
create or replace function private.fn_block_writer_security_truncate_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using
    errcode='55000',
    message='writer security relations cannot be truncated';
end;
$function$;

alter function private.fn_block_writer_security_truncate_v7() owner to postgres;
revoke all on function private.fn_block_writer_security_truncate_v7()
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

drop trigger if exists trg_block_lf_writer_hmac_keys_v7_truncate
  on private.lf_writer_hmac_keys_v7;
create trigger trg_block_lf_writer_hmac_keys_v7_truncate
before truncate on private.lf_writer_hmac_keys_v7
for each statement execute function private.fn_block_writer_security_truncate_v7();
alter table private.lf_writer_hmac_keys_v7
  enable always trigger trg_block_lf_writer_hmac_keys_v7_truncate;

drop trigger if exists trg_block_lf_writer_nonces_v7_truncate
  on private.lf_reconciliation_writer_nonces_v7;
create trigger trg_block_lf_writer_nonces_v7_truncate
before truncate on private.lf_reconciliation_writer_nonces_v7
for each statement execute function private.fn_block_writer_security_truncate_v7();
alter table private.lf_reconciliation_writer_nonces_v7
  enable always trigger trg_block_lf_writer_nonces_v7_truncate;

-- Convert a JSON primitive to the representation produced by an ordinary element in
-- JavaScript Array.join(':'). Missing and JSON null values become an empty component.
create or replace function private.fn_json_join_component_v7(p_value jsonb)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_type text;
begin
  if p_value is null or p_value='null'::jsonb then
    return '';
  end if;

  v_type:=jsonb_typeof(p_value);
  if v_type not in ('string','number','boolean') then
    raise exception using
      errcode='22023',
      message='canonical preimage component must be a JSON primitive';
  end if;

  return jsonb_build_object('v',p_value)->>'v';
end;
$function$;

alter function private.fn_json_join_component_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_json_join_component_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_json_join_component_v7(jsonb)
  to lf_governance_owner_v3;

-- Reproduce JavaScript String(value) for the primitive values allowed by the writer.
create or replace function private.fn_json_js_string_v7(
  p_value jsonb,
  p_present boolean
)
returns text
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_type text;
begin
  if not coalesce(p_present,false) then
    return 'undefined';
  end if;
  if p_value is null or p_value='null'::jsonb then
    return 'null';
  end if;

  v_type:=jsonb_typeof(p_value);
  if v_type not in ('string','number','boolean') then
    raise exception using
      errcode='22023',
      message='JavaScript String canonical component must be a JSON primitive';
  end if;

  return jsonb_build_object('v',p_value)->>'v';
end;
$function$;

alter function private.fn_json_js_string_v7(jsonb,boolean)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_json_js_string_v7(jsonb,boolean)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_json_js_string_v7(jsonb,boolean)
  to lf_governance_owner_v3;

create or replace function private.fn_reconciliation_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
set search_path to ''
as $function$
  select array_to_string(array[
    'reconciliation-v7',
    coalesce(p_execution_id,''),
    private.fn_json_join_component_v7(p_payload->'artifact_id'),
    private.fn_json_join_component_v7(p_payload->'workflow_run_id'),
    private.fn_json_join_component_v7(p_payload->'merge_commit_sha'),
    private.fn_json_join_component_v7(p_payload->'artifact_sha256'),
    private.fn_json_join_component_v7(p_payload->'branch_protection_status'),
    private.fn_json_join_component_v7(p_payload->'result'),
    private.fn_json_join_component_v7(p_payload->'audit_manifest_sha256')
  ],':','');
$function$;

alter function private.fn_reconciliation_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

create or replace function private.fn_gate_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
set search_path to ''
as $function$
  select array_to_string(array[
    'gate-v7',
    coalesce(p_execution_id,''),
    private.fn_json_join_component_v7(p_payload->'artifact_id'),
    private.fn_json_join_component_v7(p_payload->'test_code'),
    private.fn_json_join_component_v7(p_payload->'source_workflow_run_id'),
    private.fn_json_join_component_v7(p_payload->'source_commit_sha'),
    private.fn_json_js_string_v7(p_payload->'passed',p_payload?'passed'),
    private.fn_json_join_component_v7(p_payload->'target_relation'),
    private.fn_json_join_component_v7(p_payload->'gate_code'),
    private.fn_json_join_component_v7(p_payload#>'{probe_preimage,expected_sha256}'),
    private.fn_json_join_component_v7(p_payload#>'{observed_outcome,artifact_sha256}'),
    private.fn_json_js_string_v7(
      p_payload#>'{observed_outcome,audit_covered}',
      coalesce((p_payload->'observed_outcome')?'audit_covered',false)
    ),
    private.fn_json_join_component_v7(
      p_payload#>'{persisted_effects,github_reconciliation_run_id}'
    )
  ],':','');
$function$;

alter function private.fn_gate_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_gate_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

-- Recreate the reconciliation writer with fixed-position canonicalization.
create or replace function public.record_external_ci_verification_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_event_id bigint;
  v_run_id bigint;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_payload->'artifact_id') is distinct from 'number'
     or jsonb_typeof(p_payload->'workflow_run_id') is distinct from 'number'
     or coalesce(p_payload->>'merge_commit_sha','') !~ '^[0-9a-f]{40}$'
     or not (p_payload?'artifact_sha256')
     or jsonb_typeof(p_payload->'branch_protection_status') is distinct from 'string'
     or coalesce(p_payload->>'audit_manifest_sha256','') !~ '^[0-9a-f]{64}$'
     or coalesce(p_payload->>'result','') not in ('PASS','FAIL') then
    raise exception using errcode='23514',message='external reconciliation payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=private.fn_reconciliation_preimage_v7(p_payload,p_execution_id);
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce reconciliation writer failed';
  end if;

  if p_payload->>'target_branch'<>'main'
     or p_payload->>'workflow_event'<>'push'
     or p_payload->>'workflow_conclusion'<>'success'
     or p_payload->>'workflow_head_sha' is distinct from p_payload->>'merge_commit_sha'
     or coalesce((p_payload->>'merged')::boolean,false) is not true
     or p_payload->>'pr_state'<>'MERGED'
     or (p_payload->>'observed_at')::timestamptz<clock_timestamp()-interval '24 hours'
     or (p_payload->>'observed_at')::timestamptz>clock_timestamp()+interval '5 minutes' then
    raise exception using errcode='23514',message='external reconciliation source is not current post-merge evidence';
  end if;

  if p_payload->>'result'='PASS' and (
       p_payload->>'branch_protection_status'<>'VERIFIED'
       or coalesce(p_payload#>>'{details,actual_branch_protection_status}','')<>'VERIFIED'
       or not coalesce((p_payload->>'artifact_exercised_by_workflow')::boolean,false)
       or coalesce(p_payload->>'artifact_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(p_payload->>'artifact_git_blob','') !~ '^[0-9a-f]{40}$'
     ) then
    raise exception using errcode='23514',message='PASS requires native protection and complete workflow evidence';
  end if;

  if p_payload->>'artifact_path' is distinct from v_artifact.relative_path then
    raise exception using errcode='23514',message='external reconciliation artifact path mismatch';
  end if;
  if p_payload->>'result'='PASS' and (
    not v_artifact.is_current
    or p_payload->>'artifact_sha256' is distinct from v_artifact.content_sha256
  ) then
    raise exception using errcode='23514',message='external reconciliation PASS does not match current artifact content';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-github-v7:'||v_artifact.id::text,0));

  select g.id,g.details->>'signed_preimage_sha256'
    into v_run_id,v_existing_preimage_hash
  from private.lf_github_reconciliation_runs_v3 g
  where g.artifact_id=v_artifact.id
    and g.workflow_run_id=(p_payload->>'workflow_run_id')::bigint
    and g.merge_commit_sha=p_payload->>'merge_commit_sha'
    and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';

  if found then
    if v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting V7 reconciliation already exists for source workflow';
    end if;
    return v_run_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_payload:=(p_payload-'verification_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','external-ci-verification/v3',
    'execution_id',p_execution_id,
    'verification_mode','GITHUB_ACTIONS_OIDC_HMAC_V7',
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('verification_payload_sha256',v_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'EXTERNAL_CI_VERIFICATION_COMPLETED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'Authoritative OIDC HMAC nonce post-merge GitHub reconciliation recorded',
    case when v_payload->>'result'='PASS' then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_github_reconciliation_runs_v3(
    artifact_id,repository,target_branch,artifact_path,pr_number,pr_state,merged,merge_commit_sha,
    workflow_run_id,workflow_name,workflow_event,workflow_head_sha,workflow_conclusion,
    artifact_git_blob,artifact_sha256,file_touched_by_merge,artifact_exercised_by_workflow,
    audit_artifact_name,audit_manifest_sha256,branch_protection_status,result,authoritative,
    failure_reasons,details,verification_payload_sha256,source_external_event_id,evidence_event_id,
    reconciled_by_execution_id,observed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_artifact.id,v_payload->>'repository',v_payload->>'target_branch',v_payload->>'artifact_path',
    case when v_payload->'pr_number'='null'::jsonb or not(v_payload?'pr_number')
      then null else (v_payload->>'pr_number')::integer end,
    v_payload->>'pr_state',(v_payload->>'merged')::boolean,v_payload->>'merge_commit_sha',
    (v_payload->>'workflow_run_id')::bigint,v_payload->>'workflow_name',v_payload->>'workflow_event',
    v_payload->>'workflow_head_sha',v_payload->>'workflow_conclusion',v_payload->>'artifact_git_blob',
    v_payload->>'artifact_sha256',(v_payload->>'file_touched_by_merge')::boolean,
    (v_payload->>'artifact_exercised_by_workflow')::boolean,v_payload->>'audit_artifact_name',
    v_payload->>'audit_manifest_sha256',v_payload->>'branch_protection_status',v_payload->>'result',true,
    v_payload->'failure_reasons',coalesce(v_payload->'details','{}'::jsonb)||jsonb_build_object(
      'writer_authentication_v7','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_nonce_sha256',v_nonce_hash,
      'writer_proof_expires_at',v_proof_expires_at,
      'signed_preimage_sha256',v_preimage_hash
    ),v_hash,v_event_id,v_event_id,p_execution_id,(v_payload->>'observed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_run_id;

  return v_run_id;
end;
$function$;

alter function public.record_external_ci_verification_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_external_ci_verification_v7(jsonb,text,text,text)
  to service_role;

-- Recreate the gate writer with the same fixed-position canonicalization contract.
create or replace function public.record_lf_gate_test_v7(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_artifact private.lf_skill_artifacts%rowtype;
  v_payload jsonb;
  v_probe_hash text;
  v_effect_hash text;
  v_payload_hash text;
  v_signature_hash text;
  v_nonce_hash text;
  v_proof_expires_at timestamptz;
  v_preimage text;
  v_preimage_hash text;
  v_persisted_effects jsonb;
  v_event_id bigint;
  v_id bigint;
  v_reconciliation_id bigint;
  v_existing_writer text;
  v_existing_preimage_hash text;
begin
  if jsonb_typeof(p_payload) is distinct from 'object'
     or jsonb_typeof(p_payload->'artifact_id') is distinct from 'number'
     or jsonb_typeof(p_payload->'source_workflow_run_id') is distinct from 'number'
     or coalesce(p_payload->>'source_commit_sha','') !~ '^[0-9a-f]{40}$'
     or nullif(p_payload->>'test_code','') is null
     or nullif(p_payload->>'target_relation','') is null
     or nullif(p_payload->>'gate_code','') is null
     or jsonb_typeof(p_payload->'passed') is distinct from 'boolean'
     or jsonb_typeof(p_payload->'probe_preimage') is distinct from 'object'
     or jsonb_typeof(p_payload->'observed_outcome') is distinct from 'object'
     or jsonb_typeof(p_payload#>'{observed_outcome,audit_covered}') is distinct from 'boolean'
     or jsonb_typeof(p_payload->'persisted_effects') is distinct from 'object' then
    raise exception using errcode='23514',message='gate test payload is incomplete';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then
    raise exception using errcode='P0002',message='artifact not found';
  end if;

  v_preimage:=private.fn_gate_preimage_v7(p_payload,p_execution_id);
  v_preimage_hash:=encode(
    extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_preimage,lower(p_writer_signature),p_writer_nonce
  ) then
    raise exception using errcode='42501',message='OIDC HMAC nonce gate writer failed';
  end if;

  v_reconciliation_id:=nullif(
    p_payload#>>'{persisted_effects,github_reconciliation_run_id}',''
  )::bigint;
  if coalesce((p_payload->>'passed')::boolean,false) and not exists (
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    where g.id=v_reconciliation_id
      and g.artifact_id=v_artifact.id
      and g.result='PASS'
      and g.authoritative
      and g.branch_protection_status='VERIFIED'
      and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
      and g.workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
      and g.merge_commit_sha=p_payload->>'source_commit_sha'
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and private.fn_reconciliation_nonce_v7_valid(g.id)
  ) then
    raise exception using errcode='23514',message='passing gate test requires matching V7 reconciliation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'lf-gate-v7:'||v_artifact.id::text||':'||coalesce(p_payload->>'test_code',''),0
  ));

  select t.id,t.writer_authentication,t.persisted_effects->>'signed_preimage_sha256'
    into v_id,v_existing_writer,v_existing_preimage_hash
  from private.lf_gate_test_runs_v3 t
  where t.test_code=p_payload->>'test_code'
    and t.artifact_id=v_artifact.id
    and t.source_workflow_run_id=(p_payload->>'source_workflow_run_id')::bigint
    and t.source_commit_sha=p_payload->>'source_commit_sha';

  if found then
    if v_existing_writer<>'GITHUB_OIDC_HMAC_NONCE_V7'
       or v_existing_preimage_hash is distinct from v_preimage_hash then
      raise exception using errcode='23505',message='conflicting gate evidence already exists for source workflow';
    end if;
    return v_id;
  end if;

  v_signature_hash:=encode(
    extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex'
  );
  v_nonce_hash:=encode(
    extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'
  );
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_probe_hash:=encode(
    extensions.digest(convert_to((p_payload->'probe_preimage')::text,'UTF8'),'sha256'),'hex'
  );
  v_persisted_effects:=coalesce(p_payload->'persisted_effects','{}'::jsonb)
    ||jsonb_build_object('signed_preimage_sha256',v_preimage_hash);
  v_effect_hash:=encode(
    extensions.digest(convert_to(v_persisted_effects::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=(p_payload-'evidence_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','gate-test-run/v3',
    'execution_id',p_execution_id,
    'probe_sha256',v_probe_hash,
    'persisted_effects',v_persisted_effects,
    'persisted_effects_sha256',v_effect_hash,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_payload_hash:=encode(
    extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex'
  );
  v_payload:=v_payload||jsonb_build_object('evidence_payload_sha256',v_payload_hash);

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,created_by_execution_id
  ) values (
    'GATE_TEST_RUN_RECORDED','LF_SKILL_ARTIFACT',v_artifact.artifact_code,
    'OIDC HMAC nonce reproducible architecture gate test recorded',
    case when coalesce((v_payload->>'passed')::boolean,false) then 'INFO' else 'WARN' end,
    v_payload,p_execution_id
  ) returning id into v_event_id;

  insert into private.lf_gate_test_runs_v3(
    test_code,artifact_id,gate_code,test_kind,target_relation,probe_preimage,probe_sha256,
    expected_outcome,observed_outcome,persisted_effects,persisted_effects_sha256,passed,
    runner_type,runner_identity,source_workflow_run_id,source_commit_sha,evidence_event_id,
    executed_by_execution_id,executed_at,writer_authentication,writer_signature_sha256
  ) values (
    v_payload->>'test_code',v_artifact.id,v_payload->>'gate_code',v_payload->>'test_kind',
    v_payload->>'target_relation',v_payload->'probe_preimage',v_probe_hash,
    v_payload->'expected_outcome',v_payload->'observed_outcome',
    v_persisted_effects,v_effect_hash,(v_payload->>'passed')::boolean,
    v_payload->>'runner_type',v_payload->>'runner_identity',
    (v_payload->>'source_workflow_run_id')::bigint,v_payload->>'source_commit_sha',
    v_event_id,p_execution_id,(v_payload->>'executed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.record_lf_gate_test_v7(jsonb,text,text,text)
  owner to lf_governance_owner_v3;
revoke all on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  to service_role;

-- Explicitly include the postgres RLS policy in the separation predicate.
create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    exists (
      select 1
      from pg_policies p
      where p.schemaname='private'
        and p.tablename='lf_writer_hmac_keys_v7'
        and p.policyname='pol_lf_writer_hmac_keys_v7_postgres'
        and p.cmd='ALL'
        and 'postgres'=any(p.roles)
    )
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

-- CA-N33: expose a non-secret reason when readiness is false after rotation.
create or replace function private.fn_writer_key_rotation_status_v7()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when not private.fn_writer_key_separation_v7_valid()
      then 'KEY_SEPARATION_INVALID'
    when (select count(*) from private.lf_writer_hmac_keys_v7
where lifecycle_state='ACTIVE' and active)<>1
      then 'ACTIVE_KEY_COUNT_INVALID'
    when exists (
      select 1 from private.lf_writer_hmac_keys_v7
      where lifecycle_state='RETIRING'
        and retiring_until<=clock_timestamp()
    )
      then 'RETIREMENT_DUE'
    when exists (
      select 1 from private.lf_writer_hmac_keys_v7
      where lifecycle_state='RETIRING'
    )
      then 'OVERLAP_ACTIVE'
    when exists (
      select 1 from private.lf_writer_hmac_keys_v7
      where lifecycle_state='PREPARED'
    )
      then 'PREPARED_PENDING'
    else 'READY'
  end;
$function$;

alter function private.fn_writer_key_rotation_status_v7() owner to postgres;
revoke all on function private.fn_writer_key_rotation_status_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_rotation_status_v7()
  to postgres,service_role,lf_governance_owner_v3;

-- Remove all temporary owner context created by this migration.
revoke create on schema public from lf_governance_owner_v3;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_writer_verifier_v7 from postgres granted by postgres;
revoke lf_governance_owner_v3 from postgres granted by postgres;

commit;
$source_20260801180500$]::text[],
  'writer_canonicalization_rls_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:d41297db3d3bed95ba4f0a6286399dbee268570b',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 16/18 · 20260801180510_writer_full_payload_binding_v7.sql
-- Git blob SHA-1: a52faeedf7b44e00da512dd6c6b34aacd3976a95
-- -----------------------------------------------------------------------------
-- PR #93 / CA-N36..CA-N38 full-payload binding for the active V7 writer.
-- Versioned only. Exercise in an isolated environment before deployment.
--
-- Canonical contract shared with Edge:
--   * every payload key is ASCII and sorted bytewise;
--   * strings use JSON escaping;
--   * arrays preserve order;
--   * numbers must be JavaScript-safe integers;
--   * the signed payload component is SHA-256(canonical JSON);
--   * preimage components use UTF-8 byte-length framing, not delimiters.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null then
    raise exception 'V7 canonical preimage helpers must exist before full-payload binding';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'lf_governance_owner_v3 must exist before full-payload binding';
  end if;
end
$preflight$;

-- Temporary owner context. A failure rolls this back with the migration.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

create or replace function private.fn_canonical_json_v7(p_value jsonb)
returns text
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_type text;
  v_result text;
  v_number numeric;
begin
  v_type:=jsonb_typeof(p_value);

  if v_type='null' then
    return 'null';
  elsif v_type='boolean' then
    return p_value::text;
  elsif v_type='number' then
    begin
      v_number:=(p_value#>>'{}')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using
errcode='22023',
message='canonical JSON number is invalid';
    end;

    if v_number<>trunc(v_number)
       or v_number < -9007199254740991::numeric
       or v_number >  9007199254740991::numeric then
      raise exception using
        errcode='22023',
        message='canonical JSON numbers must be JavaScript-safe integers';
    end if;

    return trunc(v_number)::text;
  elsif v_type='string' then
    return to_jsonb(p_value#>>'{}')::text;
  elsif v_type='array' then
    select '['||coalesce(string_agg(
      private.fn_canonical_json_v7(e.value),
      ',' order by e.ordinality
    ),'')||']'
      into v_result
    from jsonb_array_elements(p_value) with ordinality as e(value,ordinality);

    return v_result;
  elsif v_type='object' then
    if exists (
      select 1
      from jsonb_object_keys(p_value) as k(key_name)
      where k.key_name !~ '^[A-Za-z0-9_.-]+$'
    ) then
      raise exception using
        errcode='22023',
        message='canonical JSON object keys must be ASCII identifiers';
    end if;

    select '{'||coalesce(string_agg(
      to_jsonb(e.key)::text||':'||private.fn_canonical_json_v7(e.value),
      ',' order by e.key collate "C"
    ),'')||'}'
      into v_result
    from jsonb_each(p_value) as e(key,value);

    return v_result;
  end if;

  raise exception using
    errcode='22023',
    message='canonical JSON value has unsupported type';
end;
$function$;

alter function private.fn_canonical_json_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_canonical_json_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_canonical_json_v7(jsonb)
  to lf_governance_owner_v3;

create or replace function private.fn_payload_sha256_v7(p_payload jsonb)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select encode(
    extensions.digest(
      convert_to(private.fn_canonical_json_v7(p_payload),'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

alter function private.fn_payload_sha256_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_payload_sha256_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_payload_sha256_v7(jsonb)
  to lf_governance_owner_v3;

create or replace function private.fn_frame_component_v7(p_value text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select octet_length(coalesce(p_value,''))::text||'#'||coalesce(p_value,'');
$function$;

alter function private.fn_frame_component_v7(text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_frame_component_v7(text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_frame_component_v7(text)
  to lf_governance_owner_v3;

-- CA-N36: framing removes delimiter ambiguity.
-- CA-N37: the payload digest binds every payload field, including nested details.
-- CA-N38: canonical JSON rejects non-integer and unsafe numeric values.
create or replace function private.fn_reconciliation_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select
    private.fn_frame_component_v7('reconciliation-v7')
    ||private.fn_frame_component_v7(p_execution_id)
    ||private.fn_frame_component_v7(private.fn_payload_sha256_v7(p_payload));
$function$;

alter function private.fn_reconciliation_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

create or replace function private.fn_gate_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select
    private.fn_frame_component_v7('gate-v7')
    ||private.fn_frame_component_v7(p_execution_id)
    ||private.fn_frame_component_v7(private.fn_payload_sha256_v7(p_payload));
$function$;

alter function private.fn_gate_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_gate_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180510',
  array[$source_20260801180510$-- PR #93 / CA-N36..CA-N38 full-payload binding for the active V7 writer.
-- Versioned only. Exercise in an isolated environment before deployment.
--
-- Canonical contract shared with Edge:
--   * every payload key is ASCII and sorted bytewise;
--   * strings use JSON escaping;
--   * arrays preserve order;
--   * numbers must be JavaScript-safe integers;
--   * the signed payload component is SHA-256(canonical JSON);
--   * preimage components use UTF-8 byte-length framing, not delimiters.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null then
    raise exception 'V7 canonical preimage helpers must exist before full-payload binding';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'lf_governance_owner_v3 must exist before full-payload binding';
  end if;
end
$preflight$;

-- Temporary owner context. A failure rolls this back with the migration.
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

create or replace function private.fn_canonical_json_v7(p_value jsonb)
returns text
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_type text;
  v_result text;
  v_number numeric;
begin
  v_type:=jsonb_typeof(p_value);

  if v_type='null' then
    return 'null';
  elsif v_type='boolean' then
    return p_value::text;
  elsif v_type='number' then
    begin
      v_number:=(p_value#>>'{}')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception using
errcode='22023',
message='canonical JSON number is invalid';
    end;

    if v_number<>trunc(v_number)
       or v_number < -9007199254740991::numeric
       or v_number >  9007199254740991::numeric then
      raise exception using
        errcode='22023',
        message='canonical JSON numbers must be JavaScript-safe integers';
    end if;

    return trunc(v_number)::text;
  elsif v_type='string' then
    return to_jsonb(p_value#>>'{}')::text;
  elsif v_type='array' then
    select '['||coalesce(string_agg(
      private.fn_canonical_json_v7(e.value),
      ',' order by e.ordinality
    ),'')||']'
      into v_result
    from jsonb_array_elements(p_value) with ordinality as e(value,ordinality);

    return v_result;
  elsif v_type='object' then
    if exists (
      select 1
      from jsonb_object_keys(p_value) as k(key_name)
      where k.key_name !~ '^[A-Za-z0-9_.-]+$'
    ) then
      raise exception using
        errcode='22023',
        message='canonical JSON object keys must be ASCII identifiers';
    end if;

    select '{'||coalesce(string_agg(
      to_jsonb(e.key)::text||':'||private.fn_canonical_json_v7(e.value),
      ',' order by e.key collate "C"
    ),'')||'}'
      into v_result
    from jsonb_each(p_value) as e(key,value);

    return v_result;
  end if;

  raise exception using
    errcode='22023',
    message='canonical JSON value has unsupported type';
end;
$function$;

alter function private.fn_canonical_json_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_canonical_json_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_canonical_json_v7(jsonb)
  to lf_governance_owner_v3;

create or replace function private.fn_payload_sha256_v7(p_payload jsonb)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select encode(
    extensions.digest(
      convert_to(private.fn_canonical_json_v7(p_payload),'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

alter function private.fn_payload_sha256_v7(jsonb)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_payload_sha256_v7(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_payload_sha256_v7(jsonb)
  to lf_governance_owner_v3;

create or replace function private.fn_frame_component_v7(p_value text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select octet_length(coalesce(p_value,''))::text||'#'||coalesce(p_value,'');
$function$;

alter function private.fn_frame_component_v7(text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_frame_component_v7(text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_frame_component_v7(text)
  to lf_governance_owner_v3;

-- CA-N36: framing removes delimiter ambiguity.
-- CA-N37: the payload digest binds every payload field, including nested details.
-- CA-N38: canonical JSON rejects non-integer and unsafe numeric values.
create or replace function private.fn_reconciliation_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select
    private.fn_frame_component_v7('reconciliation-v7')
    ||private.fn_frame_component_v7(p_execution_id)
    ||private.fn_frame_component_v7(private.fn_payload_sha256_v7(p_payload));
$function$;

alter function private.fn_reconciliation_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

create or replace function private.fn_gate_preimage_v7(
  p_payload jsonb,
  p_execution_id text
)
returns text
language sql
immutable
strict
set search_path to ''
as $function$
  select
    private.fn_frame_component_v7('gate-v7')
    ||private.fn_frame_component_v7(p_execution_id)
    ||private.fn_frame_component_v7(private.fn_payload_sha256_v7(p_payload));
$function$;

alter function private.fn_gate_preimage_v7(jsonb,text)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_preimage_v7(jsonb,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_gate_preimage_v7(jsonb,text)
  to lf_governance_owner_v3;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

commit;
$source_20260801180510$]::text[],
  'writer_full_payload_binding_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:a52faeedf7b44e00da512dd6c6b34aacd3976a95',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 17/18 · 20260801180520_writer_scope_nonce_binding_realign_v7.sql
-- Git blob SHA-1: a1ae795920180014b4fa84fa4010b7fc7f5f7f64
-- -----------------------------------------------------------------------------
-- PR #93 / CA-N39..CA-N42 scope and nonce-binding realignment.
-- Versioned only. Exercise in an isolated environment before deployment.
--
-- The active V7 preimage is:
--   frame(scope) || frame(execution_id) || frame(payload_sha256)
-- This migration makes the nonce consumer and post-write validators understand that
-- same contract without adding columns or weakening fail-closed behavior.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_reconciliation_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null then
    raise exception 'V7 writer, nonce validators and framing helper must exist before realignment';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7')
     or not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'V7 writer roles must exist before realignment';
  end if;
end
$preflight$;

grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_writer_verifier_v7;
grant create on schema private to lf_governance_owner_v3;

set local role lf_writer_verifier_v7;

-- Decode all three length-framed components. Returning NULL is the fail-closed result
-- for legacy, malformed, truncated or overlong input.
create or replace function private.fn_writer_preimage_scope_v7(p_preimage text)
returns text
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_bytes bytea:=convert_to(p_preimage,'UTF8');
  v_total integer:=octet_length(p_preimage);
  v_offset integer:=1;
  v_tail text;
  v_separator integer;
  v_length_text text;
  v_length integer;
  v_value_bytes bytea;
  v_value text;
  v_scope text;
  v_execution text;
  v_payload_hash text;
  v_frame integer;
begin
  for v_frame in 1..3 loop
    if v_offset>v_total then
      return null;
    end if;

    v_tail:=convert_from(substring(v_bytes from v_offset),'UTF8');
    v_separator:=strpos(v_tail,'#');
    if v_separator<=1 then
      return null;
    end if;

    v_length_text:=left(v_tail,v_separator-1);
    if v_length_text !~ '^(0|[1-9][0-9]*)$' then
      return null;
    end if;

    begin
      v_length:=v_length_text::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        return null;
    end;

    if v_length<0 or v_length>1048576 then
      return null;
    end if;

    v_value_bytes:=substring(v_bytes from v_offset+v_separator for v_length);
    if octet_length(v_value_bytes)<>v_length then
      return null;
    end if;

    begin
      v_value:=convert_from(v_value_bytes,'UTF8');
    exception
      when character_not_in_repertoire then
        return null;
    end;

    if v_frame=1 then
      v_scope:=v_value;
    elsif v_frame=2 then
      v_execution:=v_value;
    else
      v_payload_hash:=v_value;
    end if;

    v_offset:=v_offset+v_separator+v_length;
  end loop;

  if v_offset<>v_total+1
     or nullif(v_execution,'') is null
     or coalesce(v_payload_hash,'') !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  if v_scope='reconciliation-v7' then
    return 'RECONCILIATION';
  elsif v_scope='gate-v7' then
    return 'GATE';
  end if;

  return null;
exception
  when invalid_parameter_value
    or character_not_in_repertoire
    or numeric_value_out_of_range then
    return null;
end;
$function$;

alter function private.fn_writer_preimage_scope_v7(text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_writer_preimage_scope_v7(text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_writer_preimage_scope_v7(text)
  to lf_governance_owner_v3;

create or replace function private.fn_consume_writer_proof_v7(
  p_preimage text,
  p_signature text,
  p_writer_nonce text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_claims jsonb:='{}'::jsonb;
  v_role text;
  v_exp timestamptz;
  v_scope text;
  v_key_id text;
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(
      nullif(current_setting('request.jwt.claims',true),'')::jsonb,
      '{}'::jsonb
    );
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then
    return false;
  end if;

  if nullif(p_preimage,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  if coalesce(p_writer_nonce,'') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range
      or datetime_field_overflow then
      return false;
  end;

  if v_exp<=clock_timestamp()-interval '5 seconds'
     or v_exp>clock_timestamp()+interval '6 minutes' then
    return false;
  end if;

  v_scope:=private.fn_writer_preimage_scope_v7(p_preimage);
  if v_scope is null then
    return false;
  end if;

  v_key_id:=private.fn_writer_hmac_v7_match_key(
    p_preimage,p_writer_nonce,lower(p_signature)
  );
  if v_key_id is null then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role,key_id
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role,
    v_key_id
  )
  on conflict do nothing;

  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

reset role;
set local role lf_governance_owner_v3;

-- Link a reconciliation row to the exact nonce and exact signed preimage persisted by
-- the public writer. No legacy preimage reconstruction is attempted.
create or replace function private.fn_reconciliation_nonce_v7_valid(p_run_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='RECONCILIATION'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=g.details->>'signed_preimage_sha256'
     and n.nonce_sha256=g.details->>'writer_nonce_sha256'
    where g.id=p_run_id
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(g.details->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(g.details->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (g.reconciled_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_reconciliation_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

-- Gate rows keep signed_preimage_sha256 in persisted_effects; the nonce hash is bound
-- through the immutable evidence event written in the same transaction.
create or replace function private.fn_gate_nonce_v7_valid(p_test_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    join public.lf_eventos e
      on e.id=t.evidence_event_id
     and e.evento_tipo='GATE_TEST_RUN_RECORDED'
     and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
     and e.payload#>>'{persisted_effects,signed_preimage_sha256}'
         =t.persisted_effects->>'signed_preimage_sha256'
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=e.payload->>'writer_nonce_sha256'
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(e.payload->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

reset role;
revoke create on schema private from lf_writer_verifier_v7;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;
revoke lf_writer_verifier_v7 from postgres granted by postgres;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180520',
  array[$source_20260801180520$-- PR #93 / CA-N39..CA-N42 scope and nonce-binding realignment.
-- Versioned only. Exercise in an isolated environment before deployment.
--
-- The active V7 preimage is:
--   frame(scope) || frame(execution_id) || frame(payload_sha256)
-- This migration makes the nonce consumer and post-write validators understand that
-- same contract without adding columns or weakening fail-closed behavior.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_reconciliation_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null then
    raise exception 'V7 writer, nonce validators and framing helper must exist before realignment';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7')
     or not exists (select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'V7 writer roles must exist before realignment';
  end if;
end
$preflight$;

grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant create on schema private to lf_writer_verifier_v7;
grant create on schema private to lf_governance_owner_v3;

set local role lf_writer_verifier_v7;

-- Decode all three length-framed components. Returning NULL is the fail-closed result
-- for legacy, malformed, truncated or overlong input.
create or replace function private.fn_writer_preimage_scope_v7(p_preimage text)
returns text
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_bytes bytea:=convert_to(p_preimage,'UTF8');
  v_total integer:=octet_length(p_preimage);
  v_offset integer:=1;
  v_tail text;
  v_separator integer;
  v_length_text text;
  v_length integer;
  v_value_bytes bytea;
  v_value text;
  v_scope text;
  v_execution text;
  v_payload_hash text;
  v_frame integer;
begin
  for v_frame in 1..3 loop
    if v_offset>v_total then
      return null;
    end if;

    v_tail:=convert_from(substring(v_bytes from v_offset),'UTF8');
    v_separator:=strpos(v_tail,'#');
    if v_separator<=1 then
      return null;
    end if;

    v_length_text:=left(v_tail,v_separator-1);
    if v_length_text !~ '^(0|[1-9][0-9]*)$' then
      return null;
    end if;

    begin
      v_length:=v_length_text::integer;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        return null;
    end;

    if v_length<0 or v_length>1048576 then
      return null;
    end if;

    v_value_bytes:=substring(v_bytes from v_offset+v_separator for v_length);
    if octet_length(v_value_bytes)<>v_length then
      return null;
    end if;

    begin
      v_value:=convert_from(v_value_bytes,'UTF8');
    exception
      when character_not_in_repertoire then
        return null;
    end;

    if v_frame=1 then
      v_scope:=v_value;
    elsif v_frame=2 then
      v_execution:=v_value;
    else
      v_payload_hash:=v_value;
    end if;

    v_offset:=v_offset+v_separator+v_length;
  end loop;

  if v_offset<>v_total+1
     or nullif(v_execution,'') is null
     or coalesce(v_payload_hash,'') !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  if v_scope='reconciliation-v7' then
    return 'RECONCILIATION';
  elsif v_scope='gate-v7' then
    return 'GATE';
  end if;

  return null;
exception
  when invalid_parameter_value
    or character_not_in_repertoire
    or numeric_value_out_of_range then
    return null;
end;
$function$;

alter function private.fn_writer_preimage_scope_v7(text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_writer_preimage_scope_v7(text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_writer_preimage_scope_v7(text)
  to lf_governance_owner_v3;

create or replace function private.fn_consume_writer_proof_v7(
  p_preimage text,
  p_signature text,
  p_writer_nonce text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_claims jsonb:='{}'::jsonb;
  v_role text;
  v_exp timestamptz;
  v_scope text;
  v_key_id text;
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(
      nullif(current_setting('request.jwt.claims',true),'')::jsonb,
      '{}'::jsonb
    );
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then
    return false;
  end if;

  if nullif(p_preimage,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  if coalesce(p_writer_nonce,'') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range
      or datetime_field_overflow then
      return false;
  end;

  if v_exp<=clock_timestamp()-interval '5 seconds'
     or v_exp>clock_timestamp()+interval '6 minutes' then
    return false;
  end if;

  v_scope:=private.fn_writer_preimage_scope_v7(p_preimage);
  if v_scope is null then
    return false;
  end if;

  v_key_id:=private.fn_writer_hmac_v7_match_key(
    p_preimage,p_writer_nonce,lower(p_signature)
  );
  if v_key_id is null then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role,key_id
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role,
    v_key_id
  )
  on conflict do nothing;

  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

reset role;
set local role lf_governance_owner_v3;

-- Link a reconciliation row to the exact nonce and exact signed preimage persisted by
-- the public writer. No legacy preimage reconstruction is attempted.
create or replace function private.fn_reconciliation_nonce_v7_valid(p_run_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='RECONCILIATION'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=g.details->>'signed_preimage_sha256'
     and n.nonce_sha256=g.details->>'writer_nonce_sha256'
    where g.id=p_run_id
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(g.details->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(g.details->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (g.reconciled_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_reconciliation_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

-- Gate rows keep signed_preimage_sha256 in persisted_effects; the nonce hash is bound
-- through the immutable evidence event written in the same transaction.
create or replace function private.fn_gate_nonce_v7_valid(p_test_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    join public.lf_eventos e
      on e.id=t.evidence_event_id
     and e.evento_tipo='GATE_TEST_RUN_RECORDED'
     and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
     and e.payload#>>'{persisted_effects,signed_preimage_sha256}'
         =t.persisted_effects->>'signed_preimage_sha256'
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=e.payload->>'writer_nonce_sha256'
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(e.payload->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

reset role;
revoke create on schema private from lf_writer_verifier_v7;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;
revoke lf_writer_verifier_v7 from postgres granted by postgres;

commit;
$source_20260801180520$]::text[],
  'writer_scope_nonce_binding_realign_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:a1ae795920180014b4fa84fa4010b7fc7f5f7f64',
  null
);

commit;


-- -----------------------------------------------------------------------------
-- 18/18 · 20260801180530_writer_evidence_runtime_hardening_v7.sql
-- Git blob SHA-1: d38230b6bd2e899ccbafb28dc15adb881f1677cb
-- -----------------------------------------------------------------------------
-- PR #93 / LOTE-E / CA-N56..CA-N60 final static hardening.
-- This migration has not been deployed. It replaces the pre-deployment LOTE-C
-- definition so the migration chain remains executable and fail-closed.

begin;

do $preflight$
begin
  if to_regclass('private.lf_gate_test_runs_v3') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null
     or to_regclass('public.lf_eventos') is null
     or to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_canonical_json_v7(jsonb)') is null
     or to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null
     or to_regprocedure('extensions.digest(bytea,text)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_valid(text,text,text)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_install_writer_hmac_key_v7(text,text,text)') is null
     or to_regprocedure('private.fn_writer_hmac_challenge_v7(text,text)') is null
     or to_regprocedure('private.fn_promote_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_retire_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_key_separation_v7_valid()') is null then
    raise exception 'V7 tables, crypto dependencies, helpers, validator and separation invariant must exist before LOTE-E';
  end if;

  if not exists(select 1 from pg_roles where rolname='lf_writer_verifier_v7')
     or not exists(select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'V7 owner roles must exist before LOTE-E';
  end if;

end
$preflight$;


-- CA-N49/CA-N50: obtain both owner contexts before any function grant or table DDL.
grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;

do $table_owner_preflight$
declare
  v_gate_owner oid;
begin
  select c.relowner into v_gate_owner
  from pg_class c
  where c.oid='private.lf_gate_test_runs_v3'::regclass;

  if not pg_has_role(current_user,pg_get_userbyid(v_gate_owner),'USAGE')
     and not coalesce((select r.rolsuper from pg_roles r where r.rolname=current_user),false) then
    raise exception 'migration executor cannot administer private.lf_gate_test_runs_v3';
  end if;
end
$table_owner_preflight$;

-- CA-N52: keep signed persisted_effects byte-for-byte aligned with the event.
-- The writer nonce gets a dedicated private column instead of mutating signed JSON.
alter table private.lf_gate_test_runs_v3
  add column if not exists writer_nonce_sha256 text;

-- CA-N51: no silent invalidation. A partially deployed environment with old V7
-- rows must explicitly backfill them before applying this migration.
do $preexisting_v7$
begin
  if exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    where t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.writer_nonce_sha256,'') !~ '^[0-9a-f]{64}$'
  ) then
    raise exception using
      errcode='55000',
      message='preexisting V7 gate rows require explicit nonce backfill before LOTE-E';
  end if;
end
$preexisting_v7$;

do $nonce_constraint$
begin
  if not exists(
    select 1
    from pg_constraint c
    where c.conrelid='private.lf_gate_test_runs_v3'::regclass
      and c.conname='lf_gate_test_runs_v3_writer_nonce_v7_ck'
  ) then
    alter table private.lf_gate_test_runs_v3
      add constraint lf_gate_test_runs_v3_writer_nonce_v7_ck
      check (
        writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
        or coalesce(writer_nonce_sha256,'') ~ '^[0-9a-f]{64}$'
      );
  end if;
end
$nonce_constraint$;

-- CA-N49: issue each helper grant under its actual owner role.
set local role lf_writer_verifier_v7;
grant execute on function private.fn_writer_preimage_scope_v7(text) to postgres;
reset role;

grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_gate_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_canonical_json_v7(jsonb) to postgres;
grant execute on function private.fn_payload_sha256_v7(jsonb) to postgres;
grant execute on function private.fn_frame_component_v7(text) to postgres;

-- CA-N45/CA-N52: bind the nonce to a dedicated private column and verify that
-- persisted_effects and its digest remain identical to the signed event payload.
create or replace function private.fn_bind_gate_writer_nonce_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_event_nonce text;
  v_event_preimage text;
  v_event_effects jsonb;
  v_event_effects_hash text;
  v_row_effects_hash text;
begin
  if tg_op='UPDATE'
     and old.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
     and new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    raise exception using
      errcode='55000',
      message='V7 gate authentication cannot be downgraded';
  end if;

  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if tg_op='UPDATE' then
    if new.evidence_event_id is distinct from old.evidence_event_id
       or new.persisted_effects is distinct from old.persisted_effects
       or new.persisted_effects_sha256 is distinct from old.persisted_effects_sha256
       or new.writer_nonce_sha256 is distinct from old.writer_nonce_sha256 then
      raise exception using
        errcode='55000',
        message='V7 gate proof binding is immutable';
    end if;
  end if;

  select
    e.payload->>'writer_nonce_sha256',
    e.payload#>>'{persisted_effects,signed_preimage_sha256}',
    e.payload->'persisted_effects',
    e.payload->>'persisted_effects_sha256'
    into v_event_nonce,v_event_preimage,v_event_effects,v_event_effects_hash
  from public.lf_eventos e
  where e.id=new.evidence_event_id
    and e.evento_tipo='GATE_TEST_RUN_RECORDED'
    and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7';

  v_row_effects_hash:=encode(
    extensions.digest(convert_to(new.persisted_effects::text,'UTF8'),'sha256'),
    'hex'
  );

  if coalesce(v_event_nonce,'') !~ '^[0-9a-f]{64}$'
     or coalesce(v_event_preimage,'') !~ '^[0-9a-f]{64}$'
     or v_event_preimage is distinct from new.persisted_effects->>'signed_preimage_sha256'
     or v_event_effects is distinct from new.persisted_effects
     or v_event_effects_hash is distinct from new.persisted_effects_sha256
     or v_row_effects_hash is distinct from new.persisted_effects_sha256
     or (
       new.writer_nonce_sha256 is not null
       and new.writer_nonce_sha256 is distinct from v_event_nonce
     ) then
    raise exception using
      errcode='23514',
      message='V7 gate row does not match its signed evidence event';
  end if;

  new.writer_nonce_sha256:=v_event_nonce;
  return new;
end;
$function$;

alter function private.fn_bind_gate_writer_nonce_v7()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_bind_gate_writer_nonce_v7()
  from public,anon,authenticated,service_role;
-- CREATE TRIGGER requires EXECUTE for its creator; this grant is temporary.
grant execute on function private.fn_bind_gate_writer_nonce_v7() to postgres;

-- The private row is authoritative; the event independently cross-checks nonce,
-- preimage, persisted_effects and persisted_effects_sha256.
create or replace function private.fn_gate_nonce_v7_valid(p_test_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    join public.lf_eventos e
      on e.id=t.evidence_event_id
     and e.evento_tipo='GATE_TEST_RUN_RECORDED'
     and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
     and e.payload#>>'{persisted_effects,signed_preimage_sha256}'
         =t.persisted_effects->>'signed_preimage_sha256'
     and e.payload->>'writer_nonce_sha256'=t.writer_nonce_sha256
     and e.payload->'persisted_effects'=t.persisted_effects
     and e.payload->>'persisted_effects_sha256'=t.persisted_effects_sha256
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=t.writer_nonce_sha256
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(t.writer_nonce_sha256,'') ~ '^[0-9a-f]{64}$'
      and t.persisted_effects_sha256=encode(
        extensions.digest(convert_to(t.persisted_effects::text,'UTF8'),'sha256'),
        'hex'
      )
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

reset role;

-- CA-N50: table DDL runs in the migration executor context, matching 180315.
drop trigger if exists trg_05_bind_gate_writer_nonce_v7
  on private.lf_gate_test_runs_v3;
create trigger trg_05_bind_gate_writer_nonce_v7
before insert or update on private.lf_gate_test_runs_v3
for each row execute function private.fn_bind_gate_writer_nonce_v7();
alter table private.lf_gate_test_runs_v3
  enable always trigger trg_05_bind_gate_writer_nonce_v7;

-- The trigger is installed; remove the temporary creator privilege.
set local role lf_governance_owner_v3;
revoke execute on function private.fn_bind_gate_writer_nonce_v7() from postgres;
reset role;

revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;
revoke lf_writer_verifier_v7 from postgres granted by postgres;

do $post_create_dependencies$
begin
  if to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is null then
    raise exception 'V7 gate binder must exist before the separation invariant';
  end if;
end
$post_create_dependencies$;

-- CA-N48: preserve every prior separation check and include the parser/binder.
create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    exists (
      select 1
      from pg_policies p
      where p.schemaname='private'
        and p.tablename='lf_writer_hmac_keys_v7'
        and p.policyname='pol_lf_writer_hmac_keys_v7_postgres'
        and p.cmd='ALL'
        and 'postgres'=any(p.roles)
    )
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

-- Ledger record is part of the same transaction as the source migration.
insert into supabase_migrations.schema_migrations(
  version,statements,name,created_by,idempotency_key,rollback
) values (
  '20260801180530',
  array[$source_20260801180530$-- PR #93 / LOTE-E / CA-N56..CA-N60 final static hardening.
-- This migration has not been deployed. It replaces the pre-deployment LOTE-C
-- definition so the migration chain remains executable and fail-closed.

begin;

do $preflight$
begin
  if to_regclass('private.lf_gate_test_runs_v3') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null
     or to_regclass('public.lf_eventos') is null
     or to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_canonical_json_v7(jsonb)') is null
     or to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null
     or to_regprocedure('extensions.digest(bytea,text)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_valid(text,text,text)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_install_writer_hmac_key_v7(text,text,text)') is null
     or to_regprocedure('private.fn_writer_hmac_challenge_v7(text,text)') is null
     or to_regprocedure('private.fn_promote_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_retire_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_key_separation_v7_valid()') is null then
    raise exception 'V7 tables, crypto dependencies, helpers, validator and separation invariant must exist before LOTE-E';
  end if;

  if not exists(select 1 from pg_roles where rolname='lf_writer_verifier_v7')
     or not exists(select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'V7 owner roles must exist before LOTE-E';
  end if;

end
$preflight$;


-- CA-N49/CA-N50: obtain both owner contexts before any function grant or table DDL.
grant lf_writer_verifier_v7 to postgres
  with admin false, inherit true, set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false, inherit true, set true
  granted by postgres;

do $table_owner_preflight$
declare
  v_gate_owner oid;
begin
  select c.relowner into v_gate_owner
  from pg_class c
  where c.oid='private.lf_gate_test_runs_v3'::regclass;

  if not pg_has_role(current_user,pg_get_userbyid(v_gate_owner),'USAGE')
     and not coalesce((select r.rolsuper from pg_roles r where r.rolname=current_user),false) then
    raise exception 'migration executor cannot administer private.lf_gate_test_runs_v3';
  end if;
end
$table_owner_preflight$;

-- CA-N52: keep signed persisted_effects byte-for-byte aligned with the event.
-- The writer nonce gets a dedicated private column instead of mutating signed JSON.
alter table private.lf_gate_test_runs_v3
  add column if not exists writer_nonce_sha256 text;

-- CA-N51: no silent invalidation. A partially deployed environment with old V7
-- rows must explicitly backfill them before applying this migration.
do $preexisting_v7$
begin
  if exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    where t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.writer_nonce_sha256,'') !~ '^[0-9a-f]{64}$'
  ) then
    raise exception using
      errcode='55000',
      message='preexisting V7 gate rows require explicit nonce backfill before LOTE-E';
  end if;
end
$preexisting_v7$;

do $nonce_constraint$
begin
  if not exists(
    select 1
    from pg_constraint c
    where c.conrelid='private.lf_gate_test_runs_v3'::regclass
      and c.conname='lf_gate_test_runs_v3_writer_nonce_v7_ck'
  ) then
    alter table private.lf_gate_test_runs_v3
      add constraint lf_gate_test_runs_v3_writer_nonce_v7_ck
      check (
        writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
        or coalesce(writer_nonce_sha256,'') ~ '^[0-9a-f]{64}$'
      );
  end if;
end
$nonce_constraint$;

-- CA-N49: issue each helper grant under its actual owner role.
set local role lf_writer_verifier_v7;
grant execute on function private.fn_writer_preimage_scope_v7(text) to postgres;
reset role;

grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_gate_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_canonical_json_v7(jsonb) to postgres;
grant execute on function private.fn_payload_sha256_v7(jsonb) to postgres;
grant execute on function private.fn_frame_component_v7(text) to postgres;

-- CA-N45/CA-N52: bind the nonce to a dedicated private column and verify that
-- persisted_effects and its digest remain identical to the signed event payload.
create or replace function private.fn_bind_gate_writer_nonce_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_event_nonce text;
  v_event_preimage text;
  v_event_effects jsonb;
  v_event_effects_hash text;
  v_row_effects_hash text;
begin
  if tg_op='UPDATE'
     and old.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
     and new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    raise exception using
      errcode='55000',
      message='V7 gate authentication cannot be downgraded';
  end if;

  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if tg_op='UPDATE' then
    if new.evidence_event_id is distinct from old.evidence_event_id
       or new.persisted_effects is distinct from old.persisted_effects
       or new.persisted_effects_sha256 is distinct from old.persisted_effects_sha256
       or new.writer_nonce_sha256 is distinct from old.writer_nonce_sha256 then
      raise exception using
        errcode='55000',
        message='V7 gate proof binding is immutable';
    end if;
  end if;

  select
    e.payload->>'writer_nonce_sha256',
    e.payload#>>'{persisted_effects,signed_preimage_sha256}',
    e.payload->'persisted_effects',
    e.payload->>'persisted_effects_sha256'
    into v_event_nonce,v_event_preimage,v_event_effects,v_event_effects_hash
  from public.lf_eventos e
  where e.id=new.evidence_event_id
    and e.evento_tipo='GATE_TEST_RUN_RECORDED'
    and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7';

  v_row_effects_hash:=encode(
    extensions.digest(convert_to(new.persisted_effects::text,'UTF8'),'sha256'),
    'hex'
  );

  if coalesce(v_event_nonce,'') !~ '^[0-9a-f]{64}$'
     or coalesce(v_event_preimage,'') !~ '^[0-9a-f]{64}$'
     or v_event_preimage is distinct from new.persisted_effects->>'signed_preimage_sha256'
     or v_event_effects is distinct from new.persisted_effects
     or v_event_effects_hash is distinct from new.persisted_effects_sha256
     or v_row_effects_hash is distinct from new.persisted_effects_sha256
     or (
       new.writer_nonce_sha256 is not null
       and new.writer_nonce_sha256 is distinct from v_event_nonce
     ) then
    raise exception using
      errcode='23514',
      message='V7 gate row does not match its signed evidence event';
  end if;

  new.writer_nonce_sha256:=v_event_nonce;
  return new;
end;
$function$;

alter function private.fn_bind_gate_writer_nonce_v7()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_bind_gate_writer_nonce_v7()
  from public,anon,authenticated,service_role;
-- CREATE TRIGGER requires EXECUTE for its creator; this grant is temporary.
grant execute on function private.fn_bind_gate_writer_nonce_v7() to postgres;

-- The private row is authoritative; the event independently cross-checks nonce,
-- preimage, persisted_effects and persisted_effects_sha256.
create or replace function private.fn_gate_nonce_v7_valid(p_test_id bigint)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    join public.lf_eventos e
      on e.id=t.evidence_event_id
     and e.evento_tipo='GATE_TEST_RUN_RECORDED'
     and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
     and e.payload#>>'{persisted_effects,signed_preimage_sha256}'
         =t.persisted_effects->>'signed_preimage_sha256'
     and e.payload->>'writer_nonce_sha256'=t.writer_nonce_sha256
     and e.payload->'persisted_effects'=t.persisted_effects
     and e.payload->>'persisted_effects_sha256'=t.persisted_effects_sha256
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=t.writer_nonce_sha256
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(t.writer_nonce_sha256,'') ~ '^[0-9a-f]{64}$'
      and t.persisted_effects_sha256=encode(
        extensions.digest(convert_to(t.persisted_effects::text,'UTF8'),'sha256'),
        'hex'
      )
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

reset role;

-- CA-N50: table DDL runs in the migration executor context, matching 180315.
drop trigger if exists trg_05_bind_gate_writer_nonce_v7
  on private.lf_gate_test_runs_v3;
create trigger trg_05_bind_gate_writer_nonce_v7
before insert or update on private.lf_gate_test_runs_v3
for each row execute function private.fn_bind_gate_writer_nonce_v7();
alter table private.lf_gate_test_runs_v3
  enable always trigger trg_05_bind_gate_writer_nonce_v7;

-- The trigger is installed; remove the temporary creator privilege.
set local role lf_governance_owner_v3;
revoke execute on function private.fn_bind_gate_writer_nonce_v7() from postgres;
reset role;

revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;
revoke lf_writer_verifier_v7 from postgres granted by postgres;

do $post_create_dependencies$
begin
  if to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is null then
    raise exception 'V7 gate binder must exist before the separation invariant';
  end if;
end
$post_create_dependencies$;

-- CA-N48: preserve every prior separation check and include the parser/binder.
create or replace function private.fn_writer_key_separation_v7_valid()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    exists (
      select 1
      from pg_policies p
      where p.schemaname='private'
        and p.tablename='lf_writer_hmac_keys_v7'
        and p.policyname='pol_lf_writer_hmac_keys_v7_postgres'
        and p.cmd='ALL'
        and 'postgres'=any(p.roles)
    )
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('anon','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('authenticated','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','SELECT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','INSERT')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','UPDATE')
    and not has_table_privilege('service_role','private.lf_writer_hmac_keys_v7','DELETE')
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_valid(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_v7_match_key(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_consume_writer_proof_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_install_writer_hmac_key_v7(text,text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_writer_hmac_challenge_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_promote_writer_hmac_key_v7(text,text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_retire_writer_hmac_key_v7(text,text)','EXECUTE'
    );
$function$;

alter function private.fn_writer_key_separation_v7_valid() owner to postgres;
revoke all on function private.fn_writer_key_separation_v7_valid()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_separation_v7_valid()
  to postgres,service_role,lf_governance_owner_v3;

commit;
$source_20260801180530$]::text[],
  'writer_evidence_runtime_hardening_v7',
  'pr93_v7_static_resume_from_4',
  'gitblob:d38230b6bd2e899ccbafb28dc15adb881f1677cb',
  null
);

commit;


-- =============================================================================
-- FINAL SOURCE-APPLICATION READBACK. This is not RUNTIME_PASS/readiness.
-- =============================================================================
with target(version) as (
  values
    ('20260801175950'),
    ('20260801175955'),
    ('20260801180000'),
    ('20260801180005'),
    ('20260801180010'),
    ('20260801180100'),
    ('20260801180150'),
    ('20260801180200'),
    ('20260801180300'),
    ('20260801180305'),
    ('20260801180310'),
    ('20260801180315'),
    ('20260801180320'),
    ('20260801180400'),
    ('20260801180500'),
    ('20260801180510'),
    ('20260801180520'),
    ('20260801180530')
), ledger as (
  select count(*) as applied_count
  from target t join supabase_migrations.schema_migrations sm using(version)
), temp_memberships as (
  select count(*) as cnt
  from pg_auth_members pam
  join pg_roles granted on granted.oid=pam.roleid
  join pg_roles member on member.oid=pam.member
  join pg_roles grantor on grantor.oid=pam.grantor
  where member.rolname='postgres'
    and granted.rolname in ('lf_governance_owner_v3','lf_writer_verifier_v7')
    and grantor.rolname='postgres'
)
select jsonb_build_object(
  'status',case
    when l.applied_count=18
     and tm.cnt=0
     and to_regclass('private.lf_reconciliation_writer_nonces_v7') is not null
     and to_regclass('private.lf_github_reconciliation_quarantine_v7') is not null
     and to_regclass('private.lf_writer_hmac_keys_v7') is not null
     and to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is not null
     and to_regprocedure('private.fn_writer_hmac_v7_valid(text,text,text)') is not null
     and not has_schema_privilege('lf_governance_owner_v3','private','CREATE')
     and not has_schema_privilege('lf_governance_owner_v3','public','CREATE')
     and not has_schema_privilege('lf_writer_verifier_v7','private','CREATE')
    then 'SOURCE_PACKAGE_APPLIED_AWAITING_RUNTIME_TESTS'
    else 'INCOMPLETE_READBACK'
  end,
  'applied_migrations',l.applied_count,
  'expected_migrations',18,
  'postgres_granted_temp_memberships',tm.cnt,
  'objects',jsonb_build_object(
    'nonce_table',to_regclass('private.lf_reconciliation_writer_nonces_v7') is not null,
    'quarantine_table',to_regclass('private.lf_github_reconciliation_quarantine_v7') is not null,
    'key_table',to_regclass('private.lf_writer_hmac_keys_v7') is not null,
    'consume_writer',to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is not null,
    'hmac_verifier',to_regprocedure('private.fn_writer_hmac_v7_valid(text,text,text)') is not null
  ),
  'temporary_create',jsonb_build_object(
    'governance_private',has_schema_privilege('lf_governance_owner_v3','private','CREATE'),
    'governance_public',has_schema_privilege('lf_governance_owner_v3','public','CREATE'),
    'writer_private',has_schema_privilege('lf_writer_verifier_v7','private','CREATE')
  ),
  'runtime_pass_declared',false,
  'production_readiness_declared',false,
  'merge_authorized',false
) as pr93_v7_resume_readback
from ledger l cross join temp_memberships tm;
