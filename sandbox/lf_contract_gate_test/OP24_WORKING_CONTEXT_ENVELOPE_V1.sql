-- OP24 Working Context Envelope V1 — sandbox harness
-- Contract-level verifier only. It does not perform retrieval or model calls.

create or replace function private.sbx_fn_lf_working_context_envelope_v1(
  p_envelope jsonb,
  p_expected_contract_version text
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'private'
as $function$
declare
  v_errors jsonb := '[]'::jsonb;
  v_estimated numeric;
  v_budget numeric;
  v_refs jsonb;
begin
  if p_envelope is null or jsonb_typeof(p_envelope) <> 'object' then
    return jsonb_build_object('valid', false, 'errors', jsonb_build_array('ENVELOPE_OBJECT_REQUIRED'));
  end if;

  if coalesce(p_envelope->>'contract_version','') <> coalesce(p_expected_contract_version,'') then
    v_errors := v_errors || jsonb_build_array('STALE_OR_WRONG_CONTRACT_VERSION');
  end if;

  if coalesce(p_envelope->>'context_sha256','') !~ '^[0-9a-f]{64}$' then
    v_errors := v_errors || jsonb_build_array('CONTEXT_SHA256_REQUIRED');
  end if;

  v_refs := p_envelope->'selected_refs';
  if jsonb_typeof(v_refs) <> 'array' or jsonb_array_length(v_refs) = 0 then
    v_errors := v_errors || jsonb_build_array('SELECTED_REFS_REQUIRED');
  end if;

  if length(btrim(coalesce(p_envelope->>'provenance_ref',''))) = 0 then
    v_errors := v_errors || jsonb_build_array('PROVENANCE_REF_REQUIRED');
  end if;

  if length(btrim(coalesce(p_envelope->>'request_id',''))) = 0
     or p_envelope->>'request_id' is distinct from p_envelope->>'consumer_request_id' then
    v_errors := v_errors || jsonb_build_array('SAME_REQUEST_BINDING_REQUIRED');
  end if;

  begin
    v_estimated := (p_envelope->>'estimated_tokens')::numeric;
    v_budget := (p_envelope->>'token_budget')::numeric;
  exception when others then
    v_errors := v_errors || jsonb_build_array('TOKEN_BUDGET_NUMERIC_REQUIRED');
  end;

  if v_estimated is not null and v_budget is not null then
    if v_estimated < 0 or v_budget <= 0 then
      v_errors := v_errors || jsonb_build_array('TOKEN_BUDGET_INVALID');
    elsif v_estimated > v_budget then
      v_errors := v_errors || jsonb_build_array('OVER_BUDGET');
    end if;
  end if;

  if coalesce(p_envelope->>'budget_status','') = '' then
    v_errors := v_errors || jsonb_build_array('BUDGET_STATUS_REQUIRED');
  elsif p_envelope->>'budget_status' = 'RED' then
    v_errors := v_errors || jsonb_build_array('BUDGET_STATUS_RED');
  end if;

  if length(btrim(coalesce(p_envelope->>'generated_at',''))) = 0 then
    v_errors := v_errors || jsonb_build_array('GENERATED_AT_REQUIRED');
  end if;

  return jsonb_build_object(
    'valid', jsonb_array_length(v_errors) = 0,
    'errors', v_errors,
    'authorization_scope', 'SANDBOX_ENVELOPE_ONLY',
    'retrieval_executed', false,
    'model_call_authorized', false
  );
end;
$function$;

revoke all on function private.sbx_fn_lf_working_context_envelope_v1(jsonb,text)
  from public, anon, authenticated, service_role;

comment on function private.sbx_fn_lf_working_context_envelope_v1(jsonb,text) is
  'OP24 sandbox-only Working Context envelope verifier. Does not retrieve or authorize model calls.';
