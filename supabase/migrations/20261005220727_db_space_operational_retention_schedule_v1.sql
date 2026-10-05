-- DB-SPACE PR-B1b pilot.
-- Schedule only: create lf-operational-retention-v1 at 08:43 UTC daily.
-- No retention execution occurs in this migration.
begin;

do $b1b$
declare
  v_before jsonb;
  v_after jsonb;
  v_jobid bigint;
begin
  if to_regprocedure('private.fn_operational_retention_v1(boolean,timestamp with time zone)') is null then
    raise exception 'BLOCK_B1B_RETENTION_FUNCTION_MISSING';
  end if;

  if exists (
    select 1 from cron.job where jobname='lf-operational-retention-v1'
  ) then
    raise exception 'BLOCK_B1B_TARGET_JOB_ALREADY_EXISTS';
  end if;

  select coalesce(jsonb_agg(to_jsonb(j) order by j.jobid),'[]'::jsonb)
    into v_before
  from cron.job j;

  v_jobid := cron.schedule(
    'lf-operational-retention-v1',
    '43 8 * * *',
    'select private.fn_operational_retention_v1(true);'
  );

  if not exists (
    select 1
    from cron.job
    where jobid=v_jobid
      and jobname='lf-operational-retention-v1'
      and schedule='43 8 * * *'
      and command='select private.fn_operational_retention_v1(true);'
      and database='postgres'
      and active is true
  ) then
    raise exception 'BLOCK_B1B_TARGET_JOB_READBACK_FAILED';
  end if;

  select coalesce(jsonb_agg(to_jsonb(j) order by j.jobid),'[]'::jsonb)
    into v_after
  from cron.job j
  where j.jobname <> 'lf-operational-retention-v1';

  if v_after is distinct from v_before then
    raise exception 'BLOCK_B1B_UNRELATED_CRON_JOB_CHANGED';
  end if;
end
$b1b$;

commit;
