-- Read-only post-release canary for S30 Strategy Factory.
with route as (
  select public.lf_router_resolve_v1(
    'crear nueva estrategia LF',
    null,
    'STRATEGY_CREATE',
    'STRATEGY',
    'ROUTER'
  ) as r
), control as (
  select
    (select status from public.lf_operation_registry where operation_code='CREACION_ESTRATEGIA_LF') as registry_status,
    (select count(*) from public.lf_operation_contracts where operation_code='CREACION_ESTRATEGIA_LF' and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) as active_contracts,
    (select count(*) from public.lf_operation_step_contracts where operation_code='CREACION_ESTRATEGIA_LF' and status in ('ACTIVE_ENFORCEMENT','ACTIVE','ACTIVO')) as active_step_contracts,
    (select count(*) from public.lf_operation_judges where operation_code='CREACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT') as active_judges,
    (select count(*) from public.lf_operation_step_judge_bindings where operation_code='CREACION_ESTRATEGIA_LF' and status='ACTIVE_ENFORCEMENT') as active_bindings,
    (select count(*) filter(where required) from public.v_lf_operation_policy_snapshot where operation_code='CREACION_ESTRATEGIA_LF' and 'ROUTER'=any(distribution_modes)) as required_policies,
    (select count(*) filter(where required and policy_sha is not null) from public.v_lf_operation_policy_snapshot where operation_code='CREACION_ESTRATEGIA_LF' and 'ROUTER'=any(distribution_modes)) as resolved_policies,
    (select allowed from public.lf_operation_contracts where operation_code='CREACION_ESTRATEGIA_LF' and contract_code='CONTRACT-CREACION-ESTRATEGIA-LF-v0.3.2') as allowed
)
select
  r->>'status' as router_status,
  r->>'blocking_code' as blocking_code,
  r->>'operation_code' as operation_code,
  r->>'operation_status' as operation_status,
  (r->>'contract_count')::int as router_contract_count,
  (r->>'step_count')::int as router_step_count,
  (r->>'required_policy_count')::int as router_required_policy_count,
  (r->>'resolved_policy_count')::int as router_resolved_policy_count,
  c.registry_status,
  c.active_contracts,
  c.active_step_contracts,
  c.active_judges,
  c.active_bindings,
  c.required_policies,
  c.resolved_policies,
  c.allowed->>'strategy_status' as strategy_status_ceiling,
  c.allowed->>'runtime_state' as runtime_state_ceiling,
  c.allowed->>'automatic_impact' as automatic_impact_ceiling,
  (
    r->>'status'='READY_TO_EXECUTE'
    and r->>'operation_code'='CREACION_ESTRATEGIA_LF'
    and c.registry_status='PRODUCCION_CONTROLADA_READ_ONLY'
    and c.active_contracts=1
    and c.active_step_contracts=43
    and c.active_judges=43
    and c.active_bindings=43
    and c.required_policies>0
    and c.required_policies=c.resolved_policies
    and c.allowed->>'strategy_status'='CANDIDATO_READ_ONLY'
    and c.allowed->>'runtime_state'='PLAN_ONLY'
    and c.allowed->>'automatic_impact'='BLOQUEADO'
  ) as release_pass
from route,cross join control c;
