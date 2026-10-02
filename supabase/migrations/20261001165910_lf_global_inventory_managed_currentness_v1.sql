-- LF Global Inventory B2 - managed currentness semantics
-- Exact-version identity: 20261001165910
-- Transport: EXACT_VERSION_SOURCE_FIRST
-- Managed source systems are explicit and fail closed when stale/unmapped.

create or replace function inventory.fn_managed_currentness_eval_v1(
  p_source_system text,
  p_completed_at timestamptz,
  p_snapshot_status text,
  p_pg_catalog_drift integer,
  p_registry_status text,
  p_as_of timestamptz default now()
)
returns text
language sql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
select case
  when p_source_system not in (
    'SUPABASE_PG_CATALOG',
    'LF_ACTIVOS',
    'PROGRAMACION_CONTRATOS',
    'LF_OPERATION_REGISTRY'
  ) then 'UNKNOWN'
  when p_completed_at is null
    or p_snapshot_status is distinct from 'COMPLETED'
    or p_completed_at > p_as_of
    or p_as_of - p_completed_at > interval '7 hours'
    then 'UNKNOWN'
  when p_source_system='SUPABASE_PG_CATALOG'
    and coalesce(p_pg_catalog_drift,-1)=0
    then 'CATALOG_MANAGED'
  when p_source_system in ('LF_ACTIVOS','PROGRAMACION_CONTRATOS','LF_OPERATION_REGISTRY')
    and p_registry_status='COMPLETED'
    then 'CATALOG_MANAGED'
  else 'UNKNOWN'
end;
$$;

create or replace view inventory.v_managed_currentness_v1
with (security_invoker=true)
as
with latest as (
  select s.*
  from inventory.snapshots s
  where s.source_system='INVENTORY_STAGED_REFRESH_V1'
    and s.scope='DATABASE_AND_REGISTRIES'
  order by s.completed_at desc nulls last
  limit 1
),
sources(source_system,currentness_source) as (
  values
    ('SUPABASE_PG_CATALOG'::text,'PG_CATALOG_REFRESH'::text),
    ('LF_ACTIVOS','LF_REGISTRY_REFRESH'),
    ('PROGRAMACION_CONTRATOS','LF_REGISTRY_REFRESH'),
    ('LF_OPERATION_REGISTRY','LF_REGISTRY_REFRESH')
)
select
  src.source_system,
  src.currentness_source,
  l.snapshot_code,
  l.completed_at as observed_at,
  inventory.fn_managed_currentness_eval_v1(
    src.source_system,
    l.completed_at,
    l.status,
    nullif(l.metadata->>'pg_catalog_drift','')::integer,
    l.metadata#>>'{registries,status}',
    now()
  ) as currentness
from sources src
left join latest l on true;

alter table inventory.search_index
  drop constraint if exists inventory_search_currentness_ck;

alter table inventory.search_index
  add constraint inventory_search_currentness_ck
  check (currentness is null or currentness in (
    'CURRENT','STALE','MISSING','NEW','UNKNOWN','CATALOG_MANAGED'
  ));

create or replace view inventory.v_objects_search_v1
with (security_invoker=true)
as
select
  o.object_id,o.object_ref,o.object_type,o.schema_name,o.object_name,o.domain,
  o.source_system,o.source_of_truth,o.status,o.definition_sha256,o.source_version,
  coalesce(tags.tags,'{}'::text[]) as tags,
  o.metadata,o.last_seen_at,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then coalesce(o.currentness,'UNKNOWN')
    when ms.source_system is not null then ms.currentness
    else 'UNKNOWN'
  end as currentness,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then o.currentness_source
    when ms.source_system is not null then ms.currentness_source
    else null
  end as currentness_source,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then o.observed_at
    when ms.source_system is not null then ms.observed_at
    else null
  end as observed_at,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then o.observed_main_sha
    else null
  end as observed_main_sha,
  case
    when o.object_ref like 'edge://%'
      then coalesce(o.source_traceability_state,'UNKNOWN')
    else o.source_traceability_state
  end as source_traceability_state
from inventory.objects o
left join inventory.v_managed_currentness_v1 ms
  on ms.source_system=o.source_system
left join lateral (
  select array_agg(distinct ot.tag_code order by ot.tag_code) tags
  from inventory.object_tags ot
  where ot.object_id=o.object_id
) tags on true
where o.active;

create or replace function inventory.fn_refresh_search_index_v1()
returns bigint
language plpgsql
set search_path=inventory,pg_catalog
as $$
declare
  v_count bigint;
begin
  insert into inventory.search_index(
    object_id,object_ref,object_ref_lc,object_type,schema_name,object_name,object_name_lc,
    tags,tags_lc,column_names,column_names_lc,source_system,source_of_truth,status,
    search_document,refreshed_at,currentness,currentness_source,observed_at,
    observed_main_sha,source_traceability_state
  )
  select
    o.object_id,o.object_ref,lower(o.object_ref),o.object_type,o.schema_name,o.object_name,lower(o.object_name),
    coalesce(t.tags,'{}'::text[]),coalesce(t.tags_lc,'{}'::text[]),
    coalesce(c.cols,'{}'::text[]),coalesce(c.cols_lc,'{}'::text[]),
    o.source_system,o.source_of_truth,o.status,
    to_tsvector(
      'simple',
      coalesce(o.object_ref,'')||' '||coalesce(o.object_name,'')||' '||
      coalesce(o.schema_name,'')||' '||
      array_to_string(coalesce(t.tags,'{}'::text[]),' ')||' '||
      array_to_string(coalesce(c.cols,'{}'::text[]),' ')
    ),
    now(),
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then coalesce(o.currentness,'UNKNOWN')
      when ms.source_system is not null then ms.currentness
      else 'UNKNOWN'
    end,
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then o.currentness_source
      when ms.source_system is not null then ms.currentness_source
      else null
    end,
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then o.observed_at
      when ms.source_system is not null then ms.observed_at
      else null
    end,
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then o.observed_main_sha
      else null
    end,
    case
      when o.object_ref like 'edge://%'
        then coalesce(o.source_traceability_state,'UNKNOWN')
      else o.source_traceability_state
    end
  from inventory.objects o
  left join inventory.v_managed_currentness_v1 ms
    on ms.source_system=o.source_system
  left join lateral (
    select array_agg(distinct ot.tag_code order by ot.tag_code) tags,
           array_agg(distinct lower(ot.tag_code) order by lower(ot.tag_code)) tags_lc
    from inventory.object_tags ot
    where ot.object_id=o.object_id
  ) t on true
  left join lateral (
    select array_agg(ic.column_name order by ic.ordinal_position) cols,
           array_agg(lower(ic.column_name) order by ic.ordinal_position) cols_lc
    from inventory.columns ic
    where ic.object_id=o.object_id
  ) c on true
  where o.active
  on conflict(object_id) do update set
    object_ref=excluded.object_ref,object_ref_lc=excluded.object_ref_lc,
    object_type=excluded.object_type,schema_name=excluded.schema_name,
    object_name=excluded.object_name,object_name_lc=excluded.object_name_lc,
    tags=excluded.tags,tags_lc=excluded.tags_lc,
    column_names=excluded.column_names,column_names_lc=excluded.column_names_lc,
    source_system=excluded.source_system,source_of_truth=excluded.source_of_truth,
    status=excluded.status,search_document=excluded.search_document,
    refreshed_at=now(),currentness=excluded.currentness,
    currentness_source=excluded.currentness_source,observed_at=excluded.observed_at,
    observed_main_sha=excluded.observed_main_sha,
    source_traceability_state=excluded.source_traceability_state;

  delete from inventory.search_index s
  where not exists (
    select 1 from inventory.objects o
    where o.object_id=s.object_id and o.active
  );

  select count(*) into v_count from inventory.search_index;
  return v_count;
end;
$$;

create or replace function inventory.fn_normalize_currentness_filter_v1(
  p_currentness text[]
)
returns text[]
language plpgsql
immutable
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_result text[];
  v_bad text;
begin
  if p_currentness is null then
    return null;
  end if;

  if cardinality(p_currentness)=0 then
    raise exception 'INVALID_CURRENTNESS_FILTER: EMPTY'
      using errcode='22023';
  end if;

  if exists (
    select 1
    from unnest(p_currentness) x(value)
    where value is null or btrim(value)=''
  ) then
    raise exception 'INVALID_CURRENTNESS_FILTER: NULL_OR_EMPTY_VALUE'
      using errcode='22023';
  end if;

  select array_agg(distinct upper(btrim(value)) order by upper(btrim(value)))
  into v_result
  from unnest(p_currentness) x(value);

  select value into v_bad
  from unnest(v_result) x(value)
  where value not in ('CURRENT','CATALOG_MANAGED','STALE','MISSING','NEW','UNKNOWN')
  order by value
  limit 1;

  if v_bad is not null then
    raise exception 'INVALID_CURRENTNESS_FILTER: %',v_bad
      using errcode='22023';
  end if;

  return v_result;
end;
$$;

create or replace function inventory.fn_lookup_v3(
  p_term text default null,
  p_object_types text[] default null,
  p_limit integer default 100,
  p_currentness text[] default null
)
returns table(
  object_ref text,
  object_type text,
  schema_name text,
  object_name text,
  match_reason text,
  matching_columns text[],
  tags text[],
  source_system text,
  source_of_truth boolean,
  status text,
  currentness text,
  currentness_source text,
  observed_at timestamptz,
  observed_main_sha text,
  source_traceability_state text
)
language plpgsql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_requested text[];
begin
  v_requested := inventory.fn_normalize_currentness_filter_v1(p_currentness);

  return query
  with enriched as (
    select
      s.*,
      case
        when s.object_ref like 'repo://%' or s.object_ref like 'edge://%'
          then coalesce(s.currentness,'UNKNOWN')
        when ms.source_system is not null then ms.currentness
        else 'UNKNOWN'
      end as effective_currentness,
      case
        when s.object_ref like 'repo://%' or s.object_ref like 'edge://%'
          then s.currentness_source
        when ms.source_system is not null then ms.currentness_source
        else null
      end as effective_currentness_source,
      case
        when s.object_ref like 'repo://%' or s.object_ref like 'edge://%'
          then s.observed_at
        when ms.source_system is not null then ms.observed_at
        else null
      end as effective_observed_at
    from inventory.search_index s
    left join inventory.v_managed_currentness_v1 ms
      on ms.source_system=s.source_system
  ),
  matched as (
    select
      e.*,
      case
        when lower(nullif(btrim(p_term),'')) is null then 'ALL'
        when e.object_ref_lc=lower(btrim(p_term)) then 'EXACT_REF'
        when e.object_name_lc=lower(btrim(p_term)) then 'EXACT_NAME'
        when lower(btrim(p_term))=any(e.tags_lc) then 'TAG'
        when lower(btrim(p_term))=any(e.column_names_lc) then 'COLUMN'
        when e.search_document @@ plainto_tsquery('simple',lower(btrim(p_term))) then 'TEXT'
        else null
      end as computed_match_reason,
      case
        when lower(nullif(btrim(p_term),'')) is not null
         and lower(btrim(p_term))=any(e.column_names_lc)
        then array(
          select c from unnest(e.column_names) c
          where lower(c)=lower(btrim(p_term))
        )
        else '{}'::text[]
      end as computed_matching_columns
    from enriched e
    where (p_object_types is null or e.object_type=any(p_object_types))
      and (
        v_requested is null
        or e.effective_currentness=any(v_requested)
        or (
          'CURRENT'=any(v_requested)
          and e.effective_currentness='CATALOG_MANAGED'
        )
      )
      and (
        lower(nullif(btrim(p_term),'')) is null
        or e.object_ref_lc=lower(btrim(p_term))
        or e.object_name_lc=lower(btrim(p_term))
        or lower(btrim(p_term))=any(e.tags_lc)
        or lower(btrim(p_term))=any(e.column_names_lc)
        or e.search_document @@ plainto_tsquery('simple',lower(btrim(p_term)))
      )
  )
  select
    m.object_ref,m.object_type,m.schema_name,m.object_name,
    m.computed_match_reason,m.computed_matching_columns,m.tags,
    m.source_system,m.source_of_truth,m.status,
    m.effective_currentness,m.effective_currentness_source,
    m.effective_observed_at,
    case
      when m.object_ref like 'repo://%' or m.object_ref like 'edge://%'
        then m.observed_main_sha
      else null
    end,
    m.source_traceability_state
  from matched m
  order by
    case m.computed_match_reason
      when 'EXACT_REF' then 0
      when 'EXACT_NAME' then 1
      when 'TAG' then 2
      when 'COLUMN' then 3
      else 4
    end,
    m.object_ref
  limit greatest(1,least(coalesce(p_limit,100),500));
end;
$$;

comment on function inventory.fn_lookup_v3(text,text[],integer,text[]) is
'CANONICAL_GLOBAL_INVENTORY_LOOKUP_V3. CURRENT includes externally CURRENT plus internally CATALOG_MANAGED sources that passed the latest <=7h managed refresh. Edge CURRENT does not imply source traceability: RUNTIME_WITHOUT_SOURCE remains a separate axis. Empty, NULL-containing, or unknown currentness filters raise INVALID_CURRENTNESS_FILTER.';

revoke all on function inventory.fn_lookup_v3(text,text[],integer,text[]) from public;

grant execute on function inventory.fn_lookup_v3(text,text[],integer,text[]) to
  programacion_auditor,
  programacion_builder,
  programacion_human_authority,
  programacion_verifier,
  service_role;

select inventory.fn_refresh_search_index_v1();

do $$
declare
  v_latest inventory.snapshots%rowtype;
begin
  select * into v_latest
  from inventory.snapshots
  where source_system='INVENTORY_STAGED_REFRESH_V1'
    and scope='DATABASE_AND_REGISTRIES'
  order by completed_at desc nulls last
  limit 1;

  if not exists (
    select 1
    from inventory.fn_lookup_v3('brand_assets',array['DB_TABLE'],10,array['CURRENT'])
    where currentness='CATALOG_MANAGED'
      and currentness_source='PG_CATALOG_REFRESH'
  ) then
    raise exception 'BLOCK_MANAGED_CURRENTNESS_BRAND_ASSETS_NOT_CURRENT';
  end if;

  if inventory.fn_managed_currentness_eval_v1(
    'SUPABASE_PG_CATALOG',
    v_latest.completed_at,
    v_latest.status,
    nullif(v_latest.metadata->>'pg_catalog_drift','')::integer,
    v_latest.metadata#>>'{registries,status}',
    v_latest.completed_at + interval '8 hours'
  ) <> 'UNKNOWN' then
    raise exception 'BLOCK_MANAGED_CURRENTNESS_STALE_SNAPSHOT_ACCEPTED';
  end if;

  if exists (
    select 1
    from inventory.v_managed_currentness_v1
    where source_system='SUPABASE_PG_CATALOG'
      and currentness_source<>'PG_CATALOG_REFRESH'
  ) then
    raise exception 'BLOCK_PG_CATALOG_CURRENTNESS_SOURCE_INVALID';
  end if;

  if exists (
    select 1
    from inventory.v_managed_currentness_v1
    where source_system in ('LF_ACTIVOS','PROGRAMACION_CONTRATOS','LF_OPERATION_REGISTRY')
      and currentness_source<>'LF_REGISTRY_REFRESH'
  ) then
    raise exception 'BLOCK_REGISTRY_CURRENTNESS_SOURCE_INVALID';
  end if;
end
$$;
