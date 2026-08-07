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

commit;
