-- PR #93 — conclusive V7 writer tests for a Supabase preview branch.
-- Never run this against production. All test state is rolled back.
-- A positive control is mandatory before interpreting negative controls.

begin;

-- The preview branch must not contain a production writer secret.
do $setup$
begin
  if exists (
    select 1 from vault.secrets where name='lf_reconciliation_writer_hmac_v7'
  ) then
    raise exception 'Refusing to run: preview test found a pre-existing writer secret';
  end if;
end
$setup$;

select vault.create_secret(
  'PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2',
  'lf_reconciliation_writer_hmac_v7',
  'Transaction-scoped PR93 adversarial test secret; rolled back at end'
);

-- 1. Positive control: a correct HMAC, fresh nonce and service_role claims must work.
do $positive$
declare
  v_preimage text:='reconciliation-v7:PR93-POSITIVE-CONTROL';
  v_nonce text:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if not private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'POSITIVE_CONTROL_FAILED: valid V7 proof was rejected';
  end if;

  -- 2. Replay of exactly the same nonce must fail.
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'REPLAY_CONTROL_FAILED: reused nonce was accepted';
  end if;
end
$positive$;

-- 3. Expired nonce must fail.
do $expired$
declare
  v_preimage text:='reconciliation-v7:PR93-EXPIRED';
  v_nonce text:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()-interval '10 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'EXPIRY_CONTROL_FAILED: expired nonce was accepted';
  end if;
end
$expired$;

-- 4. Excessively future-dated nonce must fail.
do $future$
declare
  v_preimage text:='reconciliation-v7:PR93-FUTURE';
  v_nonce text:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '1 day'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'FUTURE_CONTROL_FAILED: future nonce was accepted';
  end if;
end
$future$;

-- 5. Incorrect HMAC must fail even with service_role claims.
do $bad_signature$
declare
  v_preimage text:='reconciliation-v7:PR93-BAD-SIGNATURE';
  v_nonce text:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  if private.fn_consume_writer_proof_v7(v_preimage,repeat('0',64),v_nonce) then
    raise exception 'SIGNATURE_CONTROL_FAILED: invalid HMAC was accepted';
  end if;
end
$bad_signature$;

-- 6. Missing JWT request context must fail even with a correct HMAC.
do $no_claims$
declare
  v_preimage text:='reconciliation-v7:PR93-NO-CLAIMS';
  v_nonce text:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'JWT_CONTROL_FAILED: proof without claims was accepted';
  end if;
end
$no_claims$;

-- 7. anon claims must fail even with a correct HMAC.
do $anon_claims$
declare
  v_preimage text:='reconciliation-v7:PR93-ANON-CLAIMS';
  v_nonce text:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'ROLE_CONTROL_FAILED: anon proof was accepted';
  end if;
end
$anon_claims$;

-- Only the positive control may have consumed a nonce.
do $effects$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from private.lf_reconciliation_writer_nonces_v7;
  if v_count<>1 then
    raise exception 'PERSISTED_EFFECT_CONTROL_FAILED: expected 1 consumed nonce, found %',v_count;
  end if;
end
$effects$;

rollback;
