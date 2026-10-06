-- ENGINEERING contract sanitation split 3a: refresh current execution authority.

create or replace function programacion.fn_engineering_bootstrap_refresh_execution_v1(
  p_plan_code text,
  p_unit_code text,
  p_payload jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_out jsonb := p_payload;
  v_cp text;
  v_spec jsonb;
  v_packet jsonb;
  v_readiness jsonb;
  v_input jsonb;
begin
  v_cp:=v_out#>>'{current_checkpoint,checkpoint_code}';
  if v_cp is null then
    return v_out;
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    p_plan_code,p_unit_code,v_cp
  );
  v_input:=coalesce(
    v_out#>'{execution_packet,execution_input}',
    v_out->'execution_input',
    '{}'::jsonb
  );
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    p_plan_code,p_unit_code,v_cp,coalesce(v_spec,'{}'::jsonb),v_input
  );

  if v_out#>'{context_snapshot,unit_metadata}' is not null then
    v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_context_v1(
      v_cp,
      coalesce(v_spec,'{}'::jsonb),
      coalesce(v_packet,'{}'::jsonb),
      v_out#>'{context_snapshot,unit_metadata}'
    );
  else
    v_readiness:=programacion.fn_engineering_checkpoint_execution_readiness_from_payload_v1(
      p_plan_code,p_unit_code,v_cp,
      coalesce(v_spec,'{}'::jsonb),
      coalesce(v_packet,'{}'::jsonb)
    );
  end if;

  v_out:=jsonb_set(v_out,'{action_spec}',coalesce(v_spec,'null'::jsonb),true);
  v_out:=jsonb_set(v_out,'{execution_packet}',coalesce(v_packet,'null'::jsonb),true);
  v_out:=v_out||jsonb_build_object('execution_readiness',v_readiness);

  if coalesce(v_out->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
     and not coalesce((v_readiness->>'execution_ready')::boolean,false) then
    v_out:=v_out||jsonb_build_object(
      'terminal_action','STOP_EXECUTION_PREFLIGHT',
      'execution_allowed',false,
      'preflight_block',jsonb_build_object(
        'status','NOT_READY',
        'checkpoint_code',v_cp,
        'reasons',coalesce(v_readiness->'reasons','[]'::jsonb),
        'gates',coalesce(v_readiness->'gates','{}'::jsonb),
        'next_action','FIX_PREFLIGHT_CONTRACT_BEFORE_CONNECTOR_EXECUTION'
      )
    );
  elsif coalesce((v_readiness->>'execution_ready')::boolean,false) then
    v_out:=v_out||jsonb_build_object('execution_allowed',true);
  end if;

  return v_out;
end;
$function$;

comment on function programacion.fn_engineering_bootstrap_refresh_execution_v1(text,text,jsonb)
is 'Refreshes current Action Spec, packet and readiness so cached snapshot context cannot preserve stale READY execution authority.';
