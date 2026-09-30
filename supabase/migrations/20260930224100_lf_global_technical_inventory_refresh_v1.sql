
-- LF Global Technical Inventory - Refresh/maintenance v1

-- Reconcile exploratory pre-R16 inventory functions that were created live in Sandbox
-- and are superseded by the Git-versioned implementations below.
drop function if exists inventory.fn_refresh_all_v1();
drop function if exists inventory.fn_lookup_v1(text,text[],integer);
drop function if exists inventory.fn_refresh_catalog_v1();
drop function if exists inventory.fn_refresh_db_details_v1();
drop function if exists inventory.fn_refresh_dependencies_v1();
drop function if exists inventory.fn_refresh_dependencies_v2();
drop function if exists inventory.fn_refresh_sql_reads_writes_v1();


create or replace function inventory.fn_refresh_search_index_v1()
returns bigint
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_count bigint;
begin
  insert into inventory.search_index(
    object_id,object_ref,object_ref_lc,object_type,schema_name,object_name,object_name_lc,
    tags,tags_lc,column_names,column_names_lc,source_system,source_of_truth,status,search_document,refreshed_at
  )
  select
    o.object_id,o.object_ref,lower(o.object_ref),o.object_type,o.schema_name,o.object_name,lower(o.object_name),
    coalesce(t.tags,'{}'::text[]),coalesce(t.tags_lc,'{}'::text[]),
    coalesce(c.cols,'{}'::text[]),coalesce(c.cols_lc,'{}'::text[]),
    o.source_system,o.source_of_truth,o.status,
    to_tsvector('simple',
      coalesce(o.object_ref,'')||' '||coalesce(o.object_name,'')||' '||coalesce(o.schema_name,'')||' '||
      array_to_string(coalesce(t.tags,'{}'::text[]),' ')||' '||
      array_to_string(coalesce(c.cols,'{}'::text[]),' ')
    ),
    now()
  from inventory.objects o
  left join lateral (
    select array_agg(distinct ot.tag_code order by ot.tag_code) tags,
           array_agg(distinct lower(ot.tag_code) order by lower(ot.tag_code)) tags_lc
    from inventory.object_tags ot where ot.object_id=o.object_id
  ) t on true
  left join lateral (
    select array_agg(ic.column_name order by ic.ordinal_position) cols,
           array_agg(lower(ic.column_name) order by ic.ordinal_position) cols_lc
    from inventory.columns ic where ic.object_id=o.object_id
  ) c on true
  where o.active
  on conflict(object_id) do update set
    object_ref=excluded.object_ref,object_ref_lc=excluded.object_ref_lc,object_type=excluded.object_type,
    schema_name=excluded.schema_name,object_name=excluded.object_name,object_name_lc=excluded.object_name_lc,
    tags=excluded.tags,tags_lc=excluded.tags_lc,column_names=excluded.column_names,
    column_names_lc=excluded.column_names_lc,source_system=excluded.source_system,
    source_of_truth=excluded.source_of_truth,status=excluded.status,
    search_document=excluded.search_document,refreshed_at=now();

  delete from inventory.search_index s
  where not exists(select 1 from inventory.objects o where o.object_id=s.object_id and o.active);

  select count(*) into v_count from inventory.search_index;
  return v_count;
end;
$$;

create or replace function inventory.fn_retire_missing_pg_objects_v1()
returns bigint
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare v_count bigint;
begin
  with current_objects as (
    select 'db://'||n.nspname||'.'||c.relname object_ref
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where c.relkind in ('r','p','v','m')
      and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
        'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
      and n.nspname not like 'pg_%'
    union all
    select 'dbfunc://'||n.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')'
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where p.prokind in ('f','p')
      and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
        'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
      and n.nspname not like 'pg_%'
    union all
    select 'trigger://'||n.nspname||'.'||c.relname||'/'||t.tgname
    from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal
      and n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
        'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
      and n.nspname not like 'pg_%'
    union all
    select 'policy://'||p.schemaname||'.'||p.tablename||'/'||p.policyname
    from pg_policies p
    where p.schemaname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
      and p.schemaname not like 'pg_%'
    union all
    select 'dbindex://'||n.nspname||'.'||tc.relname||'/'||ic.relname
    from pg_index i join pg_class tc on tc.oid=i.indrelid
    join pg_namespace n on n.oid=tc.relnamespace join pg_class ic on ic.oid=i.indexrelid
    where n.nspname not in ('pg_catalog','information_schema','pg_toast','auth','storage','realtime','extensions',
      'cron','net','vault','graphql_public','pgbouncer','supabase_migrations','inventory')
      and n.nspname not like 'pg_%'
  )
  update inventory.objects o
  set active=false,status='NO_LONGER_IN_PG_CATALOG',updated_at=now()
  where o.active
    and o.source_system='SUPABASE_PG_CATALOG'
    and o.object_type in ('DB_TABLE','DB_PARTITIONED_TABLE','DB_VIEW','DB_MATERIALIZED_VIEW',
      'DB_FUNCTION','DB_PROCEDURE','DB_TRIGGER','RLS_POLICY','DB_INDEX')
    and not exists(select 1 from current_objects c where c.object_ref=o.object_ref);

  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

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
    metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

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
    definition_sha256=excluded.definition_sha256,metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

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
  perform inventory.fn_refresh_search_index_v1();

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
    status='ACTIVE',metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

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
    status='ACTIVE',definition_sha256=excluded.definition_sha256,metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

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
    status='ACTIVE',metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

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
    definition_sha256=excluded.definition_sha256,definition_bytes=excluded.definition_bytes,metadata=excluded.metadata,updated_at=now();

  perform inventory.fn_retire_missing_pg_objects_v1();

  return jsonb_build_object('status','COMPLETED',
    'drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;

create or replace function inventory.fn_refresh_dependencies_exact_v1()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare v_start timestamptz:=clock_timestamp();
begin
  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,confidence,source_system,metadata,last_verified_at,active)
  select 'FK|'||con.oid,src.object_id,tgt.object_id,tgt.object_ref,'FK_TO','PG_CONSTRAINT',
    pg_get_constraintdef(con.oid,true),1.0,'SUPABASE_PG_CATALOG',
    jsonb_build_object('constraint_name',con.conname,'constraint_oid',con.oid),v_start,true
  from pg_constraint con
  join pg_class sc on sc.oid=con.conrelid join pg_namespace sn on sn.oid=sc.relnamespace
  join pg_class tc on tc.oid=con.confrelid join pg_namespace tn on tn.oid=tc.relnamespace
  join inventory.objects src on src.object_ref='db://'||sn.nspname||'.'||sc.relname and src.active
  join inventory.objects tgt on tgt.object_ref='db://'||tn.nspname||'.'||tc.relname and tgt.active
  where con.contype='f'
  on conflict(dependency_key) do update set
    source_object_id=excluded.source_object_id,target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,
    relation_type=excluded.relation_type,evidence_type=excluded.evidence_type,evidence=excluded.evidence,
    confidence=excluded.confidence,source_system=excluded.source_system,metadata=excluded.metadata,
    last_verified_at=excluded.last_verified_at,active=true;

  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,confidence,source_system,metadata,last_verified_at,active)
  select distinct 'VIEW|'||v.oid||'|'||ref.oid,src.object_id,tgt.object_id,tgt.object_ref,'READS_FROM','PG_REWRITE_DEPENDENCY',
    'PostgreSQL rewrite dependency',1.0,'SUPABASE_PG_CATALOG',
    jsonb_build_object('view_oid',v.oid,'target_oid',ref.oid),v_start,true
  from pg_rewrite rw
  join pg_class v on v.oid=rw.ev_class and v.relkind in ('v','m')
  join pg_depend dep on dep.classid='pg_rewrite'::regclass and dep.objid=rw.oid
  join pg_class ref on ref.oid=dep.refobjid and ref.relkind in ('r','p','v','m')
  join pg_namespace vn on vn.oid=v.relnamespace join pg_namespace rn on rn.oid=ref.relnamespace
  join inventory.objects src on src.object_ref='db://'||vn.nspname||'.'||v.relname and src.active
  join inventory.objects tgt on tgt.object_ref='db://'||rn.nspname||'.'||ref.relname and tgt.active
  where ref.oid<>v.oid
  on conflict(dependency_key) do update set
    source_object_id=excluded.source_object_id,target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,
    relation_type=excluded.relation_type,evidence_type=excluded.evidence_type,evidence=excluded.evidence,
    confidence=excluded.confidence,source_system=excluded.source_system,metadata=excluded.metadata,
    last_verified_at=excluded.last_verified_at,active=true;

  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,confidence,source_system,metadata,last_verified_at,active)
  select 'TRIGGER_TABLE|'||o.object_id,o.object_id,tr.table_object_id,tab.object_ref,'ATTACHED_TO','PG_TRIGGER',
    tr.trigger_definition,1.0,'SUPABASE_PG_CATALOG','{}'::jsonb,v_start,true
  from inventory.triggers tr join inventory.objects o on o.object_id=tr.object_id and o.active
  join inventory.objects tab on tab.object_id=tr.table_object_id and tab.active
  on conflict(dependency_key) do update set
    target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,evidence=excluded.evidence,
    last_verified_at=excluded.last_verified_at,active=true;

  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,confidence,source_system,metadata,last_verified_at,active)
  select 'TRIGGER_FN|'||o.object_id,o.object_id,fn.object_id,tr.function_ref,'EXECUTES','PG_TRIGGER',
    tr.trigger_definition,1.0,'SUPABASE_PG_CATALOG','{}'::jsonb,v_start,true
  from inventory.triggers tr join inventory.objects o on o.object_id=tr.object_id and o.active
  left join inventory.objects fn on fn.object_ref=tr.function_ref and fn.active
  on conflict(dependency_key) do update set
    target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,evidence=excluded.evidence,
    last_verified_at=excluded.last_verified_at,active=true;

  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,confidence,source_system,metadata,last_verified_at,active)
  select 'POLICY|'||o.object_id,o.object_id,pol.table_object_id,t.object_ref,'GOVERNS','PG_POLICY',
    concat_ws(' | ',pol.command,pol.using_expression,pol.check_expression),1.0,'SUPABASE_PG_CATALOG','{}'::jsonb,v_start,true
  from inventory.policies pol join inventory.objects o on o.object_id=pol.object_id and o.active
  join inventory.objects t on t.object_id=pol.table_object_id and t.active
  on conflict(dependency_key) do update set
    target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,evidence=excluded.evidence,
    last_verified_at=excluded.last_verified_at,active=true;

  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,confidence,source_system,metadata,last_verified_at,active)
  select 'INDEX_ON|'||idx.object_id,idx.object_id,t.object_id,t.object_ref,'INDEX_ON','PG_INDEX',
    i.definition,1.0,'SUPABASE_PG_CATALOG','{}'::jsonb,v_start,true
  from inventory.indexes i
  join inventory.objects t on t.object_id=i.object_id and t.active
  join inventory.objects idx on idx.object_ref='dbindex://'||t.schema_name||'.'||t.object_name||'/'||i.index_name and idx.active
  on conflict(dependency_key) do update set
    target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,evidence=excluded.evidence,
    last_verified_at=excluded.last_verified_at,active=true;

  update inventory.dependencies
  set active=false
  where active and source_system='SUPABASE_PG_CATALOG' and last_verified_at<v_start;

  return jsonb_build_object('status','COMPLETED',
    'exact_edges',(select count(*) from inventory.dependencies where active and source_system='SUPABASE_PG_CATALOG'),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;

create or replace function inventory.fn_refresh_static_incremental_v1()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_start timestamptz:=clock_timestamp();
  v_changed bigint;
begin
  select count(*) into v_changed
  from inventory.functions f
  join inventory.objects o on o.object_id=f.object_id
  where o.active and o.source_system='SUPABASE_PG_CATALOG'
    and o.object_type in ('DB_FUNCTION','DB_PROCEDURE')
    and coalesce(f.metadata->>'static_analysis_sha256','')<>coalesce(o.definition_sha256,'');

  if v_changed=0 then
    return jsonb_build_object('status','NO_CHANGES','changed_functions',0,'duration_ms',0);
  end if;

  delete from inventory.dependencies d
  using inventory.functions f,inventory.objects o
  where d.source_object_id=o.object_id and f.object_id=o.object_id
    and o.active and o.source_system='SUPABASE_PG_CATALOG'
    and coalesce(f.metadata->>'static_analysis_sha256','')<>coalesce(o.definition_sha256,'')
    and d.source_system in ('STATIC_SQL_ANALYSIS','STATIC_SQL_ANALYSIS_V2');

  with changed_fn as (
    select o.object_id,lower(regexp_replace(pg_get_functiondef(p.oid),'[[:space:]]+',' ','g')) def
    from inventory.functions f
    join inventory.objects o on o.object_id=f.object_id
    join pg_namespace n on n.nspname=o.schema_name
    join pg_proc p on p.pronamespace=n.oid
      and o.object_ref='dbfunc://'||n.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')'
    where o.active and o.source_system='SUPABASE_PG_CATALOG'
      and coalesce(f.metadata->>'static_analysis_sha256','')<>coalesce(o.definition_sha256,'')
  ), rels as (
    select object_id,object_ref,schema_name,object_name
    from inventory.objects
    where active and source_system='SUPABASE_PG_CATALOG'
      and object_type in ('DB_TABLE','DB_PARTITIONED_TABLE','DB_VIEW','DB_MATERIALIZED_VIEW')
  ), m as (
    select f.object_id source_object_id,r.object_id target_object_id,r.object_ref,
      r.schema_name||'.'||r.object_name qname,f.def
    from changed_fn f
    join rels r on position(lower(r.schema_name||'.'||r.object_name) in f.def)>0
  )
  insert into inventory.dependencies(
    dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,
    confidence,source_system,metadata,last_verified_at,active
  )
  select
    case when def ~ ('(insert into|update|delete from|merge into)[[:space:]]+'||replace(lower(qname),'.','\.')||'\y')
      then 'FUNC_WRITE|'||source_object_id||'|'||target_object_id
      else 'FUNC_READ|'||source_object_id||'|'||target_object_id end,
    source_object_id,target_object_id,object_ref,
    case when def ~ ('(insert into|update|delete from|merge into)[[:space:]]+'||replace(lower(qname),'.','\.')||'\y')
      then 'WRITES_TO' else 'READS_FROM' end,
    'FUNCTION_SQL_PATTERN',qname,
    case when def ~ ('(insert into|update|delete from|merge into)[[:space:]]+'||replace(lower(qname),'.','\.')||'\y')
      then 0.90 else 0.85 end,
    'STATIC_SQL_ANALYSIS_V2',jsonb_build_object('classifier','SQL_PATTERN_V1'),v_start,true
  from m
  where def ~ ('(insert into|update|delete from|merge into|from|join)[[:space:]]+'||replace(lower(qname),'.','\.')||'\y')
  on conflict(dependency_key) do update set
    target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,relation_type=excluded.relation_type,
    evidence=excluded.evidence,confidence=excluded.confidence,metadata=excluded.metadata,
    last_verified_at=excluded.last_verified_at,active=true;

  with changed_fn as (
    select o.object_id,o.schema_name,o.object_name,
      lower(replace(pg_get_functiondef(p.oid),'"','')) def
    from inventory.functions f
    join inventory.objects o on o.object_id=f.object_id
    join pg_namespace n on n.nspname=o.schema_name
    join pg_proc p on p.pronamespace=n.oid
      and o.object_ref='dbfunc://'||n.nspname||'.'||p.proname||'('||inventory.fn_function_identity_args_stable(p.oid)||')'
    where o.active and o.source_system='SUPABASE_PG_CATALOG'
      and coalesce(f.metadata->>'static_analysis_sha256','')<>coalesce(o.definition_sha256,'')
  ), all_fn as (
    select o.object_id,o.object_ref,o.schema_name,o.object_name
    from inventory.objects o
    where o.active and o.source_system='SUPABASE_PG_CATALOG'
      and o.object_type in ('DB_FUNCTION','DB_PROCEDURE')
  ), nc as (
    select object_name,count(*) n from all_fn group by object_name
  )
  insert into inventory.dependencies(
    dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,evidence,
    confidence,source_system,metadata,last_verified_at,active
  )
  select distinct
    'FUNC_CALL|'||caller.object_id||'|'||callee.object_id,
    caller.object_id,callee.object_id,callee.object_ref,'CALLS','FUNCTION_DEFINITION_REFERENCE',
    'Function name reference',
    case when position(lower(callee.schema_name||'.'||callee.object_name||'(') in caller.def)>0 then 0.90 else 0.70 end,
    'STATIC_SQL_ANALYSIS',jsonb_build_object('classifier','FUNCTION_CALL_REFERENCE_V1'),v_start,true
  from changed_fn caller
  join all_fn callee on callee.object_id<>caller.object_id
  join nc on nc.object_name=callee.object_name
  where position(lower(callee.schema_name||'.'||callee.object_name||'(') in caller.def)>0
     or (nc.n=1 and position(lower(callee.object_name||'(') in caller.def)>0)
  on conflict(dependency_key) do update set
    target_object_id=excluded.target_object_id,target_ref=excluded.target_ref,confidence=excluded.confidence,
    metadata=excluded.metadata,last_verified_at=excluded.last_verified_at,active=true;

  update inventory.functions f
  set metadata=jsonb_set(coalesce(f.metadata,'{}'::jsonb),'{static_analysis_sha256}',to_jsonb(o.definition_sha256),true),
      updated_at=now()
  from inventory.objects o
  where o.object_id=f.object_id and o.active and o.source_system='SUPABASE_PG_CATALOG'
    and coalesce(f.metadata->>'static_analysis_sha256','')<>coalesce(o.definition_sha256,'');

  return jsonb_build_object('status','COMPLETED','changed_functions',v_changed,
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;

create or replace function inventory.fn_refresh_registries_v1()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,public,programacion,pg_catalog
as $$
declare v_start timestamptz:=clock_timestamp();
begin
  insert into inventory.objects(object_ref,object_type,object_name,domain,source_system,source_of_truth,status,source_version,metadata,last_seen_at,updated_at,active)
  select 'asset://'||a.codigo_activo,
    case when a.subtipo_activo='EDGE_FUNCTION' then 'EDGE_FUNCTION'
         when a.tipo_activo='CAPABILITY' then 'CAPABILITY' else 'LF_ASSET' end,
    a.codigo_activo,coalesce(a.metadata->>'dominio',a.metadata->>'domain',a.tipo_activo),
    'LF_ACTIVOS',true,coalesce(a.estado_operativo,a.estado_documental,'ACTIVE'),a.version,
    jsonb_build_object('lf_activo_id',a.id,'nombre_canonico',a.nombre_canonico,'tipo_activo',a.tipo_activo,
      'subtipo_activo',a.subtipo_activo,'ruta_esperada',a.ruta_esperada,'url',a.url,
      'rol_arquitectura',a.rol_arquitectura,'owner',a.owner_name,'metadata',a.metadata),
    now(),now(),true
  from public.lf_activos a where a.archived_at is null
  on conflict(object_ref) do update set object_type=excluded.object_type,object_name=excluded.object_name,
    domain=excluded.domain,status=excluded.status,source_version=excluded.source_version,
    metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

  insert into inventory.objects(object_ref,object_type,schema_name,object_name,domain,source_system,source_of_truth,status,source_version,metadata,last_seen_at,updated_at,active)
  select 'contract://programacion.contratos/'||c.contrato_codigo||'#'||c.id,'CONTRACT','programacion',
    c.contrato_codigo,case when c.contrato_codigo ilike 'INPUT_%' then 'INPUT_GOVERNANCE' else 'PROGRAMACION' end,
    'PROGRAMACION_CONTRATOS',true,c.estado,
    coalesce(c.especificacion->>'contract_revision',c.especificacion->>'schema_version'),
    jsonb_build_object('id',c.id,'version_id',c.version_id,'fail_closed',c.fail_closed,'especificacion',c.especificacion),
    now(),now(),true
  from programacion.contratos c
  on conflict(object_ref) do update set status=excluded.status,source_version=excluded.source_version,
    metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

  insert into inventory.objects(object_ref,object_type,object_name,domain,source_system,source_of_truth,status,source_version,metadata,last_seen_at,updated_at,active)
  select 'operation://'||r.operation_code,'OPERATION',r.operation_code,
    coalesce(r.operation_domain,r.operation_family,'OPERATIONS'),'LF_OPERATION_REGISTRY',true,r.status,r.version,
    jsonb_build_object('operation_family',r.operation_family,'operation_domain',r.operation_domain,
      'operation_type',r.operation_type,'applies_to_asset_type',r.applies_to_asset_type,
      'source_repo',r.source_repo,'source_paths',r.source_paths,'notes',r.notes),
    now(),now(),true
  from public.lf_operation_registry r
  on conflict(object_ref) do update set domain=excluded.domain,status=excluded.status,source_version=excluded.source_version,
    metadata=excluded.metadata,last_seen_at=now(),active=true,updated_at=now();

  delete from inventory.dependencies where source_system='LF_ACTIVO_RELACIONES';

  insert into inventory.dependencies(dependency_key,source_object_id,target_object_id,target_ref,relation_type,evidence_type,
    evidence,confidence,source_system,metadata,last_verified_at,active)
  select 'LF_ASSET_REL|'||r.id,src.object_id,tgt.object_id,'asset://'||r.relacionado_codigo,
    r.relacion_tipo,'LF_ACTIVO_RELACION',r.valor_original,1.0,'LF_ACTIVO_RELACIONES',
    jsonb_build_object('relation_id',r.id,'fuente',r.fuente,'migration_batch_id',r.migration_batch_id),now(),true
  from public.lf_activo_relaciones r
  join inventory.objects src on src.object_ref='asset://'||r.codigo_activo and src.active
  left join inventory.objects tgt on tgt.object_ref='asset://'||r.relacionado_codigo and tgt.active;

  return jsonb_build_object('status','COMPLETED',
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;

create or replace function inventory.fn_finalize_refresh_v1()
returns jsonb
language plpgsql
security invoker
set search_path=inventory,pg_catalog
as $$
declare
  v_start timestamptz:=clock_timestamp();
  v_reg jsonb;
  v_indexed bigint;
begin
  v_reg := inventory.fn_refresh_registries_v1();
  v_indexed := inventory.fn_refresh_search_index_v1();

  insert into inventory.snapshots(
    snapshot_code,source_system,scope,started_at,completed_at,status,
    object_count,dependency_count,metadata
  )
  values(
    'LF_AUTO_REFRESH_'||to_char(v_start at time zone 'UTC','YYYYMMDDHH24MISSMS'),
    'INVENTORY_STAGED_REFRESH_V1','DATABASE_AND_REGISTRIES',
    v_start,clock_timestamp(),'COMPLETED',
    (select count(*) from inventory.objects where active),
    (select count(*) from inventory.dependencies where active),
    jsonb_build_object(
      'registries',v_reg,
      'search_index_objects',v_indexed,
      'pg_catalog_drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
      'external_repo_sync_included',false,
      'edge_runtime_sync_included',false
    )
  );

  return jsonb_build_object(
    'status','COMPLETED',
    'objects',(select count(*) from inventory.objects where active),
    'dependencies',(select count(*) from inventory.dependencies where active),
    'search_index_objects',v_indexed,
    'pg_catalog_drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000)
  );
end;
$$;

revoke all on function inventory.fn_refresh_search_index_v1() from public;
revoke all on function inventory.fn_retire_missing_pg_objects_v1() from public;
revoke all on function inventory.fn_refresh_catalog_v2() from public;
revoke all on function inventory.fn_refresh_db_details_v2() from public;
revoke all on function inventory.fn_refresh_dependencies_exact_v1() from public;
revoke all on function inventory.fn_refresh_static_incremental_v1() from public;
revoke all on function inventory.fn_refresh_registries_v1() from public;
revoke all on function inventory.fn_finalize_refresh_v1() from public;
