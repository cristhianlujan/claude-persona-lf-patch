-- DB-SPACE / PR-B1b — schedule operational retention only.
-- Owner-approved pilot for the migration merge train.
-- Preconditions:
--   * private.fn_operational_retention_v1(boolean,timestamptz) exists.
--   * no lf-operational-retention-v1 cron job exists yet.
-- Safety:
--   * snapshot every pre-existing cron.job row;
--   * create exactly one new job;
--   * fail if any pre-existing job changed schedule/active/command.

create temporary table _lf_b1b_cron_before
on commit drop
as
select jobid,jobname,schedule,active,command
from cron.job;

do $b1b$
declare
  v_jobid bigint;
  v_before_count bigint;
  v_after_count bigint;
begin
  if to_regprocedure('private.fn_operational_retention_v1(boolean,timestamptz)') is null then
    raise exception 'BLOCK_B1B_RETENTION_FUNCTION_MISSING';
  end if;

  if exists (
    select 1 from cron.job where jobname='lf-operational-retention-v1'
  ) then
    raise exception 'BLOCK_B1B_RETENTION_JOB_ALREADY_EXISTS';
  end if;

  select count(*) into v_before_count from _lf_b1b_cron_before;

  select cron.schedule(
    'lf-operational-retention-v1',
    '43 8 * * *',
    $cron$select private.fn_operational_retention_v1(true);$cron$
  ) into v_jobid;

  if v_jobid is null then
    raise exception 'BLOCK_B1B_CRON_SCHEDULE_NO_JOBID';
  end if;

  if not exists (
    select 1
    from cron.job
    where jobid=v_jobid
      and jobname='lf-operational-retention-v1'
      and schedule='43 8 * * *'
      and active is true
      and command='select private.fn_operational_retention_v1(true);'
  ) then
    raise exception 'BLOCK_B1B_RETENTION_JOB_READBACK_MISMATCH';
  end if;

  if exists (
    select 1
    from _lf_b1b_cron_before b
    left join cron.job j using(jobid)
    where j.jobid is null
       or j.jobname is distinct from b.jobname
       or j.schedule is distinct from b.schedule
       or j.active is distinct from b.active
       or j.command is distinct from b.command
  ) then
    raise exception 'BLOCK_B1B_EXISTING_CRON_DRIFT';
  end if;

  select count(*) into v_after_count from cron.job;
  if v_after_count <> v_before_count + 1 then
    raise exception 'BLOCK_B1B_CRON_COUNT_DELTA expected=% observed=%',v_before_count+1,v_after_count;
  end if;
end
$b1b$;
