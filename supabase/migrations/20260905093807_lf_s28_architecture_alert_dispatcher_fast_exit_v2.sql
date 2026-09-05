do $migration$
declare
  v_jobid bigint;
begin
  select j.jobid
    into v_jobid
  from cron.job j
  where j.jobname = 'lf-architecture-alert-delivery-v4'
    and j.schedule = '*/2 * * * *'
    and j.database = 'postgres'
    and j.active;

  if v_jobid is null then
    raise exception using
      errcode = 'P0002',
      message = 'S28 dispatcher fast-exit v2 precondition failed: expected active */2 cron job not found';
  end if;

  perform cron.alter_job(
    v_jobid,
    command => $cron$
select case
  when not exists (
    select 1
    from private.lf_architecture_delivery_config_v6
    where config_id = 1 and enabled
  ) then private.fn_dispatch_architecture_outbox_v4(
    'CRON-ALERT-V4-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISS'), 20
  )
  when not exists (
    select 1
    from private.lf_architecture_delivery_secrets_v4
    where is_active
      and not_before <= clock_timestamp()
      and (not_after is null or clock_timestamp() < not_after)
  ) then private.fn_dispatch_architecture_outbox_v4(
    'CRON-ALERT-V4-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISS'), 20
  )
  when exists (
    select 1
    from private.lf_architecture_notification_attempts_v4
    where completed_at is null
      and attempt_status in ('PENDING','SUBMITTED')
  ) then private.fn_dispatch_architecture_outbox_v4(
    'CRON-ALERT-V4-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISS'), 20
  )
  when (
    select count(*)
    from private.lf_architecture_notification_outbox_v4
    where channel = 'EXTERNAL_HTTP'
  ) <> (
    select count(distinct a.outbox_id)
    from private.lf_architecture_notification_attempts_v4 a
    join private.lf_architecture_notification_outbox_v4 o
      on o.id = a.outbox_id
     and o.channel = 'EXTERNAL_HTTP'
    where a.delivery_schema_version = 'lf-architecture-alert-delivery/v6'
      and a.attempt_status = 'DELIVERED'
  ) then private.fn_dispatch_architecture_outbox_v4(
    'CRON-ALERT-V4-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISS'), 20
  )
  else 0
end;
$cron$
  );
end
$migration$;
