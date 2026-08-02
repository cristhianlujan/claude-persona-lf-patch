-- PR #93 / LOTE-E / CA-N56..CA-N60 final static hardening.
-- This migration has not been deployed. It replaces the pre-deployment LOTE-C
-- definition so the migration chain remains executable and fail-closed.

begin;

do $preflight$
begin
  if to_regclass('private.lf_gate_test_runs_v3') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null
     or to_regclass('public.lf_eventos') is null
     or to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_canonical_json_v7(jsonb)') is null
     or to_regprocedure('private.fn_payload_sha256_v7(jsonb)') is null
     or to_regprocedure('private.fn_frame_component_v7(text)') is null
     or to_regprocedure('extensions.digest(bytea,text)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_valid(text,text,text)') is null
     or to_regprocedure('private.fn_writer_hmac_v7_match_key(text,text,text)') is null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_install_writer_hmac_key_v7(text,text,text)') is null
     or to_regprocedure('private.fn_writer_hmac_challenge_v7(text,text)') is null
     or to_regprocedure('private.fn_promote_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_retire_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_writer_key_separation_v7_valid()') is null then
    raise exception 'V7 tables, crypto dependencies, helpers, validator and separation invariant must exist before LOTE-E';
  end if;

  if not exists(select 1 from pg_roles where rolname='lf_writer_verifier_v7')
     or not exists(select 1 from pg_roles where rolname='lf_governance_owner_v3') then
    raise exception 'V7 owner roles must exist before LOTE-E';
  end if;

end
$preflight$;


-- CA-N49/CA-N50: obtain both owner contexts before any function grant or table DDL.
grant lf_writer_verifier_v7 to postgres
  with admin false inherit true set true
  granted by postgres;
grant lf_governance_owner_v3 to postgres
  with admin false inherit true set true
  granted by postgres;

do $table_owner_preflight$
declare
  v_gate_owner oid;
begin
  select c.relowner into v_gate_owner
  from pg_class c
  where c.oid='private.lf_gate_test_runs_v3'::regclass;

  if not pg_has_role(current_user,pg_get_userbyid(v_gate_owner),'USAGE')
     and not coalesce((select r.rolsuper from pg_roles r where r.rolname=current_user),false) then
    raise exception 'migration executor cannot administer private.lf_gate_test_runs_v3';
  end if;
end
$table_owner_preflight$;

-- CA-N52: keep signed persisted_effects byte-for-byte aligned with the event.
-- The writer nonce gets a dedicated private column instead of mutating signed JSON.
alter table private.lf_gate_test_runs_v3
  add column if not exists writer_nonce_sha256 text;

-- CA-N51: no silent invalidation. A partially deployed environment with old V7
-- rows must explicitly backfill them before applying this migration.
do $preexisting_v7$
begin
  if exists(
    select 1
    from private.lf_gate_test_runs_v3 t
    where t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.writer_nonce_sha256,'') !~ '^[0-9a-f]{64}$'
  ) then
    raise exception using
      errcode='55000',
      message='preexisting V7 gate rows require explicit nonce backfill before LOTE-E';
  end if;
end
$preexisting_v7$;

do $nonce_constraint$
begin
  if not exists(
    select 1
    from pg_constraint c
    where c.conrelid='private.lf_gate_test_runs_v3'::regclass
      and c.conname='lf_gate_test_runs_v3_writer_nonce_v7_ck'
  ) then
    alter table private.lf_gate_test_runs_v3
      add constraint lf_gate_test_runs_v3_writer_nonce_v7_ck
      check (
        writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7'
        or coalesce(writer_nonce_sha256,'') ~ '^[0-9a-f]{64}$'
      );
  end if;
end
$nonce_constraint$;

-- CA-N49: issue each helper grant under its actual owner role.
set local role lf_writer_verifier_v7;
grant execute on function private.fn_writer_preimage_scope_v7(text) to postgres;
reset role;

grant create on schema private to lf_governance_owner_v3;
set local role lf_governance_owner_v3;

grant execute on function private.fn_reconciliation_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_gate_preimage_v7(jsonb,text) to postgres;
grant execute on function private.fn_canonical_json_v7(jsonb) to postgres;
grant execute on function private.fn_payload_sha256_v7(jsonb) to postgres;
grant execute on function private.fn_frame_component_v7(text) to postgres;

-- CA-N45/CA-N52: bind the nonce to a dedicated private column and verify that
-- persisted_effects and its digest remain identical to the signed event payload.
create or replace function private.fn_bind_gate_writer_nonce_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_event_nonce text;
  v_event_preimage text;
  v_event_effects jsonb;
  v_event_effects_hash text;
  v_row_effects_hash text;
begin
  if tg_op='UPDATE'
     and old.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
     and new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    raise exception using
      errcode='55000',
      message='V7 gate authentication cannot be downgraded';
  end if;

  if new.writer_authentication is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    return new;
  end if;

  if tg_op='UPDATE' then
    if new.evidence_event_id is distinct from old.evidence_event_id
       or new.persisted_effects is distinct from old.persisted_effects
       or new.persisted_effects_sha256 is distinct from old.persisted_effects_sha256
       or new.writer_nonce_sha256 is distinct from old.writer_nonce_sha256 then
      raise exception using
        errcode='55000',
        message='V7 gate proof binding is immutable';
    end if;
  end if;

  select
    e.payload->>'writer_nonce_sha256',
    e.payload#>>'{persisted_effects,signed_preimage_sha256}',
    e.payload->'persisted_effects',
    e.payload->>'persisted_effects_sha256'
    into v_event_nonce,v_event_preimage,v_event_effects,v_event_effects_hash
  from public.lf_eventos e
  where e.id=new.evidence_event_id
    and e.evento_tipo='GATE_TEST_RUN_RECORDED'
    and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7';

  v_row_effects_hash:=encode(
    extensions.digest(convert_to(new.persisted_effects::text,'UTF8'),'sha256'),
    'hex'
  );

  if coalesce(v_event_nonce,'') !~ '^[0-9a-f]{64}$'
     or coalesce(v_event_preimage,'') !~ '^[0-9a-f]{64}$'
     or v_event_preimage is distinct from new.persisted_effects->>'signed_preimage_sha256'
     or v_event_effects is distinct from new.persisted_effects
     or v_event_effects_hash is distinct from new.persisted_effects_sha256
     or v_row_effects_hash is distinct from new.persisted_effects_sha256
     or (
       new.writer_nonce_sha256 is not null
       and new.writer_nonce_sha256 is distinct from v_event_nonce
     ) then
    raise exception using
      errcode='23514',
      message='V7 gate row does not match its signed evidence event';
  end if;

  new.writer_nonce_sha256:=v_event_nonce;
  return new;
end;
$function$;

alter function private.fn_bind_gate_writer_nonce_v7()
  owner to lf_governance_owner_v3;
revoke all on function private.fn_bind_gate_writer_nonce_v7()
  from public,anon,authenticated,service_role;
-- CREATE TRIGGER requires EXECUTE for its creator; this grant is temporary.
grant execute on function private.fn_bind_gate_writer_nonce_v7() to postgres;

-- The private row is authoritative; the event independently cross-checks nonce,
-- preimage, persisted_effects and persisted_effects_sha256.
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
    join public.lf_eventos e
      on e.id=t.evidence_event_id
     and e.evento_tipo='GATE_TEST_RUN_RECORDED'
     and e.payload->>'writer_authentication'='GITHUB_OIDC_HMAC_NONCE_V7'
     and e.payload#>>'{persisted_effects,signed_preimage_sha256}'
         =t.persisted_effects->>'signed_preimage_sha256'
     and e.payload->>'writer_nonce_sha256'=t.writer_nonce_sha256
     and e.payload->'persisted_effects'=t.persisted_effects
     and e.payload->>'persisted_effects_sha256'=t.persisted_effects_sha256
    join private.lf_reconciliation_writer_nonces_v7 n
      on n.proof_scope='GATE'
     and n.authentication_mode='GITHUB_OIDC_HMAC_NONCE_V7'
     and n.preimage_sha256=t.persisted_effects->>'signed_preimage_sha256'
     and n.nonce_sha256=t.writer_nonce_sha256
    where t.id=p_test_id
      and t.writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7'
      and coalesce(t.persisted_effects->>'signed_preimage_sha256','') ~ '^[0-9a-f]{64}$'
      and coalesce(t.writer_nonce_sha256,'') ~ '^[0-9a-f]{64}$'
      and t.persisted_effects_sha256=encode(
        extensions.digest(convert_to(t.persisted_effects::text,'UTF8'),'sha256'),
        'hex'
      )
      and n.request_role='service_role'
      and n.key_id is not null
      and n.consumed_at<=n.expires_at
      and abs(extract(epoch from (t.executed_at-n.consumed_at)))<=60
  );
$function$;

alter function private.fn_gate_nonce_v7_valid(bigint)
  owner to lf_governance_owner_v3;
revoke all on function private.fn_gate_nonce_v7_valid(bigint)
  from public,anon,authenticated,service_role;

reset role;

-- CA-N50: table DDL runs in the migration executor context, matching 180315.
drop trigger if exists trg_05_bind_gate_writer_nonce_v7
  on private.lf_gate_test_runs_v3;
create trigger trg_05_bind_gate_writer_nonce_v7
before insert or update on private.lf_gate_test_runs_v3
for each row execute function private.fn_bind_gate_writer_nonce_v7();
alter table private.lf_gate_test_runs_v3
  enable always trigger trg_05_bind_gate_writer_nonce_v7;

-- The trigger is installed; remove the temporary creator privilege.
set local role lf_governance_owner_v3;
revoke execute on function private.fn_bind_gate_writer_nonce_v7() from postgres;
reset role;

revoke create on schema private from lf_governance_owner_v3;
revoke lf_governance_owner_v3 from postgres granted by postgres;
revoke lf_writer_verifier_v7 from postgres granted by postgres;

do $post_create_dependencies$
begin
  if to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is null then
    raise exception 'V7 gate binder must exist before the separation invariant';
  end if;
end
$post_create_dependencies$;

-- CA-N48: preserve every prior separation check and include the parser/binder.
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
      'service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE'
    )
    and not has_function_privilege(
      'service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE'
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

commit;
