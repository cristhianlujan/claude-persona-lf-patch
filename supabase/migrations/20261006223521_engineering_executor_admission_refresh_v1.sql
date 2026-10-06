-- ENGINEERING contract sanitation split 3b: executor admission on freshly compiled authority.

create or replace function programacion.fn_engineering_unit_execution_admission_v1(
  p_plan_code text,
  p_unit_code text
)
returns jsonb
language plpgsql
stable
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_boot jsonb;
  v_admitted boolean;
begin
  v_boot:=programacion.fn_engineering_bootstrap_refresh_execution_v1(
    p_plan_code,
    p_unit_code,
    programacion.fn_engineering_unit_bootstrap_v3(p_plan_code,p_unit_code)
  );

  v_admitted :=
    v_boot#>>'{current_checkpoint,checkpoint_code}' is not null
    and coalesce(v_boot#>>'{action_spec,status}','')='READY'
    and coalesce(v_boot#>>'{execution_packet,status}','')='READY'
    and coalesce((v_boot#>>'{execution_readiness,execution_ready}')::boolean,false)
    and coalesce(v_boot->>'terminal_action','')='CONTINUE_CURRENT_CHECKPOINT'
    and coalesce((v_boot->>'execution_allowed')::boolean,true);

  return jsonb_build_object(
    'schema_version','ENGINEERING_UNIT_EXECUTION_ADMISSION_V1',
    'plan_code',p_plan_code,
    'unit_code',p_unit_code,
    'checkpoint_code',v_boot#>>'{current_checkpoint,checkpoint_code}',
    'admitted',v_admitted,
    'action_spec_status',v_boot#>>'{action_spec,status}',
    'contract_source',v_boot#>>'{action_spec,contract_source}',
    'packet_status',v_boot#>>'{execution_packet,status}',
    'execution_ready',coalesce((v_boot#>>'{execution_readiness,execution_ready}')::boolean,false),
    'terminal_action',v_boot->>'terminal_action',
    'reasons',coalesce(
      v_boot#>'{execution_readiness,reasons}',
      v_boot#>'{execution_packet,block_reasons}',
      '[]'::jsonb
    )
  );
end;
$function$;

comment on function programacion.fn_engineering_unit_execution_admission_v1(text,text)
is 'Executor admission evaluates freshly compiled current checkpoint authority before lane claim.';
