-- LF TRANSVERSAL Router-to-Terminal matrix generator v1
-- READ ONLY. No DDL/DML.
-- Canonical source: Supabase operation/router/contract/policy/step surfaces.
-- Output shape is directly consumable by matrix_engine_v1.py.
-- Adversarial probes that are not executed by this structural query are emitted as
-- NOT_EXECUTED so the engine remains fail-closed until a probe-enrichment stage runs.

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
  where operation_code is not null
  group by operation_code
),
contract_summary as (
  select operation_code,
         count(*) filter (where status in ('ACTIVE','ACTIVE_ENFORCEMENT','ACTIVO')) as active_contract_count
  from public.lf_operation_contracts
  group by operation_code
),
active_step_rows as (
  select
    s.operation_code,
    s.step_id,
    s.required,
    s.step_order,
    s.execution_order,
    sc.next_if_pass,
    sc.next_if_blocked,
    (sc.step_id is not null) as step_contract_present
  from public.lf_operation_steps s
  left join public.lf_operation_step_contracts sc
    on sc.operation_code=s.operation_code
   and sc.step_id=s.step_id
   and sc.status in ('ACTIVE','ACTIVE_ENFORCEMENT','ACTIVO')
  where s.active is true
),
step_summary as (
  select operation_code,
         count(*) as active_step_count,
         count(*) filter (where required) as required_step_count,
         jsonb_agg(
           jsonb_build_object(
             'step_id',step_id,
             'required',required,
             'step_order',step_order,
             'execution_order',execution_order,
             'next_if_pass',next_if_pass,
             'next_if_blocked',next_if_blocked,
             'step_contract_present',step_contract_present
           ) order by coalesce(execution_order,step_order),step_id
         ) as active_steps
  from active_step_rows
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
),
direct_ops as (
  select jsonb_build_object(
    'operation_code',operation_code,
    'active_route_count',active_route_count,
    'active_contract_count',active_contract_count,
    'active_step_count',active_step_count,
    'required_step_count',required_step_count,
    'required_policy_count',required_policy_count,
    'resolved_policy_count',resolved_policy_count,
    'active_steps',active_steps,
    'invalid_mode_verdict','NOT_EXECUTED'
  ) as row_json
  from ops
  where active_route_count>0
  order by operation_code
),
unrouted_ops as (
  select jsonb_build_object(
    'operation_code',operation_code,
    'status',status,
    'operation_family',operation_family,
    'operation_type',operation_type,
    'classification',
      case
        when upper(coalesce(status,'')) like 'CANDIDATO%' or upper(coalesce(status,'')) like 'CANDIDATE%' then 'CANDIDATE_INACTIVE'
        when upper(coalesce(operation_type,''))='SCHEDULER_DRIVEN' then 'SCHEDULER'
        when upper(coalesce(operation_family,'')) like '%ENFORCEMENT%'
          or upper(coalesce(operation_type,'')) in ('CONTRACT_GATE','REGRESSION_SUITE','SANDBOX_TEST','TEST_RECORDS_CLASSIFICATION','TEST_RECORDS_SANITIZATION','INTERNAL_ENFORCEMENT') then 'CONTROL_PLANE'
        when upper(coalesce(operation_type,''))='SKILL_EXECUTION' then 'INTERNAL_SUBOPERATION'
        when upper(coalesce(status,'')) like '%PRODUCCION%' or upper(coalesce(status,''))='SANDBOX_ACTIVE' then 'INTERNAL_PROTOCOL'
        else 'UNCLASSIFIED'
      end,
    'provenance_status',
      case
        when upper(coalesce(status,'')) like 'CANDIDATO%' or upper(coalesce(status,'')) like 'CANDIDATE%' then 'NOT_APPLICABLE_INACTIVE'
        when upper(coalesce(operation_type,'')) in ('REGRESSION_SUITE','SANDBOX_TEST') then 'NOT_APPLICABLE_TEST_ONLY'
        else 'UNKNOWN'
      end
  ) as row_json
  from ops
  where active_route_count=0
  order by operation_code
),
reserve_probe as (
  select
    exists(
      select 1
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='fn_lf_operation_reserve_execution_v1'
        and p.prokind='f'
        and pg_get_functiondef(p.oid) ilike '%lf_router_resolve_v1%'
    ) as router_provenance_required,
    exists(
      select 1 from pg_trigger t
      where not t.tgisinternal and t.tgrelid='public.lf_operation_execution'::regclass
        and t.tgname='trg_00_lf_operation_policy_snapshot_v1'
    ) as policy_snapshot_on_insert,
    exists(
      select 1 from pg_trigger t
      where not t.tgisinternal and t.tgrelid='public.lf_operation_execution'::regclass
        and t.tgname='trg_00_lf_operation_policy_snapshot_v1'
    ) as required_policy_resolution_guard,
    exists(
      select 1 from pg_trigger t
      where not t.tgisinternal and t.tgrelid='public.lf_operation_execution'::regclass
        and t.tgname='trg_01_lf_operation_policy_snapshot_guard_v1'
    ) as policy_snapshot_immutable_and_currentness_guard,
    exists(
      select 1 from pg_trigger t
      where not t.tgisinternal and t.tgrelid='public.lf_operation_execution'::regclass
        and t.tgname='trg_lf_prod_enforcement_execution_v01'
    ) as registered_operation_required
)
select jsonb_build_object(
  'snapshot_version','lf-transversal-e2e-live/v1',
  'observed_at',now(),
  'metadata',jsonb_build_object(
    'operation_count',(select count(*) from public.lf_operation_registry),
    'active_route_count',(select count(*) from public.lf_router_action_registry where status='ACTIVE'),
    'routed_operation_count',(select count(*) from ops where active_route_count>0),
    'unrouted_operation_count',(select count(*) from ops where active_route_count=0),
    'static_execution_route_count',(select count(*) from public.lf_router_action_registry where status='ACTIVE' and operation_resolution='STATIC'),
    'inspection_no_execution_route_count',(select count(*) from public.lf_router_action_registry where status='ACTIVE' and operation_resolution='NONE')
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
  'direct_operations',(select coalesce(jsonb_agg(row_json),'[]'::jsonb) from direct_ops),
  'unrouted_operations',(select coalesce(jsonb_agg(row_json),'[]'::jsonb) from unrouted_ops),
  'target_authority_case',jsonb_build_object('status','NOT_EXECUTED'),
  'direct_reservation_case',(
    select jsonb_build_object(
      'function','fn_lf_operation_reserve_execution_v1',
      'router_provenance_required',router_provenance_required,
      'policy_snapshot_on_insert',policy_snapshot_on_insert,
      'required_policy_resolution_guard',required_policy_resolution_guard,
      'policy_snapshot_immutable_and_currentness_guard',policy_snapshot_immutable_and_currentness_guard,
      'registered_operation_required',registered_operation_required,
      'status','STRUCTURAL_PROBE_ONLY'
    ) from reserve_probe
  )
) as transversal_e2e_matrix_live_v1;
