-- LF PR #93 / LOTE 1 / two-phase key installation and rotation.
-- Versioned candidate SQL. Do not run against the live project.
-- Key material must be supplied out-of-band and must never be committed or logged.

begin;

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
  if coalesce(p_key_id, '') !~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$' then
    raise exception using errcode = '22023', message = 'invalid key_id';
  end if;
  if length(coalesce(p_key_material, '')) < 32 then
    raise exception using errcode = '22023', message = 'key material is too short';
  end if;
  if nullif(p_execution_id, '') is null then
    raise exception using errcode = '22023', message = 'execution id is required';
  end if;

  insert into private.lf_writer_hmac_keys_v7(
    key_id,
    key_material,
    lifecycle_state,
    installed_by_execution_id,
    last_transition_execution_id
  ) values (
    p_key_id,
    p_key_material,
    'PREPARED',
    p_execution_id,
    p_execution_id
  );
end;
$function$;

alter function private.fn_install_writer_hmac_key_v7(text, text, text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_install_writer_hmac_key_v7(text, text, text)
  from public, anon, authenticated, service_role, lf_governance_owner_v3;
grant execute on function private.fn_install_writer_hmac_key_v7(text, text, text)
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
  if coalesce(p_challenge, '') !~
    '^rotation-check-v7:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception using errcode = '22023', message = 'invalid rotation challenge';
  end if;

  select k.key_material
    into strict v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_id = p_key_id
    and k.lifecycle_state in ('PREPARED', 'ACTIVE', 'RETIRING');

  return encode(
    extensions.hmac(
      convert_to(p_challenge, 'UTF8'),
      convert_to(v_key, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
end;
$function$;

alter function private.fn_writer_hmac_challenge_v7(text, text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_writer_hmac_challenge_v7(text, text)
  from public, anon, authenticated, service_role, lf_governance_owner_v3;
grant execute on function private.fn_writer_hmac_challenge_v7(text, text)
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
begin
  if nullif(p_execution_id, '') is null then
    raise exception using errcode = '22023', message = 'execution id is required';
  end if;

  update private.lf_writer_hmac_keys_v7
  set lifecycle_state = 'RETIRING',
      retiring_at = clock_timestamp(),
      last_transition_execution_id = p_execution_id
  where lifecycle_state = 'ACTIVE';

  update private.lf_writer_hmac_keys_v7
  set lifecycle_state = 'ACTIVE',
      activated_at = clock_timestamp(),
      last_transition_execution_id = p_execution_id
  where key_id = p_key_id
    and lifecycle_state = 'PREPARED';

  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception using errcode = '55000', message = 'exactly one prepared key must be promoted';
  end if;
end;
$function$;

alter function private.fn_promote_writer_hmac_key_v7(text, text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_promote_writer_hmac_key_v7(text, text)
  from public, anon, authenticated, service_role, lf_governance_owner_v3;
grant execute on function private.fn_promote_writer_hmac_key_v7(text, text)
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
  if nullif(p_execution_id, '') is null then
    raise exception using errcode = '22023', message = 'execution id is required';
  end if;

  if exists (
    select 1
    from private.lf_reconciliation_writer_nonces_v7 n
    where n.key_id = p_key_id
      and n.expires_at >= clock_timestamp()
  ) then
    raise exception using errcode = '55000', message = 'unexpired nonces still reference this key';
  end if;

  update private.lf_writer_hmac_keys_v7
  set lifecycle_state = 'RETIRED',
      retired_at = clock_timestamp(),
      last_transition_execution_id = p_execution_id
  where key_id = p_key_id
    and lifecycle_state = 'RETIRING';

  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception using errcode = '55000', message = 'exactly one retiring key must be retired';
  end if;
end;
$function$;

alter function private.fn_retire_writer_hmac_key_v7(text, text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_retire_writer_hmac_key_v7(text, text)
  from public, anon, authenticated, service_role, lf_governance_owner_v3;
grant execute on function private.fn_retire_writer_hmac_key_v7(text, text)
  to postgres;

commit;
