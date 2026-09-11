create or replace view public.v_lf_operation_policy_snapshot as
with routable as (
  select distinct r.operation_code
  from public.lf_router_action_registry r
  where r.status='ACTIVE' and r.operation_code is not null
), expected as (
  select b.operation_code,
         b.policy_role,
         b.required,
         b.distribution_modes,
         b.policy_code,
         b.updated_at as binding_updated_at,
         0 as precedence
  from public.lf_operation_policy_bindings b
  where b.binding_status='ACTIVE'

  union all

  select r.operation_code,
         case a.metadata->>'policy_kind'
           when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
           when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
           when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
           when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
           else null
         end as policy_role,
         true as required,
         array['ROUTER','DIRECT']::text[] as distribution_modes,
         a.codigo_activo as policy_code,
         null::timestamptz as binding_updated_at,
         1 as precedence
  from routable r
  cross join public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
    and a.metadata->>'policy_kind' = any(array[
      'OPERATION_LIFECYCLE_POLICY',
      'POLICY_CONSUMPTION_POLICY',
      'SOURCE_RESOLUTION_POLICY',
      'STATE_MODEL_POLICY'
    ])
), dedup as (
  select distinct on (e.operation_code,e.policy_code)
         e.operation_code,
         e.policy_role,
         e.required,
         e.policy_code,
         e.binding_updated_at
  from expected e
  order by e.operation_code,e.policy_code,e.precedence
), modes as (
  select e.operation_code,
         e.policy_code,
         array_agg(distinct m.mode order by m.mode) as distribution_modes
  from expected e
  cross join lateral unnest(e.distribution_modes) as m(mode)
  group by e.operation_code,e.policy_code
)
select d.operation_code,
       d.policy_role,
       d.required,
       m.distribution_modes,
       d.policy_code,
       a.nombre_canonico as policy_name,
       a.tipo_activo,
       a.subtipo_activo,
       v.policy_version,
       v.policy_sha,
       v.policy_payload,
       v.effective_at,
       v.source_ref,
       d.binding_updated_at,
       v.updated_at as policy_updated_at
from dedup d
join modes m on m.operation_code=d.operation_code and m.policy_code=d.policy_code
join public.lf_activos a on a.codigo_activo=d.policy_code
left join public.lf_policy_versions v
  on v.policy_code=d.policy_code and v.status='ACTIVE';