\set ON_ERROR_STOP on

begin;
\ir OP24_WORKING_CONTEXT_ENVELOPE_V1.sql

do $test$
declare
  v jsonb;
  e jsonb := '{"contract_version":"v0.1","context_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","selected_refs":["EKB:1"],"provenance_ref":"receipt://1","request_id":"REQ-1","consumer_request_id":"REQ-1","estimated_tokens":3500,"token_budget":8000,"budget_status":"GREEN","generated_at":"2026-09-07T05:00:00Z"}'::jsonb;
begin
  v := private.sbx_fn_lf_working_context_envelope_v1(e,'v0.1');
  if (v->>'valid')::boolean is distinct from true
     or (v->>'retrieval_executed')::boolean is distinct from false
     or (v->>'model_call_authorized')::boolean is distinct from false then
    raise exception 'EXPECTED_VALID_SANDBOX_ENVELOPE_ONLY: %',v;
  end if;

  v := private.sbx_fn_lf_working_context_envelope_v1(jsonb_set(e,'{contract_version}','"v0.0"'::jsonb),'v0.1');
  if (v->>'valid')::boolean is distinct from false or not (v->'errors' @> '["STALE_OR_WRONG_CONTRACT_VERSION"]'::jsonb) then
    raise exception 'EXPECTED_STALE_CONTRACT_BLOCK: %',v;
  end if;

  v := private.sbx_fn_lf_working_context_envelope_v1(jsonb_set(e,'{estimated_tokens}','9000'::jsonb),'v0.1');
  if (v->>'valid')::boolean is distinct from false or not (v->'errors' @> '["OVER_BUDGET"]'::jsonb) then
    raise exception 'EXPECTED_OVER_BUDGET_BLOCK: %',v;
  end if;

  v := private.sbx_fn_lf_working_context_envelope_v1(e - 'provenance_ref','v0.1');
  if (v->>'valid')::boolean is distinct from false or not (v->'errors' @> '["PROVENANCE_REF_REQUIRED"]'::jsonb) then
    raise exception 'EXPECTED_PROVENANCE_BLOCK: %',v;
  end if;

  v := private.sbx_fn_lf_working_context_envelope_v1(jsonb_set(e,'{consumer_request_id}','"REQ-2"'::jsonb),'v0.1');
  if (v->>'valid')::boolean is distinct from false or not (v->'errors' @> '["SAME_REQUEST_BINDING_REQUIRED"]'::jsonb) then
    raise exception 'EXPECTED_REQUEST_BINDING_BLOCK: %',v;
  end if;

  v := private.sbx_fn_lf_working_context_envelope_v1(jsonb_set(e,'{budget_status}','"RED"'::jsonb),'v0.1');
  if (v->>'valid')::boolean is distinct from false or not (v->'errors' @> '["BUDGET_STATUS_RED"]'::jsonb) then
    raise exception 'EXPECTED_RED_BUDGET_BLOCK: %',v;
  end if;
end
$test$;

rollback;

do $post$
begin
  if to_regprocedure('private.sbx_fn_lf_working_context_envelope_v1(jsonb,text)') is not null then
    raise exception 'WORKING_CONTEXT_TEST_LEFT_FUNCTION_RESIDUE';
  end if;
end
$post$;
