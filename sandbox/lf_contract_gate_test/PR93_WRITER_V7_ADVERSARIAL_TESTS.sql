-- PR #93 / active V7 writer, canonicalization and key-rotation adversarial tests.
-- Isolated environment only. The transaction is always rolled back.
-- A private-verifier positive control and a public-writer positive control are both
-- mandatory before any negative result is interpreted.

begin;

do $preflight$
begin
  if to_regclass('private.lf_writer_hmac_keys_v7') is null
     or to_regclass('private.lf_reconciliation_writer_nonces_v7') is null then
    raise exception 'V7 writer relations are missing';
  end if;

  if to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_install_writer_hmac_key_v7(text,text,text)') is null
     or to_regprocedure('private.fn_promote_writer_hmac_key_v7(text,text)') is null
     or to_regprocedure('private.fn_reconciliation_preimage_v7(jsonb,text)') is null
     or to_regprocedure('private.fn_gate_preimage_v7(jsonb,text)') is null then
    raise exception 'V7 writer hardening functions are missing';
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

-- CA-N30: fixed-position components must not collapse when adjacent fields are NULL.
do $canonicalization$
declare
  v_left text;
  v_right text;
  v_gate text;
begin
  v_left:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object(
      'artifact_id',1,
      'workflow_run_id',2,
      'merge_commit_sha',repeat('a',40),
      'artifact_sha256',null,
      'branch_protection_status','VERIFIED',
      'result','FAIL',
      'audit_manifest_sha256',repeat('b',64)
    ),
    'PR93-CANON'
  );

  v_right:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object(
      'artifact_id',1,
      'workflow_run_id',2,
      'merge_commit_sha',repeat('a',40),
      'artifact_sha256','VERIFIED',
      'branch_protection_status',null,
      'result','FAIL',
      'audit_manifest_sha256',repeat('b',64)
    ),
    'PR93-CANON'
  );

  if v_left=v_right then
    raise exception 'CANONICALIZATION_FAILED: distinct payload positions collapsed';
  end if;

  if v_left not like 'reconciliation-v7:PR93-CANON:1:2:%::VERIFIED:FAIL:%' then
    raise exception 'CANONICALIZATION_FAILED: empty component separator was not preserved';
  end if;

  v_gate:=private.fn_gate_preimage_v7(
    jsonb_build_object(
      'artifact_id',1,
      'test_code','T',
      'source_workflow_run_id',2,
      'source_commit_sha',repeat('c',40),
      'passed',false,
      'target_relation','x',
      'gate_code','G',
      'probe_preimage',jsonb_build_object('expected_sha256',null),
      'observed_outcome',jsonb_build_object('artifact_sha256',null,'audit_covered',false),
      'persisted_effects',jsonb_build_object('github_reconciliation_run_id',null)
    ),
    'PR93-CANON'
  );

  if v_gate not like 'gate-v7:PR93-CANON:1:T:2:%:false:x:G:::false:' then
    raise exception 'CANONICALIZATION_FAILED: gate primitive representation differs';
  end if;
end
$canonicalization$;

-- Positive control and replay.
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

-- Public writer positive control. This catches an always-rejecting writer before test 13.
do $public_writer_positive$
declare
  v_artifact_id bigint;
  v_artifact_path text;
  v_payload jsonb;
  v_preimage text;
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint::text;
  v_signature text;
  v_run_id bigint;
begin
  select id,relative_path
    into v_artifact_id,v_artifact_path
  from private.lf_skill_artifacts
  order by id
  limit 1;

  if v_artifact_id is null then
    raise exception 'PUBLIC_POSITIVE_SETUP_FAILED: no artifact exists';
  end if;

  v_payload:=jsonb_build_object(
    'result','FAIL',
    'artifact_id',v_artifact_id,
    'repository','cristhianlujan/claude-persona-lf-patch',
    'target_branch','main',
    'artifact_path',v_artifact_path,
    'pr_number',999999,
    'pr_state','MERGED',
    'merged',true,
    'merge_commit_sha',repeat('c',40),
    'workflow_run_id',900000000000000001::bigint,
    'workflow_name','lf-contract-check',
    'workflow_event','push',
    'workflow_head_sha',repeat('c',40),
    'workflow_conclusion','success',
    'artifact_git_blob',null,
    'artifact_sha256',null,
    'file_touched_by_merge',false,
    'artifact_exercised_by_workflow',false,
    'audit_artifact_name','PR93_TEST_ONLY',
    'audit_manifest_sha256',repeat('d',64),
    'branch_protection_status','VERIFIED_COMPENSATING_CONTROLS',
    'failure_reasons',jsonb_build_array('PR93_TEST_ONLY'),
    'details',jsonb_build_object('actual_branch_protection_status','NOT_CONFIGURED'),
    'observed_at',clock_timestamp()
  );

  v_preimage:=private.fn_reconciliation_preimage_v7(v_payload,'PR93-PUBLIC-POSITIVE');
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
    execute 'set local role service_role';
    v_run_id:=public.record_external_ci_verification_v7(
      v_payload,'PR93-PUBLIC-POSITIVE',v_signature,v_nonce
    );
    execute 'reset role';
  exception
    when others then
      execute 'reset role';
      raise;
  end;

  if v_run_id is null then
    raise exception 'PUBLIC_POSITIVE_CONTROL_FAILED: writer returned no reconciliation';
  end if;
end
$public_writer_positive$;

-- A valid HMAC with an expired nonce proves the public writer reaches nonce freshness
-- and distinguishes that guard from the fabricated-signature test.
do $public_writer_expired$
declare
  v_artifact_id bigint;
  v_artifact_path text;
  v_payload jsonb;
  v_preimage text;
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()-interval '10 minutes'))::bigint::text;
  v_signature text;
  v_rejected boolean:=false;
  v_nonce_before bigint;
  v_run_before bigint;
  v_event_before bigint;
begin
  select id,relative_path
    into v_artifact_id,v_artifact_path
  from private.lf_skill_artifacts
  order by id
  limit 1;

  v_payload:=jsonb_build_object(
    'result','FAIL',
    'artifact_id',v_artifact_id,
    'repository','cristhianlujan/claude-persona-lf-patch',
    'target_branch','main',
    'artifact_path',v_artifact_path,
    'pr_number',999999,
    'pr_state','MERGED',
    'merged',true,
    'merge_commit_sha',repeat('e',40),
    'workflow_run_id',900000000000000002::bigint,
    'workflow_name','lf-contract-check',
    'workflow_event','push',
    'workflow_head_sha',repeat('e',40),
    'workflow_conclusion','success',
    'artifact_git_blob',null,
    'artifact_sha256',null,
    'file_touched_by_merge',false,
    'artifact_exercised_by_workflow',false,
    'audit_artifact_name','PR93_TEST_ONLY',
    'audit_manifest_sha256',repeat('f',64),
    'branch_protection_status','VERIFIED_COMPENSATING_CONTROLS',
    'failure_reasons',jsonb_build_array('PR93_TEST_ONLY'),
    'details',jsonb_build_object('actual_branch_protection_status','NOT_CONFIGURED'),
    'observed_at',clock_timestamp()
  );

  v_preimage:=private.fn_reconciliation_preimage_v7(v_payload,'PR93-PUBLIC-EXPIRED');
  v_signature:=encode(
    extensions.hmac(
      convert_to(v_preimage||':'||v_nonce,'UTF8'),
      convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
      'sha256'
    ),
    'hex'
  );

  select count(*) into v_nonce_before from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_run_before from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_event_before from public.lf_eventos;

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
    execute 'set local role service_role';
    begin
      perform public.record_external_ci_verification_v7(
        v_payload,'PR93-PUBLIC-EXPIRED',v_signature,v_nonce
      );
    exception
      when insufficient_privilege then
        if sqlerrm='OIDC HMAC nonce reconciliation writer failed' then
          v_rejected:=true;
        else
          raise;
        end if;
    end;
    execute 'reset role';
  exception
    when others then
      execute 'reset role';
      raise;
  end;

  if not v_rejected then
    raise exception 'PUBLIC_EXPIRED_FAILED: expired valid proof was not rejected';
  end if;
  if (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonce_before
     or (select count(*) from private.lf_github_reconciliation_runs_v3)<>v_run_before
     or (select count(*) from public.lf_eventos)<>v_event_before then
    raise exception 'PUBLIC_EXPIRED_FAILED: rejected proof changed persisted evidence';
  end if;
end
$public_writer_expired$;

-- Test 13 exercises the real public writer as service_role and guarantees RESET ROLE.
do $test_13_service_role_fabrication$
declare
  v_artifact_id bigint;
  v_artifact_path text;
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
  v_event_before bigint;
  v_event_after bigint;
begin
  select id,relative_path
    into v_artifact_id,v_artifact_path
  from private.lf_skill_artifacts
  order by id
  limit 1;
  if v_artifact_id is null then
    raise exception 'TEST_13_SETUP_FAILED: no artifact exists';
  end if;

  v_payload:=jsonb_build_object(
    'result','FAIL',
    'artifact_id',v_artifact_id,
    'repository','cristhianlujan/claude-persona-lf-patch',
    'target_branch','main',
    'artifact_path',v_artifact_path,
    'pr_number',999999,
    'pr_state','MERGED',
    'merged',true,
    'merge_commit_sha',repeat('1',40),
    'workflow_run_id',900000000000000003::bigint,
    'workflow_name','lf-contract-check',
    'workflow_event','push',
    'workflow_head_sha',repeat('1',40),
    'workflow_conclusion','success',
    'artifact_git_blob',null,
    'artifact_sha256',null,
    'file_touched_by_merge',false,
    'artifact_exercised_by_workflow',false,
    'audit_artifact_name','PR93_TEST_ONLY',
    'audit_manifest_sha256',repeat('2',64),
    'branch_protection_status','VERIFIED_COMPENSATING_CONTROLS',
    'failure_reasons',jsonb_build_array('PR93_TEST_ONLY'),
    'details',jsonb_build_object('actual_branch_protection_status','NOT_CONFIGURED'),
    'observed_at',clock_timestamp()
  );

  select count(*) into v_nonce_before from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_run_before from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_event_before from public.lf_eventos;

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
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
  exception
    when others then
      execute 'reset role';
      raise;
  end;

  if not v_table_denied then
    raise exception 'TEST_13_FAILED: service_role read the keystore';
  end if;
  if not v_private_denied then
    raise exception 'TEST_13_FAILED: service_role executed the private verifier';
  end if;
  if not v_public_rejected then
    raise exception 'TEST_13_FAILED: fabricated public-writer proof was not rejected';
  end if;

  select count(*) into v_nonce_after from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_run_after from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_event_after from public.lf_eventos;

  if v_nonce_after<>v_nonce_before
     or v_run_after<>v_run_before
     or v_event_after<>v_event_before then
    raise exception 'TEST_13_FAILED: fabricated proof changed persisted evidence';
  end if;
end
$test_13_service_role_fabrication$;

-- Rotation control.
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
  v_test_count bigint;
  v_old_count bigint;
  v_new_count bigint;
  v_status text;
begin
  select count(*) into v_test_count
  from private.lf_reconciliation_writer_nonces_v7
  where key_id in ('lf-writer-2099-01-r98','lf-writer-2099-01-r99');
  select count(*) into v_old_count
  from private.lf_reconciliation_writer_nonces_v7
  where key_id='lf-writer-2099-01-r98';
  select count(*) into v_new_count
  from private.lf_reconciliation_writer_nonces_v7
  where key_id='lf-writer-2099-01-r99';

  if v_test_count<>4 or v_old_count<>3 or v_new_count<>1 then
    raise exception
      'PERSISTED_EFFECT_CONTROL_FAILED: test total %, old %, new %',
      v_test_count,v_old_count,v_new_count;
  end if;

  if not private.fn_writer_key_ready_v7() then
    raise exception 'KEY_READINESS_FAILED: rotation state is not ready';
  end if;

  v_status:=private.fn_writer_key_rotation_status_v7();
  if v_status<>'OVERLAP_ACTIVE' then
    raise exception 'KEY_STATUS_FAILED: expected OVERLAP_ACTIVE, observed %',v_status;
  end if;
end
$effects$;

rollback;
