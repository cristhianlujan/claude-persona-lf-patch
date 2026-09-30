-- Preserve static-analysis state across pg_catalog detail refreshes.
-- The previous upsert replaced inventory.functions.metadata wholesale, deleting
-- static_analysis_sha256 and forcing all functions to be reanalyzed every cycle.

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
    definition_sha256=excluded.definition_sha256,definition_bytes=excluded.definition_bytes,metadata=inventory.functions.metadata || excluded.metadata,updated_at=now();

  perform inventory.fn_retire_missing_pg_objects_v1();

  return jsonb_build_object('status','COMPLETED',
    'drift',(select count(*) from inventory.v_pg_catalog_drift_v1),
    'duration_ms',round(extract(epoch from clock_timestamp()-v_start)*1000));
end;
$$;
