insert into public.lf_operation_steps (
  operation_code, step_order, step_id, required, evidence_required, source_path, source_sha,
  active, execution_order, created_by_execution_id, updated_by_execution_id
)
select
  c.operation_code,
  c.step_order,
  c.step_id,
  true,
  coalesce((select string_agg(x, '; ' order by ord) from jsonb_array_elements_text(c.required_evidence_keys) with ordinality as e(x,ord)), c.step_id || '_evidence'),
  'public.lf_operation_step_contracts/' || c.operation_code || '/' || c.step_id,
  null,
  true,
  c.execution_order,
  'EXEC-REPAIR-ROUTER-ENFORCEMENT-20260830-001',
  'EXEC-REPAIR-ROUTER-ENFORCEMENT-20260830-001'
from public.lf_operation_step_contracts c
where c.operation_code='ACTUALIZACION_ROUTER_LF' and c.status='ACTIVE_ENFORCEMENT'
on conflict (operation_code, step_order) do update set
  step_id=excluded.step_id,
  required=excluded.required,
  evidence_required=excluded.evidence_required,
  source_path=excluded.source_path,
  active=true,
  execution_order=excluded.execution_order,
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_operation_judges (
  operation_code, judge_code, judge_path, judge_sha, pass_if, fail_if, result_values,
  status, created_by_execution_id, updated_by_execution_id
) values (
  'ACTUALIZACION_ROUTER_LF','JUDGE_ROUTER_CANARY_MINIMAL_V1',
  'public.lf_operation_judges/ACTUALIZACION_ROUTER_LF/JUDGE_ROUTER_CANARY_MINIMAL_V1',null,
  jsonb_build_array('step_contract_present','required_evidence_keys_present','pass_condition_met','blocking_condition_absent','minimal_scope_preserved'),
  jsonb_build_array('step_contract_missing','required_evidence_missing','block_condition_met','new_layer_or_massification','symbolic_pass_without_evidence'),
  jsonb_build_array('STEP_CLEAN_PASS','RETURN_TO_WORKER_FOR_SELF_REPAIR','BLOCKED_ROUTER_CANARY_NOT_CLEAN'),
  'ACTIVE_ENFORCEMENT','EXEC-REPAIR-ROUTER-ENFORCEMENT-20260830-001','EXEC-REPAIR-ROUTER-ENFORCEMENT-20260830-001'
)
on conflict (operation_code, judge_code) do update set
  pass_if=excluded.pass_if,
  fail_if=excluded.fail_if,
  result_values=excluded.result_values,
  status='ACTIVE_ENFORCEMENT',
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

insert into public.lf_operation_step_judge_bindings (
  operation_code, step_order, step_id, judge_code,
  clean_result_value, blocked_result_value, return_result_value,
  required_evidence_keys, status, created_by_execution_id, updated_by_execution_id
)
select
  c.operation_code,c.step_order,c.step_id,'JUDGE_ROUTER_CANARY_MINIMAL_V1',
  'STEP_CLEAN_PASS','BLOCKED_ROUTER_CANARY_NOT_CLEAN','RETURN_TO_WORKER_FOR_SELF_REPAIR',
  c.required_evidence_keys,'ACTIVE_ENFORCEMENT',
  'EXEC-REPAIR-ROUTER-ENFORCEMENT-20260830-001','EXEC-REPAIR-ROUTER-ENFORCEMENT-20260830-001'
from public.lf_operation_step_contracts c
where c.operation_code='ACTUALIZACION_ROUTER_LF' and c.status='ACTIVE_ENFORCEMENT'
on conflict (operation_code, step_order, step_id) do update set
  judge_code=excluded.judge_code,
  clean_result_value=excluded.clean_result_value,
  blocked_result_value=excluded.blocked_result_value,
  return_result_value=excluded.return_result_value,
  required_evidence_keys=excluded.required_evidence_keys,
  status='ACTIVE_ENFORCEMENT',
  updated_at=now(),
  updated_by_execution_id=excluded.updated_by_execution_id;

update public.lf_activos
set metadata = jsonb_set(
    coalesce(metadata,'{}'::jsonb),
    '{audit_inventory_gate_v1}',
    jsonb_build_object(
      'version','v1.0',
      'status','ACTIVE_ENFORCEMENT',
      'purpose','Prevent global audit closure until inventory coverage is demonstrated across all discovered LF source families.',
      'discovery_scope',jsonb_build_array('public.lf_%','private.lf_%','public.v_lf_%'),
      'discovery_strategy','Discover LF relations dynamically from PostgreSQL catalogs; do not assume a single inventory table.',
      'coverage_units',jsonb_build_object(
        'INVENTORY_ROOT','CURRENT_ENTITY',
        'SUPPORTING_CONTRACT','ACTIVE_CONTRACT',
        'RUNTIME_EVIDENCE','RELATION_AND_SAMPLE',
        'DERIVED_VIEW','DEFINITION_AND_DEPENDENCIES',
        'SECURITY_SUPPORT','CONTROL_EXISTENCE_NO_SECRET_VALUES',
        'HISTORY_LEGACY','PROVENANCE_ONLY',
        'EXCLUDED_WITH_REASON','NONE'
      ),
      'closure_rule','Every discovered source must be classified; every required coverage unit must be AUDITADO or EXCLUIDO_CON_MOTIVO before a global audit can close.',
      'allowed_final_states',jsonb_build_array('AUDITADO','EXCLUIDO_CON_MOTIVO'),
      'heterogeneous_universes_must_not_be_summed',true,
      'last_sandbox_discovered_relations',221,
      'last_sandbox_unclassified_sources',0,
      'last_verified_execution','EXEC-ACT0001-GATE0-INVENTORY-20260830-001',
      'last_verified_at',now()
    ),
    true
  ),
  updated_at=now(),
  updated_by_execution_id='EXEC-ACT0001-GATE0-INVENTORY-20260830-001'
where codigo_activo='ACT-0001';