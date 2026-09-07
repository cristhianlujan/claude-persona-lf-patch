\set ON_ERROR_STOP on

begin;
\ir ../../../supabase/migrations/20260907055240_lf_retrieval_null_shape_guard.sql

do $test$
declare
  failed boolean;
  v_query jsonb := jsonb_build_object('probe','OP24_NULL_SHAPE_GUARD');
  v_digest text;
begin
  -- SQL NULL must be rejected.
  v_digest := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'status','BLOCKED','query',v_query,'selected',null::jsonb,
    'missing_critical_context','[]'::jsonb,'filtered_counts','{}'::jsonb));
  failed := false;
  begin
    insert into programacion.retrieval_runs(
      id,execution_id,head_sha,query,status,context_sha256,missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
    ) overriding system value values(
      99024040,93,'dfeb03e84acc78a209a8d343e60cd0d43d297881',v_query,'BLOCKED',v_digest,'[]'::jsonb,'{}'::jsonb,null::jsonb,null);
  exception when others then
    failed := sqlerrm like '%retrieval canonical payload shape invalid%';
  end;
  if failed is not true then raise exception 'SQL_NULL_SELECTED_PAYLOAD_MUST_REJECT'; end if;

  -- JSON null must also be rejected.
  v_digest := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'status','BLOCKED','query',v_query,'selected','null'::jsonb,
    'missing_critical_context','[]'::jsonb,'filtered_counts','{}'::jsonb));
  failed := false;
  begin
    insert into programacion.retrieval_runs(
      id,execution_id,head_sha,query,status,context_sha256,missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
    ) overriding system value values(
      99024041,93,'dfeb03e84acc78a209a8d343e60cd0d43d297881',v_query,'BLOCKED',v_digest,'[]'::jsonb,'{}'::jsonb,'null'::jsonb,null);
  exception when others then
    failed := sqlerrm like '%retrieval canonical payload shape invalid%';
  end;
  if failed is not true then raise exception 'JSON_NULL_SELECTED_PAYLOAD_MUST_REJECT'; end if;

  -- Canonical empty array remains valid for BLOCKED when digest is exact.
  v_digest := programacion.fn_v09_sha256_jsonb(jsonb_build_object(
    'schema_version',1,'status','BLOCKED','query',v_query,'selected','[]'::jsonb,
    'missing_critical_context','[]'::jsonb,'filtered_counts','{}'::jsonb));
  insert into programacion.retrieval_runs(
    id,execution_id,head_sha,query,status,context_sha256,missing_critical_context,filtered_counts,selected_payload,provenance_receipt_id
  ) overriding system value values(
    99024042,93,'dfeb03e84acc78a209a8d343e60cd0d43d297881',v_query,'BLOCKED',v_digest,'[]'::jsonb,'{}'::jsonb,'[]'::jsonb,null);

  if not exists(select 1 from programacion.retrieval_runs where id=99024042 and selected_payload='[]'::jsonb and status='BLOCKED') then
    raise exception 'VALID_BLOCKED_ARRAY_MUST_PASS';
  end if;
end
$test$;

rollback;

do $post$
begin
  if exists(select 1 from programacion.retrieval_runs where id between 99024040 and 99024042) then
    raise exception 'RETRIEVAL_NULL_SHAPE_TEST_RESIDUE';
  end if;
end
$post$;
