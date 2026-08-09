
begin;

-- The governed trigger is owned by lf_governance_owner_v3. Temporarily allow
-- postgres to SET ROLE, then restore the original membership option before
-- this transaction can commit.
grant lf_governance_owner_v3 to postgres with set true;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

do $patch_event_guard$
declare
  def text;
  old_required text := $$'writer_authentication','writer_signature_sha256'];$$;
  new_required text := $$'writer_authentication','writer_signature_sha256','writer_nonce_sha256','writer_proof_expires_at'];$$;
  old_mode text := $$new.payload->>'verification_mode'<>'GITHUB_APP_OIDC_READBACK'$$;
  new_mode text := $$new.payload->>'verification_mode'<>'GITHUB_ACTIONS_OIDC_HMAC_V7'$$;
  old_writer text := $$'HMAC_TOKEN_V5'$$;
  new_writer text := $$'GITHUB_OIDC_HMAC_NONCE_V7'$$;
  old_envelope_tail text := $$or coalesce(new.payload->>'writer_signature_sha256','') !~ '^[0-9a-f]{64}$' then$$;
  new_envelope_tail text := $$or coalesce(new.payload->>'writer_signature_sha256','') !~ '^[0-9a-f]{64}$'
       or coalesce(new.payload->>'writer_nonce_sha256','') !~ '^[0-9a-f]{64}$'
       or private.fn_lf_try_timestamptz(new.payload->>'writer_proof_expires_at') is null
       or private.fn_lf_try_timestamptz(new.payload->>'writer_proof_expires_at') <= clock_timestamp() then$$;
begin
  select pg_get_functiondef('private.fn_enforce_lf_eventos_validation_acceptance_v2()'::regprocedure)
    into def;

  if length(def)-length(replace(def,old_required,'')) <> length(old_required) then
    raise exception 'event guard required-field anchor count is not 1';
  end if;
  if length(def)-length(replace(def,old_mode,'')) <> length(old_mode) then
    raise exception 'event guard verification-mode anchor count is not 1';
  end if;
  if (length(def)-length(replace(def,old_writer,'')))/length(old_writer) <> 2 then
    raise exception 'event guard writer-authentication anchor count is not 2';
  end if;
  if length(def)-length(replace(def,old_envelope_tail,'')) <> length(old_envelope_tail) then
    raise exception 'event guard envelope-tail anchor count is not 1';
  end if;

  def := replace(def,old_required,new_required);
  def := replace(def,old_mode,new_mode);
  def := replace(def,old_writer,new_writer);
  def := replace(def,old_envelope_tail,new_envelope_tail);
  execute def;
end;
$patch_event_guard$;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

create table private.lf_schema_fingerprint_baseline_v14 (
  object_identity text primary key,
  object_type text not null check (object_type in ('TABLE','VIEW','FUNCTION','TRIGGER','CRON_JOB','ROLE')),
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  definition_snapshot text not null,
  baseline_execution_id text not null,
  baselined_at timestamptz not null default clock_timestamp()
);

create or replace function private.fn_guard_schema_fingerprint_baseline_v14()
returns trigger
language plpgsql
set search_path='pg_catalog'
as $function$
begin
  if current_user<>'postgres' then
    raise exception using errcode='42501',message='schema fingerprint baseline v14 accepts inserts only from governed maintenance';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode='55000',message='schema fingerprint baseline v14 is append-only';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_guard_schema_fingerprint_baseline_v14() from public,anon,authenticated,service_role;

alter table private.lf_schema_fingerprint_baseline_v14 enable row level security;
alter table private.lf_schema_fingerprint_baseline_v14 force row level security;
revoke all on private.lf_schema_fingerprint_baseline_v14 from public,anon,authenticated,service_role;

create policy pol_lf_schema_fingerprint_baseline_v14_postgres
on private.lf_schema_fingerprint_baseline_v14 for all to postgres using (true) with check (true);

create trigger trg_00_guard_lf_schema_fingerprint_baseline_v14
before insert or update or delete on private.lf_schema_fingerprint_baseline_v14
for each row execute function private.fn_guard_schema_fingerprint_baseline_v14();

create or replace view public.v_lf_schema_fingerprint_drift_v14
with (security_invoker=true)
as
select b.object_identity,b.object_type,b.definition_sha256 baseline_sha256,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),'sha256'),'hex') current_sha256,
       private.fn_architecture_object_definition_v3(b.object_type,b.object_identity)='<missing>' missing,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),'sha256'),'hex')<>b.definition_sha256 drifted
from private.lf_schema_fingerprint_baseline_v14 b
where b.object_identity not in (
  'public.v_lf_schema_fingerprint_drift_v14',
  'public.v_lf_architecture_closure_v4',
  'public.v_lf_architecture_closure_v5',
  'public.v_lf_architecture_closure_v6',
  'public.v_lf_architecture_closure_current'
);

revoke all on public.v_lf_schema_fingerprint_drift_v14 from anon,authenticated;

insert into private.lf_schema_fingerprint_baseline_v14(
  object_identity,object_type,definition_sha256,definition_snapshot,baseline_execution_id
)
select o.object_identity,o.object_type,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),'UTF8'),'sha256'),'hex'),
       private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),
       'WORK-PR93-BASELINE-V14-20260809'
from (
  select object_identity,object_type from private.lf_schema_fingerprint_baseline_v13
  union
  select 'private.lf_schema_fingerprint_baseline_v14','TABLE'
  union
  select 'private.fn_guard_schema_fingerprint_baseline_v14()','FUNCTION'
  union
  select 'public.v_lf_schema_fingerprint_drift_v14','VIEW'
) o
order by o.object_type,o.object_identity;

do $activate$
declare
  def text;
begin
  select pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true) into def;
  if position('v_lf_schema_fingerprint_drift_v13' in def)=0 then
    raise exception 'closure v4 does not reference v13';
  end if;
  def:=replace(def,'v_lf_schema_fingerprint_drift_v13','v_lf_schema_fingerprint_drift_v14');
  execute 'create or replace view public.v_lf_architecture_closure_v4 as '||def;
end;
$activate$;

do $assertions$
declare
  expected_count bigint;
  observed_count bigint;
  drift_count bigint;
  owner_name text;
  membership_ok boolean;
begin
  select count(*)+3 into expected_count from private.lf_schema_fingerprint_baseline_v13;
  select count(*) into observed_count from private.lf_schema_fingerprint_baseline_v14;
  if observed_count<>expected_count then
    raise exception 'baseline v14 count mismatch expected %, got %',expected_count,observed_count;
  end if;

  select count(*) into drift_count
  from public.v_lf_schema_fingerprint_drift_v14
  where drifted or missing;
  if drift_count<>0 then
    raise exception 'baseline v14 unexpected drift count %',drift_count;
  end if;

  if position('v_lf_schema_fingerprint_drift_v14' in pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true))=0 then
    raise exception 'closure v4 did not switch to baseline v14';
  end if;

  select pg_get_userbyid(p.proowner) into owner_name
  from pg_proc p
  where p.oid='private.fn_enforce_lf_eventos_validation_acceptance_v2()'::regprocedure;
  if owner_name<>'lf_governance_owner_v3' then
    raise exception 'event guard owner changed to %',owner_name;
  end if;

  select coalesce(bool_and(am.admin_option and not am.inherit_option and not am.set_option),false)
    into membership_ok
  from pg_auth_members am
  join pg_roles granted on granted.oid=am.roleid
  join pg_roles member on member.oid=am.member
  where granted.rolname='lf_governance_owner_v3' and member.rolname='postgres';
  if not membership_ok then
    raise exception 'governance owner membership options were not restored';
  end if;

  if not has_schema_privilege('lf_governance_owner_v3','private','USAGE')
     or has_schema_privilege('lf_governance_owner_v3','private','CREATE') then
    raise exception 'governance owner schema privileges were not restored';
  end if;

  if not private.fn_governance_role_separation_v7_valid() then
    raise exception 'governance role separation v7 became invalid';
  end if;
end;
$assertions$;

-- Exercise the complete strict V7 envelope. The transaction's rollback dry-run
-- and the migration transaction both prove the acceptance path; this row is
-- intentionally retained only when the actual migration commits.
do $v7_probe$
declare
  a record;
  p jsonb;
  execution_id text := 'WORK-PR93-V7-EVENT-GUARD-PROBE-20260809';
  merge_sha text := '14ee012c8becddc5415cbb75732c4b37bedfd70b';
begin
  select id,artifact_code,relative_path,content_sha256
    into a
  from private.lf_skill_artifacts
  where is_current
  order by id
  limit 1;

  if not found then
    raise exception 'no current LF skill artifact is available for V7 probe';
  end if;

  p := jsonb_build_object(
    'evidence_schema_version','external-ci-verification/v3',
    'result','PASS',
    'artifact_id',a.id,
    'repository','cristhianlujan/claude-persona-lf-patch',
    'target_branch','main',
    'artifact_path',a.relative_path,
    'pr_number',117,
    'pr_state','MERGED',
    'merged',true,
    'merge_commit_sha',merge_sha,
    'workflow_run_id',31296617922,
    'workflow_name','lf-contract-check',
    'workflow_event','push',
    'workflow_head_sha',merge_sha,
    'workflow_conclusion','success',
    'artifact_git_blob','1111111111111111111111111111111111111111',
    'artifact_sha256',a.content_sha256,
    'file_touched_by_merge',false,
    'artifact_exercised_by_workflow',true,
    'audit_artifact_name','lf-contract-audit-probe',
    'audit_manifest_sha256',repeat('2',64),
    'branch_protection_status','VERIFIED',
    'failure_reasons','[]'::jsonb,
    'details',jsonb_build_object('probe','strict-v7-event-guard'),
    'observed_at',clock_timestamp(),
    'verification_mode','GITHUB_ACTIONS_OIDC_HMAC_V7',
    'producer','supabase-governed-migration',
    'purpose','prove strict V7 event envelope acceptance before reconciliation',
    'execution_id',execution_id,
    'writer_authentication','GITHUB_OIDC_HMAC_NONCE_V7',
    'writer_signature_sha256',repeat('3',64),
    'writer_nonce_sha256',repeat('4',64),
    'writer_proof_expires_at',clock_timestamp()+interval '5 minutes'
  );
  p := p || jsonb_build_object(
    'verification_payload_sha256',
    encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex')
  );

  insert into public.lf_eventos(
    evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id
  ) values (
    'EXTERNAL_CI_VERIFICATION_COMPLETED','LF_SKILL_ARTIFACT',a.artifact_code,
    'Strict V7 event-envelope migration probe','INFO',p,
    'CHATGPT_SUPABASE_CONNECTOR',execution_id
  );
end;
$v7_probe$;

commit;
