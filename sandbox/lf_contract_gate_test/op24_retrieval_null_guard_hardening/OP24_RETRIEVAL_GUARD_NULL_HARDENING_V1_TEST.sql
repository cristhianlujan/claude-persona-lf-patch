\set ON_ERROR_STOP on

select md5(pg_get_functiondef('programacion.fn_guard_retrieval_run_insert()'::regprocedure)) as op24_original_guard_md5 \gset

begin;
\ir OP24_RETRIEVAL_GUARD_NULL_HARDENING_V1.sql

create or replace function pg_temp.op24_expect_retrieval_reject(
  p_status text,
  p_query jsonb,
  p_selected jsonb,
  p_missing jsonb,
  p_filtered jsonb,
  p_expected text
) returns boolean
language plpgsql
as $helper$
declare
  d text;
  e text;
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
    return false;
  exception when others then
    e := sqlerrm;
    return position(p_expected in e) > 0;
  end;
end;
$helper$;

do $test$
declare
  d text;
  f jsonb;
  a jsonb;
  n integer := 0;
begin
  -- Positive structural baseline.
  d := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'status','BLOCKED','query','{}'::jsonb,'selected','[]'::jsonb,
    'missing_critical_context','[]'::jsonb,'filtered_counts','{}'::jsonb
  ));
  insert into programacion.retrieval_runs(
    execution_id,head_sha,query,status,context_sha256,
    missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
  ) values (
    50,'8d79b57d2befc3b897575b91eac25ac738eeec61','{}'::jsonb,'BLOCKED',d,
    '[]'::jsonb,'{}'::jsonb,'[]'::jsonb,null
  );
  n := n + 1;

  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,null,'[]'::jsonb,'{}'::jsonb,'retrieval canonical payload shape invalid') then n:=n+1; else raise exception 'NEG_SELECTED_SQL_NULL_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('BLOCKED',null,'[]'::jsonb,'[]'::jsonb,'{}'::jsonb,'retrieval canonical payload shape invalid') then n:=n+1; else raise exception 'NEG_QUERY_SQL_NULL_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,'[]'::jsonb,null,'{}'::jsonb,'retrieval canonical payload shape invalid') then n:=n+1; else raise exception 'NEG_MISSING_SQL_NULL_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,'[]'::jsonb,'[]'::jsonb,null,'retrieval canonical payload shape invalid') then n:=n+1; else raise exception 'NEG_FILTERED_SQL_NULL_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,'null'::jsonb,'[]'::jsonb,'{}'::jsonb,'retrieval canonical payload shape invalid') then n:=n+1; else raise exception 'NEG_SELECTED_JSON_NULL_FAILED'; end if;

  f := jsonb_build_object(
    'source','documentation','record_id','OP24-TEST-1','title','OP24 test fragment',
    'content','sandbox only','score',1,'reasons',jsonb_build_array('sandbox'),
    'provenance',jsonb_build_object('snapshot_sha256',repeat('a',64))
  );
  f := f || jsonb_build_object(
    'content_sha256',
    programacion.fn_v09_sha256_jsonb(jsonb_build_object(
      'source',f->'source','record_id',f->'record_id','title',f->'title',
      'content',f->'content','provenance',f->'provenance'
    ))
  );
  a := jsonb_build_array(f);

  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,jsonb_build_array(f-'score'),'[]'::jsonb,'{}'::jsonb,'retrieval selected payload contains 1 invalid fragment') then n:=n+1; else raise exception 'NEG_SCORE_MISSING_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,jsonb_build_array(f-'reasons'),'[]'::jsonb,'{}'::jsonb,'retrieval selected payload contains 1 invalid fragment') then n:=n+1; else raise exception 'NEG_REASONS_MISSING_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('BLOCKED','{}'::jsonb,jsonb_build_array(f-'provenance'),'[]'::jsonb,'{}'::jsonb,'retrieval selected payload contains 1 invalid fragment') then n:=n+1; else raise exception 'NEG_PROVENANCE_MISSING_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('PASS','{}'::jsonb,a,'[]'::jsonb,'{}'::jsonb,'retrieval PASS requires required_sources') then n:=n+1; else raise exception 'NEG_REQUIRED_SOURCES_MISSING_FAILED'; end if;
  if pg_temp.op24_expect_retrieval_reject('PASS',jsonb_build_object('required_sources','null'::jsonb),a,'[]'::jsonb,'{}'::jsonb,'retrieval PASS requires required_sources') then n:=n+1; else raise exception 'NEG_REQUIRED_SOURCES_JSON_NULL_FAILED'; end if;

  if n <> 11 then
    raise exception 'OP24_EXPECTED_11_OF_11_GOT_%', n;
  end if;
end;
$test$;

select jsonb_build_object('passed',11,'total',11,'production_authorized',false) as op24_test_result;
rollback;

select jsonb_build_object(
  'original_function_restored',
    md5(pg_get_functiondef('programacion.fn_guard_retrieval_run_insert()'::regprocedure)) = :'op24_original_guard_md5',
  'recent_execution50_rows_after_rollback',
    (select count(*) from programacion.retrieval_runs where execution_id=50 and created_at > clock_timestamp()-interval '2 minutes')
) as op24_post_rollback;
