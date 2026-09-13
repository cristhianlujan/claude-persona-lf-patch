begin;

-- S30 Strategy Factory release: activate the existing governed control-plane
-- without raising the strategy artifact ceiling. Generated strategies remain
-- CANDIDATO_READ_ONLY / PLAN_ONLY / automatic impact BLOQUEADO.
do $guard$
declare
  v_count integer;
  v_required integer;
  v_resolved integer;
begin
  select count(*) into v_count
  from public.lf_operation_registry
  where operation_code='CREACION_ESTRATEGIA_LF'
    and status='CANDIDATO_READ_ONLY';
  if v_count <> 1 then
    raise exception 'S30_STRATEGY_FACTORY_REGISTRY_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_router_action_registry
  where asset_type='STRATEGY'
    and action_code='STRATEGY_CREATE'
    and operation_code='CREACION_ESTRATEGIA_LF'
    and operation_resolution='STATIC'
    and status='ACTIVE'
    and requires_existing_target=false
    and requires_missing_target=true
    and write_allowed=true;
  if v_count <> 1 then
    raise exception 'S30_STRATEGY_FACTORY_ROUTE_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_contracts
  where operation_code='CREACION_ESTRATEGIA_LF'
    and contract_code='CONTRACT-CREACION-ESTRATEGIA-LF-v0.3.2'
    and status='CANDIDATO_READ_ONLY'
    and contract_sha='2c469e3cd2ae7bb7171ca4e52fc6da84b58af3a3'
    and allowed->>'strategy_status'='CANDIDATO_READ_ONLY'
    and allowed->>'runtime_state'='PLAN_ONLY'
    and allowed->>'automatic_impact'='BLOQUEADO';
  if v_count <> 1 then
    raise exception 'S30_STRATEGY_FACTORY_CONTRACT_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_contracts
  where operation_code='CREACION_ESTRATEGIA_LF'
    and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO');
  if v_count <> 0 then
    raise exception 'S30_STRATEGY_FACTORY_UNEXPECTED_ACTIVE_CONTRACT:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_steps
  where operation_code='CREACION_ESTRATEGIA_LF' and active and required;
  if v_count <> 43 then
    raise exception 'S30_STRATEGY_FACTORY_REQUIRED_STEP_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_step_contracts
  where operation_code='CREACION_ESTRATEGIA_LF'
    and status='CANDIDATO_READ_ONLY';
  if v_count <> 43 then
    raise exception 'S30_STRATEGY_FACTORY_STEP_CONTRACT_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_judges
  where operation_code='CREACION_ESTRATEGIA_LF'
    and status='CANDIDATO_READ_ONLY';
  if v_count <> 43 then
    raise exception 'S30_STRATEGY_FACTORY_JUDGE_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_operation_step_judge_bindings
  where operation_code='CREACION_ESTRATEGIA_LF'
    and status='COMPLETE';
  if v_count <> 43 then
    raise exception 'S30_STRATEGY_FACTORY_JUDGE_BINDING_PRECONDITION:%', v_count;
  end if;

  select count(*) into v_count
  from public.lf_policy_versions
  where policy_code='POL-STRATEGY-CREATION-001'
    and policy_version='v0.1-candidate'
    and policy_sha='563b91a1e5405c1e1f8806c1f8d12b8ab2dfbd901638f7b432a3e601cc2558fc'
    and status='CANDIDATE'
    and policy_payload->>'status_ceiling'='CANDIDATE_ONLY';
  if v_count <> 1 then
    raise exception 'S30_STRATEGY_FACTORY_POLICY_PRECONDITION:%', v_count;
  end if;

  select count(*) filter (where required),
         count(*) filter (where required and policy_sha is not null)
    into v_required,v_resolved
  from public.v_lf_operation_policy_snapshot
  where operation_code='CREACION_ESTRATEGIA_LF'
    and 'ROUTER'=any(distribution_modes);
  if v_required <> 5 or v_resolved <> 4 then
    raise exception 'S30_STRATEGY_FACTORY_POLICY_BASELINE:%:%', v_required,v_resolved;
  end if;
end
$guard$;

-- Resolve the last required Strategy Factory policy. Its payload remains
-- candidate-only; ACTIVE here means enforce this policy during governed creation.
update public.lf_policy_versions
set status='ACTIVE'
where policy_code='POL-STRATEGY-CREATION-001'
  and policy_version='v0.1-candidate'
  and policy_sha='563b91a1e5405c1e1f8806c1f8d12b8ab2dfbd901638f7b432a3e601cc2558fc'
  and status='CANDIDATE';

update public.lf_operation_contracts
set status='ACTIVE_ENFORCEMENT'
where operation_code='CREACION_ESTRATEGIA_LF'
  and contract_code='CONTRACT-CREACION-ESTRATEGIA-LF-v0.3.2'
  and status='CANDIDATO_READ_ONLY';

update public.lf_operation_step_contracts
set status='ACTIVE'
where operation_code='CREACION_ESTRATEGIA_LF'
  and status='CANDIDATO_READ_ONLY';

update public.lf_operation_judges
set status='ACTIVE_ENFORCEMENT'
where operation_code='CREACION_ESTRATEGIA_LF'
  and status='CANDIDATO_READ_ONLY';

update public.lf_operation_step_judge_bindings
set status='ACTIVE_ENFORCEMENT'
where operation_code='CREACION_ESTRATEGIA_LF'
  and status='COMPLETE';

update public.lf_operation_registry
set version='v0.3.2',
    status='PRODUCCION_CONTROLADA_READ_ONLY',
    notes='S30 governed Strategy Factory v0.3.2 released for controlled candidate creation. Strategy artifacts remain CANDIDATO_READ_ONLY, PLAN_ONLY and automatic impact BLOQUEADO; runtime and automatic production promotion remain forbidden.'
where operation_code='CREACION_ESTRATEGIA_LF'
  and status='CANDIDATO_READ_ONLY';

do $verify$
declare
  v_count integer;
  v_required integer;
  v_resolved integer;
begin
  select count(*) into v_count from public.lf_operation_registry
  where operation_code='CREACION_ESTRATEGIA_LF'
    and version='v0.3.2'
    and status='PRODUCCION_CONTROLADA_READ_ONLY';
  if v_count <> 1 then raise exception 'S30_STRATEGY_FACTORY_REGISTRY_VERIFY:%',v_count; end if;

  select count(*) into v_count from public.lf_operation_contracts
  where operation_code='CREACION_ESTRATEGIA_LF'
    and contract_code='CONTRACT-CREACION-ESTRATEGIA-LF-v0.3.2'
    and status='ACTIVE_ENFORCEMENT'
    and allowed->>'strategy_status'='CANDIDATO_READ_ONLY'
    and allowed->>'runtime_state'='PLAN_ONLY'
    and allowed->>'automatic_impact'='BLOQUEADO';
  if v_count <> 1 then raise exception 'S30_STRATEGY_FACTORY_CONTRACT_VERIFY:%',v_count; end if;

  select count(*) into v_count from public.lf_operation_step_contracts
  where operation_code='CREACION_ESTRATEGIA_LF' and status='ACTIVE';
  if v_count <> 43 then raise exception 'S30_STRATEGY_FACTORY_STEP_CONTRACT_VERIFY:%',v_count; end if;

  select count(*) into v_count from public.lf_operation_judges
  where operation_code='CREACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT';
  if v_count <> 43 then raise exception 'S30_STRATEGY_FACTORY_JUDGE_VERIFY:%',v_count; end if;

  select count(*) into v_count from public.lf_operation_step_judge_bindings
  where operation_code='CREACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT';
  if v_count <> 43 then raise exception 'S30_STRATEGY_FACTORY_BINDING_VERIFY:%',v_count; end if;

  select count(*) filter (where required),
         count(*) filter (where required and policy_sha is not null)
    into v_required,v_resolved
  from public.v_lf_operation_policy_snapshot
  where operation_code='CREACION_ESTRATEGIA_LF'
    and 'ROUTER'=any(distribution_modes);
  if v_required = 0 or v_required <> v_resolved then
    raise exception 'S30_STRATEGY_FACTORY_POLICY_VERIFY:%:%',v_required,v_resolved;
  end if;
end
$verify$;

commit;
