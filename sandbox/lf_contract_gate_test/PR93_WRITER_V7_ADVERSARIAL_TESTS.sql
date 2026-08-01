-- PR #93 — conclusive V7 writer tests for a Supabase preview branch.
-- Never run this against production. The transaction is always rolled back.
-- A positive control is mandatory before interpreting any negative result.

begin;

do $setup$
begin
  if exists (
    select 1
    from private.lf_writer_hmac_keys_v7
    where key_name='lf_reconciliation_writer_hmac_v7'
  ) then
    raise exception 'Refusing to run: preview already contains a writer key';
  end if;
end
$setup$;

insert into private.lf_writer_hmac_keys_v7(
  key_name,key_material,active,installed_by_execution_id
) values (
  'lf_reconciliation_writer_hmac_v7',
  'PR93_TEST_ONLY_HMAC_KEY_NOT_FOR_PRODUCTION_7b15d6e2',
  true,
  'PR93-STATIC-PREVIEW-TEST'
);

do $separation$
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception 'KEY_SEPARATION_FAILED: an API role can access the writer key or verifier';
  end if;
  if not private.fn_writer_key_ready_v7() then
    raise exception 'KEY_READINESS_FAILED: exactly one isolated active key was expected';
  end if;
end
$separation$;

do $positive_and_replay$
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
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'REPLAY_CONTROL_FAILED: reused nonce was accepted';
  end if;
end
$positive_and_replay$;

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
