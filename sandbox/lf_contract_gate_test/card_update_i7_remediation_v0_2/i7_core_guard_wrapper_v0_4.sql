-- LF_CARD_UPDATE_I7_CORE_GUARD_WRAPPER_V0_4
-- Repairs IR-F01, IR-F02 and IR-F07 with a narrow wrapper around the frozen I4 core.
-- No carrier write, runtime activation, promotion or Router registration is enabled.

do $$
begin
  if to_regprocedure('public.lf_record_operation_step_core_legacy_i4_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)') is null then
    if to_regprocedure('public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text)') is null then
      raise exception 'I7_CORE_BASE_FUNCTION_MISSING';
    end if;
    execute 'alter function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) rename to lf_record_operation_step_core_legacy_i4_v1';
  end if;
end;
$$;

create or replace function public.lf_record_operation_step_core_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text,
  p_expected_operation_code text,
  p_expected_target_type text,
  p_contract_status text,
  p_binding_status text,
  p_judge_status text,
  p_trust_validation jsonb,
  p_close_on_report_output boolean,
  p_recorder_name text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_canonical_input jsonb;
  v_sanitized_payload jsonb;
  v_server_assertions jsonb;
  v_server_hard_fails jsonb;
  v_input_evidence_sha256 text;
  v_input_trust_sha256 text;
begin
  if p_evidence_payload is null or jsonb_typeof(p_evidence_payload) is distinct from 'object' then
    return jsonb_build_object('outcome','BLOCKED','code','EVIDENCE_PAYLOAD_INVALID','durable',false);
  end if;

  if p_trust_validation is null
     or jsonb_typeof(p_trust_validation) is distinct from 'object'
     or not (p_trust_validation ? 'valid')
     or jsonb_typeof(p_trust_validation->'valid') is distinct from 'boolean' then
    return jsonb_build_object('outcome','BLOCKED','code','TRUST_VALIDATION_INVALID','durable',false);
  end if;

  v_server_assertions:=coalesce(p_trust_validation->'server_assertions','[]'::jsonb);
  v_server_hard_fails:=coalesce(p_trust_validation->'server_hard_fails','[]'::jsonb);

  if jsonb_typeof(v_server_assertions) is distinct from 'array'
     or jsonb_typeof(v_server_hard_fails) is distinct from 'array' then
    return jsonb_build_object('outcome','BLOCKED','code','SERVER_JUDGE_EVIDENCE_ARRAYS_INVALID','durable',false);
  end if;

  if (p_trust_validation->'valid') is not distinct from 'true'::jsonb
     and not (p_trust_validation ? 'server_assertions') then
    return jsonb_build_object('outcome','BLOCKED','code','SERVER_ASSERTIONS_REQUIRED_FOR_VALID_TRUST','durable',false);
  end if;

  v_canonical_input:=p_evidence_payload - array[
    'assertions_checked','hard_fails_checked','input_evidence_sha256','input_trust_sha256',
    'caller_assertions_ignored','step_result','derived_result','derived_by_judge','mini_judge_code',
    'mini_judge_result','missing_pass_items','triggered_fail_items','attempt_history','recorded_by_rpc',
    'core_recorder','trust_validation','blocking_findings','return_to_worker_reasons'
  ]::text[];

  v_input_evidence_sha256:=encode(extensions.digest(v_canonical_input::text,'sha256'),'hex');
  v_input_trust_sha256:=encode(extensions.digest(p_trust_validation::text,'sha256'),'hex');

  v_sanitized_payload:=v_canonical_input||jsonb_build_object(
    'assertions_checked',v_server_assertions,
    'hard_fails_checked',v_server_hard_fails,
    'input_evidence_sha256',v_input_evidence_sha256,
    'input_trust_sha256',v_input_trust_sha256,
    'caller_assertions_ignored',true
  );

  return public.lf_record_operation_step_core_legacy_i4_v1(
    p_execution_id,p_step_id,p_evidence_ref,v_sanitized_payload,p_actor_execution_id,
    p_expected_operation_code,p_expected_target_type,p_contract_status,p_binding_status,p_judge_status,
    p_trust_validation,p_close_on_report_output,p_recorder_name
  );
end;
$function$;

revoke execute on function public.lf_record_operation_step_core_legacy_i4_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) from public,anon,authenticated;
revoke execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) from public,anon,authenticated;
grant execute on function public.lf_record_operation_step_core_legacy_i4_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) to service_role;
grant execute on function public.lf_record_operation_step_core_v1(text,text,text,jsonb,text,text,text,text,text,text,jsonb,boolean,text) to service_role;
