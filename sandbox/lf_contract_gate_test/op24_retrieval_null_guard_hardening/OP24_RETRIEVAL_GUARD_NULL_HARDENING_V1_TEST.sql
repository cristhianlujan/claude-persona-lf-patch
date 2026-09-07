\set ON_ERROR_STOP on

begin;
\ir OP24_RETRIEVAL_GUARD_NULL_HARDENING_V1.sql

create temp table op24_null_guard_results(
  case_code text primary key,
  outcome text not null,
  detail text
) on commit drop;

do $test$
declare
  v_digest text;
  v_fragment jsonb;
  v_selected jsonb;
  v_err text;
  v_count integer;

  procedure expect_reject(
    p_case text,
    p_status text,
    p_query jsonb,
    p_selected jsonb,
    p_missing jsonb,
    p_filtered jsonb,
    p_expected_error text
  ) language plpgsql as $proc$
  declare d text; e text;
  begin
    d := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'schema_version',1,
      'status',p_status,
      'query',p_query,
      'selected',p_selected,
      'missing_critical_context',p_missing,
      'filtered_counts',p_filtered
    ));
    begin
      insert into programacion.retrieval_runs(
        execution_id,head_sha,query,status,context_sha256,
        missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
      ) values (
        50,'8d79b57d2befc3b897575b91eac25ac738eeec61',p_query,p_status,d,
        p_missing,p_filtered,p_selected,null
      );
      insert into op24_null_guard_results values(p_case,'UNEXPECTED_ACCEPT',null);
    exception when others then
      e := sqlerrm;
      if position(p_expected_error in e) = 0 then
        raise exception 'CASE % WRONG_ERROR expected=% observed=%',p_case,p_expected_error,e;
      end if;
      insert into op24_null_guard_results values(p_case,'EXPECTED_REJECT',e);
    end;
  end;
  $proc$;

begin
  -- Positive baseline: BLOCKED + empty array is structurally valid and should persist inside the transaction.
  v_digest := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'status','BLOCKED','query','{}'::jsonb,'selected','[]'::jsonb,
    'missing_critical_context','[]'::jsonb,'filtered_counts','{}'::jsonb
  ));
  insert into programacion.retrieval_runs(
    execution_id,head_sha,query,status,context_sha256,
    missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
  ) values (
    50,'8d79b57d2befc3b897575b91eac25ac738eeec61','{}'::jsonb,'BLOCKED',v_digest,
    '[]'::jsonb,'{}'::jsonb,'[]'::jsonb,null
  );
  insert into op24_null_guard_results values('POS_BLOCKED_EMPTY_ARRAY','EXPECTED_ACCEPT',null);

  call expect_reject('NEG_SELECTED_SQL_NULL','BLOCKED','{}'::jsonb,null,'[]'::jsonb,'{}'::jsonb,'retrieval canonical payload shape invalid');
  call expect_reject('NEG_QUERY_SQL_NULL','BLOCKED',null,'[]'::jsonb,'[]'::jsonb,'{}'::jsonb,'retrieval canonical payload shape invalid');
  call expect_reject('NEG_MISSING_SQL_NULL','BLOCKED','{}'::jsonb,'[]'::jsonb,null,'{}'::jsonb,'retrieval canonical payload shape invalid');
  call expect_reject('NEG_FILTERED_SQL_NULL','BLOCKED','{}'::jsonb,'[]'::jsonb,'[]'::jsonb,null,'retrieval canonical payload shape invalid');
  call expect_reject('NEG_SELECTED_JSON_NULL','BLOCKED','{}'::jsonb,'null'::jsonb,'[]'::jsonb,'{}'::jsonb,'retrieval canonical payload shape invalid');

  v_fragment := jsonb_build_object(
    'source','documentation',
    'record_id','OP24-TEST-1',
    'title','OP24 test fragment',
    'content','sandbox only',
    'score',1,
    'reasons',jsonb_build_array('sandbox'),
    'provenance',jsonb_build_object('snapshot_sha256',repeat('a',64))
  );
  v_fragment := v_fragment || jsonb_build_object(
    'content_sha256',
    programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'source',v_fragment->'source','record_id',v_fragment->'record_id','title',v_fragment->'title',
      'content',v_fragment->'content','provenance',v_fragment->'provenance'
    ))
  );
  v_selected := jsonb_build_array(v_fragment);

  call expect_reject('NEG_FRAGMENT_SCORE_MISSING','BLOCKED','{}'::jsonb,jsonb_build_array(v_fragment - 'score'),'[]'::jsonb,'{}'::jsonb,'retrieval selected payload contains 1 invalid fragment');
  call expect_reject('NEG_FRAGMENT_REASONS_MISSING','BLOCKED','{}'::jsonb,jsonb_build_array(v_fragment - 'reasons'),'[]'::jsonb,'{}'::jsonb,'retrieval selected payload contains 1 invalid fragment');
  call expect_reject('NEG_FRAGMENT_PROVENANCE_MISSING','BLOCKED','{}'::jsonb,jsonb_build_array(v_fragment - 'provenance'),'[]'::jsonb,'{}'::jsonb,'retrieval selected payload contains 1 invalid fragment');
  call expect_reject('NEG_PASS_REQUIRED_SOURCES_MISSING','PASS','{}'::jsonb,v_selected,'[]'::jsonb,'{}'::jsonb,'retrieval PASS requires required_sources');
  call expect_reject('NEG_PASS_REQUIRED_SOURCES_JSON_NULL','PASS',jsonb_build_object('required_sources','null'::jsonb),v_selected,'[]'::jsonb,'{}'::jsonb,'retrieval PASS requires required_sources');

  select count(*) into v_count
  from op24_null_guard_results
  where outcome in ('EXPECTED_ACCEPT','EXPECTED_REJECT');
  if v_count <> 11 then
    raise exception 'EXPECTED_11_CASES_OBSERVED:%',v_count;
  end if;

  if exists(select 1 from op24_null_guard_results where outcome like 'UNEXPECTED%') then
    raise exception 'UNEXPECTED_CASE_OUTCOME:%',(select jsonb_agg(to_jsonb(r)) from op24_null_guard_results r where outcome like 'UNEXPECTED%');
  end if;
end
$test$;

select jsonb_agg(to_jsonb(r) order by case_code) as results
from op24_null_guard_results r;

rollback;

select jsonb_build_object(
  'retrieval_test_residue',count(*)
) as post_rollback
from programacion.retrieval_runs
where execution_id=50
  and created_at >= clock_timestamp() - interval '5 minutes'
  and query in ('{}'::jsonb,jsonb_build_object('required_sources','null'::jsonb));
