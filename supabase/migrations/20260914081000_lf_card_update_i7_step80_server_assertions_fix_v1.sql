-- LF_CARD_UPDATE_I7_STEP80_SERVER_ASSERTIONS_FIX_V1
-- Step 80 must preserve the trust validator's server-derived assertions exactly.
-- No provider/carrier write or runtime activation.

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
begin
  if p_step_id='pre_write_execution_binding_gate' then
    v_result:=public.lf_validate_card_update_trust_v1(p_execution_id,p_step_id,p_evidence_payload);
    if v_result is null or jsonb_typeof(v_result) is distinct from 'object'
       or not (v_result ? 'valid') or jsonb_typeof(v_result->'valid') is distinct from 'boolean' then
      return jsonb_build_object('valid',false,'code','CARD_TRUST_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    if (v_result->'valid') is not distinct from 'true'::jsonb then
      if jsonb_typeof(v_result->'server_assertions') is distinct from 'array'
         or jsonb_typeof(coalesce(v_result->'server_hard_fails','[]'::jsonb)) is distinct from 'array' then
        return jsonb_build_object('valid',false,'code','CARD_TRUST_SERVER_JUDGE_ARRAYS_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
      end if;
      return v_result||jsonb_build_object('validation_scope','SERVER_TRUST_EXACT');
    end if;
    return v_result||jsonb_build_object('server_assertions','[]'::jsonb,'server_hard_fails',coalesce(v_result->'server_hard_fails','[]'::jsonb),'validation_scope','SERVER_TRUST_BLOCKED');
  end if;

  v_result:=public.lf_validate_card_update_step_evidence_v3(p_execution_id,p_step_id,p_evidence_payload);
  if v_result is null or jsonb_typeof(v_result) is distinct from 'object' or (v_result->'valid') is distinct from 'true'::jsonb then
    return coalesce(v_result,jsonb_build_object('valid',false,'code','CARD_STEP_V3_RESULT_INVALID','server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb));
  end if;

  if p_step_id='baseline_read' then
    v_baseline:=public.lf_validate_card_reversible_baseline_v1(p_execution_id,p_evidence_payload);
    if (v_baseline->'valid') is distinct from 'true'::jsonb then
      return jsonb_build_object('valid',false,'code','CARD_STEP_BASELINE_REVERSIBILITY_FAILED','baseline_validation',v_baseline,'server_assertions','[]'::jsonb,'server_hard_fails','[]'::jsonb);
    end if;
    v_result:=v_result||jsonb_build_object('baseline_validation',v_baseline);
  end if;

  return v_result;
end;
$function$;

revoke execute on function public.lf_validate_card_update_step_evidence_v4(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.lf_validate_card_update_step_evidence_v4(text,text,jsonb) to service_role;
