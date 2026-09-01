-- AUD24-F05 remediation follow-up.
-- PostgREST exposes `public`, not private `lf_ops` / `programacion` schemas.
-- Keep private tables/functions private and expose only narrow SECURITY DEFINER
-- service-role RPCs required by the protected Edge issuer.

create or replace function public.programming_agent_f05_context_v1()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','lf_ops'
as $function$
declare
  v_status text;
  v_owner text;
  v_asset jsonb;
  v_verifier_run_id bigint;
  v_verifier jsonb;
begin
  select q.status, q.current_owner, q.asset_ref
    into v_status, v_owner, v_asset
    from lf_ops.system_audit_queue q
   where q.work_id = 7;

  if v_asset is null then
    return null;
  end if;

  if coalesce(v_asset->>'latest_verifier_run_id','') ~ '^[0-9]+$' then
    v_verifier_run_id := (v_asset->>'latest_verifier_run_id')::bigint;
    select jsonb_build_object(
      'run_id', r.run_id,
      'run_status', r.run_status,
      'scope_summary', r.scope_summary,
      'verification', r.verification,
      'handoff', r.handoff
    )
      into v_verifier
      from lf_ops.system_audit_runs r
     where r.run_id = v_verifier_run_id;
  end if;

  return jsonb_build_object(
    'work_id', 7,
    'status', v_status,
    'current_owner', v_owner,
    'asset_ref', v_asset,
    'verifier_run', v_verifier
  );
end;
$function$;

revoke all on function public.programming_agent_f05_context_v1() from public, anon, authenticated;
grant execute on function public.programming_agent_f05_context_v1() to service_role;

create or replace function public.programming_agent_f05_signing_seed_v1()
returns text
language sql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select programacion.f05_signing_seed_v1();
$function$;

revoke all on function public.programming_agent_f05_signing_seed_v1() from public, anon, authenticated;
grant execute on function public.programming_agent_f05_signing_seed_v1() to service_role;

create or replace function public.programming_agent_f05_existing_receipt_v1(
  p_head_sha text,
  p_subject_ref text
)
returns bigint
language sql
security definer
stable
set search_path to 'pg_catalog','programacion'
as $function$
  select pr.id
    from programacion.provenance_receipts pr
   where pr.receipt_kind = 'AUD24_F05_BASELINE_AUTHORIZATION'
     and pr.head_sha = p_head_sha
     and pr.subject_ref = p_subject_ref
   order by pr.id desc
   limit 1;
$function$;

revoke all on function public.programming_agent_f05_existing_receipt_v1(text,text) from public, anon, authenticated;
grant execute on function public.programming_agent_f05_existing_receipt_v1(text,text) to service_role;

create or replace function public.programming_agent_issue_f05_provenance_receipt_v1(
  p_head_sha text,
  p_subject_ref text,
  p_subject_sha256 text,
  p_issuer_identity text,
  p_verification_ref text,
  p_payload jsonb
)
returns table(id bigint, receipt_sha256 text)
language sql
security definer
set search_path to 'pg_catalog','programacion'
as $function$
  select r.id, r.receipt_sha256
    from programacion.issue_f05_provenance_receipt_v1(
      p_head_sha,
      p_subject_ref,
      p_subject_sha256,
      p_issuer_identity,
      p_verification_ref,
      p_payload
    ) r;
$function$;

revoke all on function public.programming_agent_issue_f05_provenance_receipt_v1(
  text,text,text,text,text,jsonb
) from public, anon, authenticated;
grant execute on function public.programming_agent_issue_f05_provenance_receipt_v1(
  text,text,text,text,text,jsonb
) to service_role;
