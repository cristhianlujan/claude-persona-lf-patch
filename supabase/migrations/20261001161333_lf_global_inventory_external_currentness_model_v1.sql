-- LF Global Technical Inventory - External Currentness Model v1
-- Block 2 / A4a.
--
-- This migration adds only the currentness model and makes it visible through
-- inventory.v_objects_search_v1 + inventory.search_index.
-- It does NOT apply the external detector classifications. Existing repo:// and
-- edge:// rows therefore project as UNKNOWN until Block 3 observes them.
-- Drive provenance remains untouched.

alter table inventory.objects
  add column if not exists currentness text,
  add column if not exists currentness_source text,
  add column if not exists observed_at timestamptz,
  add column if not exists observed_main_sha text,
  add column if not exists source_traceability_state text;

alter table inventory.search_index
  add column if not exists currentness text,
  add column if not exists currentness_source text,
  add column if not exists observed_at timestamptz,
  add column if not exists observed_main_sha text,
  add column if not exists source_traceability_state text;

comment on column inventory.objects.currentness is
'Latest external-currentness classification for this inventory object. NULL means the object is outside the external detector model or has not been persisted yet. repo:// and edge:// rows are projected as UNKNOWN until observed.';

comment on column inventory.objects.currentness_source is
'Authority that produced currentness, for example GITHUB_MAIN or SUPABASE_EDGE_RUNTIME. NULL until an authorized detector observation is persisted.';

comment on column inventory.objects.observed_at is
'Timestamp of the external observation that produced currentness. NULL means no persisted external observation.';

comment on column inventory.objects.observed_main_sha is
'Exact repository main SHA observed alongside the classification. Used for repo:// currentness and Edge source-traceability evidence.';

comment on column inventory.objects.source_traceability_state is
'Independent runtime-to-source traceability state. Edge values are SOURCE_PRESENT, RUNTIME_WITHOUT_SOURCE or UNKNOWN; this does not imply runtime currentness.';

comment on column inventory.search_index.currentness is
'Search projection of inventory.objects.currentness; repo:// and edge:// rows with no persisted observation are exposed as UNKNOWN.';

comment on column inventory.search_index.source_traceability_state is
'Search projection of Edge runtime-to-source traceability; unobserved edge:// rows are exposed as UNKNOWN.';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='inventory.objects'::regclass
      and conname='inventory_objects_currentness_ck'
  ) then
    alter table inventory.objects
      add constraint inventory_objects_currentness_ck
      check (currentness is null or currentness in ('CURRENT','STALE','MISSING','NEW','UNKNOWN'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='inventory.objects'::regclass
      and conname='inventory_objects_source_traceability_state_ck'
  ) then
    alter table inventory.objects
      add constraint inventory_objects_source_traceability_state_ck
      check (
        source_traceability_state is null
        or source_traceability_state in ('SOURCE_PRESENT','RUNTIME_WITHOUT_SOURCE','UNKNOWN')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='inventory.search_index'::regclass
      and conname='inventory_search_currentness_ck'
  ) then
    alter table inventory.search_index
      add constraint inventory_search_currentness_ck
      check (currentness is null or currentness in ('CURRENT','STALE','MISSING','NEW','UNKNOWN'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='inventory.search_index'::regclass
      and conname='inventory_search_source_traceability_state_ck'
  ) then
    alter table inventory.search_index
      add constraint inventory_search_source_traceability_state_ck
      check (
        source_traceability_state is null
        or source_traceability_state in ('SOURCE_PRESENT','RUNTIME_WITHOUT_SOURCE','UNKNOWN')
      );
  end if;
end
$$;

create index if not exists inventory_objects_currentness_idx
  on inventory.objects(currentness,active);

create index if not exists inventory_objects_source_traceability_idx
  on inventory.objects(source_traceability_state,active);

create index if not exists inventory_search_currentness_idx
  on inventory.search_index(currentness);

create index if not exists inventory_search_source_traceability_idx
  on inventory.search_index(source_traceability_state);

create or replace view inventory.v_objects_search_v1
with (security_invoker = true)
as
select
  o.object_id,
  o.object_ref,
  o.object_type,
  o.schema_name,
  o.object_name,
  o.domain,
  o.source_system,
  o.source_of_truth,
  o.status,
  o.definition_sha256,
  o.source_version,
  coalesce(tags.tags,'{}'::text[]) as tags,
  o.metadata,
  o.last_seen_at,
  case
    when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
      then coalesce(o.currentness,'UNKNOWN')
    else o.currentness
  end as currentness,
  o.currentness_source,
  o.observed_at,
  o.observed_main_sha,
  case
    when o.object_ref like 'edge://%'
      then coalesce(o.source_traceability_state,'UNKNOWN')
    else o.source_traceability_state
  end as source_traceability_state
from inventory.objects o
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
    object_id,
    object_ref,
    object_ref_lc,
    object_type,
    schema_name,
    object_name,
    object_name_lc,
    tags,
    tags_lc,
    column_names,
    column_names_lc,
    source_system,
    source_of_truth,
    status,
    search_document,
    refreshed_at,
    currentness,
    currentness_source,
    observed_at,
    observed_main_sha,
    source_traceability_state
  )
  select
    o.object_id,
    o.object_ref,
    lower(o.object_ref),
    o.object_type,
    o.schema_name,
    o.object_name,
    lower(o.object_name),
    coalesce(t.tags,'{}'::text[]),
    coalesce(t.tags_lc,'{}'::text[]),
    coalesce(c.cols,'{}'::text[]),
    coalesce(c.cols_lc,'{}'::text[]),
    o.source_system,
    o.source_of_truth,
    o.status,
    to_tsvector(
      'simple',
      coalesce(o.object_ref,'')||' '||
      coalesce(o.object_name,'')||' '||
      coalesce(o.schema_name,'')||' '||
      array_to_string(coalesce(t.tags,'{}'::text[]),' ')||' '||
      array_to_string(coalesce(c.cols,'{}'::text[]),' ')
    ),
    now(),
    case
      when o.object_ref like 'repo://%' or o.object_ref like 'edge://%'
        then coalesce(o.currentness,'UNKNOWN')
      else o.currentness
    end,
    o.currentness_source,
    o.observed_at,
    o.observed_main_sha,
    case
      when o.object_ref like 'edge://%'
        then coalesce(o.source_traceability_state,'UNKNOWN')
      else o.source_traceability_state
    end
  from inventory.objects o
  left join lateral (
    select
      array_agg(distinct ot.tag_code order by ot.tag_code) tags,
      array_agg(distinct lower(ot.tag_code) order by lower(ot.tag_code)) tags_lc
    from inventory.object_tags ot
    where ot.object_id=o.object_id
  ) t on true
  left join lateral (
    select
      array_agg(ic.column_name order by ic.ordinal_position) cols,
      array_agg(lower(ic.column_name) order by ic.ordinal_position) cols_lc
    from inventory.columns ic
    where ic.object_id=o.object_id
  ) c on true
  where o.active
  on conflict(object_id) do update set
    object_ref=excluded.object_ref,
    object_ref_lc=excluded.object_ref_lc,
    object_type=excluded.object_type,
    schema_name=excluded.schema_name,
    object_name=excluded.object_name,
    object_name_lc=excluded.object_name_lc,
    tags=excluded.tags,
    tags_lc=excluded.tags_lc,
    column_names=excluded.column_names,
    column_names_lc=excluded.column_names_lc,
    source_system=excluded.source_system,
    source_of_truth=excluded.source_of_truth,
    status=excluded.status,
    search_document=excluded.search_document,
    refreshed_at=now(),
    currentness=excluded.currentness,
    currentness_source=excluded.currentness_source,
    observed_at=excluded.observed_at,
    observed_main_sha=excluded.observed_main_sha,
    source_traceability_state=excluded.source_traceability_state;

  delete from inventory.search_index s
  where not exists(
    select 1
    from inventory.objects o
    where o.object_id=s.object_id
      and o.active
  );

  select count(*) into v_count
  from inventory.search_index;

  return v_count;
end;
$$;

-- Populate the new search projection only. This does not classify inventory.objects.
select inventory.fn_refresh_search_index_v1();

-- Fail closed if an active external object can still be surfaced without a
-- visible effective currentness state.
do $$
begin
  if exists (
    select 1
    from inventory.search_index
    where (object_ref like 'repo://%' or object_ref like 'edge://%')
      and currentness is null
  ) then
    raise exception 'BLOCK_EXTERNAL_CURRENTNESS_NOT_VISIBLE_IN_SEARCH_INDEX';
  end if;

  if exists (
    select 1
    from inventory.search_index
    where object_ref like 'edge://%'
      and source_traceability_state is null
  ) then
    raise exception 'BLOCK_EDGE_SOURCE_TRACEABILITY_NOT_VISIBLE_IN_SEARCH_INDEX';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='inventory'
      and c.relname='v_objects_search_v1'
      and 'security_invoker=true'=any(coalesce(c.reloptions,'{}'::text[]))
  ) then
    raise exception 'BLOCK_INVENTORY_SEARCH_VIEW_NOT_SECURITY_INVOKER';
  end if;
end
$$;
