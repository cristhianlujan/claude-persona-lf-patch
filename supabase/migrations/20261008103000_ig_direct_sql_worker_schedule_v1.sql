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
