-- LF_CARD_UPDATE_I7_SERVER_VALIDATION_ADAPTER_V0_4
-- Composes v3 deterministic step validation, reversible baseline validation and I4 trust validation.
-- Keeps step >80 blocked and Google/GitHub carrier writes unauthorized.

create or replace function public.lf_validate_card_update_step_evidence_v4(
  p_execution_id text,
  p_step_id text,
  p_evidence_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_result jsonb;
  v_baseline jsonb;
  v_assertions jsonb:=jsonb_build_array(
    'required evidence present',
    'prior required steps clean',
    'Supabase operational authority preserved',
    'external carrier not used as authority'
  );
begin
  if p_step_id='pre_write_execution_binding_gate' then
    v_result:=public.lf_validate_card_update_trust_v1(p_execution_id,p_step_id,p_evidence_payload);
    if v_result is null or jsonb_typeof(v_result) is distinct from 'object' or not (v_result ? 'valid') or jsonb_typeof(v_result->'valid') is distinct from 'boolean' then
      return jsonb_build_object('valid',false,'code','CARD_TRUST_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    if (v_result->'valid') is not distinct from 'true'::jsonb then
      return v_result||jsonb_build_object('server_assertions',v_assertions,'server_hard_fails','[]'::jsonb,'validation_scope','SERVER_TRUST_EXACT');
    end if;
    return v_result||jsonb_build_object('server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb,'validation_scope','SERVER_TRUST_BLOCKED');
  end if;

  v_result:=public.lf_validate_card_update_step_evidence_v3(p_execution_id,p_step_id,p_evidence_payload);
  if v_result is null or jsonb_typeof(v_result) is distinct from 'object' or (v_result->'valid') is distinct from 'true'::jsonb then
    return coalesce(v_result,jsonb_build_object('valid',false,'code','CARD_STEP_V3_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb));
  end if;

  if p_step_id='baseline_read' then
    v_baseline:=public.lf_validate_card_reversible_baseline_v1(p_execution_id,p_evidence_payload);
    if (v_baseline->'valid') is distinct from 'true'::jsonb then
      return jsonb_build_object(
        'valid',false,
        'code','CARD_STEP_BASELINE_REVERSIBILITY_FAILED',
        'baseline_validation',v_baseline,
        'server_assertions','[]'::jsonb,
        'server_hard_fails','[]'::jsonb
      );
    end if;
    v_result:=v_result||jsonb_build_object('baseline_validation',v_baseline);
  end if;

  return v_result;
end;
$function$;

create or replace function public.lf_record_card_operation_step_v1(
  p_execution_id text,
  p_step_id text,
  p_evidence_ref text,
  p_evidence_payload jsonb,
  p_actor_execution_id text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_step_order integer;
  v_server_validation jsonb;
begin
  select step_order into v_step_order
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_CARD_LF'
    and step_id=p_step_id
    and active is true;
  if v_step_order is null then
    return jsonb_build_object('outcome','BLOCKED','code','STEP_NOT_ACTIVE','durable',false);
  end if;

  if v_step_order>80 then
    v_server_validation:=jsonb_build_object(
      'valid',false,
      'code','CARD_UPDATE_WRITE_PHASE_NOT_AUTHORIZED_I7',
      'details',jsonb_build_object('step_order',v_step_order,'ceiling_step_order',80),
      'server_assertions','[]'::jsonb,
      'server_hard_fails',jsonb_build_array('runtime or automatic promotion requested')
    );
  else
    v_server_validation:=public.lf_validate_card_update_step_evidence_v4(p_execution_id,p_step_id,p_evidence_payload);
  end if;

  return public.lf_record_operation_step_core_v1(
    p_execution_id,p_step_id,p_evidence_ref,p_evidence_payload,p_actor_execution_id,
    'ACTUALIZACION_CARD_LF','CARD','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY','CANDIDATO_READ_ONLY',
    v_server_validation,true,'lf_record_card_operation_step_v1'
  );
end;
$function$;

revoke execute on function public.lf_validate_card_update_step_evidence_v4(text,text,jsonb) from public,anon,authenticated;
revoke execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_step_evidence_v4(text,text,jsonb) to service_role;
grant execute on function public.lf_record_card_operation_step_v1(text,text,text,jsonb,text) to service_role;
