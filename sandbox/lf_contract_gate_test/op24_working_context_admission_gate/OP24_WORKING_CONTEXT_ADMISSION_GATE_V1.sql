-- OP24 Working Context Admission Gate V1 — sandbox candidate only.
-- Stack dependency: OP24_WORKING_CONTEXT_BUDGET_GATE_V1.sql / PR #572.
-- No runtime activation. No production authorization. No model call.
-- IMPORTANT: Context Pack and Retrieval digests are distinct canonical payloads; equality is NOT required.

create or replace function private.sbx_fn_lf_working_context_admission_v1(
  p_execution_id bigint,
  p_retrieval_run_id bigint,
  p_request_ref text,
  p_consumer_request_ref text,
  p_expected_contract_version text,
  p_actual_contract_version text,
  p_budget_limit bigint,
  p_max_age interval default interval '1 hour'
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private', 'programacion'
as $function$
declare
  v_errors jsonb := '[]'::jsonb;
  v_execution_request_ref text;
  v_head_sha text;
  v_pack programacion.context_packs%rowtype;
  v_retrieval programacion.retrieval_runs%rowtype;
  v_receipt programacion.provenance_receipts%rowtype;
  v_budget jsonb;
  v_selected_refs jsonb := '[]'::jsonb;
  v_conditions_met boolean := false;
begin
  if p_execution_id is null then
    v_errors := v_errors || jsonb_build_array('EXECUTION_ID_REQUIRED');
  end if;
  if p_retrieval_run_id is null then
    v_errors := v_errors || jsonb_build_array('RETRIEVAL_RUN_ID_REQUIRED');
  end if;
  if length(btrim(coalesce(p_request_ref,''))) = 0 then
    v_errors := v_errors || jsonb_build_array('REQUEST_REF_REQUIRED');
  end if;
  if length(btrim(coalesce(p_consumer_request_ref,''))) = 0 then
    v_errors := v_errors || jsonb_build_array('CONSUMER_REQUEST_REF_REQUIRED');
  end if;
  if coalesce(p_request_ref,'') is distinct from coalesce(p_consumer_request_ref,'') then
    v_errors := v_errors || jsonb_build_array('SAME_REQUEST_BINDING_REQUIRED');
  end if;
  if length(btrim(coalesce(p_expected_contract_version,''))) = 0
     or p_actual_contract_version is distinct from p_expected_contract_version then
    v_errors := v_errors || jsonb_build_array('STALE_OR_WRONG_CONTRACT_VERSION');
  end if;

  if p_execution_id is not null then
    select e.request_ref,e.head_sha
      into v_execution_request_ref,v_head_sha
    from programacion.ejecuciones e
    where e.id=p_execution_id;
    if not found then
      v_errors := v_errors || jsonb_build_array('EXECUTION_NOT_FOUND');
    elsif v_execution_request_ref is distinct from p_request_ref then
      v_errors := v_errors || jsonb_build_array('REQUEST_REF_EXECUTION_MISMATCH');
    end if;
  end if;

  if v_execution_request_ref is not null then
    if to_regprocedure('private.sbx_fn_lf_working_context_budget_gate_v1(text,bigint,interval)') is null then
      v_errors := v_errors || jsonb_build_array('BUDGET_GATE_DEPENDENCY_MISSING');
    else
      v_budget := private.sbx_fn_lf_working_context_budget_gate_v1(v_execution_request_ref,p_budget_limit,p_max_age);
      if coalesce((v_budget->>'authorized')::boolean,false) is not true then
        v_errors := v_errors || jsonb_build_array(coalesce(v_budget->>'reason','BUDGET_GATE_UNKNOWN_BLOCK'));
      end if;
    end if;
  end if;

  if p_execution_id is not null then
    select cp.* into v_pack
    from programacion.context_packs cp
    where cp.execution_id=p_execution_id
    order by cp.id desc
    limit 1;
    if not found then
      v_errors := v_errors || jsonb_build_array('CONTEXT_PACK_NOT_FOUND');
    else
      if v_pack.estado <> 'COMPLETE' then
        v_errors := v_errors || jsonb_build_array('CONTEXT_PACK_NOT_COMPLETE');
      end if;
      if v_pack.digest_version <> 2 then
        v_errors := v_errors || jsonb_build_array('CONTEXT_PACK_V2_REQUIRED');
      end if;
    end if;
  end if;

  if p_retrieval_run_id is not null then
    select rr.* into v_retrieval
    from programacion.retrieval_runs rr
    where rr.id=p_retrieval_run_id;
    if not found then
      v_errors := v_errors || jsonb_build_array('RETRIEVAL_NOT_FOUND');
    else
      if v_retrieval.execution_id is distinct from p_execution_id then
        v_errors := v_errors || jsonb_build_array('RETRIEVAL_EXECUTION_MISMATCH');
      else
        if v_retrieval.status <> 'PASS' then
          v_errors := v_errors || jsonb_build_array('RETRIEVAL_NOT_PASS');
        end if;
        if jsonb_typeof(v_retrieval.selected_payload) <> 'array' then
          v_errors := v_errors || jsonb_build_array('RETRIEVAL_SELECTED_PAYLOAD_REQUIRED');
        else
          select coalesce(jsonb_agg(jsonb_build_object(
              'source',f.value->>'source',
              'record_id',f.value->>'record_id',
              'content_sha256',f.value->>'content_sha256',
              'snapshot_sha256',f.value->'provenance'->>'snapshot_sha256'
            ) order by f.value->>'source',f.value->>'record_id'),'[]'::jsonb)
            into v_selected_refs
          from jsonb_array_elements(v_retrieval.selected_payload) f(value);
        end if;
        if v_retrieval.provenance_receipt_id is null then
          v_errors := v_errors || jsonb_build_array('RETRIEVAL_PROVENANCE_REQUIRED');
        else
          begin
            perform programacion.fn_assert_provenance_receipt(
              v_retrieval.provenance_receipt_id,
              'RETRIEVAL_PASS',
              p_execution_id,
              v_head_sha,
              'retrieval_context',
              'retrieval:'||p_execution_id::text,
              v_retrieval.context_sha256
            );
          exception when others then
            v_errors := v_errors || jsonb_build_array('RETRIEVAL_PROVENANCE_EXACT_BINDING_FAILED');
          end;
          select pr.* into v_receipt
          from programacion.provenance_receipts pr
          where pr.id=v_retrieval.provenance_receipt_id;
          if found and v_receipt.issuer_channel <> 'SOURCE_VERIFIER_V1' then
            v_errors := v_errors || jsonb_build_array('RETRIEVAL_PROVENANCE_WRONG_CHANNEL');
          end if;
        end if;
      end if;
    end if;
  end if;

  v_conditions_met := jsonb_array_length(v_errors)=0;

  return jsonb_build_object(
    'conditions_met',v_conditions_met,
    'errors',v_errors,
    'execution_id',p_execution_id,
    'request_ref',v_execution_request_ref,
    'context_pack_id',v_pack.id,
    'context_pack_sha256',v_pack.context_sha256,
    'retrieval_run_id',v_retrieval.id,
    'retrieval_context_sha256',v_retrieval.context_sha256,
    'digest_equality_required',false,
    'selected_refs',v_selected_refs,
    'retrieval_provenance_receipt_id',v_retrieval.provenance_receipt_id,
    'retrieval_provenance_verification_ref',v_receipt.verification_ref,
    'budget',v_budget,
    'authorization_scope','SANDBOX_PRE_MODEL_ADMISSION_ONLY',
    'model_call_authorized',false,
    'production_authorized',false
  );
end
$function$;

revoke all on function private.sbx_fn_lf_working_context_admission_v1(bigint,bigint,text,text,text,text,bigint,interval)
  from public, anon, authenticated, service_role;

comment on function private.sbx_fn_lf_working_context_admission_v1(bigint,bigint,text,text,text,text,bigint,interval) is
  'OP24 sandbox-only pre-model admission evaluator. Preserves distinct pack/retrieval hashes; requires same request, verified retrieval provenance and GREEN fresh budget; never authorizes a model call itself.';
