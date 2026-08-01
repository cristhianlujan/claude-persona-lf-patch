-- PR #93 / LOTE 1 / conclusive tests for CA-N22 and CA-N23.
-- Isolated environment only. The transaction is always rolled back.
-- A positive control is mandatory before any negative result is interpreted.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'LOTE 1 relations are missing';
  end if;

  if exists (select 1 from private.lf_writer_hmac_keys_v7) then
    raise exception 'Refusing to run: isolated test keystore is not empty';
  end if;
end
$preflight$;

select private.fn_install_writer_hmac_key_v7(
  'lf-writer-2099-01-r99',
  'PR93_LOTE1_TEST_ONLY_HMAC_KEY_7b15d6e2_DO_NOT_REUSE',
  'PR93-LOTE1-TEST'
);
select private.fn_promote_writer_hmac_key_v7(
  'lf-writer-2099-01-r99',
  'PR93-LOTE1-TEST'
);

do $positive_and_replay$
declare
  v_preimage text := 'reconciliation-v7:PR93-POSITIVE-CONTROL';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '5 minutes'))::bigint::text;
  v_key_id text := 'lf-writer-2099-01-r99';
  v_canonical text;
  v_signature text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_canonical := v_preimage || E'\n' || v_token || E'\n' || v_key_id;
  v_signature := encode(
    extensions.hmac(
      convert_to(v_canonical, 'UTF8'),
      convert_to('PR93_LOTE1_TEST_ONLY_HMAC_KEY_7b15d6e2_DO_NOT_REUSE', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if not private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_signature
  ) then
    raise exception 'POSITIVE_CONTROL_FAILED: valid keyed proof was rejected';
  end if;

  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_signature
  ) then
    raise exception 'TEST_7_FAILED: replay was accepted';
  end if;
end
$positive_and_replay$;

do $test_8_expired$
declare
  v_preimage text := 'reconciliation-v7:PR93-EXPIRED';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() - interval '10 minutes'))::bigint::text;
  v_key_id text := 'lf-writer-2099-01-r99';
  v_signature text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_signature := encode(
    extensions.hmac(
      convert_to(v_preimage || E'\n' || v_token || E'\n' || v_key_id, 'UTF8'),
      convert_to('PR93_LOTE1_TEST_ONLY_HMAC_KEY_7b15d6e2_DO_NOT_REUSE', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_signature
  ) then
    raise exception 'TEST_8_FAILED: expired token was accepted';
  end if;
end
$test_8_expired$;

do $test_9_future$
declare
  v_preimage text := 'reconciliation-v7:PR93-FUTURE';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '1 day'))::bigint::text;
  v_key_id text := 'lf-writer-2099-01-r99';
  v_signature text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_signature := encode(
    extensions.hmac(
      convert_to(v_preimage || E'\n' || v_token || E'\n' || v_key_id, 'UTF8'),
      convert_to('PR93_LOTE1_TEST_ONLY_HMAC_KEY_7b15d6e2_DO_NOT_REUSE', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_signature
  ) then
    raise exception 'TEST_9_FAILED: token beyond the TTL was accepted';
  end if;
end
$test_9_future$;

do $test_10_bad_signature$
declare
  v_preimage text := 'reconciliation-v7:PR93-BAD-SIGNATURE';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '5 minutes'))::bigint::text;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, 'lf-writer-2099-01-r99', repeat('0', 64)
  ) then
    raise exception 'TEST_10_FAILED: invalid signature was accepted';
  end if;
end
$test_10_bad_signature$;

do $test_11_no_claims$
declare
  v_preimage text := 'reconciliation-v7:PR93-NO-CLAIMS';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '5 minutes'))::bigint::text;
  v_key_id text := 'lf-writer-2099-01-r99';
  v_signature text;
begin
  perform set_config('request.jwt.claims', '', true);
  v_signature := encode(
    extensions.hmac(
      convert_to(v_preimage || E'\n' || v_token || E'\n' || v_key_id, 'UTF8'),
      convert_to('PR93_LOTE1_TEST_ONLY_HMAC_KEY_7b15d6e2_DO_NOT_REUSE', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_signature
  ) then
    raise exception 'TEST_11_FAILED: proof without claims was accepted';
  end if;
end
$test_11_no_claims$;

do $test_12_anon$
declare
  v_preimage text := 'reconciliation-v7:PR93-ANON';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '5 minutes'))::bigint::text;
  v_key_id text := 'lf-writer-2099-01-r99';
  v_signature text;
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_signature := encode(
    extensions.hmac(
      convert_to(v_preimage || E'\n' || v_token || E'\n' || v_key_id, 'UTF8'),
      convert_to('PR93_LOTE1_TEST_ONLY_HMAC_KEY_7b15d6e2_DO_NOT_REUSE', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_signature
  ) then
    raise exception 'TEST_12_FAILED: anon proof was accepted';
  end if;
end
$test_12_anon$;

do $test_13_service_role_fabrication$
declare
  v_preimage text := 'reconciliation-v7:PR93-SERVICE-ROLE-FABRICATION';
  v_token text := gen_random_uuid()::text || '.' ||
    floor(extract(epoch from clock_timestamp() + interval '5 minutes'))::bigint::text;
  v_key_id text := 'lf-writer-2099-01-r99';
  v_fabricated_signature text;
  v_before bigint;
  v_after bigint;
begin
  if has_table_privilege('service_role', 'private.lf_writer_hmac_keys_v7', 'SELECT')
     or has_table_privilege('service_role', 'private.lf_writer_hmac_keys_v7', 'INSERT')
     or has_table_privilege('service_role', 'private.lf_writer_hmac_keys_v7', 'UPDATE') then
    raise exception 'TEST_13_FAILED: service_role can access the keystore';
  end if;

  if has_function_privilege(
       'service_role',
       'private.fn_verify_reconciliation_writer_token_v7(text,text,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'private.fn_install_writer_hmac_key_v7(text,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'private.fn_writer_hmac_challenge_v7(text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'private.fn_promote_writer_hmac_key_v7(text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'private.fn_retire_writer_hmac_key_v7(text,text)',
       'EXECUTE'
     ) then
    raise exception 'TEST_13_FAILED: service_role can execute a private writer function';
  end if;

  select count(*) into v_before
  from private.lf_reconciliation_writer_nonces_v7;

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_fabricated_signature := encode(
    extensions.hmac(
      convert_to(v_preimage || E'\n' || v_token || E'\n' || v_key_id, 'UTF8'),
      convert_to('ATTACKER_CONTROLLED_KEY_WITHOUT_DATABASE_ACCESS', 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if private.fn_verify_reconciliation_writer_token_v7(
    v_preimage, v_token, v_key_id, v_fabricated_signature
  ) then
    raise exception 'TEST_13_FAILED: service_role fabricated an accepted proof';
  end if;

  select count(*) into v_after
  from private.lf_reconciliation_writer_nonces_v7;

  if v_after <> v_before then
    raise exception 'TEST_13_FAILED: fabricated proof consumed a nonce';
  end if;
end
$test_13_service_role_fabrication$;

do $effects$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from private.lf_reconciliation_writer_nonces_v7;

  if v_count <> 1 then
    raise exception 'PERSISTED_EFFECT_CONTROL_FAILED: expected 1 nonce, found %', v_count;
  end if;
end
$effects$;

rollback;
