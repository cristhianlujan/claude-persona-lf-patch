-- PR #93 V7 framed-writer integration tests. Isolated environment only.
begin;

do $preflight$
begin
  if to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_reconciliation_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null then
    raise exception 'V7 scope/nonce realignment is missing';
  end if;
  if exists(select 1 from private.lf_writer_hmac_keys_v7) then
    raise exception 'isolated test keystore must be empty';
  end if;
end $preflight$;

select private.fn_install_writer_hmac_key_v7(
  'lf-writer-2099-01-r98','PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','PR93-N39-N42'
);
select private.fn_promote_writer_hmac_key_v7('lf-writer-2099-01-r98','PR93-N39-N42');

do $real_path$
declare
  v_artifact_id bigint;
  v_path text;
  v_payload jsonb;
  v_gate jsonb;
  v_preimage text;
  v_nonce text;
  v_sig text;
  v_run bigint;
  v_retry bigint;
  v_gate_id bigint;
  v_before bigint;
  v_rejected boolean:=false;
  v_legacy_nonce text;
begin
  select id,relative_path into v_artifact_id,v_path
  from private.lf_skill_artifacts order by id limit 1;
  if v_artifact_id is null then raise exception 'no artifact exists'; end if;

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_payload:=jsonb_build_object(
    'result','FAIL','artifact_id',v_artifact_id,
    'repository','cristhianlujan/claude-persona-lf-patch','target_branch','main',
    'artifact_path',v_path,'pr_number',999999,'pr_state','MERGED','merged',true,
    'merge_commit_sha',repeat('a',40),'workflow_run_id',900000000000000101::bigint,
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
  if private.fn_writer_preimage_scope_v7(v_preimage)<>'RECONCILIATION'
     or private.fn_writer_preimage_scope_v7('reconciliation-v7:legacy') is not null then
    raise exception 'scope parser failed';
  end if;
  v_nonce:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_sig:=encode(extensions.hmac(convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'),'hex');
  execute 'set local role service_role';
  v_run:=public.record_external_ci_verification_v7(v_payload,'PR93-REAL-PATH',v_sig,v_nonce);
  execute 'reset role';
  if not private.fn_reconciliation_nonce_v7_valid(v_run) then
    raise exception 'reconciliation nonce binding failed';
  end if;

  v_nonce:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_sig:=encode(extensions.hmac(convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'),'hex');
  execute 'set local role service_role';
  v_retry:=public.record_external_ci_verification_v7(v_payload,'PR93-REAL-PATH',v_sig,v_nonce);
  execute 'reset role';
  if v_retry<>v_run then raise exception 'idempotent retry created a different row'; end if;

  select count(*) into v_before from private.lf_reconciliation_writer_nonces_v7;
  begin
    execute 'set local role service_role';
    perform public.record_external_ci_verification_v7(
      jsonb_set(v_payload,'{artifact_path}',to_jsonb(v_path||':mutated')),
      'PR93-REAL-PATH',v_sig,v_nonce
    );
  exception when insufficient_privilege then v_rejected:=true;
  end;
  execute 'reset role';
  if not v_rejected or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_before then
    raise exception 'post-signature mutation was not fail-closed';
  end if;

  v_gate:=jsonb_build_object(
    'test_code','PR93-N39-N42','artifact_id',v_artifact_id,'gate_code','EXTERNAL-CI-V3',
    'test_kind','INTEGRATION','target_relation',v_path,
    'probe_preimage',jsonb_build_object('expected_sha256',repeat('c',64)),
    'expected_outcome',jsonb_build_object('result','FAIL'),
    'observed_outcome',jsonb_build_object('artifact_sha256',null,'audit_covered',false),
    'persisted_effects',jsonb_build_object('rows',1,'github_reconciliation_run_id',v_run),
    'passed',false,'runner_type','EXTERNAL_INDEPENDENT','runner_identity','PR93_TEST',
    'source_workflow_run_id',900000000000000101::bigint,
    'source_commit_sha',repeat('a',40),'executed_at',clock_timestamp()
  );
  v_preimage:=private.fn_gate_preimage_v7(v_gate,'PR93-REAL-GATE');
  if private.fn_writer_preimage_scope_v7(v_preimage)<>'GATE' then raise exception 'gate scope failed'; end if;
  v_nonce:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_sig:=encode(extensions.hmac(convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'),'hex');
  execute 'set local role service_role';
  v_gate_id:=public.record_lf_gate_test_v7(v_gate,'PR93-REAL-GATE',v_sig,v_nonce);
  execute 'reset role';
  if not private.fn_gate_nonce_v7_valid(v_gate_id) then raise exception 'gate nonce binding failed'; end if;

  v_legacy_nonce:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_sig:=encode(extensions.hmac(convert_to('reconciliation-v7:legacy:'||v_legacy_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'),'hex');
  if private.fn_consume_writer_proof_v7('reconciliation-v7:legacy',v_sig,v_legacy_nonce) then
    raise exception 'legacy preimage was accepted';
  end if;
exception when others then
  execute 'reset role';
  raise;
end $real_path$;

-- Test 13: service_role cannot read the key or call the verifier, and a fabricated proof has zero effects.
do $test_13$
declare
  v_denied_table boolean:=false; v_denied_fn boolean:=false; v_rejected boolean:=false;
  v_before bigint; v_payload jsonb; v_id bigint; v_path text; v_nonce text;
begin
  select id,relative_path into v_id,v_path from private.lf_skill_artifacts order by id limit 1;
  v_payload:=jsonb_build_object('result','FAIL','artifact_id',v_id,'repository','x','target_branch','main',
    'artifact_path',v_path,'pr_state','MERGED','merged',true,'merge_commit_sha',repeat('d',40),
    'workflow_run_id',900000000000000102::bigint,'workflow_event','push','workflow_head_sha',repeat('d',40),
    'workflow_conclusion','success','artifact_sha256',null,'artifact_exercised_by_workflow',false,
    'audit_manifest_sha256',repeat('e',64),'branch_protection_status','VERIFIED_COMPENSATING_CONTROLS',
    'observed_at',clock_timestamp());
  v_nonce:=gen_random_uuid()::text||'.'||floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  select count(*) into v_before from private.lf_reconciliation_writer_nonces_v7;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  execute 'set local role service_role';
  begin perform key_material from private.lf_writer_hmac_keys_v7 limit 1;
  exception when insufficient_privilege then v_denied_table:=true; end;
  begin perform private.fn_consume_writer_proof_v7('x',repeat('0',64),v_nonce);
  exception when insufficient_privilege then v_denied_fn:=true; end;
  begin perform public.record_external_ci_verification_v7(v_payload,'PR93-FABRICATED',repeat('0',64),v_nonce);
  exception when insufficient_privilege then v_rejected:=true; end;
  execute 'reset role';
  if not v_denied_table or not v_denied_fn or not v_rejected
     or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_before then
    raise exception 'test 13 failed';
  end if;
exception when others then execute 'reset role'; raise;
end $test_13$;

rollback;
