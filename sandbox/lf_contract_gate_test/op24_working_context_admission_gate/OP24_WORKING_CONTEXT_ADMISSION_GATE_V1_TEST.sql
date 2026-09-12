\set ON_ERROR_STOP on

begin;
\ir ../op24_working_context_budget_gate/OP24_WORKING_CONTEXT_BUDGET_GATE_V1.sql
\ir OP24_WORKING_CONTEXT_ADMISSION_GATE_V1.sql

insert into private.lf_context_budget_events_v2(
  id,execution_id,estimated_tokens,context_status,source,recommendation,recorded_at,evidence_event_id
) overriding system value values
(99024020,'BUILDER-PROG-013-014-REMEDIATION-2875a4a74022',800,'GREEN','OP24_SANDBOX_ADMISSION',null,clock_timestamp(),null),
(99024021,'agent-task://27',800,'GREEN','OP24_SANDBOX_ADMISSION',null,clock_timestamp(),null);

do $test$
declare
  r jsonb;
  failed boolean;
begin
  r := private.sbx_fn_lf_working_context_admission_v1(
    60,7,'BUILDER-PROG-013-014-REMEDIATION-2875a4a74022','BUILDER-PROG-013-014-REMEDIATION-2875a4a74022',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',1000,interval '1 hour');
  if not (r->'errors' ? 'CONTEXT_PACK_V2_REQUIRED') then raise exception 'EXPECTED_PACK_V2_BLOCK:%',r; end if;
  if not (r->'errors' ? 'RETRIEVAL_PROVENANCE_REQUIRED') then raise exception 'EXPECTED_PROVENANCE_BLOCK:%',r; end if;
  if coalesce((r->>'digest_equality_required')::boolean,true) is not false then raise exception 'EXPECTED_DUAL_HASH_SEMANTICS:%',r; end if;
  if coalesce((r->>'model_call_authorized')::boolean,true) is not false then raise exception 'MODEL_CALL_MUST_REMAIN_FALSE:%',r; end if;

  r := private.sbx_fn_lf_working_context_admission_v1(
    93,7,'agent-task://27','agent-task://27',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',1000,interval '1 hour');
  if not (r->'errors' ? 'RETRIEVAL_EXECUTION_MISMATCH') then raise exception 'EXPECTED_RETRIEVAL_EXECUTION_BLOCK:%',r; end if;

  r := private.sbx_fn_lf_working_context_admission_v1(
    93,999999999,'agent-task://27','agent-task://27',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',1000,interval '1 hour');
  if not (r->'errors' ? 'RETRIEVAL_NOT_FOUND') then raise exception 'EXPECTED_RETRIEVAL_NOT_FOUND:%',r; end if;

  r := private.sbx_fn_lf_working_context_admission_v1(
    93,7,'wrong-request','wrong-request',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',1000,interval '1 hour');
  if not (r->'errors' ? 'REQUEST_REF_EXECUTION_MISMATCH') then raise exception 'EXPECTED_REQUEST_REF_BLOCK:%',r; end if;

  r := private.sbx_fn_lf_working_context_admission_v1(
    93,7,'agent-task://27','different-consumer-request',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',1000,interval '1 hour');
  if not (r->'errors' ? 'SAME_REQUEST_BINDING_REQUIRED') then raise exception 'EXPECTED_CONSUMER_REQUEST_BLOCK:%',r; end if;

  r := private.sbx_fn_lf_working_context_admission_v1(
    93,7,'agent-task://27','agent-task://27',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.0',1000,interval '1 hour');
  if not (r->'errors' ? 'STALE_OR_WRONG_CONTRACT_VERSION') then raise exception 'EXPECTED_CONTRACT_VERSION_BLOCK:%',r; end if;

  r := private.sbx_fn_lf_working_context_admission_v1(
    50,2,'BUILDER-2026-08-15-V09-ROADMAP-8D79B57D','BUILDER-2026-08-15-V09-ROADMAP-8D79B57D',
    'LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1','LF_WORKING_CONTEXT_CONTRACT_20260907:v0.1',1000,interval '1 hour');
  if not (r->'errors' ? 'BUDGET_NOT_OBSERVED') then raise exception 'EXPECTED_BUDGET_NOT_OBSERVED:%',r; end if;
  if not (r->'errors' ? 'CONTEXT_PACK_V2_REQUIRED') then raise exception 'EXPECTED_LEGACY_PACK_BLOCK:%',r; end if;
  if not (r->'errors' ? 'RETRIEVAL_SELECTED_PAYLOAD_REQUIRED') then raise exception 'EXPECTED_LEGACY_RETRIEVAL_SHAPE_BLOCK:%',r; end if;
  if not (r->'errors' ? 'RETRIEVAL_PROVENANCE_REQUIRED') then raise exception 'EXPECTED_LEGACY_PROVENANCE_BLOCK:%',r; end if;

  failed := false;
  begin
    perform * from programacion.issue_provenance_receipt(
      'SOURCE_VERIFIER_V1',repeat('x',32),'RETRIEVAL_PASS',93,
      'dfeb03e84acc78a209a8d343e60cd0d43d297881','retrieval_context','retrieval:93',repeat('a',64),
      'OP24_SANDBOX_DUMMY','op24://dummy',
      jsonb_build_object('execution_id','93','head_sha','dfeb03e84acc78a209a8d343e60cd0d43d297881','subject_type','retrieval_context','subject_ref','retrieval:93','subject_sha256',repeat('a',64))
    );
  exception when others then
    failed := true;
  end;
  if failed is not true then raise exception 'DUMMY_SOURCE_VERIFIER_TOKEN_MUST_FAIL'; end if;
end
$test$;

rollback;

do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_working_context_admission_v1(bigint,bigint,text,text,text,text,bigint,interval)') is not null then
    raise exception 'ADMISSION_GATE_FUNCTION_RESIDUE';
  end if;
  if to_regprocedure('private.sbx_fn_lf_working_context_budget_gate_v1(text,bigint,interval)') is not null then
    raise exception 'BUDGET_GATE_FUNCTION_RESIDUE';
  end if;
  if exists(select 1 from private.lf_context_budget_events_v2 where id between 99024020 and 99024021) then
    raise exception 'ADMISSION_BUDGET_EVENT_RESIDUE';
  end if;
end
$post$;
