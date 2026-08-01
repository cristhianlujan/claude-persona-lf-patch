-- LF PR #93 / LOTE 1 / keyed HMAC verifier with single-use nonce.
-- Versioned candidate SQL. Do not run against the live project.
-- Infrastructure failures are not converted to false.

begin;

do $dependency_guard$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'LOTE 1 key and nonce relations must exist first';
  end if;
end
$dependency_guard$;

create or replace function private.fn_verify_reconciliation_writer_token_v7(
  p_preimage text,
  p_writer_token text,
  p_key_id text,
  p_signature text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_claims jsonb := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
  v_request_role text := coalesce(v_claims ->> 'role', '');
  v_expires_at timestamptz;
  v_scope text;
  v_key text;
  v_canonical text;
  v_expected text;
  v_rows integer := 0;
begin
  if v_request_role <> 'service_role' then
    return false;
  end if;

  if coalesce(p_signature, '') !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  if coalesce(p_writer_token, '') !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9]{10}$' then
    return false;
  end if;

  if coalesce(p_key_id, '') !~ '^lf-writer-[0-9]{4}-[0-9]{2}-r[0-9]{2,}$' then
    return false;
  end if;

  if p_preimage like 'reconciliation-v7:%' then
    v_scope := 'RECONCILIATION';
  elsif p_preimage like 'gate-v7:%' then
    v_scope := 'GATE';
  else
    return false;
  end if;

  v_expires_at := to_timestamp(split_part(p_writer_token, '.', 2)::bigint);
  if v_expires_at <= clock_timestamp() - interval '5 seconds'
     or v_expires_at > clock_timestamp() + interval '10 minutes' then
    return false;
  end if;

  select k.key_material
    into strict v_key
  from private.lf_writer_hmac_keys_v7 k
  where k.key_id = p_key_id
    and k.lifecycle_state in ('ACTIVE', 'RETIRING');

  v_canonical := p_preimage || E'\n' || p_writer_token || E'\n' || p_key_id;
  v_expected := encode(
    extensions.hmac(
      convert_to(v_canonical, 'UTF8'),
      convert_to(v_key, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if extensions.digest(convert_to(v_expected, 'UTF8'), 'sha256')
     <> extensions.digest(convert_to(lower(p_signature), 'UTF8'), 'sha256') then
    return false;
  end if;

  insert into private.lf_reconciliation_writer_nonces_v7(
    nonce_sha256,
    key_id,
    proof_scope,
    preimage_sha256,
    expires_at,
    request_role
  ) values (
    encode(extensions.digest(convert_to(p_writer_token, 'UTF8'), 'sha256'), 'hex'),
    p_key_id,
    v_scope,
    encode(extensions.digest(convert_to(p_preimage, 'UTF8'), 'sha256'), 'hex'),
    v_expires_at,
    v_request_role
  ) on conflict do nothing;

  get diagnostics v_rows = row_count;
  return v_rows = 1;
end;
$function$;

alter function private.fn_verify_reconciliation_writer_token_v7(text, text, text, text)
  owner to lf_writer_verifier_v7;
revoke all on function private.fn_verify_reconciliation_writer_token_v7(text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function private.fn_verify_reconciliation_writer_token_v7(text, text, text, text)
  to lf_governance_owner_v3;

commit;
