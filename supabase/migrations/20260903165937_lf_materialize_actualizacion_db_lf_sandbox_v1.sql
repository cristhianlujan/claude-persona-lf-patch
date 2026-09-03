insert into public.lf_operation_registry(
  operation_code,version,status,source_model,source_repo,source_paths,notes,
  operation_family,operation_domain,operation_type,applies_to_asset_type,
  created_by_execution_id,updated_by_execution_id
) values (
  'ACTUALIZACION_DB_LF','v0.1','SANDBOX_ACTIVE','SUPABASE_STRUCTURED_OPERATION',
  'Supabase/LF_OPERATION_GOVERNANCE',
  '["public.lf_router_action_registry","public.lf_operation_registry","public.lf_operation_contracts","public.lf_operation_steps","public.lf_operation_step_contracts"]'::jsonb,
  'Ruta canónica sandbox para reparación mínima y reversible de DB/MIGRATION/FUNCTION/TRIGGER. No producción; exige EKB/schema/source-first, target exacto, rollback y readback/regresión.',
  'DATABASE_OPERATIONS','DATABASE_MAINTENANCE','UPDATE_PROTOCOL',null,
  'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'
)
on conflict (operation_code) do update set
  version=excluded.version,status=excluded.status,source_model=excluded.source_model,
  source_repo=excluded.source_repo,source_paths=excluded.source_paths,notes=excluded.notes,
  operation_family=excluded.operation_family,operation_domain=excluded.operation_domain,
  operation_type=excluded.operation_type,applies_to_asset_type=excluded.applies_to_asset_type,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=now();

insert into public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,
  required_before_write,allowed,blocked,required_after_write,status,
  created_by_execution_id,updated_by_execution_id
) values (
  'ACTUALIZACION_DB_LF','CONTRACT-ACTUALIZACION-DB-LF-v0.1',
  'supabase://public/lf_operation_contracts/ACTUALIZACION_DB_LF/v0.1',null,
  '["router_read","ekb_read","schema_source_read","exact_target_bound","rollback_plan","migration_parity_precheck_if_applicable"]'::jsonb,
  '{"sandbox_only":true,"minimal_reversible_patch":true,"migration_reconciliation":true,"function_trigger_repair":true,"schema_or_contract_repair":true,"production_allowed":false,"manual_hash_patch":false,"bypass_allowed":false}'::jsonb,
  '["production","direct_hash_patch","parity_bypass","unscoped_ddl","write_without_exact_target","write_without_rollback","write_without_readback"]'::jsonb,
  '["exact_target_readback","regression_or_parity_retest","no_unscoped_changes","ekb_closeout"]'::jsonb,
  'ACTIVE_ENFORCEMENT','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'
)
on conflict (operation_code,contract_code) do update set
  contract_path=excluded.contract_path,contract_sha=excluded.contract_sha,
  required_before_write=excluded.required_before_write,allowed=excluded.allowed,
  blocked=excluded.blocked,required_after_write=excluded.required_after_write,
  status=excluded.status,updated_by_execution_id=excluded.updated_by_execution_id,updated_at=now();

insert into public.lf_operation_steps(
  operation_code,step_order,execution_order,step_id,required,evidence_required,source_path,source_sha,active,
  created_by_execution_id,updated_by_execution_id
) values
('ACTUALIZACION_DB_LF',10,10,'preflight',true,'router_binding; ekb_refs; schema_source_readback; exact_target; rollback_plan','public.lf_operation_step_contracts/ACTUALIZACION_DB_LF/preflight',null,true,'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'),
('ACTUALIZACION_DB_LF',20,20,'patch',true,'minimal_diff; write_receipt; target_binding','public.lf_operation_step_contracts/ACTUALIZACION_DB_LF/patch',null,true,'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'),
('ACTUALIZACION_DB_LF',30,30,'verify',true,'readback; regression_or_parity; ekb_closeout','public.lf_operation_step_contracts/ACTUALIZACION_DB_LF/verify',null,true,'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001')
on conflict (operation_code,step_id) do update set
  step_order=excluded.step_order,execution_order=excluded.execution_order,required=excluded.required,
  evidence_required=excluded.evidence_required,source_path=excluded.source_path,active=excluded.active,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=now();

insert into public.lf_operation_step_contracts(
  operation_code,step_id,step_order,execution_order,contract_code,purpose,input_required,resolver_ref,
  output_payload,pass_condition,block_condition,blocking_code,mini_judge_code,required_evidence_keys,
  next_if_pass,next_if_blocked,status,notes,created_by_execution_id,updated_by_execution_id
) values
('ACTUALIZACION_DB_LF','preflight',10,10,'CONTRACT-ACTUALIZACION-DB-LF-v0.1','Validar Router, EKB, schema/source, target exacto y rollback antes de cualquier write.',
 '["router_binding","ekb_refs","schema_source","exact_target","rollback_plan"]'::jsonb,'SUPABASE_MCP',
 '["preflight_pass"]'::jsonb,'{"preflight_pass":true}'::jsonb,'{"preflight_pass":false}'::jsonb,'BLOCK_DB_PREWRITE_PREFLIGHT','JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1',
 '["router_binding","ekb_refs","schema_source_readback","exact_target","rollback_plan"]'::jsonb,'patch','close','ACTIVE_ENFORCEMENT','Sandbox only; no production.',
 'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'),
('ACTUALIZACION_DB_LF','patch',20,20,'CONTRACT-ACTUALIZACION-DB-LF-v0.1','Aplicar únicamente el delta mínimo reversible al target exacto.',
 '["minimal_diff","exact_target","rollback_plan"]'::jsonb,'SUPABASE_MCP',
 '["write_receipt"]'::jsonb,'{"minimal_patch":true}'::jsonb,'{"unscoped_or_irreversible":true}'::jsonb,'BLOCK_DB_PATCH_SCOPE','JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1',
 '["minimal_diff","write_receipt","target_binding"]'::jsonb,'verify','close','ACTIVE_ENFORCEMENT','No parity bypass, no direct hash patch.',
 'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'),
('ACTUALIZACION_DB_LF','verify',30,30,'CONTRACT-ACTUALIZACION-DB-LF-v0.1','Verificar readback exacto, regresión/paridad y cierre EKB.',
 '["readback","regression_or_parity","ekb_closeout"]'::jsonb,'SUPABASE_MCP',
 '["verified"]'::jsonb,'{"verified":true}'::jsonb,'{"verified":false}'::jsonb,'BLOCK_DB_VERIFY_FAILED','JUDGE_DB_MUTATION_SANDBOX_MINIMAL_V1',
 '["readback","regression_or_parity","ekb_closeout"]'::jsonb,null,null,'ACTIVE_ENFORCEMENT','PASS solo con readback y sin regresión.',
 'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001')
on conflict (operation_code,step_id) do update set
  step_order=excluded.step_order,execution_order=excluded.execution_order,contract_code=excluded.contract_code,
  purpose=excluded.purpose,input_required=excluded.input_required,resolver_ref=excluded.resolver_ref,
  output_payload=excluded.output_payload,pass_condition=excluded.pass_condition,block_condition=excluded.block_condition,
  blocking_code=excluded.blocking_code,mini_judge_code=excluded.mini_judge_code,
  required_evidence_keys=excluded.required_evidence_keys,next_if_pass=excluded.next_if_pass,next_if_blocked=excluded.next_if_blocked,
  status=excluded.status,notes=excluded.notes,updated_by_execution_id=excluded.updated_by_execution_id,updated_at=now();

insert into public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,requires_existing_target,requires_missing_target,
  write_allowed,status,notes,created_by_execution_id,updated_by_execution_id
)
select x.asset_type,'UPDATE','ACTUALIZACION_DB_LF','STATIC',false,false,true,'ACTIVE',
       'Sandbox-only canonical DB mutation route. Explicit asset_type hint required; exact target/schema/source/rollback/readback remain mandatory.',
       'EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001','EXEC-PROGRAMMING-E2E-DB-ROUTE-REPAIR-20260903-001'
from (values ('DB'),('MIGRATION'),('FUNCTION'),('TRIGGER')) as x(asset_type)
on conflict (asset_type,action_code) do update set
  operation_code=excluded.operation_code,operation_resolution=excluded.operation_resolution,
  requires_existing_target=excluded.requires_existing_target,requires_missing_target=excluded.requires_missing_target,
  write_allowed=excluded.write_allowed,status=excluded.status,notes=excluded.notes,
  updated_by_execution_id=excluded.updated_by_execution_id,updated_at=now();