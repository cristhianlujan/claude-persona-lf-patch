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

commit;
