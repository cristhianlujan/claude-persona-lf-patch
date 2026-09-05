-- SOURCE-ONLY SANDBOX CANDIDATE. DO NOT APPLY DIRECTLY TO PRODUCTION.
-- Root objective: make existing transversal policies inherit once through the canonical
-- policy snapshot projection, preserving operation-specific bindings as overrides.
-- Proven by rollback canaries before this source materialization.

begin;

-- 1) Candidate policy versions must already exist and remain non-authoritative until promotion.
do $$
begin
  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-POLICY-CONSUMPTION'
      and policy_version='v1.1-transversal-candidate'
      and status='CANDIDATE'
  ) then raise exception 'CANDIDATE_POLICY_CONSUMPTION_MISSING'; end if;

  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-SOURCE-RESOLUTION'
      and policy_version='v1.2-transversal-candidate'
      and status='CANDIDATE'
  ) then raise exception 'CANDIDATE_SOURCE_RESOLUTION_MISSING'; end if;

  if not exists (
    select 1 from public.lf_policy_versions
    where policy_code='POL-LF-STATE-MODEL'
      and policy_version='v1.1-transversal-candidate'
      and status='CANDIDATE'
  ) then raise exception 'CANDIDATE_STATE_MODEL_MISSING'; end if;
end;
$$;

-- 2) Promotion model under test. Activation Routing is intentionally NOT generalized:
-- it mixes Profile/Adapter-specific rules and remains explicitly bound.
update public.lf_activos
set metadata = coalesce(metadata,'{}'::jsonb)
               || jsonb_build_object('pilot',false,'transversal',true,'router_required',true),
    raw_payload = case codigo_activo
      when 'POL-LF-POLICY-CONSUMPTION' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-POLICY-CONSUMPTION'
          and policy_version='v1.1-transversal-candidate'
      )
      when 'POL-LF-SOURCE-RESOLUTION' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-SOURCE-RESOLUTION'
          and policy_version='v1.2-transversal-candidate'
      )
      when 'POL-LF-STATE-MODEL' then (
        select policy_payload from public.lf_policy_versions
        where policy_code='POL-LF-STATE-MODEL'
          and policy_version='v1.1-transversal-candidate'
      )
      else raw_payload
    end
where codigo_activo in (
  'POL-LF-OPERATION-LIFECYCLE',
  'POL-LF-POLICY-CONSUMPTION',
  'POL-LF-SOURCE-RESOLUTION',
  'POL-LF-STATE-MODEL'
);

update public.lf_policy_versions
set status='CANDIDATE'
where status='ACTIVE'
  and policy_code in (
    'POL-LF-POLICY-CONSUMPTION',
    'POL-LF-SOURCE-RESOLUTION',
    'POL-LF-STATE-MODEL'
  );

update public.lf_policy_versions
set status='ACTIVE'
where (policy_code='POL-LF-POLICY-CONSUMPTION' and policy_version='v1.1-transversal-candidate')
   or (policy_code='POL-LF-SOURCE-RESOLUTION' and policy_version='v1.2-transversal-candidate')
   or (policy_code='POL-LF-STATE-MODEL' and policy_version='v1.1-transversal-candidate');

-- 3) Canonical projection: explicit operation binding wins; transversal policy fills only
-- missing policy codes for ACTIVE Router-mapped operations. LEFT JOIN preserves an expected
-- required row when its ACTIVE version disappears, allowing fail-closed required>resolved.
create or replace view public.v_lf_operation_policy_snapshot as
with routable as (
  select distinct operation_code
  from public.lf_router_action_registry
  where status='ACTIVE' and operation_code is not null
), expected as (
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

  select
    r.operation_code,
    case a.metadata->>'policy_kind'
      when 'OPERATION_LIFECYCLE_POLICY' then 'GOVERNANCE_LIFECYCLE'
      when 'POLICY_CONSUMPTION_POLICY' then 'POLICY_CONSUMPTION'
      when 'SOURCE_RESOLUTION_POLICY' then 'SOURCE_RESOLUTION'
      when 'STATE_MODEL_POLICY' then 'STATE_MODEL'
    end as policy_role,
    true as required,
    array['ROUTER']::text[] as distribution_modes,
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
    and a.metadata->>'policy_kind' in (
      'OPERATION_LIFECYCLE_POLICY',
      'POLICY_CONSUMPTION_POLICY',
      'SOURCE_RESOLUTION_POLICY',
      'STATE_MODEL_POLICY'
    )
), dedup as (
  select distinct on (operation_code,policy_code)
    operation_code,policy_role,required,distribution_modes,policy_code,binding_updated_at
  from expected
  order by operation_code,policy_code,precedence
)
select
  d.operation_code,
  d.policy_role,
  d.required,
  d.distribution_modes,
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
join public.lf_activos a on a.codigo_activo=d.policy_code
left join public.lf_policy_versions v
  on v.policy_code=d.policy_code
 and v.status='ACTIVE';

-- 4) Router remains ACT-0001; only required/resolved policy accounting is redirected to
-- the canonical projection. The migration asserts exact current source blocks before replace.
do $router_patch$
declare
  v_def text;
  v_old_required text := $old_required$  select count(*) filter (where b.required) into v_required_policy_count
  from public.lf_operation_policy_bindings b
  where b.operation_code=v_operation.operation_code and b.binding_status='ACTIVE'
    and (p_distribution_mode is null or p_distribution_mode=any(b.distribution_modes));$old_required$;
  v_new_required text := $new_required$  select count(*) filter (where p.required) into v_required_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new_required$;
  v_old_resolved text := $old_resolved$  select count(*) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code and p.required
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$old_resolved$;
  v_new_resolved text := $new_resolved$  select count(*) filter (where p.required and p.policy_sha is not null) into v_resolved_policy_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=v_operation.operation_code
    and (p_distribution_mode is null or p_distribution_mode=any(p.distribution_modes));$new_resolved$;
begin
  select pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure)
  into v_def;

  if length(v_def)-length(replace(v_def,v_old_required,'')) <> length(v_old_required) then
    raise exception 'ROUTER_REQUIRED_POLICY_BLOCK_NOT_EXACTLY_ONCE';
  end if;
  if length(v_def)-length(replace(v_def,v_old_resolved,'')) <> length(v_old_resolved) then
    raise exception 'ROUTER_RESOLVED_POLICY_BLOCK_NOT_EXACTLY_ONCE';
  end if;

  v_def := replace(v_def,v_old_required,v_new_required);
  v_def := replace(v_def,v_old_resolved,v_new_resolved);
  execute v_def;
end;
$router_patch$;

-- 5) Execution snapshot attaches exactly the same canonical policy set.
create or replace function public.lf_attach_operation_policy_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_snapshots jsonb;
begin
  select
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null)
  into v_required_count,v_resolved_required_count
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code,v_required_count,v_resolved_required_count;
  end if;

  select jsonb_object_agg(
    p.policy_role,
    jsonb_build_object(
      'policy_code',p.policy_code,
      'policy_version',p.policy_version,
      'policy_sha',p.policy_sha,
      'policy_payload',p.policy_payload,
      'distribution_modes',to_jsonb(p.distribution_modes),
      'effective_at',p.effective_at,
      'source_ref',p.source_ref
    )
  )
  into v_snapshots
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code
    and p.policy_sha is not null;

  if v_snapshots is not null then
    new.manifest := coalesce(new.manifest,'{}'::jsonb) || jsonb_build_object(
      'operation_policy_snapshots',v_snapshots,
      'operation_policy_snapshot_at',now(),
      'operation_policy_source','SUPABASE'
    );
  end if;

  return new;
end;
$$;

revoke all on function public.lf_attach_operation_policy_snapshot_v1() from public,anon,authenticated;

-- 6) Guard resolves the same canonical set and fails closed if any transversal required
-- policy disappears or its immutable execution snapshot becomes stale.
create or replace function public.lf_operation_policy_snapshot_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_required_count integer := 0;
  v_resolved_required_count integer := 0;
  v_enforcement_at timestamptz;
  r record;
  v_current_sha text;
begin
  select
    count(*) filter (where p.required),
    count(*) filter (where p.required and p.policy_sha is not null),
    min(p.effective_at) filter (where p.required and p.policy_sha is not null)
  into v_required_count,v_resolved_required_count,v_enforcement_at
  from public.v_lf_operation_policy_snapshot p
  where p.operation_code=new.operation_code;

  if v_required_count > v_resolved_required_count then
    raise exception 'BLOCK_OPERATION_POLICY_MISSING operation=% required=% resolved=%',
      new.operation_code,v_required_count,v_resolved_required_count;
  end if;

  if old.manifest ? 'operation_policy_snapshots'
     and (old.manifest->'operation_policy_snapshots') is distinct from (new.manifest->'operation_policy_snapshots') then
    raise exception 'BLOCK_POLICY_SNAPSHOT_IMMUTABLE execution=% operation=%',
      new.execution_id,new.operation_code;
  end if;

  if new.status is distinct from old.status and v_required_count > 0 then
    if not (new.manifest ? 'operation_policy_snapshots') then
      if v_enforcement_at is not null and old.started_at < v_enforcement_at then
        return new;
      end if;
      raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% operation=%',
        new.execution_id,new.operation_code;
    end if;

    for r in
      select key as policy_role,value as snapshot
      from jsonb_each(new.manifest->'operation_policy_snapshots')
    loop
      select p.policy_sha into v_current_sha
      from public.v_lf_operation_policy_snapshot p
      where p.operation_code=new.operation_code
        and p.policy_role=r.policy_role
        and p.policy_sha is not null
      limit 1;

      if v_current_sha is null then
        raise exception 'BLOCK_OPERATION_POLICY_MISSING execution=% role=%',
          new.execution_id,r.policy_role;
      end if;

      if v_current_sha <> (r.snapshot->>'policy_sha') then
        raise exception 'BLOCK_STALE_OPERATION_POLICY execution=% role=% snapshot_sha=% current_sha=%',
          new.execution_id,r.policy_role,r.snapshot->>'policy_sha',v_current_sha;
      end if;
    end loop;
  end if;

  return new;
end;
$$;

revoke all on function public.lf_operation_policy_snapshot_guard_v1() from public,anon,authenticated;

-- Sandbox source must never persist state when executed as-is.
rollback;
