-- DB-SPACE / PR-B1 verification.
-- Intended for a disposable/local database or a transaction that is always rolled back.
-- Do not run against the sandbox without owner approval.

begin;

create temp table _db_space_now as
select clock_timestamp() as observed_at;

create temp table _db_space_cron_readback_before as
select
  j.jobid,
  j.jobname,
  private.fn_latest_cron_status_v3(j.jobname) as status_doc
from cron.job j
order by j.jobid;

create temp table _db_space_cron_job_before as
select jobid,jobname,schedule,active,command
from cron.job
order by jobid;

create temp table _db_space_monitor_latest_before as
select id
from private.lf_architecture_monitor_runs_v4
order by completed_at desc nulls last,id desc
limit 1;

create temp table _db_space_closure_before as
select to_jsonb(v)-'computed_at' as closure_doc
from public.v_lf_architecture_closure_v4 v;

create temp table _db_space_queue_nonterminal_before as
select status,count(*)::bigint as rows
from private.lf_profile_runtime_queue_v1
where status in ('PENDING','BLOCKED','FAILED')
group by status;

create temp table _db_space_apply_results(seq int primary key,result jsonb);

insert into _db_space_apply_results
select 1,private.fn_operational_retention_v1(
  true,
  (select observed_at from _db_space_now)
);

insert into _db_space_apply_results
select 2,private.fn_operational_retention_v1(
  true,
  (select observed_at from _db_space_now)
);

do $test$
declare
  v_second jsonb;
begin
  select result into v_second
  from _db_space_apply_results
  where seq=2;

  if coalesce((v_second #>> '{deleted_rows,cron.job_run_details}')::bigint,-1) <> 0
     or coalesce((v_second #>> '{deleted_rows,private.lf_architecture_monitor_runs_v4}')::bigint,-1) <> 0
     or coalesce((v_second #>> '{deleted_rows,private.lf_architecture_notification_outbox_v4}')::bigint,-1) <> 0
     or coalesce((v_second #>> '{deleted_rows,private.lf_profile_runtime_queue_v1}')::bigint,-1) <> 0 then
    raise exception 'PR_B1_IDEMPOTENCE_FAILED';
  end if;

  if exists (
    select 1
    from _db_space_cron_readback_before b
    where private.fn_latest_cron_status_v3(b.jobname) is distinct from b.status_doc
  ) then
    raise exception 'PR_B1_LATEST_CRON_STATUS_CHANGED';
  end if;

  if exists (
    select 1
    from _db_space_monitor_latest_before b
    where not exists (
      select 1
      from private.lf_architecture_monitor_runs_v4 r
      where r.id=b.id
    )
  ) then
    raise exception 'PR_B1_LATEST_MONITOR_DELETED';
  end if;

  if exists (
    select 1
    from _db_space_closure_before b
    where (select to_jsonb(v)-'computed_at' from public.v_lf_architecture_closure_v4 v)
          is distinct from b.closure_doc
  ) then
    raise exception 'PR_B1_MONITOR_CLOSURE_CHANGED';
  end if;

  if exists (
    (select status,rows from _db_space_queue_nonterminal_before
     except
     select status,count(*)::bigint
     from private.lf_profile_runtime_queue_v1
     where status in ('PENDING','BLOCKED','FAILED')
     group by status)
    union all
    (select status,count(*)::bigint
     from private.lf_profile_runtime_queue_v1
     where status in ('PENDING','BLOCKED','FAILED')
     group by status
     except
     select status,rows from _db_space_queue_nonterminal_before)
  ) then
    raise exception 'PR_B1_NONTERMINAL_QUEUE_CHANGED';
  end if;

  if exists (
    (select * from _db_space_cron_job_before
     except
     select jobid,jobname,schedule,active,command from cron.job)
    union all
    (select jobid,jobname,schedule,active,command from cron.job
     except
     select * from _db_space_cron_job_before)
  ) then
    raise exception 'PR_B1_CRON_JOB_SCHEDULE_OR_ACTIVE_DRIFT';
  end if;
end;
$test$;

rollback;
