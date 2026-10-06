-- R7 inventory refresh no-op UPDATE suppression.
-- Draft implementation candidate. No cron schedule change.

do $pre$
begin
  if md5(pg_get_functiondef('inventory.fn_refresh_catalog_v2()'::regprocedure))
       is distinct from '7c76b882c35721741b0340d12d0d139a' then
    raise exception 'INVENTORY_REFRESH_CATALOG_V2_DRIFT';
  end if;
  if md5(pg_get_functiondef('inventory.fn_refresh_db_details_v2()'::regprocedure))
       is distinct from 'fbb27646335add35b375fa67433e3855' then
    raise exception 'INVENTORY_REFRESH_DB_DETAILS_V2_DRIFT';
  end if;
  if md5(pg_get_functiondef('inventory.fn_refresh_search_index_v1()'::regprocedure))
       is distinct from '1d9c68c09412d99f0e8080cacbc314b2' then
    raise exception 'INVENTORY_REFRESH_SEARCH_INDEX_V1_DRIFT';
  end if;
  if to_regclass('inventory.refresh_heartbeats_v1') is not null then
    raise exception 'INVENTORY_REFRESH_HEARTBEAT_ALREADY_EXISTS';
  end if;
end;
$pre$;

create table inventory.refresh_heartbeats_v1(
  refresh_key text primary key,
  source_system text not null,
  last_success_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default clock_timestamp()
);

comment on table inventory.refresh_heartbeats_v1 is
'Small per-refresh heartbeat relation. Carries last successful execution time so unchanged large inventory rows need no timestamp-only UPDATE.';
comment on column inventory.refresh_heartbeats_v1.last_success_at is
'Last successful execution/observation time for the named refresh path.';

alter table inventory.refresh_heartbeats_v1 enable row level security;
revoke all on inventory.refresh_heartbeats_v1 from public,anon,authenticated;
grant select,insert,update on inventory.refresh_heartbeats_v1 to postgres;

create or replace function inventory.fn_refresh_catalog_v2()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare v_start timestamptz:=clock_timestamp();
begin
  insert into inventory.objects(object_ref,object_type,schema_name,object_name,domain,source_system,source_of_truth,status,metadata,last_seen_at,updated_at,active)
  select 'db://'||n.nspname||'.'||c.relname,
    case c.relkind when 'r' then 'DB_TABLE' when 'p' then 'DB_PARTITIONED_TABLE' when 'v' then 'DB_VIEW' else 'DB_MATERIALIZED_VIEW' end,
    n.nspname,c.relname,upper(n.nspname),'SUPABASE_PG_CATALOG',c.relkind in ('r','p'),'ACTIVE',
    jsonb_build_object('oid',c.oid,'relkind',c.relkind),now(),now(),true
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p','v','m')
    and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions','cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
  on conflict(object_ref) do update set object_type=excluded.object_type,schema_name=excluded.schema_name,object_name=excluded.object_name,
    domain=excluded.domain,source_system='SUPABASE_PG_CATALOG',source_of_truth=excluded.source_of_truth,status='ACTIVE',
    metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now()
  where (
    inventory.objects.object_type,
    inventory.objects.schema_name,
    inventory.objects.object_name,
    inventory.objects.domain,
    inventory.objects.source_system,
    inventory.objects.source_of_truth,
    inventory.objects.status,
    inventory.objects.metadata,
    inventory.objects.active
  ) is distinct from (
    excluded.object_type,
    excluded.schema_name,
    excluded.object_name,
    excluded.domain,
    excluded.source_system,
    excluded.source_of_truth,
    excluded.status,
    excluded.metadata,
    excluded.active
  );

  insert into inventory.objects(object_ref,object_type,schema_name,object_name,domain,source_system,source_of_truth,status,definition_sha256,metadata,last_seen_at,updated_at,active)
  select 'dbfunc://'||n.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')',
    case p.prokind when 'p' then 'DB_PROCEDURE' else 'DB_FUNCTION' end,
    n.nspname,p.proname,upper(n.nspname),'SUPABASE_PG_CATALOG',true,'ACTIVE',
    encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex'),
    jsonb_build_object('oid',p.oid),now(),now(),true
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prokind in ('f','p')
    and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions','cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
  on conflict(object_ref) do update set object_type=excluded.object_type,schema_name=excluded.schema_name,object_name=excluded.object_name,
    domain=excluded.domain,source_system='SUPABASE_PG_CATALOG',source_of_truth=true,status='ACTIVE',
    definition_sha256=excluded.definition_sha256,metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now()
  where (
    inventory.objects.object_type,
    inventory.objects.schema_name,
    inventory.objects.object_name,
    inventory.objects.domain,
    inventory.objects.source_system,
    inventory.objects.source_of_truth,
    inventory.objects.status,
    inventory.objects.definition_sha256,
    inventory.objects.metadata,
    inventory.objects.active
  ) is distinct from (
    excluded.object_type,
    excluded.schema_name,
    excluded.object_name,
    excluded.domain,
    excluded.source_system,
    excluded.source_of_truth,
    excluded.status,
    excluded.definition_sha256,
    excluded.metadata,
    excluded.active
  );

  delete from inventory.columns c
  using inventory.objects o
  where c.object_id=o.object_id
    and o.source_system='SUPABASE_PG_CATALOG'
    and o.object_type in ('DB_TABLE','DB_PARTITIONED_TABLE','DB_VIEW','DB_MATERIALIZED_VIEW');

  insert into inventory.columns(object_id,ordinal_position,column_name,data_type,udt_name,is_nullable,column_default,is_generated,is_identity,is_primary_key,metadata,updated_at)
  select distinct on (o.object_id,c.column_name)
    o.object_id,c.ordinal_position,c.column_name,c.data_type,c.udt_name,c.is_nullable='YES',c.column_default,
    c.is_generated<>'NEVER',c.is_identity='YES',
    exists(select 1 from pg_namespace pn join pg_class pc on pc.relnamespace=pn.oid and pc.relname=c.table_name
      join pg_index pi on pi.indrelid=pc.oid and pi.indisprimary join lateral unnest(pi.indkey) k(attnum) on true
      join pg_attribute pa on pa.attrelid=pc.oid and pa.attnum=k.attnum
      where pn.nspname=c.table_schema and pa.attname=c.column_name),
    '{}'::jsonb,now()
  from information_schema.columns c
  join inventory.objects o on o.object_ref='db://'||c.table_schema||'.'||c.table_name
  where o.active and o.source_system='SUPABASE_PG_CATALOG'
    and o.object_type in ('DB_TABLE','DB_PARTITIONED_TABLE','DB_VIEW','DB_MATERIALIZED_VIEW')
  order by o.object_id,c.column_name,c.ordinal_position;

  perform inventory.fn_retire_missing_pg_objects_v1();

  insert into inventory.refresh_heartbeats_v1(refresh_key,source_system,last_success_at,metadata,updated_at)
  values('PG_CATALOG_CATALOG_V2','SUPABASE_PG_CATALOG',clock_timestamp(),
         jsonb_build_object('function','inventory.fn_refresh_catalog_v2'),clock_timestamp())
  on conflict(refresh_key) do update
  set source_system=excluded.source_system,
      last_success_at=excluded.last_success_at,
      metadata=excluded.metadata,
      updated_at=excluded.updated_at;

  return jsonb_build_object('status','COMPLETED',
    'objects',(select count(*) from inventory.objects where active),
    'drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;

create or replace function inventory.fn_refresh_db_details_v2()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare v_start timestamptz:=clock_timestamp();
begin
  delete from inventory.indexes i
  using inventory.objects o
  where i.object_id=o.object_id and o.source_system='SUPABASE_PG_CATALOG';

  insert into inventory.indexes(object_id,index_name,is_unique,is_primary,indexed_columns,definition,metadata,updated_at)
  select o.object_id,ic.relname,i.indisunique,i.indisprimary,
    coalesce(array_agg(a.attname order by k.ord) filter(where a.attname is not null),'{}'::text[]),
    pg_get_indexdef(i.indexrelid),jsonb_build_object('is_valid',i.indisvalid,'is_ready',i.indisready),now()
  from pg_index i
  join pg_class tc on tc.oid=i.indrelid join pg_namespace n on n.oid=tc.relnamespace
  join pg_class ic on ic.oid=i.indexrelid
  join inventory.objects o on o.object_ref='db://'||n.nspname||'.'||tc.relname
    and o.active and o.source_system='SUPABASE_PG_CATALOG'
  left join lateral unnest(i.indkey) with ordinality k(attnum,ord) on true
  left join pg_attribute a on a.attrelid=tc.oid and a.attnum=k.attnum and k.attnum>0
  group by o.object_id,ic.relname,i.indisunique,i.indisprimary,i.indexrelid,i.indisvalid,i.indisready;

  insert into inventory.objects(object_ref,object_type,schema_name,object_name,parent_object_id,domain,source_system,source_of_truth,status,metadata,last_seen_at,updated_at,active)
  select 'dbindex://'||t.schema_name||'.'||t.object_name||'/'||i.index_name,'DB_INDEX',
    t.schema_name,i.index_name,t.object_id,upper(t.schema_name),'SUPABASE_PG_CATALOG',true,'ACTIVE',
    jsonb_build_object('table_ref',t.object_ref,'indexed_columns',i.indexed_columns,'is_unique',i.is_unique,'is_primary',i.is_primary),
    now(),now(),true
  from inventory.indexes i join inventory.objects t on t.object_id=i.object_id
  where t.source_system='SUPABASE_PG_CATALOG' and t.active
  on conflict(object_ref) do update set parent_object_id=excluded.parent_object_id,source_system='SUPABASE_PG_CATALOG',
    status='ACTIVE',metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now()
  where (
    inventory.objects.parent_object_id,
    inventory.objects.source_system,
    inventory.objects.status,
    inventory.objects.metadata,
    inventory.objects.active
  ) is distinct from (
    excluded.parent_object_id,
    excluded.source_system,
    excluded.status,
    excluded.metadata,
    excluded.active
  );

  insert into inventory.objects(object_ref,object_type,schema_name,object_name,parent_object_id,domain,source_system,source_of_truth,status,definition_sha256,metadata,last_seen_at,updated_at,active)
  select 'trigger://'||n.nspname||'.'||c.relname||'/'||t.tgname,'DB_TRIGGER',n.nspname,t.tgname,parent.object_id,
    upper(n.nspname),'SUPABASE_PG_CATALOG',true,'ACTIVE',
    encode(extensions.digest(convert_to(pg_get_triggerdef(t.oid,true),'UTF8'),'sha256'),'hex'),
    jsonb_build_object('oid',t.oid,'table_ref',parent.object_ref),now(),now(),true
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  join inventory.objects parent on parent.object_ref='db://'||n.nspname||'.'||c.relname
    and parent.active and parent.source_system='SUPABASE_PG_CATALOG'
  where not t.tgisinternal
    and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions','cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
    and n.nspname not like 'pg_%'
  on conflict(object_ref) do update set parent_object_id=excluded.parent_object_id,source_system='SUPABASE_PG_CATALOG',
    status='ACTIVE',definition_sha256=excluded.definition_sha256,metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now()
  where (
    inventory.objects.parent_object_id,
    inventory.objects.source_system,
    inventory.objects.status,
    inventory.objects.definition_sha256,
    inventory.objects.metadata,
    inventory.objects.active
  ) is distinct from (
    excluded.parent_object_id,
    excluded.source_system,
    excluded.status,
    excluded.definition_sha256,
    excluded.metadata,
    excluded.active
  );

  insert into inventory.triggers(object_id,table_object_id,enabled_state,trigger_definition,function_ref,metadata,updated_at)
  select o.object_id,parent.object_id,t.tgenabled::text,pg_get_triggerdef(t.oid,true),
    'dbfunc://'||fnn.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')',
    jsonb_build_object('constraint_oid',t.tgconstraint),now()
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  join pg_proc p on p.oid=t.tgfoid join pg_namespace fnn on fnn.oid=p.pronamespace
  join inventory.objects o on o.object_ref='trigger://'||n.nspname||'.'||c.relname||'/'||t.tgname
    and o.active and o.source_system='SUPABASE_PG_CATALOG'
  join inventory.objects parent on parent.object_ref='db://'||n.nspname||'.'||c.relname
    and parent.active and parent.source_system='SUPABASE_PG_CATALOG'
  where not t.tgisinternal
  on conflict(object_id) do update set table_object_id=excluded.table_object_id,enabled_state=excluded.enabled_state,
    trigger_definition=excluded.trigger_definition,function_ref=excluded.function_ref,metadata=excluded.metadata,updated_at=now();

  insert into inventory.objects(object_ref,object_type,schema_name,object_name,parent_object_id,domain,source_system,source_of_truth,status,metadata,last_seen_at,updated_at,active)
  select 'policy://'||p.schemaname||'.'||p.tablename||'/'||p.policyname,'RLS_POLICY',
    p.schemaname,p.policyname,parent.object_id,upper(p.schemaname),'SUPABASE_PG_CATALOG',true,'ACTIVE',
    jsonb_build_object('table_ref',parent.object_ref),now(),now(),true
  from pg_policies p
  join inventory.objects parent on parent.object_ref='db://'||p.schemaname||'.'||p.tablename
    and parent.active and parent.source_system='SUPABASE_PG_CATALOG'
  where p.schemaname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions','cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
  on conflict(object_ref) do update set parent_object_id=excluded.parent_object_id,source_system='SUPABASE_PG_CATALOG',
    status='ACTIVE',metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now()
  where (
    inventory.objects.parent_object_id,
    inventory.objects.source_system,
    inventory.objects.status,
    inventory.objects.metadata,
    inventory.objects.active
  ) is distinct from (
    excluded.parent_object_id,
    excluded.source_system,
    excluded.status,
    excluded.metadata,
    excluded.active
  );

  insert into inventory.policies(object_id,table_object_id,command,roles,permissive,using_expression,check_expression,metadata,updated_at)
  select o.object_id,parent.object_id,p.cmd,p.roles,p.permissive,p.qual,p.with_check,'{}'::jsonb,now()
  from pg_policies p
  join inventory.objects o on o.object_ref='policy://'||p.schemaname||'.'||p.tablename||'/'||p.policyname
    and o.active and o.source_system='SUPABASE_PG_CATALOG'
  join inventory.objects parent on parent.object_ref='db://'||p.schemaname||'.'||p.tablename
    and parent.active and parent.source_system='SUPABASE_PG_CATALOG'
  on conflict(object_id) do update set table_object_id=excluded.table_object_id,command=excluded.command,
    roles=excluded.roles,permissive=excluded.permissive,using_expression=excluded.using_expression,
    check_expression=excluded.check_expression,updated_at=now();

  insert into inventory.functions(object_id,identity_arguments,result_type,language,function_kind,volatility,parallel_safety,
    security_definer,is_strict,definition_sha256,definition_bytes,metadata,updated_at)
  select o.object_id,inventory.fn_function_identity_args_stable(p.oid),pg_get_function_result(p.oid),l.lanname,
    case p.prokind when 'p' then 'PROCEDURE' else 'FUNCTION' end,
    case p.provolatile when 'i' then 'IMMUTABLE' when 's' then 'STABLE' else 'VOLATILE' end,
    case p.proparallel when 's' then 'SAFE' when 'r' then 'RESTRICTED' else 'UNSAFE' end,
    p.prosecdef,p.proisstrict,o.definition_sha256,octet_length(pg_get_functiondef(p.oid)),
    jsonb_build_object('returns_set',p.proretset,'estimated_cost',p.procost,'estimated_rows',p.prorows),now()
  from inventory.objects o join pg_namespace n on n.nspname=o.schema_name
  join pg_proc p on p.pronamespace=n.oid
    and o.object_ref='dbfunc://'||n.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')'
  join pg_language l on l.oid=p.prolang
  where o.active and o.source_system='SUPABASE_PG_CATALOG'
    and o.object_type in ('DB_FUNCTION','DB_PROCEDURE')
  on conflict(object_id) do update set identity_arguments=excluded.identity_arguments,result_type=excluded.result_type,
    language=excluded.language,function_kind=excluded.function_kind,volatility=excluded.volatility,
    parallel_safety=excluded.parallel_safety,security_definer=excluded.security_definer,is_strict=excluded.is_strict,
    definition_sha256=excluded.definition_sha256,definition_bytes=excluded.definition_bytes,metadata=inventory.functions.metadata || excluded.metadata,updated_at=now();

  perform inventory.fn_retire_missing_pg_objects_v1();

  insert into inventory.refresh_heartbeats_v1(refresh_key,source_system,last_success_at,metadata,updated_at)
  values('PG_CATALOG_DETAILS_V2','SUPABASE_PG_CATALOG',clock_timestamp(),
         jsonb_build_object('function','inventory.fn_refresh_db_details_v2'),clock_timestamp())
  on conflict(refresh_key) do update
  set source_system=excluded.source_system,
      last_success_at=excluded.last_success_at,
      metadata=excluded.metadata,
      updated_at=excluded.updated_at;

  return jsonb_build_object('status','COMPLETED',
    'drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;

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
        then inventory.fn_external_currentness_eval_v1(
          o.currentness,o.observed_at,now()
        )
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
    source_traceability_state=excluded.source_traceability_state
  where (
    inventory.search_index.object_ref,
    inventory.search_index.object_ref_lc,
    inventory.search_index.object_type,
    inventory.search_index.schema_name,
    inventory.search_index.object_name,
    inventory.search_index.object_name_lc,
    inventory.search_index.tags,
    inventory.search_index.tags_lc,
    inventory.search_index.column_names,
    inventory.search_index.column_names_lc,
    inventory.search_index.source_system,
    inventory.search_index.source_of_truth,
    inventory.search_index.status,
    inventory.search_index.search_document,
    inventory.search_index.currentness,
    inventory.search_index.currentness_source,
    inventory.search_index.observed_at,
    inventory.search_index.observed_main_sha,
    inventory.search_index.source_traceability_state
  ) is distinct from (
    excluded.object_ref,
    excluded.object_ref_lc,
    excluded.object_type,
    excluded.schema_name,
    excluded.object_name,
    excluded.object_name_lc,
    excluded.tags,
    excluded.tags_lc,
    excluded.column_names,
    excluded.column_names_lc,
    excluded.source_system,
    excluded.source_of_truth,
    excluded.status,
    excluded.search_document,
    excluded.currentness,
    excluded.currentness_source,
    excluded.observed_at,
    excluded.observed_main_sha,
    excluded.source_traceability_state
  );

  delete from inventory.search_index s
  where not exists (
    select 1 from inventory.objects o
    where o.object_id=s.object_id and o.active
  );

  insert into inventory.refresh_heartbeats_v1(refresh_key,source_system,last_success_at,metadata,updated_at)
  values('SEARCH_INDEX_V1','INVENTORY_DERIVED',clock_timestamp(),
         jsonb_build_object('function','inventory.fn_refresh_search_index_v1'),clock_timestamp())
  on conflict(refresh_key) do update
  set source_system=excluded.source_system,
      last_success_at=excluded.last_success_at,
      metadata=excluded.metadata,
      updated_at=excluded.updated_at;

  select count(*) into v_count from inventory.search_index;
  return v_count;
end;
$$;


do $post$
declare
  v_catalog text:=pg_get_functiondef('inventory.fn_refresh_catalog_v2()'::regprocedure);
  v_details text:=pg_get_functiondef('inventory.fn_refresh_db_details_v2()'::regprocedure);
  v_search text:=pg_get_functiondef('inventory.fn_refresh_search_index_v1()'::regprocedure);
begin
  if position('fn_refresh_search_index_v1' in v_catalog)>0 then
    raise exception 'INVENTORY_REFRESH_EARLY_SEARCH_CALL_REMAINS';
  end if;
  if position('IS DISTINCT FROM' in upper(v_catalog))=0
     or position('IS DISTINCT FROM' in upper(v_details))=0
     or position('IS DISTINCT FROM' in upper(v_search))=0 then
    raise exception 'INVENTORY_REFRESH_DISTINCT_GUARD_MISSING';
  end if;
  if to_regclass('inventory.refresh_heartbeats_v1') is null then
    raise exception 'INVENTORY_REFRESH_HEARTBEAT_MISSING';
  end if;
end;
$post$;
