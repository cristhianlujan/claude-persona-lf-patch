insert into public.lf_operation_policy_bindings(
  operation_code,policy_code,policy_role,required,distribution_modes,binding_status,
  created_by_execution_id,updated_by_execution_id
) values (
  'LEARNING_BRIDGE_KB_CARD_LF','POL-LF-OPERATION-LIFECYCLE','OPERATION_LIFECYCLE',true,ARRAY['ROUTER']::text[],'ACTIVE',
  'LF-AUTOLEARN-RUN-20260831-024','LF-AUTOLEARN-RUN-20260831-024'
)
on conflict (operation_code,policy_code,policy_role) do update set
  required=excluded.required,
  distribution_modes=excluded.distribution_modes,
  binding_status=excluded.binding_status,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=now();

insert into public.lf_operation_judges(
  operation_code,judge_code,judge_path,judge_sha,pass_if,fail_if,result_values,status,
  created_by_execution_id,updated_by_execution_id
)
select
  sc.operation_code,
  sc.mini_judge_code,
  'supabase://public/lf_operation_step_contracts/'||sc.operation_code||'/'||sc.step_order||'/'||sc.step_id,
  'CONTRACT_LEARNING_BRIDGE_'||upper(regexp_replace(sc.step_id,'[^A-Za-z0-9]+','_','g'))||'_V1',
  jsonb_build_object('step_contract_present',true,'required_evidence_keys_present',true),
  jsonb_build_object('step_contract_missing',true,'required_evidence_missing',true),
  jsonb_build_object(
    'pass','STEP_CLEAN_PASS',
    'return','RETURN_TO_WORKER_FOR_SELF_REPAIR',
    'blocked',sc.blocking_code
  ),
  'ACTIVE_ENFORCEMENT',
  'LF-AUTOLEARN-RUN-20260831-024','LF-AUTOLEARN-RUN-20260831-024'
from public.lf_operation_step_contracts sc
where sc.operation_code='LEARNING_BRIDGE_KB_CARD_LF'
  and sc.status='ACTIVE_ENFORCEMENT'
  and sc.mini_judge_code is not null
on conflict (operation_code,judge_code) do update set
  judge_path=excluded.judge_path,
  judge_sha=excluded.judge_sha,
  pass_if=excluded.pass_if,
  fail_if=excluded.fail_if,
  result_values=excluded.result_values,
  status=excluded.status,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=now();

insert into public.lf_operation_step_judge_bindings(
  operation_code,step_order,step_id,judge_code,
  clean_result_value,blocked_result_value,return_result_value,required_evidence_keys,status,
  created_by_execution_id,updated_by_execution_id
)
select
  sc.operation_code,sc.step_order,sc.step_id,sc.mini_judge_code,
  'STEP_CLEAN_PASS',sc.blocking_code,'RETURN_TO_WORKER_FOR_SELF_REPAIR',sc.required_evidence_keys,'ACTIVE_ENFORCEMENT',
  'LF-AUTOLEARN-RUN-20260831-024','LF-AUTOLEARN-RUN-20260831-024'
from public.lf_operation_step_contracts sc
where sc.operation_code='LEARNING_BRIDGE_KB_CARD_LF'
  and sc.status='ACTIVE_ENFORCEMENT'
  and sc.mini_judge_code is not null
on conflict (operation_code,step_order,step_id) do update set
  judge_code=excluded.judge_code,
  clean_result_value=excluded.clean_result_value,
  blocked_result_value=excluded.blocked_result_value,
  return_result_value=excluded.return_result_value,
  required_evidence_keys=excluded.required_evidence_keys,
  status=excluded.status,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=now();

update public.lf_operation_registry
set version='v0.3',
    status='PRODUCCION_CONTROLADA_READ_ONLY',
    notes=coalesce(notes,'') || ' | Gate10 controlled promotion after Q+P+G: lifecycle policy binding + exact 25 step judges/bindings active; runtime/production/automatic impact remain disabled.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-024',
    updated_at=now()
where operation_code='LEARNING_BRIDGE_KB_CARD_LF';
