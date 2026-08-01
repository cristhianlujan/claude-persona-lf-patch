-- LF PR #93 / LOTE 1 / CA-N22 + CA-N23 + CA-N29
-- Versioned candidate SQL. Do not run against the live project.
-- Derived from HANDOFF_GPT_LF_PR93_LOTE1_CONSOLIDADO.md.
-- No key material is embedded in this file.

begin;

do $role_guard$
begin
  if not exists (select 1 from pg_roles where rolname = 'lf_writer_verifier_v7') then
    create role lf_writer_verifier_v7 nologin noinherit nobypassrls;
  end if;

  if exists (
    select 1
    from pg_roles
    where rolname = 'lf_writer_verifier_v7'
      and (rolcanlogin or rolinherit or rolbypassrls)
  ) then
    raise exception 'lf_writer_verifier_v7 has unsafe role attributes';
  end if;
end
$role_guard$;

alter role lf_writer_verifier_v7 nologin noinherit nobypassrls;

create table if not exists private.lf_writer_hmac_keys_v7 (
  key_id text primary key
    check (key_id ~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$'),
  key_material text not null
    check (length(key_material) >= 32),
  lifecycle_state text not null
    check (lifecycle_state in ('PREPARED','ACTIVE','RETIRING','RETIRED')),
  installed_at timestamptz not null default clock_timestamp(),
  activated_at timestamptz,
  retiring_at timestamptz,
  retired_at timestamptz,
  installed_by_execution_id text not null,
  last_transition_execution_id text not null,
  constraint lf_writer_hmac_keys_v7_state_times_ck check (
    (lifecycle_state = 'PREPARED' and activated_at is null and retiring_at is null and retired_at is null)
    or (lifecycle_state = 'ACTIVE' and activated_at is not null and retiring_at is null and retired_at is null)
    or (lifecycle_state = 'RETIRING' and activated_at is not null and retiring_at is not null and retired_at is null)
    or (lifecycle_state = 'RETIRED' and activated_at is not null and retiring_at is not null and retired_at is not null)
  )
);

alter table private.lf_writer_hmac_keys_v7 owner to lf_writer_verifier_v7;
alter table private.lf_writer_hmac_keys_v7 enable row level security;
alter table private.lf_writer_hmac_keys_v7 force row level security;

revoke all on private.lf_writer_hmac_keys_v7
  from public, anon, authenticated, service_role, lf_governance_owner_v3;

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_active
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state = 'ACTIVE';

create unique index if not exists uq_lf_writer_hmac_keys_v7_one_prepared
  on private.lf_writer_hmac_keys_v7 ((lifecycle_state))
  where lifecycle_state = 'PREPARED';

drop policy if exists pol_lf_writer_hmac_keys_v7_owner on private.lf_writer_hmac_keys_v7;
create policy pol_lf_writer_hmac_keys_v7_owner
  on private.lf_writer_hmac_keys_v7
  for all
  to lf_writer_verifier_v7
  using (current_user = 'lf_writer_verifier_v7')
  with check (current_user = 'lf_writer_verifier_v7');

create or replace function private.fn_guard_lf_writer_hmac_keys_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'writer keys are append-and-transition only';
  end if;

  if tg_op = 'UPDATE' then
    if new.key_id is distinct from old.key_id
       or new.key_material is distinct from old.key_material
       or new.installed_at is distinct from old.installed_at
       or new.installed_by_execution_id is distinct from old.installed_by_execution_id then
      raise exception using errcode = '55000', message = 'writer key identity and material are immutable';
    end if;

    if not (
      (old.lifecycle_state = 'PREPARED' and new.lifecycle_state = 'ACTIVE')
      or (old.lifecycle_state = 'ACTIVE' and new.lifecycle_state = 'RETIRING')
      or (old.lifecycle_state = 'RETIRING' and new.lifecycle_state = 'RETIRED')
    ) then
      raise exception using errcode = '55000', message = 'invalid writer key lifecycle transition';
    end if;
  end if;

  return new;
end;
$function$;

alter function private.fn_guard_lf_writer_hmac_keys_v7() owner to lf_writer_verifier_v7;
revoke all on function private.fn_guard_lf_writer_hmac_keys_v7()
  from public, anon, authenticated, service_role, lf_governance_owner_v3;

drop trigger if exists trg_guard_lf_writer_hmac_keys_v7 on private.lf_writer_hmac_keys_v7;
create trigger trg_guard_lf_writer_hmac_keys_v7
before update or delete on private.lf_writer_hmac_keys_v7
for each row execute function private.fn_guard_lf_writer_hmac_keys_v7();

alter table private.lf_writer_hmac_keys_v7
  enable always trigger trg_guard_lf_writer_hmac_keys_v7;

commit;
