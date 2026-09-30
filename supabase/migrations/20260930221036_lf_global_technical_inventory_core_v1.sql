
-- LF Global Technical Inventory - Core v1
-- Additive technical catalog. Canonical business data remains in original sources.

create schema if not exists inventory;

comment on schema inventory is
'LF global technical inventory and dependency graph. Discovery/catalog only; canonical data remains in source systems.';

create table if not exists inventory.objects (
  object_id bigserial primary key,
  object_ref text not null unique,
  object_type text not null,
  schema_name text,
  object_name text not null,
  parent_object_id bigint references inventory.objects(object_id) on delete set null,
  domain text,
  source_system text not null,
  source_of_truth boolean not null default false,
  status text not null default 'ACTIVE',
  definition_sha256 text,
  source_version text,
  metadata jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists inventory.db_relations (
  object_id bigint primary key references inventory.objects(object_id) on delete cascade,
  relation_kind text not null,
  persistence text,
  owner_name text,
  rls_enabled boolean,
  force_rls boolean,
  estimated_rows bigint,
  total_bytes bigint,
  comment text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists inventory.columns (
  object_id bigint not null references inventory.objects(object_id) on delete cascade,
  ordinal_position integer not null,
  column_name text not null,
  data_type text not null,
  udt_name text,
  is_nullable boolean not null,
  column_default text,
  is_generated boolean not null default false,
  is_identity boolean not null default false,
  is_primary_key boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(object_id,column_name)
);

create table if not exists inventory.indexes (
  object_id bigint not null references inventory.objects(object_id) on delete cascade,
  index_name text not null,
  is_unique boolean not null default false,
  is_primary boolean not null default false,
  indexed_columns text[] not null default '{}'::text[],
  definition text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key(object_id,index_name)
);

create table if not exists inventory.functions (
  object_id bigint primary key references inventory.objects(object_id) on delete cascade,
  identity_arguments text not null default '',
  result_type text,
  language text,
  function_kind text,
  volatility text,
  parallel_safety text,
  security_definer boolean not null default false,
  is_strict boolean not null default false,
  definition_sha256 text,
  definition_bytes integer,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists inventory.triggers (
  object_id bigint primary key references inventory.objects(object_id) on delete cascade,
  table_object_id bigint not null references inventory.objects(object_id) on delete cascade,
  enabled_state text,
  trigger_definition text,
  function_ref text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists inventory.policies (
  object_id bigint primary key references inventory.objects(object_id) on delete cascade,
  table_object_id bigint not null references inventory.objects(object_id) on delete cascade,
  command text,
  roles text[],
  permissive text,
  using_expression text,
  check_expression text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists inventory.dependencies (
  dependency_id bigserial primary key,
  dependency_key text not null unique,
  source_object_id bigint not null references inventory.objects(object_id) on delete cascade,
  target_object_id bigint references inventory.objects(object_id) on delete cascade,
  target_ref text not null,
  relation_type text not null,
  evidence_type text not null,
  evidence text,
  confidence numeric(5,4) not null default 1.0 check(confidence between 0 and 1),
  source_system text not null,
  metadata jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_verified_at timestamptz not null default now(),
  active boolean not null default true
);

alter table inventory.dependencies add column if not exists dependency_key text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='inventory.dependencies'::regclass
      and conname='dependencies_dependency_key_key'
  ) then
    alter table inventory.dependencies
      add constraint dependencies_dependency_key_key unique(dependency_key);
  end if;
end $$;

create table if not exists inventory.tags (
  tag_code text primary key,
  tag_type text not null default 'DOMAIN',
  description text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists inventory.object_tags (
  object_id bigint not null references inventory.objects(object_id) on delete cascade,
  tag_code text not null references inventory.tags(tag_code) on delete cascade,
  evidence text,
  confidence numeric(5,4) not null default 1.0 check(confidence between 0 and 1),
  source_system text not null,
  primary key(object_id,tag_code,source_system)
);

create table if not exists inventory.snapshots (
  snapshot_id bigserial primary key,
  snapshot_code text not null unique,
  source_system text not null,
  scope text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'IN_PROGRESS',
  object_count bigint,
  dependency_count bigint,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists inventory.reconciliation (
  reconciliation_id bigserial primary key,
  object_id bigint references inventory.objects(object_id) on delete cascade,
  compared_source text not null,
  compared_at timestamptz not null default now(),
  state text not null,
  baseline_ref text,
  current_ref text,
  details jsonb not null default '{}'::jsonb
);

create table if not exists inventory.search_index (
  object_id bigint primary key references inventory.objects(object_id) on delete cascade,
  object_ref text not null,
  object_ref_lc text not null,
  object_type text not null,
  schema_name text,
  object_name text not null,
  object_name_lc text not null,
  tags text[] not null default '{}'::text[],
  tags_lc text[] not null default '{}'::text[],
  column_names text[] not null default '{}'::text[],
  column_names_lc text[] not null default '{}'::text[],
  source_system text not null,
  source_of_truth boolean not null,
  status text not null,
  search_document tsvector,
  refreshed_at timestamptz not null default now()
);

create index if not exists inventory_objects_type_idx on inventory.objects(object_type,active);
create index if not exists inventory_objects_schema_name_idx on inventory.objects(schema_name,object_name);
create index if not exists inventory_objects_source_idx on inventory.objects(source_system,active);
create index if not exists inventory_objects_metadata_gin on inventory.objects using gin(metadata);
create index if not exists inventory_objects_parent_idx on inventory.objects(parent_object_id);
create index if not exists inventory_objects_ref_lower_idx on inventory.objects(lower(object_ref));
create index if not exists inventory_objects_name_lower_idx on inventory.objects(lower(object_name));
create index if not exists inventory_columns_name_idx on inventory.columns(column_name,object_id);
create index if not exists inventory_columns_object_ordinal_idx on inventory.columns(object_id,ordinal_position);
create index if not exists inventory_columns_name_lower_idx on inventory.columns(lower(column_name),object_id);
create index if not exists inventory_indexes_columns_gin on inventory.indexes using gin(indexed_columns);
create index if not exists inventory_dependencies_source_idx on inventory.dependencies(source_object_id,relation_type,active);
create index if not exists inventory_dependencies_target_idx on inventory.dependencies(target_object_id,relation_type,active);
create index if not exists inventory_dependencies_target_ref_idx on inventory.dependencies(target_ref);
create index if not exists inventory_object_tags_tag_idx on inventory.object_tags(tag_code,object_id);
create index if not exists inventory_tags_code_lower_idx on inventory.tags(lower(tag_code));
create index if not exists inventory_policies_table_object_idx on inventory.policies(table_object_id);
create index if not exists inventory_reconciliation_object_idx on inventory.reconciliation(object_id);
create index if not exists inventory_triggers_table_object_idx on inventory.triggers(table_object_id);
create unique index if not exists inventory_search_ref_lc_idx on inventory.search_index(object_ref_lc);
create index if not exists inventory_search_name_lc_idx on inventory.search_index(object_name_lc);
create index if not exists inventory_search_type_idx on inventory.search_index(object_type);
create index if not exists inventory_search_tags_gin on inventory.search_index using gin(tags_lc);
create index if not exists inventory_search_columns_gin on inventory.search_index using gin(column_names_lc);
create index if not exists inventory_search_document_gin on inventory.search_index using gin(search_document);

do $$
declare t text;
begin
  foreach t in array array[
    'objects','db_relations','columns','indexes','functions','triggers','policies',
    'dependencies','tags','object_tags','snapshots','reconciliation','search_index'
  ]
  loop
    execute format('alter table inventory.%I enable row level security',t);
    execute format('drop policy if exists inventory_internal_read on inventory.%I',t);
    execute format(
      'create policy inventory_internal_read on inventory.%I for select to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier using (true)',
      t
    );
    execute format(
      'grant select on inventory.%I to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier',
      t
    );
  end loop;
end $$;

grant usage on schema inventory
to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier,service_role;
grant usage,select on all sequences in schema inventory
to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier;
grant select on all tables in schema inventory to service_role;

create or replace function inventory.fn_function_identity_args_stable(p_oid oid)
returns text
language sql
stable
security invoker
set search_path=pg_catalog
as $$
  select pg_get_function_identity_arguments(p_oid);
$$;

create or replace view inventory.v_objects_search_v1
with (security_invoker = true)
as
select
  o.object_id,o.object_ref,o.object_type,o.schema_name,o.object_name,o.domain,
  o.source_system,o.source_of_truth,o.status,o.definition_sha256,o.source_version,
  coalesce(tags.tags,'{}'::text[]) as tags,
  o.metadata,o.last_seen_at
from inventory.objects o
left join lateral (
  select array_agg(distinct ot.tag_code order by ot.tag_code) tags
  from inventory.object_tags ot
  where ot.object_id=o.object_id
) tags on true
where o.active;

create or replace view inventory.v_summary_v1
with (security_invoker = true)
as
select
  object_type,
  count(*) filter(where active) as active_objects,
  count(*) filter(where active and status='UNRESOLVED') as unresolved_objects,
  count(*) filter(where active and source_of_truth) as canonical_objects
from inventory.objects
group by object_type;

create or replace view inventory.v_pg_catalog_drift_v1
with (security_invoker = true)
as
with current_objects as (
  select 'db://'||n.nspname||'.'||c.relname as object_ref,
         case c.relkind when 'r' then 'DB_TABLE' when 'p' then 'DB_PARTITIONED_TABLE'
                        when 'v' then 'DB_VIEW' when 'm' then 'DB_MATERIALIZED_VIEW' end object_type
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p','v','m')
    and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
  union all
  select 'dbfunc://'||n.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')',
         case p.prokind when 'p' then 'DB_PROCEDURE' else 'DB_FUNCTION' end
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prokind in ('f','p')
    and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
  union all
  select 'trigger://'||n.nspname||'.'||c.relname||'/'||t.tgname,'DB_TRIGGER'
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
  union all
  select 'policy://'||p.schemaname||'.'||p.tablename||'/'||p.policyname,'RLS_POLICY'
  from pg_policies p
  where p.schemaname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and p.schemaname not like 'pg_%'
  union all
  select 'dbindex://'||n.nspname||'.'||tc.relname||'/'||ic.relname,'DB_INDEX'
  from pg_index i join pg_class tc on tc.oid=i.indrelid
  join pg_namespace n on n.oid=tc.relnamespace join pg_class ic on ic.oid=i.indexrelid
  where n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
),
inv as (
  select object_ref,object_type
  from inventory.objects
  where active and source_system='SUPABASE_PG_CATALOG'
)
select c.object_ref,c.object_type,'MISSING_FROM_INVENTORY'::text drift_state
from current_objects c left join inv i using(object_ref)
where i.object_ref is null
union all
select i.object_ref,i.object_type,'NO_LONGER_IN_PG_CATALOG'::text
from inv i left join current_objects c using(object_ref)
where c.object_ref is null;

create or replace function inventory.fn_lookup_v2(
  p_term text default null,
  p_object_types text[] default null,
  p_limit integer default 100
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
  status text
)
language sql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
with p as (
  select lower(nullif(btrim(p_term),'')) term
),
matched as (
  select
    s.*,
    case
      when p.term is null then 'ALL'
      when s.object_ref_lc=p.term then 'EXACT_REF'
      when s.object_name_lc=p.term then 'EXACT_NAME'
      when p.term=any(s.tags_lc) then 'TAG'
      when p.term=any(s.column_names_lc) then 'COLUMN'
      when s.search_document @@ plainto_tsquery('simple',p.term) then 'TEXT'
      else null
    end match_reason,
    case when p.term=any(s.column_names_lc)
      then array(select c from unnest(s.column_names) c where lower(c)=p.term)
      else '{}'::text[] end matching_columns
  from inventory.search_index s
  cross join p
  where (p_object_types is null or s.object_type=any(p_object_types))
    and (
      p.term is null
      or s.object_ref_lc=p.term
      or s.object_name_lc=p.term
      or p.term=any(s.tags_lc)
      or p.term=any(s.column_names_lc)
      or s.search_document @@ plainto_tsquery('simple',p.term)
    )
)
select
  m.object_ref,m.object_type,m.schema_name,m.object_name,m.match_reason,
  m.matching_columns,m.tags,m.source_system,m.source_of_truth,m.status
from matched m
order by
  case m.match_reason when 'EXACT_REF' then 0 when 'EXACT_NAME' then 1 when 'TAG' then 2 when 'COLUMN' then 3 else 4 end,
  m.object_ref
limit greatest(1,least(coalesce(p_limit,100),500));
$$;

create or replace function inventory.fn_dependencies_v1(
  p_object_ref text,
  p_direction text default 'BOTH',
  p_max_depth integer default 2
)
returns table(
  depth integer,
  direction text,
  source_ref text,
  relation_type text,
  target_ref text,
  evidence_type text,
  confidence numeric
)
language sql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
with recursive
edge_map as (
  select
    d.dependency_id,
    d.source_object_id as from_id,
    d.target_object_id as to_id,
    'OUT'::text as direction,
    so.object_ref as source_ref,
    d.relation_type,
    d.target_ref,
    d.evidence_type,
    d.confidence
  from inventory.dependencies d
  join inventory.objects so on so.object_id=d.source_object_id
  where d.active
  union all
  select
    d.dependency_id,
    d.target_object_id as from_id,
    d.source_object_id as to_id,
    'IN'::text as direction,
    so.object_ref as source_ref,
    d.relation_type,
    coalesce(t.object_ref,d.target_ref) as target_ref,
    d.evidence_type,
    d.confidence
  from inventory.dependencies d
  join inventory.objects so on so.object_id=d.source_object_id
  left join inventory.objects t on t.object_id=d.target_object_id
  where d.active and d.target_object_id is not null
),
start_obj as (
  select object_id,object_ref
  from inventory.objects
  where object_ref=p_object_ref and active
),
walk(depth,direction,current_id,source_ref,relation_type,target_ref,evidence_type,confidence,path) as (
  select
    1,e.direction,e.to_id,e.source_ref,e.relation_type,e.target_ref,e.evidence_type,e.confidence,
    array[s.object_id,coalesce(e.to_id,-e.dependency_id)]
  from start_obj s
  join edge_map e on e.from_id=s.object_id
  where upper(coalesce(p_direction,'BOTH')) in (e.direction,'BOTH')
  union all
  select
    w.depth+1,e.direction,e.to_id,e.source_ref,e.relation_type,e.target_ref,e.evidence_type,e.confidence,
    w.path||coalesce(e.to_id,-e.dependency_id)
  from walk w
  join edge_map e on e.from_id=w.current_id and e.direction=w.direction
  where w.current_id is not null
    and w.depth<greatest(1,least(coalesce(p_max_depth,2),6))
    and not coalesce(e.to_id,-e.dependency_id)=any(w.path)
)
select depth,direction,source_ref,relation_type,target_ref,evidence_type,confidence
from walk
order by depth,direction,source_ref,relation_type,target_ref;
$$;

create or replace function inventory.fn_impact_analysis_v1(
  p_object_ref text,
  p_max_depth integer default 3,
  p_min_confidence numeric default 0.80
)
returns table(
  depth integer,
  affected_ref text,
  affected_type text,
  via_relation text,
  min_confidence numeric,
  source_system text
)
language sql
stable
security invoker
set search_path=inventory,pg_catalog
as $$
with recursive start_obj as (
  select object_id from inventory.objects where object_ref=p_object_ref and active
),
walk(depth,current_id,affected_ref,via_relation,min_confidence,source_system,path) as (
  select
    1,d.source_object_id,src.object_ref,d.relation_type,d.confidence,d.source_system,
    array[s.object_id,d.source_object_id]
  from start_obj s
  join inventory.dependencies d on d.target_object_id=s.object_id and d.active
  join inventory.objects src on src.object_id=d.source_object_id and src.active
  where d.confidence>=coalesce(p_min_confidence,0.80)
  union all
  select
    w.depth+1,d.source_object_id,src.object_ref,d.relation_type,
    least(w.min_confidence,d.confidence),d.source_system,
    w.path||d.source_object_id
  from walk w
  join inventory.dependencies d on d.target_object_id=w.current_id and d.active
  join inventory.objects src on src.object_id=d.source_object_id and src.active
  where w.depth<greatest(1,least(coalesce(p_max_depth,3),6))
    and d.confidence>=coalesce(p_min_confidence,0.80)
    and not d.source_object_id=any(w.path)
)
select
  min(w.depth) depth,
  w.affected_ref,
  o.object_type affected_type,
  (array_agg(w.via_relation order by w.depth))[1] via_relation,
  min(w.min_confidence) min_confidence,
  (array_agg(w.source_system order by w.depth))[1] source_system
from walk w
join inventory.objects o on o.object_ref=w.affected_ref
group by w.affected_ref,o.object_type
order by min(w.depth),w.affected_ref;
$$;

grant select on inventory.v_objects_search_v1,inventory.v_summary_v1,inventory.v_pg_catalog_drift_v1
to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier;

revoke all on function inventory.fn_function_identity_args_stable(oid) from public;
revoke all on function inventory.fn_lookup_v2(text,text[],integer) from public;
revoke all on function inventory.fn_dependencies_v1(text,text,integer) from public;
revoke all on function inventory.fn_impact_analysis_v1(text,integer,numeric) from public;

grant execute on function inventory.fn_function_identity_args_stable(oid),
  inventory.fn_lookup_v2(text,text[],integer),
  inventory.fn_dependencies_v1(text,text,integer),
  inventory.fn_impact_analysis_v1(text,integer,numeric)
to programacion_auditor,programacion_builder,programacion_human_authority,programacion_verifier;

grant execute on function inventory.fn_lookup_v2(text,text[],integer),
  inventory.fn_dependencies_v1(text,text,integer),
  inventory.fn_impact_analysis_v1(text,integer,numeric)
to service_role;
