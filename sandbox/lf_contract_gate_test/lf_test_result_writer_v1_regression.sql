\set ON_ERROR_STOP on
create or replace function pg_temp.make_receipt(p_test_code text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  r := jsonb_build_object(
    'schema_version','lf-test-result-writer/v1','executed',true,
    'suite_run_id','11111111-1111-4111-8111-111111111111','suite_code','TS-S27-WRITER-V1',
    'test_code',p_test_code,'attempt_no',1,'execution_id','EXEC-'||p_test_code,'environment','SANDBOX',
    'code_head_sha',repeat('a',40),'source_sha256',repeat('b',64),'configuration_sha256',repeat('c',64),
    'evidence_origin','LIVE_EXECUTOR_RECEIPT','exit_code',0,
    'executor',jsonb_build_object('type','DETERMINISTIC_JUDGE','name','P9_REGRESSION'),
    'timing',jsonb_build_object('started_at','2026-09-07T13:30:00+00:00','completed_at','2026-09-07T13:30:00.025+00:00','duration_ms',25,'measurement_source','MONOTONIC_PRODUCER'),
    'outcome',jsonb_build_object('status','PASSED','expected_output',jsonb_build_object('result','PASS_WITH_EVIDENCE'),'actual_output',jsonb_build_object('result','PASS_WITH_EVIDENCE'),'severity','MEDIUM'),
    'input_payload',jsonb_build_object('fixture','exact'),'channels',jsonb_build_object(
      'assertions',jsonb_build_object('applicable',true,'items',jsonb_build_array(jsonb_build_object(
        'assertion_code','A01','assertion_order',1,'assertion_type','EQUALS','description','Observed result matches frozen expected result',
        'expected_value','PASS_WITH_EVIDENCE','actual_value','PASS_WITH_EVIDENCE','operator','equals','status','PASS','evidence_payload',jsonb_build_object('source','judge')
      ))),
      'judges',jsonb_build_object('applicable',true,'items',jsonb_build_array(jsonb_build_object(
        'judge_code','J10_TEST_COVERAGE','judge_type','DETERMINISTIC_JUDGE','executor_identity','P9_REGRESSION_JUDGE','judge_version','v0.7',
        'verdict','PASS','findings','[]'::jsonb,'evidence_payload',jsonb_build_object('output_sha256',repeat('d',64))
      ))),
      'artifacts',jsonb_build_object('applicable',true,'items',jsonb_build_array(jsonb_build_object(
        'artifact_type','EXECUTION_RECEIPT','name','writer regression receipt','storage_provider','SANDBOX','storage_ref','sandbox://receipt/'||p_test_code,
        'sha256',repeat('e',64),'mime_type','application/json','size_bytes',128,'metadata',jsonb_build_object('fixture',true)
      )))
    )
  );
  return r || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r));
end $$;

do $$
declare r jsonb; out1 jsonb; out2 jsonb; tr uuid; stored jsonb;
begin
  r := pg_temp.make_receipt('CASE-POS');
  out1 := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if out1->>'outcome' <> 'MATERIALIZED' or (out1->>'assertion_rows')::int<>1 or (out1->>'judge_rows')::int<>1 or (out1->>'artifact_rows')::int<>1 then
    raise exception 'POSITIVE_MATERIALIZATION_FAILED %',out1;
  end if;
  tr := (out1->>'test_run_id')::uuid;
  select evidence_payload into stored from public.lf_test_runs where test_run_id=tr;
  if stored->>'receipt_sha256' <> private.fn_payload_sha256_v7((stored->'receipt') - 'receipt_sha256') then
    raise exception 'FULL_ENVELOPE_HASH_RECOMPUTE_FAILED';
  end if;
  if (select duration_ms from public.lf_test_runs where test_run_id=tr) <> 25 then raise exception 'DURATION_NOT_PERSISTED'; end if;
  if (select count(*) from public.lf_test_assertion_results where test_run_id=tr)<>1
     or (select count(*) from public.lf_test_judge_results where test_run_id=tr)<>1
     or (select count(*) from public.lf_test_artifacts where test_run_id=tr)<>1 then raise exception 'NORMALIZED_CHILD_COUNTS_INVALID'; end if;
  out2 := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if out2->>'outcome' <> 'REPLAY' or coalesce((out2->>'replay')::boolean,false) is not true then raise exception 'IDEMPOTENT_REPLAY_FAILED %',out2; end if;
end $$;

do $$ declare r jsonb; o jsonb; begin
  r := pg_temp.make_receipt('CASE-HASH') || jsonb_build_object('receipt_sha256',repeat('0',64));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'RECEIPT_SHA256_MISMATCH' then raise exception 'HASH_NEGATIVE_FAILED %',o; end if;
  if exists(select 1 from public.lf_test_runs where test_code='CASE-HASH') then raise exception 'HASH_NEGATIVE_PERSISTED'; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-HEAD') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{code_head_sha}',to_jsonb(repeat('f',40)));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'CODE_HEAD_MISMATCH' then raise exception 'HEAD_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-CHANNEL') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{channels,artifacts,applicable}','false'::jsonb);
  r0 := jsonb_set(r0,'{channels,artifacts,reason}',to_jsonb('not applicable'::text));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'CHANNEL_APPLICABILITY_CONFLICT' then raise exception 'CHANNEL_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-JUDGE') - 'receipt_sha256';
  r0 := r0 #- '{channels,judges,items,0,executor_identity}';
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'JUDGE_PROVENANCE_INVALID' then raise exception 'JUDGE_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-ORIGIN') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{evidence_origin}',to_jsonb('INFERRED_HISTORICAL'::text));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'EVIDENCE_ORIGIN_INVALID' then raise exception 'ORIGIN_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r := pg_temp.make_receipt('CASE-POS');
  r0 := r - 'receipt_sha256';
  r0 := jsonb_set(r0,'{input_payload,fixture}',to_jsonb('changed-after-materialization'::text));
  r0 := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r0,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'TEST_RUN_IDEMPOTENCY_CONFLICT' then raise exception 'IDEMPOTENCY_CONFLICT_NEGATIVE_FAILED %',o; end if;
end $$;

-- AUD-018 source/config binding negatives: valid receipt hashes cannot self-authorize their provenance.
do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-HASH') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{source_sha256}',to_jsonb(repeat('9',64)));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SOURCE_SHA256_MISMATCH' then raise exception 'SOURCE_BINDING_NEGATIVE_FAILED %',o; end if;
  if exists(select 1 from public.lf_test_runs where test_code='CASE-HASH') then raise exception 'SOURCE_BINDING_NEGATIVE_PERSISTED'; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-CHANNEL') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{configuration_sha256}',to_jsonb(repeat('9',64)));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'CONFIGURATION_SHA256_MISMATCH' then raise exception 'CONFIG_BINDING_NEGATIVE_FAILED %',o; end if;
  if exists(select 1 from public.lf_test_runs where test_code='CASE-CHANNEL') then raise exception 'CONFIG_BINDING_NEGATIVE_PERSISTED'; end if;
end $$;

do $$ declare r jsonb; o jsonb; begin
  r := pg_temp.make_receipt('CASE-NO-BINDING');
  o := public.lf_test_result_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SOURCE_BINDING_MISSING_OR_INVALID' then raise exception 'MISSING_BINDING_NEGATIVE_FAILED %',o; end if;
  if exists(select 1 from public.lf_test_runs where test_code='CASE-NO-BINDING') then raise exception 'MISSING_BINDING_NEGATIVE_PERSISTED'; end if;
end $$;

-- Cross-envelope coherence negatives: a sealed receipt cannot contradict its normalized children.
do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-HASH') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{channels,assertions,items,0,status}',to_jsonb('FAIL'::text));
  r0 := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r0,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'STATUS_CHILD_EVIDENCE_CONFLICT' then raise exception 'PASS_ASSERT_FAIL_COHERENCE_NEGATIVE_FAILED %',o; end if;
  if exists(select 1 from public.lf_test_runs where test_code='CASE-HASH') then raise exception 'PASS_ASSERT_FAIL_PERSISTED'; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-HEAD') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{channels,judges,items,0,verdict}',to_jsonb('FAIL'::text));
  r0 := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r0,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'STATUS_CHILD_EVIDENCE_CONFLICT' then raise exception 'PASS_JUDGE_FAIL_COHERENCE_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-JUDGE') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{outcome,status}',to_jsonb('FAILED'::text));
  r0 := jsonb_set(r0,'{exit_code}','1'::jsonb);
  r0 := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r0,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'STATUS_CHILD_EVIDENCE_CONFLICT' then raise exception 'FAILED_WITHOUT_FAILURE_EVIDENCE_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-CHANNEL') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{outcome,status}',to_jsonb('REVIEW_REQUIRED'::text));
  r0 := jsonb_set(r0,'{exit_code}','1'::jsonb);
  r0 := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r0,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'STATUS_CHILD_EVIDENCE_CONFLICT' then raise exception 'REVIEW_WITHOUT_REVIEW_EVIDENCE_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_receipt('CASE-ORIGIN') - 'receipt_sha256';
  r0 := jsonb_set(r0,'{outcome,status}',to_jsonb('BLOCKED'::text));
  r0 := jsonb_set(r0,'{exit_code}','2'::jsonb);
  r0 := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_result_writer_v1(r0,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'STATUS_CHILD_EVIDENCE_CONFLICT' then raise exception 'BLOCKED_WITHOUT_CAUSE_NEGATIVE_FAILED %',o; end if;
end $$;

create or replace function pg_temp.make_suite_receipt(p_expected integer)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  r := jsonb_build_object(
    'schema_version','lf-test-suite-finalize-writer/v1','executed',true,
    'suite_run_id','11111111-1111-4111-8111-111111111111','suite_code','TS-S27-WRITER-V1',
    'code_head_sha',repeat('a',40),'source_sha256',repeat('b',64),'configuration_sha256',repeat('c',64),
    'evidence_origin','LIVE_EXECUTOR_RECEIPT','expected_tests_total',p_expected,
    'timing',jsonb_build_object('started_at','2026-09-07T13:29:59.900+00:00','completed_at','2026-09-07T13:30:00.100+00:00','duration_ms',200,'measurement_source','MONOTONIC_PRODUCER')
  );
  return r || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r));
end $$;

do $$ declare o jsonb; begin
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(2),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_TEST_COUNT_MISMATCH' then raise exception 'SUITE_COUNT_NEGATIVE_FAILED %',o; end if;
  if (select status from public.lf_test_suite_runs where suite_run_id='11111111-1111-4111-8111-111111111111') <> 'RUNNING' then
    raise exception 'SUITE_NEGATIVE_MUTATED_STATE';
  end if;
end $$;

-- Suite-level AUD-018 binding negatives.
do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_suite_receipt(1) - 'receipt_sha256';
  r0 := jsonb_set(r0,'{source_sha256}',to_jsonb(repeat('9',64)));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_suite_finalize_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_SOURCE_SHA256_MISMATCH' then raise exception 'SUITE_SOURCE_BINDING_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare r jsonb; r0 jsonb; o jsonb; begin
  r0 := pg_temp.make_suite_receipt(1) - 'receipt_sha256';
  r0 := jsonb_set(r0,'{configuration_sha256}',to_jsonb(repeat('9',64)));
  r := r0 || jsonb_build_object('receipt_sha256',private.fn_payload_sha256_v7(r0));
  o := public.lf_test_suite_finalize_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_CONFIGURATION_SHA256_MISMATCH' then raise exception 'SUITE_CONFIG_BINDING_NEGATIVE_FAILED %',o; end if;
end $$;

do $$ declare saved jsonb; o jsonb; begin
  select manifest into saved from public.lf_test_suite_runs where suite_run_id='11111111-1111-4111-8111-111111111111';
  update public.lf_test_suite_runs set manifest='{}'::jsonb where suite_run_id='11111111-1111-4111-8111-111111111111';
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_SOURCE_BINDING_MISSING_OR_INVALID' then raise exception 'SUITE_MISSING_BINDING_NEGATIVE_FAILED %',o; end if;
  update public.lf_test_suite_runs set manifest=saved where suite_run_id='11111111-1111-4111-8111-111111111111';
end $$;

-- Defense in depth: finalizer rechecks normalized child coherence even after out-of-band drift.
do $$ declare tr uuid; o jsonb; begin
  select test_run_id into tr from public.lf_test_runs where test_code='CASE-POS';
  update public.lf_test_assertion_results set status='FAIL' where test_run_id=tr and assertion_code='A01';
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_CHILD_STATUS_CONFLICT' then raise exception 'SUITE_CHILD_COHERENCE_NEGATIVE_FAILED %',o; end if;
  update public.lf_test_assertion_results set status='PASS' where test_run_id=tr and assertion_code='A01';
end $$;

-- Defense in depth: child source/config provenance cannot drift after materialization.
do $$ declare tr uuid; saved jsonb; o jsonb; begin
  select test_run_id,evidence_payload into tr,saved from public.lf_test_runs where test_code='CASE-POS';
  update public.lf_test_runs
  set evidence_payload=jsonb_set(evidence_payload,'{source_sha256}',to_jsonb(repeat('9',64)))
  where test_run_id=tr;
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_CHILD_SOURCE_CONFIG_BINDING_CONFLICT' then raise exception 'SUITE_CHILD_BINDING_DRIFT_NEGATIVE_FAILED %',o; end if;
  update public.lf_test_runs set evidence_payload=saved where test_run_id=tr;
end $$;

do $$ declare r jsonb; o jsonb; replay jsonb; begin
  r := pg_temp.make_suite_receipt(1);
  o := public.lf_test_suite_finalize_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if o->>'outcome' <> 'MATERIALIZED' or o->>'status' <> 'PASSED' or (o->>'duration_ms')::int <> 200 then
    raise exception 'SUITE_FINALIZE_FAILED %',o;
  end if;
  if (select tests_total from public.lf_test_suite_runs where suite_run_id='11111111-1111-4111-8111-111111111111') <> 1
     or (select tests_passed from public.lf_test_suite_runs where suite_run_id='11111111-1111-4111-8111-111111111111') <> 1 then
    raise exception 'SUITE_COUNTERS_NOT_MATERIALIZED';
  end if;
  replay := public.lf_test_suite_finalize_writer_v1(r,'EXEC-WRITER-REGRESSION');
  if replay->>'outcome' <> 'REPLAY' then raise exception 'SUITE_REPLAY_FAILED %',replay; end if;
end $$;

-- Post-finalization replay must revalidate normalized evidence rather than short-circuit on receipt hash.
do $$ declare tr uuid; saved jsonb; o jsonb; begin
  select test_run_id,evidence_payload into tr,saved from public.lf_test_runs where test_code='CASE-POS';
  update public.lf_test_runs
  set evidence_payload=jsonb_set(evidence_payload,'{source_sha256}',to_jsonb(repeat('9',64)))
  where test_run_id=tr;
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_CHILD_SOURCE_CONFIG_BINDING_CONFLICT' then raise exception 'POST_FINALIZE_SOURCE_DRIFT_NEGATIVE_FAILED %',o; end if;
  update public.lf_test_runs set evidence_payload=saved where test_run_id=tr;
end $$;

do $$ declare tr uuid; o jsonb; begin
  select test_run_id into tr from public.lf_test_runs where test_code='CASE-POS';
  update public.lf_test_assertion_results set status='FAIL' where test_run_id=tr and assertion_code='A01';
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_CHILD_STATUS_CONFLICT' then raise exception 'POST_FINALIZE_STATUS_DRIFT_NEGATIVE_FAILED %',o; end if;
  update public.lf_test_assertion_results set status='PASS' where test_run_id=tr and assertion_code='A01';
end $$;

do $$ declare tr uuid; o jsonb; begin
  select test_run_id into tr from public.lf_test_runs where test_code='CASE-POS';
  update public.lf_test_runs set status='FAILED',error_code='POST_FINALIZE_TEST_FAILURE' where test_run_id=tr;
  update public.lf_test_assertion_results set status='FAIL' where test_run_id=tr and assertion_code='A01';
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'code' <> 'SUITE_REPLAY_MATERIALIZED_STATE_DRIFT' then raise exception 'POST_FINALIZE_AGGREGATE_DRIFT_NEGATIVE_FAILED %',o; end if;
  update public.lf_test_runs set status='PASSED',error_code=null where test_run_id=tr;
  update public.lf_test_assertion_results set status='PASS' where test_run_id=tr and assertion_code='A01';
  o := public.lf_test_suite_finalize_writer_v1(pg_temp.make_suite_receipt(1),'EXEC-WRITER-REGRESSION');
  if o->>'outcome' <> 'REPLAY' then raise exception 'POST_FINALIZE_CLEAN_REPLAY_FAILED %',o; end if;
end $$;

do $$ begin
  if has_function_privilege('anon','public.lf_test_result_writer_v1(jsonb,text)','EXECUTE')
     or has_function_privilege('authenticated','public.lf_test_result_writer_v1(jsonb,text)','EXECUTE')
     or not has_function_privilege('service_role','public.lf_test_result_writer_v1(jsonb,text)','EXECUTE') then
    raise exception 'RESULT_WRITER_GRANT_CONTRACT_FAILED';
  end if;
  if has_function_privilege('anon','public.lf_test_suite_finalize_writer_v1(jsonb,text)','EXECUTE')
     or has_function_privilege('authenticated','public.lf_test_suite_finalize_writer_v1(jsonb,text)','EXECUTE')
     or not has_function_privilege('service_role','public.lf_test_suite_finalize_writer_v1(jsonb,text)','EXECUTE') then
    raise exception 'SUITE_FINALIZER_GRANT_CONTRACT_FAILED';
  end if;
end $$;

select jsonb_build_object(
 'schema_version','s27-p9-writer-regression/v1','executed',true,'positive_materialized',1,'idempotent_replay',1,
 'negative_controls',23,'suite_finalize_materialized',1,'suite_finalize_replay',1,'test_runs',(select count(*) from public.lf_test_runs),
 'assertions',(select count(*) from public.lf_test_assertion_results),
 'judges',(select count(*) from public.lf_test_judge_results),
 'artifacts',(select count(*) from public.lf_test_artifacts)
) as regression_receipt;
