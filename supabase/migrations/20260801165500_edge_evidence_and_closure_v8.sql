-- Versioned Edge deployment evidence and strict V8 closure.

create table if not exists private.lf_edge_function_deployment_evidence_v6 (
  function_slug text not null,
  deployed_version integer not null check (deployed_version>0),
  deployment_sha256 text not null check (deployment_sha256 ~ '^[0-9a-f]{64}$'),
  verify_jwt boolean not null,
  authentication_mode text not null,
  verification_source text not null,
  verified_by_execution_id text not null,
  verified_at timestamptz not null default clock_timestamp(),
  primary key(function_slug,deployed_version)
);
revoke all on private.lf_edge_function_deployment_evidence_v6
  from public,anon,authenticated,service_role;

create or replace function private.fn_guard_edge_function_deployment_evidence_v6()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $function$
begin
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode='55000',message='edge deployment evidence v6 is append-only';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_00_guard_edge_function_deployment_evidence_v6
  on private.lf_edge_function_deployment_evidence_v6;
create trigger trg_00_guard_edge_function_deployment_evidence_v6
before update or delete on private.lf_edge_function_deployment_evidence_v6
for each row execute function private.fn_guard_edge_function_deployment_evidence_v6();
alter table private.lf_edge_function_deployment_evidence_v6
  enable always trigger trg_00_guard_edge_function_deployment_evidence_v6;

insert into private.lf_edge_function_deployment_evidence_v6(
  function_slug,deployed_version,deployment_sha256,verify_jwt,
  authentication_mode,verification_source,verified_by_execution_id
) values
(
  'lf-github-reconcile-v3',
  6,
  '819ef9ce5255b7fc1349725255c6332419cbcae8d3985484c0d7fc340b5b5ce8',
  false,
  'GITHUB_OIDC_PLUS_SERVICE_ROLE_NONCE_V6',
  'SUPABASE_CONTROL_PLANE_READBACK',
  'EXEC-ARCH-V6-EDGE-NONCE-HARDENING'
),
(
  'lf-architecture-alert-sink-v4',
  1,
  '2677c616340f9b7fa53dd2119bfcacfdba7b8853cdfd04e9033af77a7b63a617',
  false,
  'HMAC_V4_DELIVERY',
  'SUPABASE_CONTROL_PLANE_READBACK',
  'EXEC-ARCH-V6-EDGE-NONCE-HARDENING'
)
on conflict do nothing;

create or replace view public.v_lf_architecture_closure_v8
with (security_invoker=true)
as
with base as (
  select * from public.v_lf_architecture_closure_v7
), latest_g as (
  select distinct on (g.artifact_id) g.*
  from private.lf_github_reconciliation_runs_v3 g
  where g.authoritative
  order by g.artifact_id,g.observed_at desc,g.id desc
), reconciliation_metrics as (
  select
    count(*) as reconciliation_count,
    count(*) filter (
      where g.result='PASS'
        and g.branch_protection_status='VERIFIED'
        and coalesce(g.details->>'actual_branch_protection_status','')='VERIFIED'
        and private.fn_reconciliation_nonce_v6_valid(g.id)
    ) as github_pass_count
  from private.lf_artifact_inventory_baseline_v3 i
  left join latest_g g on g.artifact_id=i.artifact_id
  where i.required_for_closure
), latest_gate as (
  select distinct on (t.artifact_id) t.*
  from private.lf_gate_test_runs_v3 t
  where t.test_code='POST_MERGE-LF-CONTRACT-CHECK-V3'
  order by t.artifact_id,t.executed_at desc,t.id desc
), gate_metrics as (
  select
    count(*) as latest_gate_tests,
    count(*) filter (
      where t.passed and private.fn_gate_nonce_v6_valid(t.id)
    ) as passed_gate_tests,
    count(*) filter (
      where t.id is null or not t.passed or not private.fn_gate_nonce_v6_valid(t.id)
    ) as failed_gate_tests
  from private.lf_artifact_inventory_baseline_v3 i
  left join latest_gate t on t.artifact_id=i.artifact_id
  where i.required_for_closure
), edge_state as (
  select exists(
    select 1
    from private.lf_edge_function_deployment_evidence_v6 e
    where e.function_slug='lf-github-reconcile-v3'
      and e.deployed_version>=6
      and e.deployment_sha256='819ef9ce5255b7fc1349725255c6332419cbcae8d3985484c0d7fc340b5b5ce8'
      and e.authentication_mode='GITHUB_OIDC_PLUS_SERVICE_ROLE_NONCE_V6'
  ) as edge_reconciler_v6_ready
), strict as (
  select
    b.*,
    r.reconciliation_count as strict_reconciliation_count,
    r.github_pass_count as strict_github_pass_count,
    g.latest_gate_tests as strict_latest_gate_tests,
    g.passed_gate_tests as strict_passed_gate_tests,
    g.failed_gate_tests as strict_failed_gate_tests,
    e.edge_reconciler_v6_ready,
    (
      b.internal_control_ready
      and r.github_pass_count=b.artifact_count
      and g.passed_gate_tests=b.artifact_count
      and g.failed_gate_tests=0
      and e.edge_reconciler_v6_ready
    ) as nonce_internal_control_ready
  from base b
  cross join reconciliation_metrics r
  cross join gate_metrics g
  cross join edge_state e
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
  nonce_internal_control_ready as internal_control_ready,
  external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)||jsonb_build_object(
    'writer_v6',jsonb_build_object(
      'state',case
        when edge_reconciler_v6_ready then 'DEPLOYED_WAITING_FOR_NATIVE_RECONCILIATION'
        else 'NOT_READY'
      end,
      'authentication_mode','SERVICE_ROLE_NONCE_V6',
      'nonce_reconciliation_count',strict_github_pass_count,
      'nonce_gate_test_count',strict_passed_gate_tests,
      'edge_reconciler_v6_ready',edge_reconciler_v6_ready
    )
  ) as residual_observations,
  (
    nonce_internal_control_ready
    and branch_protection_gaps=0
    and schema_drift_gaps=0
    and unresolved_notifications=0
  ) as closure_ready,
  case
    when nonce_internal_control_ready
      and branch_protection_gaps=0
      and schema_drift_gaps=0
      and unresolved_notifications=0
      then 'PASS_V8'
    when nonce_internal_control_ready
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
