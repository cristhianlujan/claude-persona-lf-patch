begin;

do $preflight$
begin
  if exists (
    select 1 from public.lf_operation_registry
    where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF')
  ) then
    raise exception 'S30_POLICY_CANARY_TARGET_OPERATION_ALREADY_EXISTS';
  end if;
  if exists (
    select 1 from public.lf_router_action_registry
    where asset_type='REGLA' and action_code in ('POLICY_CREATE','POLICY_UPDATE')
  ) then
    raise exception 'S30_POLICY_CANARY_TARGET_ROUTE_ALREADY_EXISTS';
  end if;
end;
$preflight$;

insert into public.lf_operation_execution(
  execution_id, operation_code, target_type, target_code, status, manifest, created_by_execution_id
) values
(
  'EXEC-S30-POLICY-CREATE-CANARY-20260909-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_CODE',
  'CREACION_POLITICA_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'governance_bootstrap',true,
    'bootstrap_operation_code','CREACION_POLITICA_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'source_branch','lf/s30-policy-operations-candidate-20260909',
    'claim_ceiling','ROLLBACK_ONLY_CANDIDATE_NO_ACTIVATION_NO_PRODUCTION'
  ),
  'EXEC-S30-POLICY-CREATE-CANARY-20260909-001'
),
(
  'EXEC-S30-POLICY-UPDATE-CANARY-20260909-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION_CODE',
  'ACTUALIZACION_POLITICA_LF',
  'IN_PROGRESS',
  jsonb_build_object(
    'governance_bootstrap',true,
    'bootstrap_operation_code','ACTUALIZACION_POLITICA_LF',
    'bootstrap_status_ceiling','SANDBOX_ACTIVE',
    'source_branch','lf/s30-policy-operations-candidate-20260909',
    'claim_ceiling','ROLLBACK_ONLY_CANDIDATE_NO_ACTIVATION_NO_PRODUCTION'
  ),
  'EXEC-S30-POLICY-UPDATE-CANARY-20260909-001'
);

insert into public.lf_operation_registry(
  operation_code, version, status, source_model, source_repo, source_paths, notes,
  operation_family, operation_domain, operation_type, applies_to_asset_type,
  created_by_execution_id, updated_by_execution_id
) values
(
  'CREACION_POLITICA_LF','v0.1','CANDIDATO_READ_ONLY','GIT_FIRST_YAML',
  'cristhianlujan/claude-persona-lf-patch',
  '["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/validate_policy_operations_candidate.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/test_policy_operations_candidate.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/rollback_canary.sql"]'::jsonb,
  'S30 candidate only. Create REGLA/POLICY_* asset plus first CANDIDATE policy version. No Router ACTIVE, runtime, production or automatic promotion.',
  'GOVERNANCE','POLICY_LIFECYCLE','CREATION_PROTOCOL','REGLA',
  'EXEC-S30-POLICY-CREATE-CANARY-20260909-001','EXEC-S30-POLICY-CREATE-CANARY-20260909-001'
),
(
  'ACTUALIZACION_POLITICA_LF','v0.1','CANDIDATO_READ_ONLY','GIT_FIRST_YAML',
  'cristhianlujan/claude-persona-lf-patch',
  '["sandbox/lf_contract_gate_test/s30_policy_operations_candidate/policy_operations_contract.yaml","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/validate_policy_operations_candidate.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/test_policy_operations_candidate.py","sandbox/lf_contract_gate_test/s30_policy_operations_candidate/rollback_canary.sql"]'::jsonb,
  'S30 candidate only. Create successor CANDIDATE policy version without overwriting prior authority. Supersession requires later verified promotion gate.',
  'GOVERNANCE','POLICY_LIFECYCLE','UPDATE_PROTOCOL','REGLA',
  'EXEC-S30-POLICY-UPDATE-CANARY-20260909-001','EXEC-S30-POLICY-UPDATE-CANARY-20260909-001'
);

insert into public.lf_router_action_registry(
  asset_type, action_code, operation_code, operation_resolution,
  requires_existing_target, requires_missing_target, write_allowed, status, notes,
  created_by_execution_id, updated_by_execution_id
) values
(
  'REGLA','POLICY_CREATE','CREACION_POLITICA_LF','STATIC',false,true,true,'CANDIDATE_SANDBOX',
  'Derived candidate naming from existing asset-specific Router convention; not canonical until reviewed/promoted.',
  'EXEC-S30-POLICY-CREATE-CANARY-20260909-001','EXEC-S30-POLICY-CREATE-CANARY-20260909-001'
),
(
  'REGLA','POLICY_UPDATE','ACTUALIZACION_POLITICA_LF','STATIC',true,false,true,'CANDIDATE_SANDBOX',
  'Derived candidate naming from existing asset-specific Router convention; not canonical until reviewed/promoted.',
  'EXEC-S30-POLICY-UPDATE-CANARY-20260909-001','EXEC-S30-POLICY-UPDATE-CANARY-20260909-001'
);

do $positive$
declare
  v_ops integer;
  v_routes integer;
begin
  select count(*) into v_ops
  from public.lf_operation_registry
  where operation_code in ('CREACION_POLITICA_LF','ACTUALIZACION_POLITICA_LF')
    and status='CANDIDATO_READ_ONLY'
    and applies_to_asset_type='REGLA';
  select count(*) into v_routes
  from public.lf_router_action_registry
  where asset_type='REGLA'
    and action_code in ('POLICY_CREATE','POLICY_UPDATE')
    and status='CANDIDATE_SANDBOX'
    and write_allowed=true;
  if v_ops <> 2 or v_routes <> 2 then
    raise exception 'S30_POLICY_CANARY_POSITIVE_READBACK_FAILED ops=% routes=%',v_ops,v_routes;
  end if;
end;
$positive$;

do $duplicate_route_negative$
declare
  v_blocked boolean := false;
begin
  begin
    insert into public.lf_router_action_registry(
      asset_type,action_code,operation_code,operation_resolution,
      requires_existing_target,requires_missing_target,write_allowed,status,
      created_by_execution_id,updated_by_execution_id
    ) values (
      'REGLA','POLICY_CREATE','CREACION_POLITICA_LF','STATIC',false,true,true,'CANDIDATE_SANDBOX',
      'EXEC-S30-POLICY-CREATE-CANARY-20260909-001','EXEC-S30-POLICY-CREATE-CANARY-20260909-001'
    );
  exception when unique_violation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'S30_POLICY_CANARY_DUPLICATE_ROUTE_NOT_BLOCKED';
  end if;
end;
$duplicate_route_negative$;

do $contradictory_flags_negative$
declare
  v_blocked boolean := false;
begin
  begin
    insert into public.lf_router_action_registry(
      asset_type,action_code,operation_code,operation_resolution,
      requires_existing_target,requires_missing_target,write_allowed,status,
      created_by_execution_id,updated_by_execution_id
    ) values (
      'REGLA','POLICY_INVALID_FLAGS_CANARY','CREACION_POLITICA_LF','STATIC',true,true,true,'CANDIDATE_SANDBOX',
      'EXEC-S30-POLICY-CREATE-CANARY-20260909-001','EXEC-S30-POLICY-CREATE-CANARY-20260909-001'
    );
  exception when check_violation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'S30_POLICY_CANARY_CONTRADICTORY_FLAGS_NOT_BLOCKED';
  end if;
end;
$contradictory_flags_negative$;

rollback;
