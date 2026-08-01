-- CA-N22 / CA-N23 / CA-N24 / CA-N28 remediation.
-- This migration is intentionally versioned before deployment. It must be tested on a
-- Supabase preview branch and must not be applied directly to production from this PR.
--
-- Required managed secret, configured out-of-band before exercising the writer:
--   Vault name: lf_reconciliation_writer_hmac_v7
--   Edge secret: LF_RECONCILIATION_WRITER_HMAC_V7
-- Both values must be identical. No secret value is stored in this migration.

begin;

do $block$
begin
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    create role lf_writer_verifier_v7 nologin noinherit nobypassrls;
  end if;
end
$block$;

alter role lf_writer_verifier_v7 nologin noinherit nobypassrls;

create table if not exists private.lf_reconciliation_writer_nonces_v7 (
  nonce_sha256 text primary key check (nonce_sha256 ~ '^[0-9a-f]{64}$'),
  proof_scope text not null check (proof_scope in ('RECONCILIATION','GATE')),
  preimage_sha256 text not null check (preimage_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  request_role text not null check (request_role='service_role'),
  authentication_mode text not null default 'GITHUB_OIDC_HMAC_NONCE_V7'
    check (authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7')
);

alter table private.lf_reconciliation_writer_nonces_v7 owner to lf_writer_verifier_v7;
alter table private.lf_reconciliation_writer_nonces_v7 enable row level security;
alter table private.lf_reconciliation_writer_nonces_v7 force row level security;

revoke all on private.lf_reconciliation_writer_nonces_v7
  from public,anon,authenticated,service_role;
grant select,insert on private.lf_reconciliation_writer_nonces_v7
  to lf_writer_verifier_v7;
grant select on private.lf_reconciliation_writer_nonces_v7
  to lf_governance_owner_v3;

drop policy if exists pol_lf_writer_nonce_v7_read on private.lf_reconciliation_writer_nonces_v7;
create policy pol_lf_writer_nonce_v7_read
  on private.lf_reconciliation_writer_nonces_v7
  for select
  to lf_writer_verifier_v7,lf_governance_owner_v3
  using (true);

drop policy if exists pol_lf_writer_nonce_v7_insert on private.lf_reconciliation_writer_nonces_v7;
create policy pol_lf_writer_nonce_v7_insert
  on private.lf_reconciliation_writer_nonces_v7
  for insert
  to lf_writer_verifier_v7
  with check (
    request_role='service_role'
    and nonce_sha256 ~ '^[0-9a-f]{64}$'
    and preimage_sha256 ~ '^[0-9a-f]{64}$'
    and expires_at > consumed_at - interval '5 seconds'
    and expires_at <= consumed_at + interval '6 minutes'
  );

-- The HMAC key is decrypted only inside this private boolean verifier. It is never
-- returned to the caller and the function is not executable by service_role.
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
  select count(*),min(s.decrypted_secret)
    into v_count,v_key
  from vault.decrypted_secrets s
  where s.name='lf_reconciliation_writer_hmac_v7';

  if v_count<>1 or nullif(v_key,'') is null then
    raise exception using
      errcode='55000',
      message='writer HMAC secret is not configured exactly once';
  end if;

  v_expected:=encode(
    extensions.hmac(
      convert_to(p_preimage||':'||p_nonce,'UTF8'),
      convert_to(v_key,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return extensions.digest(convert_to(v_expected,'UTF8'),'sha256')
       = extensions.digest(convert_to(lower(p_signature),'UTF8'),'sha256');
end;
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
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then return false; end if;
  if nullif(p_preimage,'') is null or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then return false; end if;
  if coalesce(p_writer_nonce,'') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow then
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

  if not private.fn_writer_hmac_v7_valid(p_preimage,p_writer_nonce,lower(p_signature)) then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role
  ) on conflict do nothing;
  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text) owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

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
     and n.preimage_sha256=encode(extensions.digest(convert_to(
       array_to_string(array[
         'reconciliation-v7',
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
      and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and n.request_role='service_role'
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (g.reconciled_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_reconciliation_nonce_v7_valid(bigint) owner to lf_governance_owner_v3;
revoke all on function private.fn_reconciliation_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

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
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=encode(extensions.digest(convert_to(
       array_to_string(array[
         'gate-v7',
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
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and n.request_role='service_role'
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint) owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

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
  v_event_id bigint;
  v_run_id bigint;
begin
  if jsonb_typeof(p_payload)<>'object'
     or nullif(btrim(coalesce(p_execution_id,'')),'') is null
     or jsonb_typeof(p_payload->'artifact_id')<>'number' then
    raise exception using errcode='23514',message='external reconciliation payload, artifact_id and execution_id are required';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then raise exception using errcode='P0002',message='artifact not found'; end if;

  v_preimage:=concat_ws(':',
    'reconciliation-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'workflow_run_id',
    p_payload->>'merge_commit_sha',p_payload->>'artifact_sha256',p_payload->>'branch_protection_status',
    p_payload->>'result',p_payload->>'audit_manifest_sha256'
  );

  if not private.fn_consume_writer_proof_v7(v_preimage,lower(p_writer_signature),p_writer_nonce) then
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
     ) then
    raise exception using errcode='23514',message='PASS requires native branch protection and exercised workflow evidence';
  end if;

  v_signature_hash:=encode(extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex');
  v_nonce_hash:=encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex');
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
  v_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_payload:=v_payload||jsonb_build_object('verification_payload_sha256',v_hash);

  if v_payload->>'artifact_path' is distinct from v_artifact.relative_path then
    raise exception using errcode='23514',message='external reconciliation artifact path mismatch';
  end if;
  if v_payload->>'result'='PASS' and (
    not v_artifact.is_current
    or v_payload->>'artifact_sha256' is distinct from v_artifact.content_sha256
  ) then
    raise exception using errcode='23514',message='external reconciliation PASS does not match current artifact content';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('lf-github-v7:'||v_artifact.id::text,0));
  select id into v_run_id
  from private.lf_github_reconciliation_runs_v3
  where artifact_id=v_artifact.id
    and workflow_run_id=(v_payload->>'workflow_run_id')::bigint
    and verification_payload_sha256=v_hash
    and writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';
  if found then return v_run_id; end if;

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
    case when v_payload->'pr_number'='null'::jsonb or not(v_payload?'pr_number') then null else (v_payload->>'pr_number')::integer end,
    v_payload->>'pr_state',(v_payload->>'merged')::boolean,v_payload->>'merge_commit_sha',
    (v_payload->>'workflow_run_id')::bigint,v_payload->>'workflow_name',v_payload->>'workflow_event',
    v_payload->>'workflow_head_sha',v_payload->>'workflow_conclusion',v_payload->>'artifact_git_blob',
    v_payload->>'artifact_sha256',(v_payload->>'file_touched_by_merge')::boolean,
    (v_payload->>'artifact_exercised_by_workflow')::boolean,v_payload->>'audit_artifact_name',
    v_payload->>'audit_manifest_sha256',v_payload->>'branch_protection_status',v_payload->>'result',true,
    v_payload->'failure_reasons',coalesce(v_payload->'details','{}'::jsonb)||jsonb_build_object(
      'writer_authentication_v7','GITHUB_OIDC_HMAC_NONCE_V7',
      'writer_nonce_sha256',v_nonce_hash,
      'writer_proof_expires_at',v_proof_expires_at
    ),v_hash,v_event_id,v_event_id,p_execution_id,(v_payload->>'observed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_run_id;

  return v_run_id;
end;
$function$;

alter function public.record_external_ci_verification_v7(jsonb,text,text,text) owner to lf_governance_owner_v3;
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
  v_event_id bigint;
  v_id bigint;
  v_reconciliation_id bigint;
begin
  if jsonb_typeof(p_payload)<>'object' or jsonb_typeof(p_payload->'artifact_id')<>'number' then
    raise exception using errcode='23514',message='gate test payload and artifact_id are required';
  end if;

  select * into v_artifact
  from private.lf_skill_artifacts
  where id=(p_payload->>'artifact_id')::bigint;
  if not found then raise exception using errcode='P0002',message='artifact not found'; end if;

  v_preimage:=concat_ws(':',
    'gate-v7',p_execution_id,p_payload->>'artifact_id',p_payload->>'test_code',
    p_payload->>'source_workflow_run_id',p_payload->>'source_commit_sha',p_payload->>'passed',
    p_payload->>'target_relation',p_payload->>'gate_code',
    p_payload->'probe_preimage'->>'expected_sha256',
    p_payload->'observed_outcome'->>'artifact_sha256',
    p_payload->'observed_outcome'->>'audit_covered',
    p_payload->'persisted_effects'->>'github_reconciliation_run_id'
  );

  if not private.fn_consume_writer_proof_v7(v_preimage,lower(p_writer_signature),p_writer_nonce) then
    raise exception using errcode='42501',message='OIDC HMAC nonce gate writer failed';
  end if;

  v_reconciliation_id:=nullif(p_payload#>>'{persisted_effects,github_reconciliation_run_id}','')::bigint;
  if coalesce((p_payload->>'passed')::boolean,false) and not exists(
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

  v_signature_hash:=encode(extensions.digest(convert_to(lower(p_writer_signature),'UTF8'),'sha256'),'hex');
  v_nonce_hash:=encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex');
  v_proof_expires_at:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  v_probe_hash:=encode(extensions.digest(convert_to((p_payload->'probe_preimage')::text,'UTF8'),'sha256'),'hex');
  v_effect_hash:=encode(extensions.digest(convert_to(coalesce(p_payload->'persisted_effects','{}'::jsonb)::text,'UTF8'),'sha256'),'hex');
  v_payload:=(p_payload-'evidence_payload_sha256')||jsonb_build_object(
    'evidence_schema_version','gate-test-run/v3',
    'execution_id',p_execution_id,
    'probe_sha256',v_probe_hash,
    'persisted_effects_sha256',v_effect_hash,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',v_signature_hash,
    'writer_nonce_sha256',v_nonce_hash,
    'writer_proof_expires_at',v_proof_expires_at
  );
  v_payload_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_payload:=v_payload||jsonb_build_object('evidence_payload_sha256',v_payload_hash);

  perform pg_advisory_xact_lock(hashtextextended(
    'lf-gate-v7:'||v_artifact.id::text||':'||coalesce(v_payload->>'test_code',''),0
  ));

  select id into v_id
  from private.lf_gate_test_runs_v3
  where test_code=v_payload->>'test_code'
    and artifact_id=v_artifact.id
    and source_workflow_run_id is not distinct from
      case when jsonb_typeof(v_payload->'source_workflow_run_id')='number'
        then (v_payload->>'source_workflow_run_id')::bigint else null end
    and source_commit_sha is not distinct from v_payload->>'source_commit_sha'
    and writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';
  if found then return v_id; end if;

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
    coalesce(v_payload->'persisted_effects','{}'::jsonb),v_effect_hash,
    (v_payload->>'passed')::boolean,v_payload->>'runner_type',v_payload->>'runner_identity',
    case when jsonb_typeof(v_payload->'source_workflow_run_id')='number'
      then (v_payload->>'source_workflow_run_id')::bigint else null end,
    v_payload->>'source_commit_sha',v_event_id,p_execution_id,
    (v_payload->>'executed_at')::timestamptz,
    'GITHUB_OIDC_HMAC_NONCE_V7',v_signature_hash
  ) returning id into v_id;

  return v_id;
end;
$function$;

alter function public.record_lf_gate_test_v7(jsonb,text,text,text) owner to lf_governance_owner_v3;
revoke all on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  from public,anon,authenticated;
grant execute on function public.record_lf_gate_test_v7(jsonb,text,text,text)
  to service_role;

-- Cut off every older operational writer. Their definitions remain for audit history,
-- but no API role can execute them after this migration.
revoke execute on function public.record_external_ci_verification_v5(jsonb,text,text,text)
  from public,anon,authenticated,service_role;
revoke execute on function public.record_lf_gate_test_v5(jsonb,text,text,text)
  from public,anon,authenticated,service_role;
revoke execute on function public.record_external_ci_verification_v6(jsonb,text,text,text)
  from public,anon,authenticated,service_role;
revoke execute on function public.record_lf_gate_test_v6(jsonb,text,text,text)
  from public,anon,authenticated,service_role;

commit;
