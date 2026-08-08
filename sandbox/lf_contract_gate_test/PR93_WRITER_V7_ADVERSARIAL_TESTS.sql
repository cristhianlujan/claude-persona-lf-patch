-- PR #93 V7 writer adversarial tests after LOTE-E.
-- Isolated environment only. The transaction always rolls back.

begin;

do $preflight$
begin
  if to_regprocedure('private.fn_writer_preimage_scope_v7(text)') is null
     or to_regprocedure('private.fn_bind_gate_writer_nonce_v7()') is null
     or to_regprocedure('private.fn_consume_writer_proof_v7(text,text,text)') is null
     or to_regprocedure('private.fn_reconciliation_nonce_v7_valid(bigint)') is null
     or to_regprocedure('private.fn_gate_nonce_v7_valid(bigint)') is null
     or not exists(
       select 1
       from information_schema.columns
       where table_schema='private'
         and table_name='lf_gate_test_runs_v3'
         and column_name='writer_nonce_sha256'
     ) then
    raise exception 'LOTE-E V7 functions or gate nonce column are missing';
  end if;
  if exists(select 1 from private.lf_writer_hmac_keys_v7) then
    raise exception 'isolated test keystore must be empty';
  end if;
end
$preflight$;

select private.fn_install_writer_hmac_key_v7(
  'lf-writer-2099-01-r98',
  'PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE',
  'PR93-LOTE-E'
);
select private.fn_promote_writer_hmac_key_v7(
  'lf-writer-2099-01-r98','PR93-LOTE-E'
);

-- Parser vectors, including a valid three-frame preimage with trailing bytes.
do $parser_vectors$
declare
  v_valid text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','parser','n',1),'PR93-PARSER'
  );
  v_hash text:=repeat('a',64);
  v_valid_manual text:='17#reconciliation-v71#x64#'||repeat('a',64);
begin
  if private.fn_writer_preimage_scope_v7(v_valid)<>'RECONCILIATION' then
    raise exception 'valid framed reconciliation was rejected';
  end if;
  if private.fn_writer_preimage_scope_v7(
       private.fn_gate_preimage_v7(jsonb_build_object('case','gate'),'PR93-PARSER')
     )<>'GATE' then
    raise exception 'valid framed gate was rejected';
  end if;
  if private.fn_writer_preimage_scope_v7(v_valid_manual)<>'RECONCILIATION' then
    raise exception 'manual three-frame control was rejected';
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
        ) is not null
     or private.fn_writer_preimage_scope_v7(v_valid_manual||'x') is not null then
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
    begin
      perform public.record_external_ci_verification_v7(
        v_mutated,'PR93-REAL-PATH',v_signature,v_nonce
      );
    exception when insufficient_privilege then
      v_rejected:=true;
    end;
    execute 'reset role';
  exception when others then
    execute 'reset role';
    raise;
  end;
  if not v_rejected
     or (select count(*) from private.lf_reconciliation_writer_nonces_v7)<>v_nonces
     or (select count(*) from private.lf_github_reconciliation_runs_v3)<>v_runs
     or (select count(*) from public.lf_eventos)<>v_events then
    raise exception 'post-signature reconciliation mutation was not fail-closed';
  end if;
end
$reconciliation_path$;

-- Public gate writer, dedicated private nonce, event cross-check and idempotence.
do $gate_path$
declare
  v_artifact_id bigint; v_path text; v_run bigint; v_payload jsonb;
  v_preimage text; v_nonce text; v_signature text;
  v_gate bigint; v_retry bigint; v_nonces bigint; v_gates bigint; v_events bigint;
  v_downgrade_rejected boolean:=false; v_message text;
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
    'test_code','PR93-LOTE-E','artifact_id',v_artifact_id,
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
     or coalesce((select writer_nonce_sha256
                  from private.lf_gate_test_runs_v3 where id=v_gate),'') !~ '^[0-9a-f]{64}$'
     or (select writer_nonce_sha256
         from private.lf_gate_test_runs_v3 where id=v_gate)
        is distinct from
        (select e.payload->>'writer_nonce_sha256'
         from private.lf_gate_test_runs_v3 t
         join public.lf_eventos e on e.id=t.evidence_event_id
         where t.id=v_gate)
     or (select persisted_effects
         from private.lf_gate_test_runs_v3 where id=v_gate)
        is distinct from
        (select e.payload->'persisted_effects'
         from private.lf_gate_test_runs_v3 t
         join public.lf_eventos e on e.id=t.evidence_event_id
         where t.id=v_gate)
     or (select persisted_effects_sha256
         from private.lf_gate_test_runs_v3 where id=v_gate)
        is distinct from
        (select e.payload->>'persisted_effects_sha256'
         from private.lf_gate_test_runs_v3 t
         join public.lf_eventos e on e.id=t.evidence_event_id
         where t.id=v_gate) then
    raise exception 'gate proof was not anchored consistently';
  end if;

  begin
    update private.lf_gate_test_runs_v3
    set writer_authentication='PR93_DOWNGRADE_ATTEMPT'
    where id=v_gate;
  exception when sqlstate '55000' then
    get stacked diagnostics v_message=message_text;
    v_downgrade_rejected:=position('cannot be downgraded' in v_message)>0;
  end;
  if not v_downgrade_rejected
     or (select writer_authentication
         from private.lf_gate_test_runs_v3 where id=v_gate)
        is distinct from 'GITHUB_OIDC_HMAC_NONCE_V7' then
    raise exception 'V7 gate authentication downgrade was not blocked';
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

-- Expired RETIRING key must be ignored by the verifier, not merely by text inspection.
do $expired_retiring_key$
declare
  v_preimage text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','expired-retiring-key'),'PR93-EXPIRED-RETIRING'
  );
  v_nonce text:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature text;
  v_nonce_hash text;
begin
  insert into private.lf_writer_hmac_keys_v7(
    key_name,key_id,key_material,active,lifecycle_state,created_at,
    installed_by_execution_id,activated_at,retiring_at,retiring_until,
    retired_at,last_transition_execution_id
  ) values (
    'lf_reconciliation_writer_hmac_v7',
    'lf-writer-2099-01-r97',
    'PR93_TEST_ONLY_EXPIRED_HMAC_KEY_4c71e8aa_DO_NOT_REUSE',
    false,
    'RETIRING',
    clock_timestamp()-interval '20 minutes',
    'PR93-LOTE-E',
    clock_timestamp()-interval '20 minutes',
    clock_timestamp()-interval '15 minutes',
    clock_timestamp()-interval '5 minutes',
    null,
    'PR93-LOTE-E'
  );

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage||':'||v_nonce,'UTF8'),
    convert_to('PR93_TEST_ONLY_EXPIRED_HMAC_KEY_4c71e8aa_DO_NOT_REUSE','UTF8'),
    'sha256'
  ),'hex');
  v_nonce_hash:=encode(
    extensions.digest(convert_to(v_nonce,'UTF8'),'sha256'),
    'hex'
  );

  if private.fn_consume_writer_proof_v7(v_preimage,v_signature,v_nonce)
     or exists(
       select 1
       from private.lf_reconciliation_writer_nonces_v7
       where nonce_sha256=v_nonce_hash
     ) then
    raise exception 'expired RETIRING key was accepted';
  end if;

  perform private.fn_retire_writer_hmac_key_v7(
    'lf-writer-2099-01-r97','PR93-LOTE-E'
  );
  if not exists(
    select 1
    from private.lf_writer_hmac_keys_v7
    where key_id='lf-writer-2099-01-r97'
      and lifecycle_state='RETIRED'
  ) then
    raise exception 'expired RETIRING fixture was not retired';
  end if;
end
$expired_retiring_key$;

-- Rotation overlap: verify exact window, both keys, key_id attribution and guards.
do $rotation_overlap$
declare
  v_preimage_a text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','retiring-key'),'PR93-ROTATE-A'
  );
  v_preimage_b text:=private.fn_reconciliation_preimage_v7(
    jsonb_build_object('case','active-key'),'PR93-ROTATE-B'
  );
  v_nonce_a text; v_nonce_b text; v_signature text;
  v_third_rejected boolean:=false;
  v_early_retire_rejected boolean:=false;
  v_message text;
begin
  perform private.fn_install_writer_hmac_key_v7(
    'lf-writer-2099-02-r99',
    'PR93_TEST_ONLY_HMAC_KEY_B_9c81f1a4_DO_NOT_REUSE',
    'PR93-LOTE-E'
  );
  perform private.fn_promote_writer_hmac_key_v7(
    'lf-writer-2099-02-r99','PR93-LOTE-E'
  );

  if not exists(
       select 1
       from private.lf_writer_hmac_keys_v7
       where key_id='lf-writer-2099-01-r98'
         and lifecycle_state='RETIRING'
         and abs(extract(epoch from (retiring_until-retiring_at))-600)<0.001
     )
     or not exists(
       select 1
       from private.lf_writer_hmac_keys_v7
       where key_id='lf-writer-2099-02-r99'
         and lifecycle_state='ACTIVE'
     ) then
    raise exception 'rotation lifecycle or overlap window is incorrect';
  end if;

  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  v_nonce_a:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage_a||':'||v_nonce_a,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_A_7b15d6e2_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if not private.fn_consume_writer_proof_v7(v_preimage_a,v_signature,v_nonce_a) then
    raise exception 'RETIRING key proof was rejected during overlap';
  end if;
  if (select key_id
      from private.lf_reconciliation_writer_nonces_v7
      where nonce_sha256=encode(
        extensions.digest(convert_to(v_nonce_a,'UTF8'),'sha256'),'hex'
      )) is distinct from 'lf-writer-2099-01-r98' then
    raise exception 'RETIRING proof recorded the wrong key_id';
  end if;

  v_nonce_b:=gen_random_uuid()::text||'.'||
    floor(extract(epoch from clock_timestamp()+interval '5 minutes'))::bigint;
  v_signature:=encode(extensions.hmac(
    convert_to(v_preimage_b||':'||v_nonce_b,'UTF8'),
    convert_to('PR93_TEST_ONLY_HMAC_KEY_B_9c81f1a4_DO_NOT_REUSE','UTF8'),'sha256'
  ),'hex');
  if not private.fn_consume_writer_proof_v7(v_preimage_b,v_signature,v_nonce_b) then
    raise exception 'ACTIVE key proof was rejected after rotation';
  end if;
  if (select key_id
      from private.lf_reconciliation_writer_nonces_v7
      where nonce_sha256=encode(
        extensions.digest(convert_to(v_nonce_b,'UTF8'),'sha256'),'hex'
      )) is distinct from 'lf-writer-2099-02-r99' then
    raise exception 'ACTIVE proof recorded the wrong key_id';
  end if;

  begin
    perform private.fn_retire_writer_hmac_key_v7(
      'lf-writer-2099-01-r98','PR93-LOTE-E'
    );
  exception when sqlstate '55000' then
    get stacked diagnostics v_message=message_text;
    v_early_retire_rejected:=position('overlap window' in v_message)>0;
  end;
  if not v_early_retire_rejected then
    raise exception 'RETIRING key was not protected during overlap';
  end if;

  perform private.fn_install_writer_hmac_key_v7(
    'lf-writer-2099-03-r100',
    'PR93_TEST_ONLY_HMAC_KEY_C_b0a113dd_DO_NOT_REUSE',
    'PR93-LOTE-E'
  );
  begin
    perform private.fn_promote_writer_hmac_key_v7(
      'lf-writer-2099-03-r100','PR93-LOTE-E'
    );
  exception when sqlstate '55000' then
    get stacked diagnostics v_message=message_text;
    v_third_rejected:=position('retiring writer key' in v_message)>0;
  end;
  if not v_third_rejected then
    raise exception 'third promotion was accepted while a key was RETIRING';
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

-- Permanent invariants remain true under the LOTE-D additions.
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
