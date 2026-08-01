-- PR #93 / active V7 writer and key-rotation adversarial tests.
-- Isolated environment only. The transaction is always rolled back.
-- A positive control is mandatory before any negative result is interpreted.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'V7 writer relations are missing';
  end if;

  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_install_writer_hmac_key_v7(text,text,text)') is null
     or to_regprocedure('private.fn_promote_writer_hmac_key_v7(text,text)') is null then
    raise exception 'V7 writer rotation functions are missing';
  end if;

  if exists (select 1 from private.lf_writer_hmac_keys_v7) then
    raise exception 'Refusing to run: isolated test keystore is not empty';
  end if;
end
$preflight$;

select private.fn_install_writer_hmac_key_v7(
  'lf-writer-2099-01-r98',
  'PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE',
  'PR93-V7-TEST-A'
);
select private.fn_promote_writer_hmac_key_v7(
  'lf-writer-2099-01-r98',
  'PR93-V7-TEST-A'
);

do $positive_and_replay$
declare
  v_preimage text:='reconciliation-v7:PR93-POSITIVE-CONTROL';
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );

  if not private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'POSITIVE_CONTROL_FAILED: valid active-key proof was rejected';
  end if;
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'TEST_7_FAILED: replayed nonce was accepted';
  end if;
end
$positive_and_replay$;

do $test_8_expired$
declare
  v_preimage text:='reconciliation-v7:PR93-EXPIRED';
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()-interval '10 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'TEST_8_FAILED: expired nonce was accepted';
  end if;
end
$test_8_expired$;

do $test_9_future$
declare
  v_preimage text:='reconciliation-v7:PR93-FUTURE';
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '1 day'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'TEST_9_FAILED: future nonce was accepted';
  end if;
end
$test_9_future$;

do $test_10_bad_signature$
declare
  v_preimage text:='reconciliation-v7:PR93-BAD-SIGNATURE';
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  if private.fn_consume_writer_proof_v7(v_preimage,repeat('0',64),v_nonce) then
    raise exception 'TEST_10_FAILED: invalid HMAC was accepted';
  end if;
end
$test_10_bad_signature$;

do $test_11_no_claims$
declare
  v_preimage text:='reconciliation-v7:PR93-NO-CLAIMS';
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'TEST_11_FAILED: proof without claims was accepted';
  end if;
end
$test_11_no_claims$;

do $test_12_anon$
declare
  v_preimage text:='reconciliation-v7:PR93-ANON';
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'TEST_12_FAILED: anon proof was accepted';
  end if;
end
$test_12_anon$;

-- Test 13 exercises the real public writer as service_role. It also proves that the
-- same role cannot read the keystore or invoke the private verifier directly.
do $test_13_service_role_fabrication$
declare
  v_artifact_id bigint;
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_payload jsonb;
  v_message text;
  v_table_denied boolean:=false;
  v_private_denied boolean:=false;
  v_public_rejected boolean:=false;
  v_nonce_before bigint;
  v_nonce_after bigint;
  v_run_before bigint;
  v_run_after bigint;
begin
  select id into v_artifact_id
  from private.lf_skill_artifacts
  order by id
  limit 1;
  if v_artifact_id is null then
    raise exception 'TEST_13_SETUP_FAILED: no artifact exists';
  end if;

  select count(*) into v_nonce_before
  from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_run_before
  from private.lf_github_reconciliation_runs_v3;

  v_payload:=jsonb_build_object(
    'artifact_id',v_artifact_id,
    'workflow_run_id',9876543210::bigint,
    'merge_commit_sha',repeat('a',40),
    'audit_manifest_sha256',repeat('b',64),
    'result','FAIL'
  );

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';

  begin
    perform key_material
    from private.lf_writer_hmac_keys_v7
    limit 1;
  exception
    when insufficient_privilege then
      v_table_denied:=true;
  end;

  begin
    perform private.fn_consume_writer_proof_v7(
      'reconciliation-v7:PR93-DIRECT-PRIVATE',repeat('0',64),v_nonce
    );
  exception
    when insufficient_privilege then
      v_private_denied:=true;
  end;

  begin
    perform public.record_external_ci_verification_v7(
      v_payload,
      'PR93-SERVICE-ROLE-FABRICATION',
      repeat('0',64),
      v_nonce
    );
  exception
    when insufficient_privilege then
      get stacked diagnostics v_message=message_text;
      if v_message='OIDC HMAC nonce reconciliation writer failed' then
        v_public_rejected:=true;
      else
        raise exception 'TEST_13_FAILED: public writer failed for the wrong reason: %',v_message;
      end if;
  end;

  execute 'reset role';

  if not v_table_denied then
    raise exception 'TEST_13_FAILED: service_role read the keystore';
  end if;
  if not v_private_denied then
    raise exception 'TEST_13_FAILED: service_role executed the private verifier';
  end if;
  if not v_public_rejected then
    raise exception 'TEST_13_FAILED: fabricated public-writer proof was not rejected';
  end if;

  select count(*) into v_nonce_after
  from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_run_after
  from private.lf_github_reconciliation_runs_v3;

  if v_nonce_after<>v_nonce_before or v_run_after<>v_run_before then
    raise exception 'TEST_13_FAILED: fabricated proof changed persisted evidence';
  end if;
end
$test_13_service_role_fabrication$;

-- Rotation control: the old key remains accepted only during the overlap window,
-- while the new active key is accepted immediately. The signed message is unchanged.
select private.fn_install_writer_hmac_key_v7(
  'lf-writer-2099-01-r99',
  'PR93_TEST_ONLY_HMAC_KEY_B_2d8e61b7_DO_NOT_REUSE',
  'PR93-V7-TEST-B'
);

do $challenge$
declare
  v_challenge text:='rotation-check-v7:'||gen_random_uuid()::text;
  v_expected text;
  v_observed text;
begin
  v_expected:=encode(
    extensions.hmac(
      convert_to(v_challenge,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_B_2d8e61b7_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );
  v_observed:=private.fn_writer_hmac_challenge_v7(
    'lf-writer-2099-01-r99',v_challenge
  );
  if v_observed is distinct from v_expected then
    raise exception 'ROTATION_CHALLENGE_FAILED: prepared key differs';
  end if;
end
$challenge$;

select private.fn_promote_writer_hmac_key_v7(
  'lf-writer-2099-01-r99',
  'PR93-V7-TEST-B'
);

do $dual_acceptance$
declare
  v_old_preimage text:='reconciliation-v7:PR93-RETIRING-KEY';
  v_new_preimage text:='reconciliation-v7:PR93-ACTIVE-KEY';
  v_old_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_new_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_old_signature text;
  v_new_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_old_signature:=encode(
    extensions.hmac(
      convert_to(v_old_preimage||':'||v_old_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );
  v_new_signature:=encode(
    extensions.hmac(
      convert_to(v_new_preimage||':'||v_new_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_B_2d8e61b7_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );

  if not private.fn_consume_writer_proof_v7(
    v_old_preimage,v_old_signature,v_old_nonce
  ) then
    raise exception 'ROTATION_FAILED: retiring key was rejected inside overlap';
  end if;
  if not private.fn_consume_writer_proof_v7(
    v_new_preimage,v_new_signature,v_new_nonce
  ) then
    raise exception 'ROTATION_FAILED: new active key was rejected';
  end if;
end
$dual_acceptance$;

do $effects$
declare
  v_count bigint;
  v_old_count bigint;
  v_new_count bigint;
begin
  select count(*) into v_count
  from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_old_count
  from private.lf_reconciliation_writer_nonces_v7
  where key_id='lf-writer-2099-01-r98';
  select count(*) into v_new_count
  from private.lf_reconciliation_writer_nonces_v7
  where key_id='lf-writer-2099-01-r99';

  if v_count<>3 or v_old_count<>2 or v_new_count<>1 then
    raise exception
      'PERSISTED_EFFECT_CONTROL_FAILED: total %, old %, new %',
      v_count,v_old_count,v_new_count;
  end if;

  if not private.fn_writer_key_ready_v7() then
    raise exception 'KEY_READINESS_FAILED: rotation state is not ready';
  end if;
end
$effects$;

rollback;
