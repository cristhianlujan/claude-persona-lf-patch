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
  with admin false inherit true set true
  granted by postgres;
grant lf_writer_verifier_v7 to postgres
  with admin false inherit true set true
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
