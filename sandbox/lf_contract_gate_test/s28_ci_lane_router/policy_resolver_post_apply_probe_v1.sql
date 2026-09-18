-- POLICY_RESOLVER_REGRESSION_V1
-- Runs only after the exact candidate migration bytes have been applied inside
-- the rollback-only DB candidate transaction.

do $policy_resolver_probe$
declare
  v_generic_count integer;
  v_bad_governed text[];
  v_duplicates integer;
  v_missing_explicit integer;
  v_profile_explicit integer;
  v_profile_resolved integer;
begin
  select count(*)
    into v_generic_count
  from public.lf_activos a
  join public.lf_policy_versions v
    on v.policy_code=a.codigo_activo
   and v.status='ACTIVE'
   and v.policy_sha is not null
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false);

  if v_generic_count < 1 then
    raise exception 'POLICY_RESOLVER_PROBE_GENERIC_SET_EMPTY';
  end if;

  with governed as (
    select distinct operation_code
    from public.lf_router_action_registry
    where status='ACTIVE' and operation_code is not null
    union
    select operation_code
    from public.lf_operation_registry
    where lifecycle_state_code='OP_OPERATIONAL'
  ),
  generic_codes as (
    select a.codigo_activo as policy_code
    from public.lf_activos a
    join public.lf_policy_versions v
      on v.policy_code=a.codigo_activo
     and v.status='ACTIVE'
     and v.policy_sha is not null
    where a.archived_at is null
      and a.tipo_activo='REGLA'
      and a.nivel_control='TRANSVERSAL'
      and coalesce((a.metadata->>'transversal')::boolean,false)
      and coalesce((a.metadata->>'router_required')::boolean,false)
  ),
  coverage as (
    select
      g.operation_code,
      count(distinct p.policy_code) filter (
        where p.policy_code in (select policy_code from generic_codes)
          and p.required
          and p.policy_sha is not null
      ) as resolved_generic
    from governed g
    left join public.v_lf_operation_policy_snapshot p
      on p.operation_code=g.operation_code
    group by g.operation_code
  )
  select array_agg(operation_code order by operation_code)
    into v_bad_governed
  from coverage
  where resolved_generic<>v_generic_count;

  if coalesce(array_length(v_bad_governed,1),0)<>0 then
    raise exception 'POLICY_RESOLVER_PROBE_GOVERNED_COVERAGE:%',v_bad_governed;
  end if;

  select count(*)
    into v_duplicates
  from (
    select operation_code,policy_code
    from public.v_lf_operation_policy_snapshot
    group by operation_code,policy_code
    having count(*)>1
  ) x;

  if v_duplicates<>0 then
    raise exception 'POLICY_RESOLVER_PROBE_DUPLICATES:%',v_duplicates;
  end if;

  select count(*)
    into v_missing_explicit
  from public.lf_operation_policy_bindings b
  where b.binding_status='ACTIVE'
    and not exists (
      select 1
      from public.v_lf_operation_policy_snapshot p
      where p.operation_code=b.operation_code
        and p.policy_code=b.policy_code
        and p.policy_sha is not null
    );

  if v_missing_explicit<>0 then
    raise exception 'POLICY_RESOLVER_PROBE_EXPLICIT_EXTENSION_MISSING:%',v_missing_explicit;
  end if;

  select count(*)
    into v_profile_explicit
  from public.lf_operation_policy_bindings b
  where b.operation_code='ACTUALIZACION_PERFIL_LF'
    and b.binding_status='ACTIVE'
    and b.required;

  select count(*)
    into v_profile_resolved
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code='ACTUALIZACION_PERFIL_LF'
    and p.required
    and p.policy_sha is not null;

  if v_profile_explicit>0 and v_profile_resolved<>(v_generic_count+v_profile_explicit) then
    raise exception 'POLICY_RESOLVER_PROBE_SPECIFIC_EXTENSION_REGRESSION generic=% explicit=% resolved=%',
      v_generic_count,v_profile_explicit,v_profile_resolved;
  end if;
end
$policy_resolver_probe$;

create temporary table pg_temp.lf_policy_resolver_execution_probe(
  execution_id text primary key,
  operation_code text not null,
  started_at timestamptz not null default clock_timestamp(),
  manifest jsonb not null default '{}'::jsonb,
  status text not null
) on commit drop;

create trigger trg_policy_resolver_probe_attach
before insert on pg_temp.lf_policy_resolver_execution_probe
for each row execute function public.lf_attach_operation_policy_snapshot_v1();

create trigger trg_policy_resolver_probe_guard
before update of status,manifest on pg_temp.lf_policy_resolver_execution_probe
for each row execute function public.lf_operation_policy_snapshot_guard_v1();

do $execution_probe$
declare
  v_manifest jsonb;
  v_expected integer;
  v_actual integer;
begin
  select count(*)
    into v_expected
  from public.lf_activos a
  join public.lf_policy_versions v
    on v.policy_code=a.codigo_activo
   and v.status='ACTIVE'
   and v.policy_sha is not null
  where a.archived_at is null
    and a.tipo_activo='REGLA'
    and a.nivel_control='TRANSVERSAL'
    and coalesce((a.metadata->>'transversal')::boolean,false)
    and coalesce((a.metadata->>'router_required')::boolean,false);

  insert into pg_temp.lf_policy_resolver_execution_probe(
    execution_id,operation_code,status,manifest
  ) values (
    'CI-POLICY-RESOLVER-PROBE',
    'ESCRITURA_BASE_CONOCIMIENTO_LF',
    'IN_PROGRESS',
    '{}'::jsonb
  )
  returning manifest into v_manifest;

  select count(*)
    into v_actual
  from jsonb_each(v_manifest->'operation_policy_snapshots');

  if v_actual<>v_expected then
    raise exception 'POLICY_RESOLVER_PROBE_EXECUTION_SNAPSHOT expected=% actual=% manifest=%',
      v_expected,v_actual,v_manifest;
  end if;

  update pg_temp.lf_policy_resolver_execution_probe
  set status='COMPLETED'
  where execution_id='CI-POLICY-RESOLVER-PROBE';

  if not exists (
    select 1
    from pg_temp.lf_policy_resolver_execution_probe
    where execution_id='CI-POLICY-RESOLVER-PROBE'
      and status='COMPLETED'
  ) then
    raise exception 'POLICY_RESOLVER_PROBE_EXECUTION_CLOSE_FAILED';
  end if;
end
$execution_probe$;

select 'POLICY_RESOLVER_REGRESSION_PASS' as result;
