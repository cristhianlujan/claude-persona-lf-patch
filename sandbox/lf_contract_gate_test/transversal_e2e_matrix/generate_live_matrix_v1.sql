-- LF TRANSVERSAL Router-to-Terminal matrix generator v1
-- READ ONLY. No DDL/DML. Canonical source: Supabase operation/router/contract/policy tables.
-- The output is designed to be consumed by matrix_engine_v1.py after a governed readback.

with route_summary as (
  select
    operation_code,
    count(*) filter (where status='ACTIVE') as active_route_count,
    jsonb_agg(
      jsonb_build_object(
        'asset_type',asset_type,
        'action_code',action_code,
        'operation_resolution',operation_resolution,
        'status',status
      ) order by asset_type,action_code
    ) filter (where status='ACTIVE') as active_routes
  from public.lf_router_action_registry
  group by operation_code
),
contract_summary as (
  select operation_code,
         count(*) filter (where status in ('ACTIVE','ACTIVE_ENFORCEMENT','ACTIVO')) as active_contract_count
  from public.lf_operation_contracts
  group by operation_code
),
step_summary as (
  select operation_code,
         count(*) filter (where active) as active_step_count,
         count(*) filter (where active and required) as required_step_count,
         jsonb_agg(
           jsonb_build_object(
             'step_id',step_id,
             'required',required,
             'step_order',step_order,
             'execution_order',execution_order
           ) order by coalesce(execution_order,step_order),step_id
         ) filter (where active) as active_steps
  from public.lf_operation_steps
  group by operation_code
),
policy_summary as (
  select operation_code,
         count(*) filter (where required) as required_policy_count,
         count(*) filter (where required and policy_sha is not null) as resolved_policy_count
  from public.v_lf_operation_policy_snapshot
  where 'ROUTER'=any(distribution_modes)
  group by operation_code
),
ops as (
  select
    o.operation_code,o.status,o.operation_family,o.operation_type,o.applies_to_asset_type,
    coalesce(r.active_route_count,0) as active_route_count,
    coalesce(c.active_contract_count,0) as active_contract_count,
    coalesce(s.active_step_count,0) as active_step_count,
    coalesce(s.required_step_count,0) as required_step_count,
    coalesce(p.required_policy_count,0) as required_policy_count,
    coalesce(p.resolved_policy_count,0) as resolved_policy_count,
    coalesce(r.active_routes,'[]'::jsonb) as active_routes,
    coalesce(s.active_steps,'[]'::jsonb) as active_steps
  from public.lf_operation_registry o
  left join route_summary r using(operation_code)
  left join contract_summary c using(operation_code)
  left join step_summary s using(operation_code)
  left join policy_summary p using(operation_code)
)
select jsonb_build_object(
  'snapshot_version','lf-transversal-e2e-live/v1',
  'observed_at',now(),
  'metadata',jsonb_build_object(
    'operation_count',(select count(*) from public.lf_operation_registry),
    'active_route_count',(select count(*) from public.lf_router_action_registry where status='ACTIVE'),
    'routed_operation_count',(select count(distinct operation_code) from public.lf_router_action_registry where status='ACTIVE' and operation_code is not null),
    'unrouted_operation_count',(select count(*) from ops where active_route_count=0)
  ),
  'inspection_routes',(
    select coalesce(jsonb_agg(jsonb_build_object(
      'asset_type',asset_type,
      'action_code',action_code,
      'operation_resolution',operation_resolution,
      'operation_code',operation_code
    ) order by asset_type,action_code),'[]'::jsonb)
    from public.lf_router_action_registry
    where status='ACTIVE' and operation_resolution='NONE'
  ),
  'operations',(select jsonb_agg(to_jsonb(ops) order by operation_code) from ops)
) as transversal_e2e_matrix_live_v1;
