
begin;

-- Use the real governed owner for function/table DDL. The secondary SET grant
-- and temporary schema CREATE privilege are removed before commit.
grant lf_governance_owner_v3 to postgres with set true;
grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

do $patch_v7_runtime$
declare
  def text;
  old_auth text := 'HMAC_TOKEN_V5';
  new_auth text := 'GITHUB_OIDC_HMAC_NONCE_V7';
  n integer;
begin
  -- Promotion guard: require V7 authentication plus persisted nonce validity.
  select pg_get_functiondef('private.fn_enforce_lf_skill_artifact_pass_shape_v2()'::regprocedure)
    into def;
  n := (length(def)-length(replace(def,old_auth,'')))/length(old_auth);
  if n<>2 then raise exception 'artifact pass guard V5 anchor count expected 2, got %',n; end if;
  def := replace(def,old_auth,new_auth);
  if position($a$or g.evidence_event_id<>(e->>'external_verification_event_id')::bigint or g.writer_authentication<>'GITHUB_OIDC_HMAC_NONCE_V7' or coalesce(g.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$' then$a$ in def)=0 then
    raise exception 'artifact pass reconciliation anchor missing';
  end if;
  def := replace(
    def,
    $a$or g.evidence_event_id<>(e->>'external_verification_event_id')::bigint or g.writer_authentication<>'GITHUB_OIDC_HMAC_NONCE_V7' or coalesce(g.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$' then$a$,
    $a$or g.evidence_event_id<>(e->>'external_verification_event_id')::bigint or g.writer_authentication<>'GITHUB_OIDC_HMAC_NONCE_V7' or coalesce(g.writer_signature_sha256,'') !~ '^[0-9a-f]{64}$' or not private.fn_reconciliation_nonce_v7_valid(g.id) then$a$
  );
  if position($a$and t.source_workflow_run_id=g.workflow_run_id and t.source_commit_sha=g.merge_commit_sha and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and coalesce(t.writer_signature_sha256,'') ~ '^[0-9a-f]{64}$') then$a$ in def)=0 then
    raise exception 'artifact pass gate anchor missing';
  end if;
  def := replace(
    def,
    $a$and t.source_workflow_run_id=g.workflow_run_id and t.source_commit_sha=g.merge_commit_sha and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and coalesce(t.writer_signature_sha256,'') ~ '^[0-9a-f]{64}$') then$a$,
    $a$and t.source_workflow_run_id=g.workflow_run_id and t.source_commit_sha=g.merge_commit_sha and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and coalesce(t.writer_signature_sha256,'') ~ '^[0-9a-f]{64}$' and private.fn_gate_nonce_v7_valid(t.id)) then$a$
  );
  execute def;

  -- Dependency readiness: V7 reconciliation/event/gate evidence and valid
  -- consumed nonce receipts are all mandatory.
  select pg_get_functiondef('private.fn_lf_artifact_dependency_ready_v4(bigint)'::regprocedure)
    into def;
  n := (length(def)-length(replace(def,old_auth,'')))/length(old_auth);
  if n<>3 then raise exception 'dependency readiness V5 anchor count expected 3, got %',n; end if;
  def := replace(def,old_auth,new_auth);
  if position($a$and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and g.writer_signature_sha256 ~ '^[0-9a-f]{64}$'$a$ in def)=0 then
    raise exception 'dependency reconciliation anchor missing';
  end if;
  def := replace(
    def,
    $a$and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and g.writer_signature_sha256 ~ '^[0-9a-f]{64}$'$a$,
    $a$and g.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and g.writer_signature_sha256 ~ '^[0-9a-f]{64}$'
      and private.fn_reconciliation_nonce_v7_valid(g.id)$a$
  );
  if position($a$and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'$a$ in def)=0 then
    raise exception 'dependency event anchor missing';
  end if;
  def := replace(
    def,
    $a$and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'$a$,
    $a$and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(e.payload->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and private.fn_lf_try_timestamptz(e.payload->>'writer_proof_expires_at') is not null$a$
  );
  if position($a$and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and t.writer_signature_sha256 ~ '^[0-9a-f]{64}$'$a$ in def)=0 then
    raise exception 'dependency gate anchor missing';
  end if;
  def := replace(
    def,
    $a$and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and t.writer_signature_sha256 ~ '^[0-9a-f]{64}$'$a$,
    $a$and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7' and t.writer_signature_sha256 ~ '^[0-9a-f]{64}$'
          and private.fn_gate_nonce_v7_valid(t.id)$a$
  );
  execute def;

  -- Contract assessment: the external-ci/v3 envelope is V7-only and carries
  -- both nonce hash and proof expiry.
  select pg_get_functiondef('private.fn_lf_event_contract_assessment_v3(text,text,text,text,jsonb,text)'::regprocedure)
    into def;
  n := (length(def)-length(replace(def,old_auth,'')))/length(old_auth);
  if n<>1 then raise exception 'event assessment V5 anchor count expected 1, got %',n; end if;
  def := replace(def,old_auth,new_auth);
  if position($a$or coalesce(p_payload->>'verification_payload_sha256','') !~ '^[0-9a-f]{64}$' or p_payload->>'writer_authentication'<>'GITHUB_OIDC_HMAC_NONCE_V7' or coalesce(p_payload->>'writer_signature_sha256','') !~ '^[0-9a-f]{64}$' then$a$ in def)=0 then
    raise exception 'event assessment V7 envelope anchor missing';
  end if;
  def := replace(
    def,
    $a$or coalesce(p_payload->>'verification_payload_sha256','') !~ '^[0-9a-f]{64}$' or p_payload->>'writer_authentication'<>'GITHUB_OIDC_HMAC_NONCE_V7' or coalesce(p_payload->>'writer_signature_sha256','') !~ '^[0-9a-f]{64}$' then$a$,
    $a$or coalesce(p_payload->>'verification_payload_sha256','') !~ '^[0-9a-f]{64}$'
         or p_payload->>'verification_mode'<>'GITHUB_ACTIONS_OIDC_HMAC_V7'
         or p_payload->>'writer_authentication'<>'GITHUB_OIDC_HMAC_NONCE_V7'
         or coalesce(p_payload->>'writer_signature_sha256','') !~ '^[0-9a-f]{64}$'
         or coalesce(p_payload->>'writer_nonce_sha256','') !~ '^[0-9a-f]{64}$'
         or private.fn_lf_try_timestamptz(p_payload->>'writer_proof_expires_at') is null then$a$
  );
  execute def;

  -- Typed gate evidence: V7-only writer fields are structurally mandatory.
  select pg_get_functiondef('private.fn_lf_typed_evidence_payload_valid_v3(text,jsonb)'::regprocedure)
    into def;
  n := (length(def)-length(replace(def,old_auth,'')))/length(old_auth);
  if n<>1 then raise exception 'typed evidence V5 anchor count expected 1, got %',n; end if;
  def := replace(def,old_auth,new_auth);
  if position($a$and p_payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7' and coalesce(p_payload->>'writer_signature_sha256','') ~ '^[0-9a-f]{64}$';$a$ in def)=0 then
    raise exception 'typed gate V7 envelope anchor missing';
  end if;
  def := replace(
    def,
    $a$and p_payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7' and coalesce(p_payload->>'writer_signature_sha256','') ~ '^[0-9a-f]{64}$';$a$,
    $a$and p_payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(p_payload->>'writer_signature_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(p_payload->>'writer_nonce_sha256','') ~ '^[0-9a-f]{64}$'
      and private.fn_lf_try_timestamptz(p_payload->>'writer_proof_expires_at') is not null;$a$
  );
  execute def;
end;
$patch_v7_runtime$;

alter table private.lf_github_reconciliation_runs_v3
  drop constraint lf_github_reconciliation_runs_v3_writer_auth_check,
  drop constraint lf_github_reconciliation_runs_v3_signed_pass_check,
  add constraint lf_github_reconciliation_runs_v3_writer_auth_check
    check (
      writer_authentication is null
      or writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
    ) not valid,
  add constraint lf_github_reconciliation_runs_v3_signed_pass_check
    check (
      result<>'PASS'
      or (
        writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
        and writer_signature_sha256 ~ '^[0-9a-f]{64}$'
      )
    ) not valid;

alter table private.lf_gate_test_runs_v3
  drop constraint lf_gate_test_runs_v3_writer_auth_check,
  drop constraint lf_gate_test_runs_v3_signed_pass_check,
  add constraint lf_gate_test_runs_v3_writer_auth_check
    check (
      writer_authentication is null
      or writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
    ) not valid,
  add constraint lf_gate_test_runs_v3_signed_pass_check
    check (
      not passed
      or (
        writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
        and writer_signature_sha256 ~ '^[0-9a-f]{64}$'
      )
    ) not valid;

reset role;
revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;

create table private.lf_schema_fingerprint_baseline_v15 (
  object_identity text primary key,
  object_type text not null check (object_type in ('TABLE','VIEW','FUNCTION','TRIGGER','CRON_JOB','ROLE')),
  definition_sha256 text not null check (definition_sha256 ~ '^[0-9a-f]{64}$'),
  definition_snapshot text not null,
  baseline_execution_id text not null,
  baselined_at timestamptz not null default clock_timestamp()
);

create or replace function private.fn_guard_schema_fingerprint_baseline_v15()
returns trigger
language plpgsql
set search_path='pg_catalog'
as $function$
begin
  if current_user<>'postgres' then
    raise exception using errcode='42501',message='schema fingerprint baseline v15 accepts inserts only from governed maintenance';
  end if;
  if tg_op in ('UPDATE','DELETE') then
    raise exception using errcode='55000',message='schema fingerprint baseline v15 is append-only';
  end if;
  return new;
end;
$function$;

revoke all on function private.fn_guard_schema_fingerprint_baseline_v15() from public,anon,authenticated,service_role;

alter table private.lf_schema_fingerprint_baseline_v15 enable row level security;
alter table private.lf_schema_fingerprint_baseline_v15 force row level security;
revoke all on private.lf_schema_fingerprint_baseline_v15 from public,anon,authenticated,service_role;

create policy pol_lf_schema_fingerprint_baseline_v15_postgres
on private.lf_schema_fingerprint_baseline_v15 for all to postgres using (true) with check (true);

create trigger trg_00_guard_lf_schema_fingerprint_baseline_v15
before insert or update or delete on private.lf_schema_fingerprint_baseline_v15
for each row execute function private.fn_guard_schema_fingerprint_baseline_v15();

create or replace view public.v_lf_schema_fingerprint_drift_v15
with (security_invoker=true)
as
select b.object_identity,b.object_type,b.definition_sha256 baseline_sha256,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),'sha256'),'hex') current_sha256,
       private.fn_architecture_object_definition_v3(b.object_type,b.object_identity)='<missing>' missing,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(b.object_type,b.object_identity),'UTF8'),'sha256'),'hex')<>b.definition_sha256 drifted
from private.lf_schema_fingerprint_baseline_v15 b
where b.object_identity not in (
  'public.v_lf_schema_fingerprint_drift_v15',
  'public.v_lf_architecture_closure_v4',
  'public.v_lf_architecture_closure_v5',
  'public.v_lf_architecture_closure_v6',
  'public.v_lf_architecture_closure_current'
);

revoke all on public.v_lf_schema_fingerprint_drift_v15 from anon,authenticated;

insert into private.lf_schema_fingerprint_baseline_v15(
  object_identity,object_type,definition_sha256,definition_snapshot,baseline_execution_id
)
select o.object_identity,o.object_type,
       encode(extensions.digest(convert_to(private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),'UTF8'),'sha256'),'hex'),
       private.fn_architecture_object_definition_v3(o.object_type,o.object_identity),
       'WORK-PR93-BASELINE-V15-20260809'
from (
  select object_identity,object_type from private.lf_schema_fingerprint_baseline_v14
  union
  select 'private.lf_schema_fingerprint_baseline_v15','TABLE'
  union
  select 'private.fn_guard_schema_fingerprint_baseline_v15()','FUNCTION'
  union
  select 'public.v_lf_schema_fingerprint_drift_v15','VIEW'
) o
order by o.object_type,o.object_identity;

do $activate$
declare
  def text;
begin
  select pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true) into def;
  if position('v_lf_schema_fingerprint_drift_v14' in def)=0 then
    raise exception 'closure v4 does not reference v14';
  end if;
  def:=replace(def,'v_lf_schema_fingerprint_drift_v14','v_lf_schema_fingerprint_drift_v15');
  execute 'create or replace view public.v_lf_architecture_closure_v4 as '||def;
end;
$activate$;

do $assertions$
declare
  expected_count bigint;
  observed_count bigint;
  drift_count bigint;
  stale_count bigint;
  v7_constraint_count bigint;
  owner_mismatch_count bigint;
  membership_ok boolean;
begin
  select count(*)+3 into expected_count from private.lf_schema_fingerprint_baseline_v14;
  select count(*) into observed_count from private.lf_schema_fingerprint_baseline_v15;
  if observed_count<>expected_count then
    raise exception 'baseline v15 count mismatch expected %, got %',expected_count,observed_count;
  end if;

  select count(*) into drift_count
  from public.v_lf_schema_fingerprint_drift_v15
  where drifted or missing;
  if drift_count<>0 then
    raise exception 'baseline v15 unexpected drift count %',drift_count;
  end if;

  if position('v_lf_schema_fingerprint_drift_v15' in pg_get_viewdef('public.v_lf_architecture_closure_v4'::regclass,true))=0 then
    raise exception 'closure v4 did not switch to baseline v15';
  end if;

  select count(*) into stale_count
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='private'
    and c.relname in ('lf_github_reconciliation_runs_v3','lf_gate_test_runs_v3')
    and con.conname in (
      'lf_github_reconciliation_runs_v3_writer_auth_check',
      'lf_github_reconciliation_runs_v3_signed_pass_check',
      'lf_gate_test_runs_v3_writer_auth_check',
      'lf_gate_test_runs_v3_signed_pass_check'
    )
    and pg_get_constraintdef(con.oid,true) like '%HMAC_TOKEN_V5%';
  if stale_count<>0 then raise exception 'V5 runtime constraints remain: %',stale_count; end if;

  select count(*) into v7_constraint_count
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='private'
    and c.relname in ('lf_github_reconciliation_runs_v3','lf_gate_test_runs_v3')
    and con.conname in (
      'lf_github_reconciliation_runs_v3_writer_auth_check',
      'lf_github_reconciliation_runs_v3_signed_pass_check',
      'lf_gate_test_runs_v3_writer_auth_check',
      'lf_gate_test_runs_v3_signed_pass_check'
    )
    and not con.convalidated
    and pg_get_constraintdef(con.oid,true) like '%GITHUB_OIDC_HMAC_NONCE_V7%';
  if v7_constraint_count<>4 then
    raise exception 'strict V7 runtime constraint count expected 4, got %',v7_constraint_count;
  end if;

  select count(*) into stale_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.prokind='f'
    and p.proname in (
      'fn_enforce_lf_skill_artifact_pass_shape_v2',
      'fn_lf_artifact_dependency_ready_v4',
      'fn_lf_event_contract_assessment_v3',
      'fn_lf_typed_evidence_payload_valid_v3'
    )
    and pg_get_functiondef(p.oid) like '%HMAC_TOKEN_V5%';
  if stale_count<>0 then raise exception 'V5 runtime function references remain: %',stale_count; end if;

  select count(*) into owner_mismatch_count
  from (
    select pg_get_userbyid(p.proowner) owner
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname in (
      'fn_enforce_lf_skill_artifact_pass_shape_v2',
      'fn_lf_artifact_dependency_ready_v4',
      'fn_lf_event_contract_assessment_v3',
      'fn_lf_typed_evidence_payload_valid_v3'
    )
    union all
    select pg_get_userbyid(c.relowner)
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='private' and c.relname in (
      'lf_github_reconciliation_runs_v3','lf_gate_test_runs_v3'
    )
  ) x
  where owner<>'lf_governance_owner_v3';
  if owner_mismatch_count<>0 then
    raise exception 'governed runtime object owner mismatch count %',owner_mismatch_count;
  end if;

  select count(*)=1 and bool_and(
           grantor.rolname='supabase_admin'
           and am.admin_option and not am.inherit_option and not am.set_option
         )
    into membership_ok
  from pg_auth_members am
  join pg_roles granted on granted.oid=am.roleid
  join pg_roles member on member.oid=am.member
  join pg_roles grantor on grantor.oid=am.grantor
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

commit;
