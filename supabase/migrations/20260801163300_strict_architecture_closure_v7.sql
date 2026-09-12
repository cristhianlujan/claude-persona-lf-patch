-- Architecture V7 strict closure.
-- Reports native GitHub branch protection gaps instead of treating compensating
-- controls as equivalent to a protected main branch.

begin;

revoke execute on function private.fn_run_architecture_monitor_v4(text)
  from public, anon, authenticated, service_role;
revoke execute on function private.fn_evaluate_architecture_alerts_v4(text)
  from public, anon, authenticated, service_role;

create or replace view public.v_lf_architecture_closure_v7 as
with base as (
  select * from public.v_lf_architecture_closure_v6
), latest_g as (
  select distinct on (g.artifact_id)
    g.artifact_id,
    g.branch_protection_status,
    g.details
  from private.lf_github_reconciliation_runs_v3 g
  where g.authoritative
  order by g.artifact_id,g.observed_at desc,g.id desc
), native_protection as (
  select count(*) filter (
    where g.artifact_id is null
       or g.branch_protection_status<>'VERIFIED'
       or coalesce(g.details->>'actual_branch_protection_status','')<>'VERIFIED'
  )::bigint as branch_protection_gaps
  from private.lf_artifact_inventory_baseline_v3 i
  left join latest_g g on g.artifact_id=i.artifact_id
  where i.required_for_closure
), strict_state as (
  select
    b.*,
    n.branch_protection_gaps as strict_branch_protection_gaps,
    (
      b.internal_control_ready
      and b.pass_v3_count=b.artifact_count
      and b.judges_pass_v3=b.judge_count
      and b.blocking_capabilities=0
      and b.token_control_ready
    ) as strict_internal_control_ready
  from base b cross join native_protection n
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
  strict_branch_protection_gaps as branch_protection_gaps,
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
  strict_internal_control_ready as internal_control_ready,
  case when strict_branch_protection_gaps>0 then 1 else 0 end::integer as external_blocker_count,
  coalesce(residual_observations,'{}'::jsonb)
    || jsonb_build_object(
      'branch_protection',jsonb_build_object(
        'state',case when strict_branch_protection_gaps=0 then 'VERIFIED' else 'NOT_CONFIGURED' end,
        'affected_artifacts',strict_branch_protection_gaps,
        'required_action','Configure a native GitHub ruleset on main with required PR, independent approval, strict lf-contract-check, no bypass, no force-push and no deletion'
      )
    ) as residual_observations,
  (
    strict_internal_control_ready
    and strict_branch_protection_gaps=0
    and schema_drift_gaps=0
    and unresolved_notifications=0
  ) as closure_ready,
  case
    when strict_internal_control_ready
      and strict_branch_protection_gaps=0
      and schema_drift_gaps=0
      and unresolved_notifications=0
    then 'PASS_V7'
    when internal_control_ready
      and strict_branch_protection_gaps>0
      and schema_drift_gaps=0
      and inventory_integrity_gaps=0
      and failed_gate_tests=0
      and provenance_gaps=0
      and quarantine_control_complete
      and active_exemptions=0
      and typed_schema_registry_gaps=0
      and unresolved_notifications=0
    then 'READY_INTERNAL_BLOCKED_EXTERNAL'
    else 'NOT_READY'
  end as computed_closure_status
from strict_state;

create or replace view public.v_lf_architecture_closure_current as
select
  computed_at,artifact_count,pass_v3_count,inventory_integrity_gaps,judge_count,judges_pass_v3,
  reconciliation_count,ci_artifacts_exercised,branch_protection_gaps,github_pass_count,
  latest_gate_tests,passed_gate_tests,failed_gate_tests,provenance_gaps,nonconforming_events,
  quarantined_events,quarantined_acceptance_references,quarantine_control_complete,
  baseline_objects,schema_drift_gaps,external_notifications,delivered_notifications,
  unresolved_notifications,unmigrated_legacy_notifications,latest_monitor_status,latest_monitor_at,
  active_exemptions,typed_schema_registry_gaps,open_findings,unresolved_internal_findings,
  blocking_capabilities,internal_control_ready,external_blocker_count,residual_observations,
  closure_ready,computed_closure_status
from public.v_lf_architecture_closure_v7;

revoke all on public.v_lf_architecture_closure_v7 from public, anon, authenticated;
revoke all on public.v_lf_architecture_closure_current from public, anon, authenticated;
grant select on public.v_lf_architecture_closure_v7 to service_role;
grant select on public.v_lf_architecture_closure_current to service_role;

commit;
