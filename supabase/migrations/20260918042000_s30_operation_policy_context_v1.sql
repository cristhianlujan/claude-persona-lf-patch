-- S30 transversal operation policy resolver coverage v1.
-- Fixes EKB: OPERATION-POLICY-CONTEXT-AMBIGUOUS-NONE-001.
--
-- Architecture:
--   OP_OPERATIONAL consumer
--     -> generic transversal policy set (resolved once from canonical asset metadata)
--     -> + explicit operation-specific bindings
--     -> dedup
--     -> one immutable execution snapshot through existing attach/guard functions.
--
-- This migration does NOT create per-operation copies of the transversal bundle,
-- does NOT add a second policy engine, and does NOT add a new policy-mode column.

do $pre$
declare
  v_view_sha text;
  v_generic_count integer;
  v_generic_resolved integer;
  v_unknown_role text[];
begin
  select encode(
    extensions.digest(
      convert_to(pg_get_viewdef('public.v_lf_operation_policy_snapshot'::regclass,true),'UTF8'),
      'sha256'
    ),
    'hex'
  ) into v_view_sha;

  if v_view_sha is distinct from 'c32c20f908ef166e26df339e49467c8ee661db8c6f2264381b40f1fb660bc2f7' then
    raise exception 'BLOCK_POLICY_RESOLVER_PRESTATE_DRIFT expected=% actual=%',
      'c32c20f908ef166e26df339e49467c8ee661db8c6f2264381b40f1fb660bc2f7',
      v_view_sha;
  end if;

  select
    count(*),
    count(*) filter (where v.policy_sha is not null and v.status='ACTIVE')
  into v_generic_count,v_generic_resolved
  from public.lf_activos a
  left join public.lf_policy_versions v
    on v.policy_code=a.codigo_activo
   and v.status='ACTIVE'
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false);

  if v_generic_count<>4 or v_generic_resolved<>v_generic_count then
    raise exception 'BLOCK_POLICY_GENERIC_SET_NOT_RESOLVED expected=4 generic=% resolved=%',
      v_generic_count,v_generic_resolved;
  end if;

  select array_agg(a.codigo_activo order by a.codigo_activo)
  into v_unknown_role
  from public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
    and coalesce(
      nullif(a.metadata->>'policy_role',''),
      case a.metadata->>'policy_kind'
        when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
        when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
        when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
        when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
      end
    ) is null;

  if coalesce(array_length(v_unknown_role,1),0)<>0 then
    raise exception 'BLOCK_POLICY_GENERIC_ROLE_UNRESOLVED:%',v_unknown_role;
  end if;
end
$pre$;

create or replace view public.v_lf_operation_policy_snapshot
with (security_invoker=true)
as
with governed_codes as (
  -- Preserve every currently routable consumer, regardless of lifecycle projection,
  -- and extend coverage to operational internal/child consumers.
  select distinct r.operation_code
  from public.lf_router_action_registry r
  where r.status='ACTIVE'
    and r.operation_code is not null

  union

  select o.operation_code
  from public.lf_operation_registry o
  where o.lifecycle_state_code='OP_OPERATIONAL'
),
governed as (
  select
    g.operation_code,
    case
      when exists (
        select 1
        from public.lf_router_action_registry r
        where r.status='ACTIVE'
          and r.operation_code=g.operation_code
      )
      then array['ROUTER','DIRECT']::text[]
      else array['DIRECT']::text[]
    end as distribution_modes
  from governed_codes g
),
generic_policies as (
  select
    a.codigo_activo as policy_code,
    coalesce(
      nullif(a.metadata->>'policy_role',''),
      case a.metadata->>'policy_kind'
        when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
        when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
        when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
        when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
      end
    ) as policy_role
  from public.lf_activos a
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false)
),
expected as (
  -- Operation-specific extension wins identity/role/required metadata.
  select
    b.operation_code,
    b.policy_role,
    b.required,
    b.distribution_modes,
    b.policy_code,
    b.updated_at as binding_updated_at,
    0 as precedence
  from public.lf_operation_policy_bindings b
  where b.binding_status='ACTIVE'

  union all

  -- Generic transversal package is inherited by every canonical operational
  -- operation. It is resolved once from metadata; no per-operation copy exists.
  select
    g.operation_code,
    p.policy_role,
    true as required,
    g.distribution_modes,
    p.policy_code,
    null::timestamptz as binding_updated_at,
    1 as precedence
  from governed g
  cross join generic_policies p
),
dedup as (
  select distinct on (e.operation_code,e.policy_code)
    e.operation_code,
    e.policy_role,
    e.required,
    e.policy_code,
    e.binding_updated_at
  from expected e
  order by e.operation_code,e.policy_code,e.precedence
),
modes as (
  select
    e.operation_code,
    e.policy_code,
    array_agg(distinct m.mode order by m.mode) as distribution_modes
  from expected e
  cross join lateral unnest(e.distribution_modes) as m(mode)
  group by e.operation_code,e.policy_code
)
select
  d.operation_code,
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
join modes m
  on m.operation_code=d.operation_code
 and m.policy_code=d.policy_code
join public.lf_activos a
  on a.codigo_activo=d.policy_code
left join public.lf_policy_versions v
  on v.policy_code=d.policy_code
 and v.status='ACTIVE';

do $post$
declare
  v_operational integer;
  v_routable integer;
  v_governed integer;
  v_all_generic integer;
  v_uncovered_bad text[];
  v_explicit_copies integer;
  v_duplicates integer;
  v_profile_count integer;
  v_profile_specific integer;
begin
  select count(*)
  into v_operational
  from public.lf_operation_registry
  where lifecycle_state_code='OP_OPERATIONAL';

  select count(distinct operation_code)
  into v_routable
  from public.lf_router_action_registry
  where status='ACTIVE'
    and operation_code is not null;

  with governed_codes as (
    select distinct operation_code
    from public.lf_router_action_registry
    where status='ACTIVE'
      and operation_code is not null
    union
    select operation_code
    from public.lf_operation_registry
    where lifecycle_state_code='OP_OPERATIONAL'
  ),
  per_operation as (
    select
      g.operation_code,
      count(*) filter (
        where p.required
          and p.policy_sha is not null
          and p.policy_code in (
            select a.codigo_activo
            from public.lf_activos a
            where a.archived_at is null
              and a.tipo_activo='REGLA'
              and a.nivel_control='TRANSVERSAL'
              and coalesce((a.metadata->>'transversal')::boolean,false)
              and coalesce((a.metadata->>'router_required')::boolean,false)
          )
      ) as generic_resolved
    from governed_codes g
    left join public.v_lf_operation_policy_snapshot p
      on p.operation_code=g.operation_code
    group by g.operation_code
  )
  select count(*),
         count(*) filter (where generic_resolved=4)
  into v_governed,v_all_generic
  from per_operation;

  if v_operational<>26
     or v_routable<>23
     or v_governed<>33
     or v_all_generic<>v_governed then
    raise exception 'BLOCK_POLICY_GENERIC_GOVERNED_COVERAGE operational=% routable=% governed=% all_generic=%',
      v_operational,v_routable,v_governed,v_all_generic;
  end if;

  select array_agg(x.operation_code order by x.operation_code)
  into v_uncovered_bad
  from (
    select operation_code
    from public.v_lf_operation_policy_snapshot
    where operation_code in (
      'ANALISIS_RIESGO_CONTENIDO_LF',
      'ESCRITURA_BASE_CONOCIMIENTO_LF',
      'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
      'EXTRACCION_FUENTES_DIGITALES_LF',
      'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
      'HOMOLOGACION_FUENTES_DIGITALES_LF',
      'ORQUESTACION_PIPELINE_LF',
      'VULNERABILITY_COVERAGE_REPAIR_LF'
    )
    group by operation_code
    having count(*) filter (
      where required
        and binding_updated_at is null
        and policy_sha is not null
    )<>4
  ) x;

  if coalesce(array_length(v_uncovered_bad,1),0)<>0 then
    raise exception 'BLOCK_POLICY_PREVIOUSLY_UNCOVERED_STILL_BAD:%',v_uncovered_bad;
  end if;

  select count(*)
  into v_explicit_copies
  from public.lf_operation_policy_bindings b
  where b.operation_code in (
      'ANALISIS_RIESGO_CONTENIDO_LF',
      'ESCRITURA_BASE_CONOCIMIENTO_LF',
      'EXTRACCION_DOCUMENTOS_REGULATORIOS_LF',
      'EXTRACCION_FUENTES_DIGITALES_LF',
      'EXTRACCION_NOTICIAS_FINANCIERAS_LF',
      'HOMOLOGACION_FUENTES_DIGITALES_LF',
      'ORQUESTACION_PIPELINE_LF',
      'VULNERABILITY_COVERAGE_REPAIR_LF'
    )
    and b.policy_code in (
      select a.codigo_activo
      from public.lf_activos a
      where a.archived_at is null
        and a.tipo_activo='REGLA'
        and a.nivel_control='TRANSVERSAL'
        and coalesce((a.metadata->>'transversal')::boolean,false)
        and coalesce((a.metadata->>'router_required')::boolean,false)
    );

  if v_explicit_copies<>0 then
    raise exception 'BLOCK_POLICY_TRANSVERSAL_COPY_CREATED count=%',v_explicit_copies;
  end if;

  select count(*)
  into v_duplicates
  from (
    select operation_code,policy_code
    from public.v_lf_operation_policy_snapshot
    group by operation_code,policy_code
    having count(*)>1
  ) d;

  if v_duplicates<>0 then
    raise exception 'BLOCK_POLICY_RESOLVER_DUPLICATE_CODES count=%',v_duplicates;
  end if;

  select count(*),
         count(*) filter (where policy_code='POL-PROFILE-UPDATE-PASS')
  into v_profile_count,v_profile_specific
  from public.v_lf_operation_policy_snapshot
  where operation_code='ACTUALIZACION_PERFIL_LF'
    and required
    and policy_sha is not null;

  if v_profile_count<>5 or v_profile_specific<>1 then
    raise exception 'BLOCK_POLICY_SPECIFIC_EXTENSION_REGRESSION profile_count=% specific=%',
      v_profile_count,v_profile_specific;
  end if;
end
$post$;
