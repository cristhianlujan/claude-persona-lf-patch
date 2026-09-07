\set ON_ERROR_STOP on

begin;

insert into public.lf_operation_execution(
  execution_id,operation_code,target_type,target_code,status,manifest,created_by_execution_id
) values (
  'EXEC-OP24-STRATEGY-UPDATE-TOPOLOGY-CANARY-20260907-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_PROTOCOL_REPAIR',
  'ACTUALIZACION_ESTRATEGIA_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'mode','OP24_STRATEGY_UPDATE_TOPOLOGY_ROLLBACK_CANARY',
    'scope','materialize 14 step-contracts + 14 mini-judges + 14 bindings inside rollback only',
    'governance_bootstrap',true,
    'bootstrap_operation_code','ACTUALIZACION_ESTRATEGIA_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'runtime_allowed',false,
    'production_allowed',false,
    'router_activation_allowed',false
  ),
  'EXEC-OP24-STRATEGY-UPDATE-TOPOLOGY-CANARY-20260907-001'
);

set local op24.bootstrap_execution_id = 'EXEC-OP24-STRATEGY-UPDATE-TOPOLOGY-CANARY-20260907-001';
\ir OP24_STRATEGY_UPDATE_TOPOLOGY_V1.sql

do $assert$
declare
  v_steps integer;
  v_contracts integer;
  v_judges integer;
  v_bindings integer;
  v_bad_required integer;
  v_bad_binding integer;
  v_route_status text;
  v_operation_status text;
begin
  select count(*) into v_steps
  from public.lf_operation_steps
  where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and active and required;

  select count(*) into v_contracts
  from public.lf_operation_step_contracts
  where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT';

  select count(*) into v_judges
  from public.lf_operation_judges
  where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT';

  select count(*) into v_bindings
  from public.lf_operation_step_judge_bindings
  where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT';

  if v_steps<>14 or v_contracts<>14 or v_judges<>14 or v_bindings<>14 then
    raise exception 'TOPOLOGY_COUNT_MISMATCH steps=% contracts=% judges=% bindings=%',v_steps,v_contracts,v_judges,v_bindings;
  end if;

  select count(*) into v_bad_required
  from public.lf_operation_steps s
  join public.lf_operation_step_contracts c
    on c.operation_code=s.operation_code and c.step_id=s.step_id
  where s.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and s.active and s.required
    and c.required_evidence_keys is distinct from to_jsonb(regexp_split_to_array(s.evidence_required, '\s*;\s*|\s*,\s*'));
  if v_bad_required<>0 then
    raise exception 'REQUIRED_EVIDENCE_BINDING_DRIFT:%',v_bad_required;
  end if;

  select count(*) into v_bad_binding
  from public.lf_operation_step_judge_bindings b
  left join public.lf_operation_judges j
    on j.operation_code=b.operation_code and j.judge_code=b.judge_code and j.status='ACTIVE_ENFORCEMENT'
  left join public.lf_operation_step_contracts c
    on c.operation_code=b.operation_code and c.step_order=b.step_order and c.step_id=b.step_id and c.status='ACTIVE_ENFORCEMENT'
  where b.operation_code='ACTUALIZACION_ESTRATEGIA_LF'
    and b.status='ACTIVE_ENFORCEMENT'
    and (j.judge_code is null or c.step_id is null or c.mini_judge_code is distinct from b.judge_code or c.required_evidence_keys is distinct from b.required_evidence_keys);
  if v_bad_binding<>0 then
    raise exception 'TOPOLOGY_BINDING_DRIFT:%',v_bad_binding;
  end if;

  select status into v_route_status
  from public.lf_router_action_registry
  where asset_type='STRATEGY' and action_code='UPDATE';
  if v_route_status is distinct from 'CANDIDATO_READ_ONLY' then
    raise exception 'ROUTER_ACTIVATED_UNEXPECTEDLY:%',coalesce(v_route_status,'<missing>');
  end if;

  select status into v_operation_status
  from public.lf_operation_registry
  where operation_code='ACTUALIZACION_ESTRATEGIA_LF';
  if v_operation_status is distinct from 'CANDIDATO_READ_ONLY' then
    raise exception 'OPERATION_PROMOTED_UNEXPECTEDLY:%',coalesce(v_operation_status,'<missing>');
  end if;

  begin
    insert into public.lf_operation_judges(
      operation_code,judge_code,judge_path,pass_if,fail_if,result_values,status,created_by_execution_id
    ) values (
      'ACTUALIZACION_ESTRATEGIA_LF','JUDGE_STRATEGY_UPDATE_ROUTER_V1','duplicate://negative',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'ACTIVE_ENFORCEMENT',
      'EXEC-OP24-STRATEGY-UPDATE-TOPOLOGY-CANARY-20260907-001'
    );
    raise exception 'EXPECTED_DUPLICATE_JUDGE_REJECTION';
  exception when unique_violation then
    null;
  end;
end
$assert$;

rollback;

do $post$
begin
  if exists(select 1 from public.lf_operation_step_contracts where operation_code='ACTUALIZACION_ESTRATEGIA_LF') then
    raise exception 'STEP_CONTRACT_RESIDUE';
  end if;
  if exists(select 1 from public.lf_operation_judges where operation_code='ACTUALIZACION_ESTRATEGIA_LF') then
    raise exception 'JUDGE_RESIDUE';
  end if;
  if exists(select 1 from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_ESTRATEGIA_LF') then
    raise exception 'BINDING_RESIDUE';
  end if;
  if exists(select 1 from public.lf_operation_execution where execution_id='EXEC-OP24-STRATEGY-UPDATE-TOPOLOGY-CANARY-20260907-001') then
    raise exception 'EXECUTION_RESIDUE';
  end if;
end
$post$;
