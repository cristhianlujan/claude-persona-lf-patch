-- PR #93 V7 writer adversarial tests after LOTE-C.
-- Isolated environment only. The transaction always rolls back.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_reconciliation_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null then
    raise exception 'LOTE-C V7 functions are missing';
  end if;
  if exists(select 1 from private.lf_writer_hmac_keys_v7) then
    raise exception 'isolated test keystore must be empty';
  end if;
end
$preflight$;

select private.fn_install_writer_hmac_key_v7(
  'lf-writer-2099-01-r98',
  'PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE',
  'PR93-LOTE-C'
);
select private.fn_promote_writer_hmac_key_v7(
  'lf-writer-2099-01-r98','PR93-LOTE-C'
);

-- Parser vectors, including malformed framing boundaries.
do $parser_vectors$
declare
  v_valid text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','parser','n',1),'PR93-PARSER'
  );
  v_hash text:=repeat('a',64);
begin
  if private.fn_writer_preimage_scope_v7(v_valid)<>'RECONCILIATION' then
    raise exception 'valid framed reconciliation was rejected';
  end if;
  if private.fn_writer_preimage_scope_v7(
       private.fn_gate_preimage_v7(jsonb_build_object('case','gate'),'PR93-PARSER')
     )<>'GATE' then
    raise exception 'valid framed gate was rejected';
  end if;
  if private.fn_writer_preimage_scope_v7('reconciliation-v7:legacy') is not null
     or private.fn_writer_preimage_scope_v7('017#reconciliation-v7') is not null
     or private.fn_writer_preimage_scope_v7('-1#x') is not null
     or private.fn_writer_preimage_scope_v7('1048577#x') is not null
     or private.fn_writer_preimage_scope_v7('17#reconciliation-v7') is not null
     or private.fn_writer_preimage_scope_v7(
          '17#reconciliation-v70#64#'||v_hash
        ) is not null
     or private.fn_writer_preimage_scope_v7(
          '17#reconciliation-v71#x63#'||repeat('a',63)
        ) is not null
     or private.fn_writer_preimage_scope_v7(
          '17#reconciliation-v71#x64#'||upper(v_hash)
        ) is not null
     or private.fn_writer_preimage_scope_v7(
          '13#unknown-scope1#x64#'||v_hash
        ) is not null
     or private.fn_writer_preimage_scope_v7(
          '7#gate-v7-extra1#x64#'||v_hash
        ) is not null then
    raise exception 'malformed parser vector was accepted';
  end if;
end
$parser_vectors$;

-- Unsafe numbers must fail before HMAC and leave all evidence tables unchanged.
do $unsafe_numeric$
declare
  v_nonces bigint; v_runs bigint; v_gates bigint; v_events bigint;
  v_rejected boolean:=false;
begin
  select count(*) into v_nonces from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_runs from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_gates from private.lf_gate_test_runs_v3;
  select count(*) into v_events from public.lf_eventos;
  begin
    perform private.fn_reconciliation_preimage_v7(
      jsonb_build_object('workflow_run_id',9007199254740992::numeric),
      'PR93-UNSAFE-NUMBER'
    );
  exception when sqlstate '22023' then
    v_rejected:=true;
  end;
  if not v_rejected
     or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonces
     or (select count(*) from private.lf_github_reconciliation_runs_v3)<>v_runs
     or (select count(*) from private.lf_gate_test_runs_v3)<>v_gates
     or (select count(*) from public.lf_eventos)<>v_events then
    raise exception 'unsafe integer was not rejected before evidence effects';
  end if;
end
$unsafe_numeric$;

-- Positive direct consumption and replay protection with the active key.
do $positive_replay$
declare
  v_preimage text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','positive-replay'),'PR93-POSITIVE-REPLAY'
  );
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature text;
begin
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),
    'sha256'
  ),'hex');
  if not private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'valid active-key proof was rejected';
  end if;
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'replayed nonce was accepted';
  end if;
end
$positive_replay$;

-- Expired, future, invalid-signature, no-claims and anon proofs are fail-closed.
do $negative_proofs$
declare
  v_preimage text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','negative-proofs'),'PR93-NEGATIVE'
  );
  v_nonce text; v_signature text;
  v_nonces bigint; v_runs bigint; v_gates bigint; v_events bigint;
begin
  select count(*) into v_nonces from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_runs from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_gates from private.lf_gate_test_runs_v3;
  select count(*) into v_events from public.lf_eventos;

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()-interval '10 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'expired nonce was accepted';
  end if;

  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '1 day'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'future nonce was accepted';
  end if;

  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  if private.fn_consume_writer_proof_v7(v_preimage,repeat('0',64),v_nonce) then
    raise exception 'invalid signature was accepted';
  end if;

  perform set_config('request.jwt.claims','',true);
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'proof without claims was accepted';
  end if;

  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce) then
    raise exception 'anon proof was accepted';
  end if;

  if (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonces
     or (select count(*) from private.lf_github_reconciliation_runs_v3)<>v_runs
     or (select count(*) from private.lf_gate_test_runs_v3)<>v_gates
     or (select count(*) from public.lf_eventos)<>v_events then
    raise exception 'negative proof changed evidence state';
  end if;
end
$negative_proofs$;

-- Public reconciliation writer, exact nonce binding and idempotent retry.
do $reconciliation_path$
declare
  v_artifact_id bigint; v_path text; v_payload jsonb; v_mutated jsonb;
  v_preimage text; v_nonce text; v_signature text;
  v_run bigint; v_retry bigint;
  v_nonces bigint; v_runs bigint; v_gates bigint; v_events bigint;
  v_rejected boolean:=false;
begin
  select id,relative_path into v_artifact_id,v_path
  from private.lf_skill_artifacts order by id limit 1;
  if v_artifact_id is null then raise exception 'no artifact exists'; end if;

  v_payload:=jsonb_build_object(
    'result','FAIL','artifact_id',v_artifact_id,
    'repository','cristhianlujan/claude-persona-lf-patch','target_branch','main',
    'artifact_path',v_path,'pr_number',999999,'pr_state','MERGED','merged',true,
    'merge_commit_sha',repeat('a',40),'workflow_run_id',9000000000000101::bigint,
    'workflow_name','lf-contract-check','workflow_event','push',
    'workflow_head_sha',repeat('a',40),'workflow_conclusion','success',
    'artifact_git_blob',null,'artifact_sha256',null,'file_touched_by_merge',false,
    'artifact_exercised_by_workflow',false,'audit_artifact_name','PR93_TEST_ONLY',
    'audit_manifest_sha256',repeat('b',64),
    'branch_protection_status','VERIFIED_COMPENSATING_CONTROLS',
    'failure_reasons',jsonb_build_array('PR93_TEST_ONLY'),
    'details',jsonb_build_object('actual_branch_protection_status','NOT_CONFIGURED'),
    'observed_at',clock_timestamp()
  );
  v_preimage:=private.fn_reconciliation_preimage_v7(v_payload,'PR93-REAL-PATH');
  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
    execute 'set local role service_role';
    v_run:=public.record_external_ci_verification_v7(
      v_payload,'PR93-REAL-PATH',v_signature,v_nonce
    );
    execute 'reset role';
  exception when others then execute 'reset role'; raise;
  end;
  if not private.fn_reconciliation_nonce_v7_valid(v_run) then
    raise exception 'reconciliation nonce binding failed';
  end if;

  select count(*) into v_nonces from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_runs from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_gates from private.lf_gate_test_runs_v3;
  select count(*) into v_events from public.lf_eventos;
  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  begin
    execute 'set local role service_role';
    v_retry:=public.record_external_ci_verification_v7(
      v_payload,'PR93-REAL-PATH',v_signature,v_nonce
    );
    execute 'reset role';
  exception when others then execute 'reset role'; raise;
  end;
  if v_retry<>v_run
     or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonces+1
     or (select count(*) from private.lf_github_reconciliation_runs_v3)<>v_runs
     or (select count(*) from private.lf_gate_test_runs_v3)<>v_gates
     or (select count(*) from public.lf_eventos)<>v_events then
    raise exception 'reconciliation idempotent retry was not exact';
  end if;

  -- Fresh proof for the original payload, then mutate the payload before the RPC.
  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  v_mutated:=jsonb_set(v_payload,'{artifact_path}',to_jsonb(v_path||':mutated'));
  select count(*) into v_nonces from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_runs from private.lf_github_reconciliation_runs_v3;
  select count(*) into v_events from public.lf_eventos;
  begin
    execute 'set local role service_role';
    perform public.record_external_ci_verification_v7(
      v_mutated,'PR93-REAL-PATH',v_signature,v_nonce
    );
  exception when insufficient_privilege then v_rejected:=true;
  end;
  execute 'reset role';
  if not v_rejected
     or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonces
     or (select count(*) from private.lf_github_reconciliation_runs_v3)<>v_runs
     or (select count(*) from public.lf_eventos)<>v_events then
    raise exception 'post-signature reconciliation mutation was not fail-closed';
  end if;
end
$reconciliation_path$;

-- Public gate writer, private nonce anchoring, event cross-check and idempotence.
do $gate_path$
declare
  v_artifact_id bigint; v_path text; v_run bigint; v_payload jsonb;
  v_preimage text; v_nonce text; v_signature text;
  v_gate bigint; v_retry bigint; v_nonces bigint; v_gates bigint; v_events bigint;
begin
  select id,relative_path into v_artifact_id,v_path
  from private.lf_skill_artifacts order by id limit 1;
  select id into v_run
  from private.lf_github_reconciliation_runs_v3
  where artifact_id=v_artifact_id
    and workflow_run_id=9000000000000101::bigint
    and merge_commit_sha=repeat('a',40)
    and writer_authentication='GITHUB_OIDC_HMAC_NONCE_V7';
  if v_run is null then raise exception 'test reconciliation missing'; end if;

  v_payload:=jsonb_build_object(
    'test_code','PR93-LOTE-C','artifact_id',v_artifact_id,
    'gate_code','EXTERNAL-CI-V3','test_kind','INTEGRATION','target_relation',v_path,
    'probe_preimage',jsonb_build_object('expected_sha256',repeat('c',64)),
    'expected_outcome',jsonb_build_object('result','FAIL'),
    'observed_outcome',jsonb_build_object('artifact_sha256',null,'audit_covered',false),
    'persisted_effects',jsonb_build_object('rows',1,'github_reconciliation_run_id',v_run),
    'passed',false,'runner_type','EXTERNAL_INDEPENDENT','runner_identity','PR93_TEST',
    'source_workflow_run_id',9000000000000101::bigint,
    'source_commit_sha',repeat('a',40),'executed_at',clock_timestamp()
  );
  v_preimage:=private.fn_gate_preimage_v7(v_payload,'PR93-REAL-GATE');
  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  begin
    execute 'set local role service_role';
    v_gate:=public.record_lf_gate_test_v7(
      v_payload,'PR93-REAL-GATE',v_signature,v_nonce
    );
    execute 'reset role';
  exception when others then execute 'reset role'; raise;
  end;
  if not private.fn_gate_nonce_v7_valid(v_gate)
     or coalesce((select persisted_effects->>'writer_nonce_sha256'
                  from private.lf_gate_test_runs_v3 where id=v_gate),'') !~ '^[0-9a-f]{64}$'
     or (select persisted_effects->>'writer_nonce_sha256'
         from private.lf_gate_test_runs_v3 where id=v_gate)
        is distinct from
        (select e.payload->>'writer_nonce_sha256'
         from private.lf_gate_test_runs_v3 t
         join public.lf_eventos e on e.id=t.evidence_event_id
         where t.id=v_gate) then
    raise exception 'gate nonce binding was not anchored in the private row';
  end if;

  select count(*) into v_nonces from private.lf_reconciliation_writer_nonces_v7;
  select count(*) into v_gates from private.lf_gate_test_runs_v3;
  select count(*) into v_events from public.lf_eventos;
  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  begin
    execute 'set local role service_role';
    v_retry:=public.record_lf_gate_test_v7(
      v_payload,'PR93-REAL-GATE',v_signature,v_nonce
    );
    execute 'reset role';
  exception when others then execute 'reset role'; raise;
  end;
  if v_retry<>v_gate
     or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonces+1
     or (select count(*) from private.lf_gate_test_runs_v3)<>v_gates
     or (select count(*) from public.lf_eventos)<>v_events then
    raise exception 'gate idempotent retry was not exact';
  end if;
end
$gate_path$;

-- Rotation overlap: the prior key becomes RETIRING and both keys verify proofs.
do $rotation_overlap$
declare
  v_preimage_a text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','retiring-key'),'PR93-ROTATE-A'
  );
  v_preimage_b text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','active-key'),'PR93-ROTATE-B'
  );
  v_nonce text; v_signature text;
begin
  perform private.fn_install_writer_hmac_key_v7(
    'lf-writer-2099-02-r99',
    'PR93_TEST_ONLY_HMAC_KEY_B_9c81f1a4_DO_NOT_REUSE',
    'PR93-LOTE-C'
  );
  perform private.fn_promote_writer_hmac_key_v7(
    'lf-writer-2099-02-r99','PR93-LOTE-C'
  );
  if not exists(select 1 from private.lf_writer_hmac_keys_v7
                where key_id='lf-writer-2099-01-r98' and lifecycle_state='RETIRING')
     or not exists(select 1 from private.lf_writer_hmac_keys_v7
                   where key_id='lf-writer-2099-02-r99' and lifecycle_state='ACTIVE') then
    raise exception 'rotation lifecycle states are incorrect';
  end if;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);

  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage_a||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if not private.fn_consume_writer_proof_v7(v_preimage_a,v_signature,v_nonce) then
    raise exception 'RETIRING key proof was rejected during overlap';
  end if;

  v_nonce:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage_b||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_B_9c81f1a4_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if not private.fn_consume_writer_proof_v7(v_preimage_b,v_signature,v_nonce) then
    raise exception 'ACTIVE key proof was rejected after rotation';
  end if;
end
$rotation_overlap$;

-- Test 13: API roles cannot read the key or call private verification helpers.
do $test_13$
declare
  v_denied_table boolean:=false;
  v_denied_consumer boolean:=false;
  v_denied_parser boolean:=false;
begin
  execute 'set local role service_role';
  begin perform key_material from private.lf_writer_hmac_keys_v7 limit 1;
  exception when insufficient_privilege then v_denied_table:=true; end;
  begin perform private.fn_consume_writer_proof_v7('x',repeat('0',64),'x');
  exception when insufficient_privilege then v_denied_consumer:=true; end;
  begin perform private.fn_writer_preimage_scope_v7('x');
  exception when insufficient_privilege then v_denied_parser:=true; end;
  execute 'reset role';
  if not v_denied_table or not v_denied_consumer or not v_denied_parser then
    raise exception 'test 13 failed';
  end if;
exception when others then execute 'reset role'; raise;
end
$test_13$;

-- Permanent invariants remain true under the LOTE-C additions.
do $final_invariants$
begin
  if not private.fn_writer_key_separation_v7_valid() then
    raise exception 'writer key separation invariant failed';
  end if;
  if has_function_privilege('service_role','private.fn_writer_preimage_scope_v7(text)','EXECUTE')
     or has_function_privilege('service_role','private.fn_bind_gate_writer_nonce_v7()','EXECUTE') then
    raise exception 'service_role gained a private helper privilege';
  end if;
end
$final_invariants$;

rollback;
