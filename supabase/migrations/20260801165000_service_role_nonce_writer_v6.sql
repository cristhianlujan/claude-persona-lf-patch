-- Architecture V6 writer hardening.
-- Replaces the embedded writer credential with PostgREST-validated service_role
-- context plus a single-use, short-lived nonce proof.

create table if not exists private.lf_reconciliation_writer_nonces_v6 (
  nonce_sha256 text primary key,
  proof_scope text not null,
  preimage_sha256 text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  request_role text not null
);
revoke all on private.lf_reconciliation_writer_nonces_v6 from public, anon, authenticated, service_role;

create or replace function private.fn_verify_reconciliation_writer_token_v5(
  p_preimage text,
  p_signature text,
  p_writer_token text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'pg_catalog','private','extensions'
as $function$
declare
  v_claims jsonb := '{}'::jsonb;
  v_role text;
  v_exp timestamptz;
  v_expected text;
  v_scope text;
  v_rows integer := 0;
begin
  begin
    v_claims := coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
  exception when others then
    v_claims := '{}'::jsonb;
  end;
  v_role := coalesce(v_claims->>'role','');
  if v_role <> 'service_role' then return false; end if;
  if p_preimage is null or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then return false; end if;
  if coalesce(p_writer_token,'') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then return false; end if;

  v_exp := to_timestamp(split_part(p_writer_token,'.',2)::bigint);
  if v_exp <= clock_timestamp()-interval '5 seconds'
     or v_exp > clock_timestamp()+interval '10 minutes' then
    return false;
  end if;

  if p_preimage like 'reconciliation-v5:%' then
    v_scope := 'RECONCILIATION';
  elsif p_preimage like 'gate-v5:%' then
    v_scope := 'GATE';
  else
    return false;
  end if;

  v_expected := encode(
    extensions.digest(convert_to(p_preimage||':'||p_writer_token,'UTF8'),'sha256'),
    'hex'
  );
  if lower(p_signature) <> v_expected then return false; end if;

  insert into private.lf_reconciliation_writer_nonces_v6(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role
  ) values (
    encode(extensions.digest(convert_to(p_writer_token,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role
  ) on conflict do nothing;
  get diagnostics v_rows = row_count;
  return v_rows=1;
exception when others then
  return false;
end;
$function$;
revoke all on function private.fn_verify_reconciliation_writer_token_v5(text,text,text)
  from public,anon,authenticated,service_role;

create or replace function private.fn_reconciliation_nonce_v6_valid(p_run_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','private','extensions'
as $function$
  select exists(
    select 1
    from private.lf_github_reconciliation_runs_v3 g
    join private.lf_reconciliation_writer_nonces_v6 n
      on n.proof_scope='RECONCILIATION'
     and n.preimage_sha256=encode(extensions.digest(convert_to(
       array_to_string(array[
         'reconciliation-v5',
         coalesce(g.reconciled_by_execution_id,''),
         g.artifact_id::text,
         g.workflow_run_id::text,
         coalesce(g.merge_commit_sha,''),
         coalesce(g.artifact_sha256,''),
         coalesce(g.branch_protection_status,''),
         coalesce(g.result,''),
         coalesce(g.audit_manifest_sha256,'')
       ],':'),'UTF8'),'sha256'),'hex')
    where g.id=p_run_id
      and n.request_role='service_role'
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (g.reconciled_at-n.consumed_at)))<=60
  );
$function$;
revoke all on function private.fn_reconciliation_nonce_v6_valid(bigint)
  from public,anon,authenticated,service_role;

create or replace function private.fn_gate_nonce_v6_valid(p_test_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','private','extensions'
as $function$
  select exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    join private.lf_reconciliation_writer_nonces_v6 n
      on n.proof_scope='GATE'
     and n.preimage_sha256=encode(extensions.digest(convert_to(
       array_to_string(array[
         'gate-v5',
         coalesce(t.executed_by_execution_id,''),
         t.artifact_id::text,
         coalesce(t.test_code,''),
         t.source_workflow_run_id::text,
         coalesce(t.source_commit_sha,''),
         t.passed::text,
         coalesce(t.target_relation,''),
         coalesce(t.gate_code,''),
         coalesce(t.probe_preimage->>'expected_sha256',''),
         coalesce(t.observed_outcome->>'artifact_sha256',''),
         coalesce(t.observed_outcome->>'audit_covered',''),
         coalesce(t.persisted_effects->>'github_reconciliation_run_id','')
       ],':'),'UTF8'),'sha256'),'hex')
    where t.id=p_test_id
      and n.request_role='service_role'
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;
revoke all on function private.fn_gate_nonce_v6_valid(bigint)
  from public,anon,authenticated,service_role;

create or replace function public.record_external_ci_verification_v6(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $function$
declare
  v_id bigint;
  v_event_id bigint;
  v_nonce_sha text;
  v_exp timestamptz;
  v_payload jsonb;
begin
  v_exp := to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_nonce_sha := encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex');
  v_payload := coalesce(p_payload,'{}'::jsonb)||jsonb_build_object(
    'writer_authentication','SERVICE_ROLE_NONCE_V6',
    'writer_nonce_sha256',v_nonce_sha,
    'writer_proof_expires_at',v_exp,
    'producer','github-actions-oidc-reconciler-service-role-nonce-v6'
  );
  v_id := public.record_external_ci_verification_v5(
    v_payload,p_execution_id,p_writer_signature,p_writer_nonce
  );
  update private.lf_github_reconciliation_runs_v3
     set details=coalesce(details,'{}'::jsonb)||jsonb_build_object(
       'writer_authentication_v6','SERVICE_ROLE_NONCE_V6',
       'writer_nonce_sha256',v_nonce_sha,
       'writer_proof_expires_at',v_exp
     )
   where id=v_id;
  select nullif(to_jsonb(r)->>'evidence_event_id','')::bigint into v_event_id
  from private.lf_github_reconciliation_runs_v3 r where r.id=v_id;
  if v_event_id is not null then
    update public.lf_eventos
       set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
         'writer_authentication','SERVICE_ROLE_NONCE_V6',
         'writer_nonce_sha256',v_nonce_sha,
         'writer_proof_expires_at',v_exp
       )
     where id=v_event_id;
  end if;
  return v_id;
end;
$function$;

create or replace function public.record_lf_gate_test_v6(
  p_payload jsonb,
  p_execution_id text,
  p_writer_signature text,
  p_writer_nonce text
)
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog','public','private','extensions'
as $function$
declare
  v_id bigint;
  v_event_id bigint;
  v_nonce_sha text;
  v_exp timestamptz;
  v_payload jsonb;
begin
  v_exp := to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_nonce_sha := encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex');
  v_payload := coalesce(p_payload,'{}'::jsonb)||jsonb_build_object(
    'writer_authentication','SERVICE_ROLE_NONCE_V6',
    'writer_nonce_sha256',v_nonce_sha,
    'writer_proof_expires_at',v_exp,
    'producer','github-actions-oidc-reconciler-service-role-nonce-v6'
  );
  v_id := public.record_lf_gate_test_v5(
    v_payload,p_execution_id,p_writer_signature,p_writer_nonce
  );
  select nullif(to_jsonb(t)->>'evidence_event_id','')::bigint into v_event_id
  from private.lf_gate_test_runs_v3 t where t.id=v_id;
  if v_event_id is not null then
    update public.lf_eventos
       set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
         'writer_authentication','SERVICE_ROLE_NONCE_V6',
         'writer_nonce_sha256',v_nonce_sha,
         'writer_proof_expires_at',v_exp
       )
     where id=v_event_id;
  end if;
  return v_id;
end;
$function$;

revoke all on function public.record_external_ci_verification_v6(jsonb,text,text,text)
  from public,anon,authenticated;
revoke all on function public.record_lf_gate_test_v6(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_external_ci_verification_v6(jsonb,text,text,text)
  to service_role;
grant execute on function public.record_lf_gate_test_v6(jsonb,text,text,text)
  to service_role;

create or replace function private.fn_mark_nonce_authenticated_event_v6()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','private','public','extensions'
as $function$
declare
  v_preimage text;
  v_scope text;
  v_proof private.lf_reconciliation_writer_nonces_v6%rowtype;
begin
  if new.evento_tipo='EXTERNAL_CI_VERIFICATION_COMPLETED' then
    v_scope:='RECONCILIATION';
    v_preimage:=array_to_string(array[
      'reconciliation-v5',
      coalesce(new.payload->>'execution_id',''),
      coalesce(new.payload->>'artifact_id',''),
      coalesce(new.payload->>'workflow_run_id',''),
      coalesce(new.payload->>'merge_commit_sha',''),
      coalesce(new.payload->>'artifact_sha256',''),
      coalesce(new.payload->>'branch_protection_status',''),
      coalesce(new.payload->>'result',''),
      coalesce(new.payload->>'audit_manifest_sha256','')
    ],':');
  elsif new.evento_tipo='GATE_TEST_RUN_RECORDED' then
    v_scope:='GATE';
    v_preimage:=array_to_string(array[
      'gate-v5',
      coalesce(new.payload->>'execution_id',''),
      coalesce(new.payload->>'artifact_id',''),
      coalesce(new.payload->>'test_code',''),
      coalesce(new.payload->>'source_workflow_run_id',''),
      coalesce(new.payload->>'source_commit_sha',''),
      coalesce(new.payload->>'passed',''),
      coalesce(new.payload->>'target_relation',''),
      coalesce(new.payload->>'gate_code',''),
      coalesce(new.payload#>>'{probe_preimage,expected_sha256}',''),
      coalesce(new.payload#>>'{observed_outcome,artifact_sha256}',''),
      coalesce(new.payload#>>'{observed_outcome,audit_covered}',''),
      coalesce(new.payload#>>'{persisted_effects,github_reconciliation_run_id}','')
    ],':');
  else
    return new;
  end if;

  select * into v_proof
  from private.lf_reconciliation_writer_nonces_v6 n
  where n.proof_scope=v_scope
    and n.preimage_sha256=encode(
      extensions.digest(convert_to(v_preimage,'UTF8'),'sha256'),'hex'
    )
    and n.request_role='service_role'
    and n.consumed_at<=n.expires_at
  order by n.consumed_at desc
  limit 1;

  if found then
    new.payload:=coalesce(new.payload,'{}'::jsonb)||jsonb_build_object(
      'writer_authentication','SERVICE_ROLE_NONCE_V6',
      'writer_nonce_sha256',v_proof.nonce_sha256,
      'writer_proof_expires_at',v_proof.expires_at
    );
  end if;
  return new;
end;
$function$;
revoke all on function private.fn_mark_nonce_authenticated_event_v6()
  from public,anon,authenticated,service_role;

drop trigger if exists trg_00_mark_nonce_authenticated_event_v6 on public.lf_eventos;
create trigger trg_00_mark_nonce_authenticated_event_v6
before insert on public.lf_eventos
for each row execute function private.fn_mark_nonce_authenticated_event_v6();
alter table public.lf_eventos enable always trigger trg_00_mark_nonce_authenticated_event_v6;
