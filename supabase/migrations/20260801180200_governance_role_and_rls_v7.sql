-- CA-N05 / CA-N06 / CA-N28 remediation.
-- The Supabase-managed postgres role remains the trusted database root. This migration
-- removes the grant made by postgres itself, turns every V4 governance table into an
-- RLS-protected internal relation, and makes any remaining supabase_admin membership
-- an explicit closure blocker.

begin;

-- Revoke the membership that was granted by postgres. A second membership granted by
-- supabase_admin can only be removed by that grantor/control plane and is checked below.
revoke lf_governance_owner_v3 from postgres granted by postgres;

alter role lf_governance_owner_v3 nologin noinherit nobypassrls;

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
      and granted_role.rolname='lf_governance_owner_v3'
  )
  and not exists (
    select 1
    from pg_roles r
    where r.rolname='lf_governance_owner_v3'
      and (r.rolcanlogin or r.rolinherit or r.rolbypassrls)
  );
$function$;

alter function private.fn_governance_role_separation_v7_valid()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_governance_role_separation_v7_valid()
  from public,anon,authenticated,service_role;

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
      'required_action','Remove every postgres membership/admin option on lf_governance_owner_v3 using the original supabase_admin grantor.'
    )
  ) as residual_observations,
  (closure_ready and role_separation_ready) as closure_ready,
  case
    when not role_separation_ready then 'NOT_READY'
    else computed_closure_status
  end as computed_closure_status
from source
cross join separation;

commit;
