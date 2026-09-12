-- PR #93 / LOTE 1 / forward-only HMAC key rotation for the active V7 writer.
-- This migration extends the active V7 chain and preserves the existing Edge/RPC
-- contract: HMAC-SHA256(preimage || ':' || nonce).
-- Versioned only. Exercise in an isolated environment before any deployment.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null then
    raise exception 'private.lf_writer_hmac_keys_v7 must exist before rotation migration';
  end if;
  if to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'private.lf_reconciliation_writer_nonces_v7 must exist before rotation migration';
  end if;
  if not exists (select 1 from pg_roles where rolname='lf_writer_verifier_v7') then
    raise exception 'lf_writer_verifier_v7 must exist before rotation migration';
  end if;
end
$preflight$;

alter table private.lf_writer_hmac_keys_v7
  add column if not exists key_id text,
  add column if not exists lifecycle_state text,
  add column if not exists activated_at timestamptz,
  add column if not exists retiring_at timestamptz,
  add column if not exists retiring_until timestamptz,
  add column if not exists retired_at timestamptz,
  add column if not exists last_transition_execution_id text;

-- Under the original fixed key_name primary key there can be at most one row.
-- Preserve it as the bootstrap generation when present.
update private.lf_writer_hmac_keys_v7
set key_id=coalesce(key_id,'lf-writer-2026-08-r00'),
    lifecycle_state=coalesce(
      lifecycle_state,
      case when active then 'ACTIVE' else 'RETIRED' end
    ),
    activated_at=coalesce(
      activated_at,
      case when active then created_at else coalesce(rotated_at,created_at) end
    ),
    retiring_at=coalesce(
      retiring_at,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    retiring_until=coalesce(
      retiring_until,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    retired_at=coalesce(
      retired_at,
      case when active then null else coalesce(rotated_at,created_at) end
    ),
    last_transition_execution_id=coalesce(
      last_transition_execution_id,
      installed_by_execution_id
    )
where key_id is null
   or lifecycle_state is null
   or last_transition_execution_id is null;

alter table private.lf_writer_hmac_keys_v7
  alter column key_id set not null,
  alter column lifecycle_state set not null,
  alter column last_transition_execution_id set not null;

-- Replace the fixed logical-name primary key with a public generation identifier.
do $primary_key$
declare
  v_pk_name text;
  v_pk_definition text;
begin
  select c.conname,pg_get_constraintdef(c.oid)
    into v_pk_name,v_pk_definition
  from pg_constraint c
  where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
    and c.contype='p';

  if v_pk_name is not null and v_pk_definition not like '%(key_id)%' then
    execute format(
      'alter table private.lf_writer_hmac_keys_v7 drop constraint %I',
      v_pk_name
    );
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and c.contype='p'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_pkey primary key (key_id);
  end if;
end
$primary_key$;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_key_id_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_key_id_ck
      check (key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_lifecycle_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_lifecycle_ck
      check (lifecycle_state in ('PREPARED','ACTIVE','RETIRING','RETIRED'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_active_lifecycle_ck'
  ) then
    alter table private.lf_writer_hmac_keys_v7
      add constraint lf_writer_hmac_keys_v7_active_lifecycle_ck
      check (active=(lifecycle_state='ACTIVE'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_writer_hmac_keys_v7'::regclass
      and conname='lf_writer_hmac_keys_v7_state_times_ck'
  ) then
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
          and retired_at is not null
          and retired_at>=retiring_at
        )
      );
  end if;
end
$constraints$;

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_active
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='ACTIVE';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_prepared
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='PREPARED';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_retiring
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state='RETIRING';

-- Nullable for compatibility with nonce rows created before this migration.
alter table private.lf_reconciliation_writer_nonces_v7
  add column if not exists key_id text;

do $nonce_constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='private.lf_reconciliation_writer_nonces_v7'::regclass
      and conname='lf_reconciliation_writer_nonces_v7_key_id_ck'
  ) then
    alter table private.lf_reconciliation_writer_nonces_v7
      add constraint lf_reconciliation_writer_nonces_v7_key_id_ck
      check (
        key_id is null
        or key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$'
      );
  end if;
end
$nonce_constraint$;

create or replace function private.fn_guard_lf_writer_hmac_keys_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op='DELETE' then
    raise exception using
      errcode='55000',
      message='writer keys are append-and-transition only';
  end if;

  if new.key_id is distinct from old.key_id
     or new.key_name is distinct from old.key_name
     or new.key_material is distinct from old.key_material
     or new.created_at is distinct from old.created_at
     or new.installed_by_execution_id is distinct from old.installed_by_execution_id then
    raise exception using
      errcode='55000',
      message='writer key identity and material are immutable';
  end if;

  if not (
    (old.lifecycle_state='PREPARED' and new.lifecycle_state='ACTIVE')
    or (old.lifecycle_state='ACTIVE' and new.lifecycle_state='RETIRING')
    or (old.lifecycle_state='RETIRING' and new.lifecycle_state='RETIRED')
  ) then
    raise exception using
      errcode='55000',
      message='invalid writer key lifecycle transition';
  end if;

  if new.active is distinct from (new.lifecycle_state='ACTIVE') then
    raise exception using
      errcode='55000',
      message='writer key active flag does not match lifecycle state';
  end if;

  if old.lifecycle_state='RETIRING'
     and new.lifecycle_state='RETIRED'
     and clock_timestamp()<old.retiring_until then
    raise exception using
      errcode='55000',
      message='writer key overlap window is still open';
  end if;

  return new;
end;
$function$;

alter function private.fn_guard_lf_writer_hmac_keys_v7() owner to postgres;
revoke all on function private.fn_guard_lf_writer_hmac_keys_v7()
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;

drop trigger if exists trg_guard_lf_writer_hmac_keys_v7
  on private.lf_writer_hmac_keys_v7;
create trigger trg_guard_lf_writer_hmac_keys_v7
before update or delete on private.lf_writer_hmac_keys_v7
for each row execute function private.fn_guard_lf_writer_hmac_keys_v7();

alter table private.lf_writer_hmac_keys_v7
  enable always trigger trg_guard_lf_writer_hmac_keys_v7;

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
      where k.lifecycle_state='ACTIVE'
        and k.active
        and nullif(k.key_material,'') is not null
    )
    and (
      select count(*)<=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='PREPARED'
    )
    and (
      select count(*)<=1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='RETIRING'
    )
    and not exists (
      select 1
      from private.lf_writer_hmac_keys_v7 k
      where k.lifecycle_state='RETIRING'
        and k.retiring_until<=clock_timestamp()
    );
$function$;

alter function private.fn_writer_key_ready_v7() owner to postgres;
revoke all on function private.fn_writer_key_ready_v7()
  from public,anon,authenticated;
grant execute on function private.fn_writer_key_ready_v7()
  to postgres,service_role,lf_governance_owner_v3;

create or replace function private.fn_writer_hmac_v7_match_key(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns text
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_active_count integer;
  v_key record;
  v_expected text;
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception using
      errcode='42501',
      message='writer key separation is not valid';
  end if;

  if nullif(p_preimage,'') is null
     or nullif(p_nonce,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select count(*)
    into v_active_count
  from private.lf_writer_hmac_keys_v7 k
  where k.lifecycle_state='ACTIVE'
    and k.active
    and nullif(k.key_material,'') is not null;

  if v_active_count<>1 then
    raise exception using
      errcode='55000',
      message='writer HMAC active key is not configured exactly once';
  end if;

  for v_key in
    select k.key_id,k.key_material
    from private.lf_writer_hmac_keys_v7 k
    where k.lifecycle_state='ACTIVE'
       or (
         k.lifecycle_state='RETIRING'
         and k.retiring_until>clock_timestamp()
       )
    order by case k.lifecycle_state when 'ACTIVE' then 0 else 1 end,k.created_at desc
  loop
    v_expected:=encode(
      extensions.hmac(
        convert_to(p_preimage||':'||p_nonce,'UTF8'),
        convert_to(v_key.key_material,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    if extensions.digest(convert_to(v_expected,'UTF8'),'sha256')
       = extensions.digest(convert_to(lower(p_signature),'UTF8'),'sha256') then
      return v_key.key_id;
    end if;
  end loop;

  return null;
end;
$function$;

alter function private.fn_writer_hmac_v7_match_key(text,text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_v7_match_key(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_v7_match_key(text,text,text)
  to lf_writer_verifier_v7;

create or replace function private.fn_writer_hmac_v7_valid(
  p_preimage text,
  p_nonce text,
  p_signature text
)
returns boolean
language sql
volatile
security definer
set search_path to ''
as $function$
  select private.fn_writer_hmac_v7_match_key(
    p_preimage,p_nonce,lower(p_signature)
  ) is not null;
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
  v_key_id text;
  v_rows integer:=0;
begin
  begin
    v_claims:=coalesce(
      nullif(current_setting('request.jwt.claims',true),'')::jsonb,
      '{}'::jsonb
    );
  exception
    when invalid_text_representation then
      return false;
  end;

  v_role:=coalesce(v_claims->>'role','');
  if v_role<>'service_role' then return false; end if;
  if nullif(p_preimage,'') is null
     or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  if coalesce(p_writer_nonce,'') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  begin
    v_exp:=to_timestamp(split_part(p_writer_nonce,'.',2)::bigint);
  exception
    when invalid_text_representation
      or numeric_value_out_of_range
      or datetime_field_overflow then
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

  v_key_id:=private.fn_writer_hmac_v7_match_key(
    p_preimage,p_writer_nonce,lower(p_signature)
  );
  if v_key_id is null then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,proof_scope,preimage_sha256,expires_at,request_role,key_id
  ) values (
    encode(extensions.digest(convert_to(p_writer_nonce,'UTF8'),'sha256'),'hex'),
    v_scope,
    encode(extensions.digest(convert_to(p_preimage,'UTF8'),'sha256'),'hex'),
    v_exp,
    v_role,
    v_key_id
  ) on conflict do nothing;

  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$function$;

alter function private.fn_consume_writer_proof_v7(text,text,text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_consume_writer_proof_v7(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function private.fn_consume_writer_proof_v7(text,text,text)
  to lf_governance_owner_v3;

create or replace function private.fn_install_writer_hmac_key_v7(
  p_key_id text,
  p_key_material text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if coalesce(p_key_id,'') !~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$' then
    raise exception using errcode='22023',message='invalid key_id';
  end if;
  if length(coalesce(p_key_material,''))<32 then
    raise exception using errcode='22023',message='key material is too short';
  end if;
  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  insert into private.lf_writer_hmac_keys_v7(
    key_name,key_id,key_material,active,lifecycle_state,created_at,
    installed_by_execution_id,last_transition_execution_id
  ) values (
    'lf_reconciliation_writer_hmac_v7',
    p_key_id,
    p_key_material,
    false,
    'PREPARED',
    clock_timestamp(),
    p_execution_id,
    p_execution_id
  );
end;
$function$;

alter function private.fn_install_writer_hmac_key_v7(text,text,text)
  owner to postgres;
revoke all on function private.fn_install_writer_hmac_key_v7(text,text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_install_writer_hmac_key_v7(text,text,text)
  to postgres;

create or replace function private.fn_writer_hmac_challenge_v7(
  p_key_id text,
  p_challenge text
)
returns text
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_key text;
begin
  if coalesce(p_challenge,'') !~
    '^rotation-check-v7:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode='22023',message='invalid rotation challenge';
  end if;

  select k.key_material
    into strict v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_id=p_key_id
    and k.lifecycle_state in ('PREPARED','ACTIVE','RETIRING')
    and (
      k.lifecycle_state<>'RETIRING'
      or k.retiring_until>clock_timestamp()
    );

  return encode(
    extensions.hmac(
      convert_to(p_challenge,'UTF8'),
      convert_to(v_key,'UTF8'),
      'sha256'
    ),
    'hex'
  );
end;
$function$;

alter function private.fn_writer_hmac_challenge_v7(text,text) owner to postgres;
revoke all on function private.fn_writer_hmac_challenge_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_writer_hmac_challenge_v7(text,text)
  to postgres;

create or replace function private.fn_promote_writer_hmac_key_v7(
  p_key_id text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_rows integer;
  v_now timestamptz:=clock_timestamp();
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7
    where lifecycle_state='RETIRING'
  ) then
    raise exception using
      errcode='55000',
      message='retiring writer key must be retired before another promotion';
  end if;

  update private.lf_writer_hmac_keys_v7
  set active=false,
      lifecycle_state='RETIRING',
      retiring_at=v_now,
      retiring_until=v_now+interval '10 minutes',
      last_transition_execution_id=p_execution_id
  where lifecycle_state='ACTIVE';

  update private.lf_writer_hmac_keys_v7
  set active=true,
      lifecycle_state='ACTIVE',
      activated_at=v_now,
      last_transition_execution_id=p_execution_id
  where key_id=p_key_id
    and lifecycle_state='PREPARED';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception using
      errcode='55000',
      message='exactly one prepared key must be promoted';
  end if;
end;
$function$;

alter function private.fn_promote_writer_hmac_key_v7(text,text) owner to postgres;
revoke all on function private.fn_promote_writer_hmac_key_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_promote_writer_hmac_key_v7(text,text)
  to postgres;

create or replace function private.fn_retire_writer_hmac_key_v7(
  p_key_id text,
  p_execution_id text
)
returns void
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_rows integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('lf-writer-key-rotation-v7',0));

  if nullif(p_execution_id,'') is null then
    raise exception using errcode='22023',message='execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7 k
    where k.key_id=p_key_id
      and k.lifecycle_state='RETIRING'
      and k.retiring_until>clock_timestamp()
  ) then
    raise exception using
      errcode='55000',
      message='writer key overlap window is still open';
  end if;

  if exists (
    select 1
    from private.lf_reconciliation_writer_nonces_v7 n
    where n.key_id=p_key_id
      and n.expires_at>=clock_timestamp()
  ) then
    raise exception using
      errcode='55000',
      message='unexpired nonces still reference this key';
  end if;

  update private.lf_writer_hmac_keys_v7
  set active=false,
      lifecycle_state='RETIRED',
      retired_at=clock_timestamp(),
      last_transition_execution_id=p_execution_id
  where key_id=p_key_id
    and lifecycle_state='RETIRING';

  get diagnostics v_rows=row_count;
  if v_rows<>1 then
    raise exception using
      errcode='55000',
      message='exactly one retiring key must be retired';
  end if;
end;
$function$;

alter function private.fn_retire_writer_hmac_key_v7(text,text) owner to postgres;
revoke all on function private.fn_retire_writer_hmac_key_v7(text,text)
  from public,anon,authenticated,service_role,lf_governance_owner_v3,lf_writer_verifier_v7;
grant execute on function private.fn_retire_writer_hmac_key_v7(text,text)
  to postgres;

commit;
