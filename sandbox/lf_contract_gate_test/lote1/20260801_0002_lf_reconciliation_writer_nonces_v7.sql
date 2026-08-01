-- LF PR #93 / LOTE 1 / nonce store for the keyed writer.
-- Versioned candidate SQL. Do not run against the live project.

begin;

do $dependency_guard$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null then
    raise exception 'private.lf_writer_hmac_keys_v7 must exist first';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'lf_writer_verifier_v7') then
    raise exception 'lf_writer_verifier_v7 must exist first';
  end if;
end
$dependency_guard$;

create table if not exists private.lf_reconciliation_writer_nonces_v7 (
  nonce_sha256 text primary key
    check (nonce_sha256 ~ '^[0-9a-f]{64}$'),
  key_id text not null
    references private.lf_writer_hmac_keys_v7(key_id),
  proof_scope text not null
    check (proof_scope in ('RECONCILIATION','GATE')),
  preimage_sha256 text not null
    check (preimage_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  consumed_at timestamptz not null default clock_timestamp(),
  request_role text not null
    check (request_role = 'service_role'),
  authentication_mode text not null default 'GITHUB_OIDC_HMAC_NONCE_V7'
    check (authentication_mode = 'GITHUB_OIDC_HMAC_NONCE_V7'),
  constraint lf_reconciliation_writer_nonces_v7_ttl_ck check (
    expires_at > consumed_at - interval '5 seconds'
    and expires_at <= consumed_at + interval '10 minutes'
  )
);

alter table private.lf_reconciliation_writer_nonces_v7 owner to lf_writer_verifier_v7;
alter table private.lf_reconciliation_writer_nonces_v7 enable row level security;
alter table private.lf_reconciliation_writer_nonces_v7 force row level security;

revoke all on private.lf_reconciliation_writer_nonces_v7
  from public, anon, authenticated, service_role, lf_governance_owner_v3;

drop policy if exists pol_lf_reconciliation_writer_nonces_v7_owner
  on private.lf_reconciliation_writer_nonces_v7;
create policy pol_lf_reconciliation_writer_nonces_v7_owner
  on private.lf_reconciliation_writer_nonces_v7
  for all
  to lf_writer_verifier_v7
  using (current_user = 'lf_writer_verifier_v7')
  with check (current_user = 'lf_writer_verifier_v7');

create or replace function private.fn_guard_lf_reconciliation_writer_nonces_v7()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  raise exception using errcode = '55000', message = 'writer nonce rows are append-only';
end;
$function$;

alter function private.fn_guard_lf_reconciliation_writer_nonces_v7()
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_guard_lf_reconciliation_writer_nonces_v7()
  from public, anon, authenticated, service_role, lf_governance_owner_v3;

drop trigger if exists trg_guard_lf_reconciliation_writer_nonces_v7
  on private.lf_reconciliation_writer_nonces_v7;
create trigger trg_guard_lf_reconciliation_writer_nonces_v7
before update or delete on private.lf_reconciliation_writer_nonces_v7
for each row execute function private.fn_guard_lf_reconciliation_writer_nonces_v7();

alter table private.lf_reconciliation_writer_nonces_v7
  enable always trigger trg_guard_lf_reconciliation_writer_nonces_v7;

commit;
