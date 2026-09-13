-- SOURCE CANDIDATE ONLY. NOT A SUPABASE MIGRATION.
-- Purpose: reproduce the governed live state of ACTUALIZACION_ESTRATEGIA_LF
-- without advancing Supabase migration history ahead of canonical Git source.
-- Validated on 2026-09-13 inside BEGIN/ROLLBACK with zero residue.
-- Historical S32 snapshot 45 is outside this write set and must remain immutable.

begin;

insert into public.lf_operation_execution(
  execution_id, operation_code, target_type, target_code, target_repo, target_path,
  manifest, created_by_execution_id, updated_by_execution_id,
  idempotency_key, request_sha256
) values (
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001',
  'VULNERABILITY_COVERAGE_REPAIR_LF',
  'OPERATION',
  'ACTUALIZACION_ESTRATEGIA_LF',
  'Supabase/LF_OPERATION_GOVERNANCE',
  'public.lf_operation_registry',
  jsonb_build_object(
    'governance_bootstrap', true,
    'bootstrap_operation_code', 'ACTUALIZACION_ESTRATEGIA_LF',
    'bootstrap_status_ceiling', 'SANDBOX_ACTIVE',
    'source_candidate_only', true,
    'exclusive_pr', 753,
    'immutable_base_sha', 'fc2967e9aa17f9e5e68f8567ef80faafb3839c53',
    'production_change', false,
    'runtime_change', false,
    'scheduler_change', false
  ),
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001',
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001',
  'strategy-update-source-candidate-v1-20260913',
  '07253987ec72383bb79acc95b510e4c133b617618f5826acd726a708e0d8de5e'
);

update public.lf_operation_contracts
set status='ACTIVE_ENFORCEMENT',
    updated_by_execution_id='EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
where operation_code='ACTUALIZACION_ESTRATEGIA_LF'
  and status in ('CANDIDATO_READ_ONLY','ACTIVE_ENFORCEMENT');

update public.lf_operation_step_contracts
set status='ACTIVE_ENFORCEMENT',
    updated_by_execution_id='EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
where operation_code='ACTUALIZACION_ESTRATEGIA_LF'
  and status in ('CANDIDATO_READ_ONLY','ACTIVE_ENFORCEMENT');

update public.lf_operation_judges
set status='ACTIVE_ENFORCEMENT',
    updated_by_execution_id='EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
where operation_code='ACTUALIZACION_ESTRATEGIA_LF'
  and status in ('CANDIDATO_READ_ONLY','ACTIVE_ENFORCEMENT');

update public.lf_operation_step_judge_bindings
set status='ACTIVE_ENFORCEMENT',
    updated_by_execution_id='EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
where operation_code='ACTUALIZACION_ESTRATEGIA_LF'
  and status in ('CANDIDATO_READ_ONLY','ACTIVE_ENFORCEMENT');

update public.lf_operation_registry
set status='SANDBOX_ACTIVE',
    updated_by_execution_id='EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
where operation_code='ACTUALIZACION_ESTRATEGIA_LF'
  and status in ('CANDIDATO_READ_ONLY','SANDBOX_ACTIVE');

insert into public.lf_router_action_registry(
  asset_type, action_code, operation_code, operation_resolution,
  requires_existing_target, requires_missing_target, write_allowed, status, notes,
  created_by_execution_id, updated_by_execution_id
) values
(
  'STRATEGY','STRATEGY_UPDATE','ACTUALIZACION_ESTRATEGIA_LF','STATIC',
  false,false,true,'ACTIVE',
  'Canonical Strategy update route. Snapshot identity is resolved inside ACTUALIZACION_ESTRATEGIA_LF/strategy_resolve; sandbox-only activation with fail-closed currentness/progress enforcement.',
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001',
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
),
(
  'STRATEGY','UPDATE','ACTUALIZACION_ESTRATEGIA_LF','STATIC',
  false,false,true,'ACTIVE',
  'Compatibility alias for current Router inference. Canonical action is STRATEGY_UPDATE; both resolve ACTUALIZACION_ESTRATEGIA_LF. Sandbox-only operation; exact snapshot resolution and prewrite currentness remain fail-closed.',
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001',
  'EXEC-SOURCE-CANDIDATE-STRATEGY-UPDATE-ACTIVATION-20260913-001'
)
on conflict (asset_type,action_code) do update
set operation_code=excluded.operation_code,
    operation_resolution=excluded.operation_resolution,
    requires_existing_target=excluded.requires_existing_target,
    requires_missing_target=excluded.requires_missing_target,
    write_allowed=excluded.write_allowed,
    status=excluded.status,
    notes=excluded.notes,
    updated_by_execution_id=excluded.updated_by_execution_id;

select jsonb_build_object(
  'operation_status',(select status from public.lf_operation_registry where operation_code='ACTUALIZACION_ESTRATEGIA_LF'),
  'active_contracts',(select count(*) from public.lf_operation_contracts where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT'),
  'active_step_contracts',(select count(*) from public.lf_operation_step_contracts where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT'),
  'active_judges',(select count(*) from public.lf_operation_judges where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT'),
  'active_judge_bindings',(select count(*) from public.lf_operation_step_judge_bindings where operation_code='ACTUALIZACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT'),
  'router_strategy_update',(select status from public.lf_router_action_registry where asset_type='STRATEGY' and action_code='STRATEGY_UPDATE'),
  'router_update_compat',(select status from public.lf_router_action_registry where asset_type='STRATEGY' and action_code='UPDATE')
) as candidate_readback;

-- Keep this artifact rollback-only until converted through the canonical migration path.
rollback;
