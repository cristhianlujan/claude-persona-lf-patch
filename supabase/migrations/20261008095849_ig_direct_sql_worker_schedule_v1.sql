-- LF_MIGRATION_RECONCILIATION_SOURCE_V1
-- reconciliation_mode=SOURCE_ONLY_NO_DDL_REPLAY
-- owner_binding_required=true
-- reconciliation_owner_operation_code=ACTUALIZACION_DB_LF
-- historical_origin_owner_status=UNAVAILABLE_PRE_OWNER_FIRST_CUTOVER
-- source_authority=supabase_migrations.schema_migrations
-- reconciliation_owner_execution_id=EXEC-DB-SOURCE-RECONCILE-BATCH1-20261013-001
-- source_version=20261008095849
-- source_name=ig_direct_sql_worker_schedule_v1
-- Activate one lightweight DB worker cadence only after the governed queue exists.
-- Each invocation chooses at most one queued IG request, processes bounded
-- SQL stages, and persists the continuation; idle tick performs no writes.
-- Does not invoke Edge or call any external paid service.
do $job$
begin
 if exists(select 1 from cron.job
           where jobname='ig-direct-sql-worker-v1' and active) then
   raise exception 'IG_DIRECT_CRON_ALREADY_ACTIVE';
 end if;
 perform cron.schedule(
   'ig-direct-sql-worker-v1',
   '* * * * *',
   'select programacion.fn_input_governance_queue_worker_v1();'
 );
end;
$job$;

do $guard$
begin
 if not exists(select 1 from cron.job
   where jobname='ig-direct-sql-worker-v1' and active
     and command='select programacion.fn_input_governance_queue_worker_v1();')
 then raise exception 'IG_DIRECT_CRON_NOT_ACTIVE'; end if;
end;
$guard$;

-- Rollback (if needed): select cron.unschedule('ig-direct-sql-worker-v1');
