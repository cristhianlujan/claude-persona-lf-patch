begin;

alter function programacion.fn_engineering_capability_bind_receipt_v1(text,text,text)
  rename to fn_engineering_capability_bind_receipt_core_v1;

create or replace function programacion.fn_engineering_capability_bind_receipt_v1(
  p_plan_code text,
  p_unit_code text,
  p_checkpoint_code text
) returns jsonb
language plpgsql
volatile
set search_path to 'programacion','public','pg_catalog'
as $function$
declare
  v_receipt jsonb;
  v_orchestrator_execution_id text;
  v_consumer_execution_id text;
  v_count integer;
begin
  v_receipt:=programacion.fn_engineering_capability_bind_receipt_core_v1(
    p_plan_code,p_unit_code,p_checkpoint_code
  );

  if coalesce((v_receipt->>'ready')::boolean,false) is not true then
    raise exception 'ENGINEERING_CAPABILITY_BIND_CORE_NOT_READY:%',v_receipt;
  end if;

  v_orchestrator_execution_id:=nullif(btrim(coalesce(v_receipt->>'orchestrator_execution_id','')),'');
  v_consumer_execution_id:=nullif(btrim(coalesce(v_receipt->>'consumer_execution_id','')),'');
  if v_orchestrator_execution_id is null or v_consumer_execution_id is null then
    raise exception 'ENGINEERING_CAPABILITY_BIND_RECEIPT_IDS_MISSING';
  end if;

  update public.lf_operation_execution
     set status='COMPLETED',
         completed_at=clock_timestamp(),
         updated_by_execution_id=v_consumer_execution_id
   where execution_id=v_consumer_execution_id
     and status='IN_PROGRESS';
  get diagnostics v_count=row_count;
  if v_count<>1 then
    raise exception 'ENGINEERING_CAPABILITY_BIND_CONSUMER_COMPLETE_FAILED:%',v_consumer_execution_id;
  end if;

  update public.lf_operation_execution
     set status='COMPLETED',
         completed_at=clock_timestamp(),
         updated_by_execution_id=v_orchestrator_execution_id
   where execution_id=v_orchestrator_execution_id
     and status='IN_PROGRESS';
  get diagnostics v_count=row_count;
  if v_count<>1 then
    raise exception 'ENGINEERING_CAPABILITY_BIND_ORCHESTRATOR_COMPLETE_FAILED:%',v_orchestrator_execution_id;
  end if;

  return v_receipt || jsonb_build_object(
    'operation_receipts_completed',true,
    'consumer_operation_status','COMPLETED',
    'orchestrator_operation_status','COMPLETED'
  );
end;
$function$;

do $verify$
declare
  v_spec jsonb;
  v_packet jsonb;
begin
  if to_regprocedure('programacion.fn_engineering_capability_bind_receipt_core_v1(text,text,text)') is null
     or to_regprocedure('programacion.fn_engineering_capability_bind_receipt_v1(text,text,text)') is null then
    raise exception 'ENGINEERING_CAPABILITY_BIND_WRAPPER_MISSING';
  end if;

  v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN'
  );
  v_packet:=programacion.fn_engineering_execution_packet_from_spec_v1(
    'IG_CURATOR_VALIDATOR_REFACTOR_V2','M3.9','SHADOW_RUN',v_spec,'{}'::jsonb
  );
  if v_packet#>>'{connector_plan,0,executor_contract,entrypoint}'
       is distinct from 'programacion.fn_engineering_capability_bind_receipt_v1' then
    raise exception 'ENGINEERING_CAPABILITY_BIND_PACKET_ENTRYPOINT_DRIFT:%',
      v_packet#>>'{connector_plan,0,executor_contract,entrypoint}';
  end if;
  if coalesce((v_packet#>>'{connector_plan,0,executor_contract,complete_operation_receipts}')::boolean,false) is not true then
    raise exception 'ENGINEERING_CAPABILITY_BIND_PACKET_COMPLETION_CONTRACT_MISSING';
  end if;
end
$verify$;

commit;
