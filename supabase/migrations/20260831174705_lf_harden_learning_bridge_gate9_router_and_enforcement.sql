update public.lf_router_action_registry
set requires_existing_target=false,
    requires_missing_target=false,
    notes=coalesce(notes,'') || ' Knowledge batch is canonical lf_knowledge_base input, not an lf_activos master asset; Router mapping must not require target hydration.',
    updated_by_execution_id='LF-AUTOLEARN-RUN-20260831-023',
    updated_at=now()
where asset_type='KNOWLEDGE'
  and action_code='KNOWLEDGE_LEARNING_BRIDGE'
  and operation_code='LEARNING_BRIDGE_KB_CARD_LF';

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
) values (
  'LEARNING_BRIDGE_KB_CARD_LF',
  'CONTRACT-LEARNING-BRIDGE-GATE9-MIN-LIFECYCLE-v0.1',
  'supabase://public/lf_operation_contracts/LEARNING_BRIDGE_KB_CARD_LF/gate9_min_lifecycle_v0_1',
  'MIGRATION_20260831_LB_GATE9_MIN_LIFECYCLE_V1',
  jsonb_build_array('router_read','operational_source_read','active_router_mapping','active_step_contracts_25','quality_gate_pass','performance_gate_pass'),
  jsonb_build_object(
    'mode','READ_ONLY_GOVERNANCE_GATE',
    'operation_status_ceiling','CANDIDATO_READ_ONLY',
    'runtime_enabled',false,
    'production_allowed',false,
    'automatic_impact',false,
    'policy_and_step_judge_bindings','DEFERRED_UNTIL_QPG_PASS'
  ),
  jsonb_build_array(
    'bypass_router','direct_production_impact','enable_act_0046_runtime_by_force',
    'fabricate_human_approval','n8n_llm_reasoning','binding_before_qpg_pass',
    'missing_active_router_mapping','missing_active_step_contract'
  ),
  jsonb_build_array('governance_gate_readback','source_parity_exact_head','no_impact_readback'),
  'ACTIVE_ENFORCEMENT',
  'LF-AUTOLEARN-RUN-20260831-023','LF-AUTOLEARN-RUN-20260831-023'
)
on conflict (operation_code,contract_code) do update set
  contract_path=excluded.contract_path,
  contract_sha=excluded.contract_sha,
  required_before_write=excluded.required_before_write,
  allowed=excluded.allowed,
  blocked=excluded.blocked,
  required_after_write=excluded.required_after_write,
  status=excluded.status,
  updated_by_execution_id=excluded.updated_by_execution_id,
  updated_at=now();
