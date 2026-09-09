-- OP24 protected RETRIEVAL_PASS issuer candidate test.
-- Run only after the candidate issuer SQL is installed in an isolated/sandbox DB.
-- The test is rollback-only and must leave zero durable receipt/retrieval residue.

begin;

do $test$
declare
  v_execution_id bigint;
  v_head_sha text;
  v_request_ref text;
  v_fragment jsonb;
  v_selected jsonb;
  v_query jsonb;
  v_context_sha256 text;
  v_receipt_id bigint;
  v_receipt_sha text;
  v_retrieval_id bigint;
  v_bad boolean;
begin
  select cp.execution_id, e.head_sha, e.request_ref
    into v_execution_id, v_head_sha, v_request_ref
    from programacion.context_packs cp
    join programacion.ejecuciones e on e.id=cp.execution_id
   where cp.estado='COMPLETE'
     and e.request_ref is not null
   order by cp.created_at desc
   limit 1;

  if v_execution_id is null then
    raise exception 'TEST_FIXTURE_COMPLETE_CONTEXT_PACK_REQUIRED';
  end if;

  v_fragment := jsonb_build_object(
    'source','OP24_TEST_SOURCE',
    'record_id','OP24-P3-PROTECTED-ISSUER-POSITIVE',
    'title','OP24 protected issuer positive fragment',
    'content','rollback-only synthetic retrieval fragment',
    'score',100,
    'reasons',jsonb_build_array('rollback_canary'),
    'provenance',jsonb_build_object(
      'snapshot_sha256',repeat('a',64),
      'source_ref','rollback://op24/protected-issuer'
    )
  );
  v_fragment := v_fragment || jsonb_build_object(
    'content_sha256', programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'source',v_fragment->'source',
      'record_id',v_fragment->'record_id',
      'title',v_fragment->'title',
      'content',v_fragment->'content',
      'provenance',v_fragment->'provenance'
    ))
  );

  v_selected := jsonb_build_array(v_fragment);
  v_query := jsonb_build_object(
    'required_sources',jsonb_build_array('OP24_TEST_SOURCE'),
    'required_record_ids',jsonb_build_array('OP24-P3-PROTECTED-ISSUER-POSITIVE')
  );
  v_context_sha256 := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,
    'status','PASS',
    'query',v_query,
    'selected',v_selected,
    'missing_critical_context','[]'::jsonb,
    'filtered_counts','{}'::jsonb
  ));

  select r.id, r.receipt_sha256
    into v_receipt_id, v_receipt_sha
    from programacion.issue_retrieval_pass_provenance_receipt_v1(
      v_execution_id,
      v_head_sha,
      v_request_ref,
      v_context_sha256,
      'OP24_INDEPENDENT_ROLLBACK_CANARY',
      'rollback://op24/source-verifier-positive/evidence',
      jsonb_build_object(
        'kind','RETRIEVAL_PASS',
        'verdict','PASS',
        'independent',true,
        'execution_id',v_execution_id::text,
        'head_sha',v_head_sha,
        'request_ref',v_request_ref,
        'context_sha256',v_context_sha256,
        'verifier_identity','OP24_INDEPENDENT_ROLLBACK_CANARY',
        'evidence_ref','rollback://op24/source-verifier-positive/evidence',
        'evidence_sha256',repeat('b',64)
      )
    ) r;

  if v_receipt_id is null or v_receipt_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'POSITIVE_RECEIPT_NOT_ISSUED';
  end if;

  insert into programacion.retrieval_runs(
    execution_id,head_sha,query,status,context_sha256,
    missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
  ) values (
    v_execution_id,v_head_sha,v_query,'PASS',v_context_sha256,
    '[]'::jsonb,'{}'::jsonb,v_selected,v_receipt_id
  ) returning id into v_retrieval_id;

  perform programacion.fn_assert_provenance_receipt(
    v_receipt_id,'RETRIEVAL_PASS',v_execution_id,v_head_sha,
    'retrieval_context','retrieval:'||v_execution_id::text,v_context_sha256
  );

  if not exists (
    select 1 from programacion.retrieval_runs
     where id=v_retrieval_id and status='PASS' and provenance_receipt_id=v_receipt_id
  ) then
    raise exception 'POSITIVE_RETRIEVAL_NOT_BOUND_TO_RECEIPT';
  end if;

  -- Negative 1: request_ref mismatch.
  v_bad := false;
  begin
    perform * from programacion.issue_retrieval_pass_provenance_receipt_v1(
      v_execution_id,v_head_sha,v_request_ref||'-WRONG',v_context_sha256,
      'OP24_INDEPENDENT_ROLLBACK_CANARY','rollback://negative-request/evidence',
      jsonb_build_object(
        'kind','RETRIEVAL_PASS','verdict','PASS','independent',true,
        'execution_id',v_execution_id::text,'head_sha',v_head_sha,
        'request_ref',v_request_ref||'-WRONG','context_sha256',v_context_sha256,
        'verifier_identity','OP24_INDEPENDENT_ROLLBACK_CANARY',
        'evidence_ref','rollback://negative-request/evidence',
        'evidence_sha256',repeat('c',64)
      )
    );
  exception when others then v_bad := true;
  end;
  if not v_bad then raise exception 'NEGATIVE_REQUEST_REF_MISMATCH_ACCEPTED'; end if;

  -- Negative 2: non-independent verdict.
  v_bad := false;
  begin
    perform * from programacion.issue_retrieval_pass_provenance_receipt_v1(
      v_execution_id,v_head_sha,v_request_ref,v_context_sha256,
      'OP24_INDEPENDENT_ROLLBACK_CANARY','rollback://negative-independence/evidence',
      jsonb_build_object(
        'kind','RETRIEVAL_PASS','verdict','PASS','independent',false,
        'execution_id',v_execution_id::text,'head_sha',v_head_sha,
        'request_ref',v_request_ref,'context_sha256',v_context_sha256,
        'verifier_identity','OP24_INDEPENDENT_ROLLBACK_CANARY',
        'evidence_ref','rollback://negative-independence/evidence',
        'evidence_sha256',repeat('d',64)
      )
    );
  exception when others then v_bad := true;
  end;
  if not v_bad then raise exception 'NEGATIVE_NON_INDEPENDENT_ACCEPTED'; end if;

  -- Negative 3: payload verifier identity must bind the RPC identity.
  v_bad := false;
  begin
    perform * from programacion.issue_retrieval_pass_provenance_receipt_v1(
      v_execution_id,v_head_sha,v_request_ref,v_context_sha256,
      'OP24_INDEPENDENT_ROLLBACK_CANARY','rollback://negative-identity/evidence',
      jsonb_build_object(
        'kind','RETRIEVAL_PASS','verdict','PASS','independent',true,
        'execution_id',v_execution_id::text,'head_sha',v_head_sha,
        'request_ref',v_request_ref,'context_sha256',v_context_sha256,
        'verifier_identity','DIFFERENT_VERIFIER',
        'evidence_ref','rollback://negative-identity/evidence',
        'evidence_sha256',repeat('e',64)
      )
    );
  exception when others then v_bad := true;
  end;
  if not v_bad then raise exception 'NEGATIVE_VERIFIER_IDENTITY_MISMATCH_ACCEPTED'; end if;

  -- Negative 4: verification_ref must bind the payload evidence_ref.
  v_bad := false;
  begin
    perform * from programacion.issue_retrieval_pass_provenance_receipt_v1(
      v_execution_id,v_head_sha,v_request_ref,v_context_sha256,
      'OP24_INDEPENDENT_ROLLBACK_CANARY','rollback://negative-ref/rpc',
      jsonb_build_object(
        'kind','RETRIEVAL_PASS','verdict','PASS','independent',true,
        'execution_id',v_execution_id::text,'head_sha',v_head_sha,
        'request_ref',v_request_ref,'context_sha256',v_context_sha256,
        'verifier_identity','OP24_INDEPENDENT_ROLLBACK_CANARY',
        'evidence_ref','rollback://negative-ref/payload',
        'evidence_sha256',repeat('f',64)
      )
    );
  exception when others then v_bad := true;
  end;
  if not v_bad then raise exception 'NEGATIVE_VERIFICATION_REF_MISMATCH_ACCEPTED'; end if;
end;
$test$;

rollback;

-- Required independent post-run readback after executing this file:
-- compare the pre/post count for issuer_channel='SOURCE_VERIFIER_PROTECTED_V1'.
-- Expected delta: 0.
