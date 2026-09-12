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

commit;
