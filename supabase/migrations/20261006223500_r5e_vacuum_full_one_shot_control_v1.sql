-- R5-E VACUUM transport only. Installs disabled jobs.
-- Exact maintenance timestamp and role-level lock_timeout are bound by a later activation migration.

do $vac_preflight$
declare
  v_cron_version text;
begin
  select extversion into v_cron_version
  from pg_extension where extname='pg_cron';

  if v_cron_version is distinct from '1.6.4' then
    raise exception 'R5E_VACUUM_PG_CRON_VERSION_UNEXPECTED:%',coalesce(v_cron_version,'<NULL>');
  end if;

  if coalesce(current_setting('cron.use_background_workers',true),'')<>'off' then
    raise exception 'R5E_VACUUM_CRON_CONNECTION_MODE_CHANGED:%',
      coalesce(current_setting('cron.use_background_workers',true),'<NULL>');
  end if;

  if exists(
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='cron' and p.proname='schedule'
      and pg_get_function_arguments(p.oid) ilike '%timestamp%'
  ) then
    raise exception 'R5E_VACUUM_NATIVE_ONE_SHOT_SIGNATURE_APPEARED_REVIEW_REQUIRED';
  end if;

  if exists(select 1 from cron.job where jobname in (
    'lf-r5e-vacuum-full-once-v1',
    'lf-r5e-vacuum-finalizer-v1'
  )) then
    raise exception 'R5E_VACUUM_JOB_ALREADY_EXISTS';
  end if;

  if to_regclass('private.lf_r5e_vacuum_checkpoint_v1') is not null
     or to_regprocedure('private.fn_r5e_vacuum_finalize_v1()') is not null then
    raise exception 'R5E_VACUUM_CONTROL_ALREADY_EXISTS';
  end if;
end;
$vac_preflight$;

create table private.lf_r5e_vacuum_checkpoint_v1(
  control_id smallint primary key check(control_id=1),
  status text not null check(status in ('DISABLED','ARMED','RUNNING','VERIFIED','FAILED','MISSED')),
  scheduled_for timestamptz,
  vacuum_job_id bigint,
  finalizer_job_id bigint,
  pre_relation_bytes bigint,
  pre_heap_bytes bigint,
  pre_index_bytes bigint,
  pre_toast_bytes bigint,
  pre_database_bytes bigint,
  post_relation_bytes bigint,
  post_heap_bytes bigint,
  post_index_bytes bigint,
  post_toast_bytes bigint,
  post_database_bytes bigint,
  vacuum_run_id bigint,
  vacuum_run_status text,
  last_error text,
  armed_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);

insert into private.lf_r5e_vacuum_checkpoint_v1(control_id,status)
values(1,'DISABLED');

revoke all on private.lf_r5e_vacuum_checkpoint_v1 from public,anon,authenticated;
grant select,insert,update on private.lf_r5e_vacuum_checkpoint_v1 to postgres;

create or replace function private.fn_r5e_vacuum_finalize_v1()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','cron','programacion'
as $function$
declare
  v_cp private.lf_r5e_vacuum_checkpoint_v1%rowtype;
  v_run record;
  v_toast oid;
  v_cleanup_error text;
begin
  select * into v_cp
  from private.lf_r5e_vacuum_checkpoint_v1
  where control_id=1
  for update;

  if not found then
    raise exception 'R5E_VACUUM_CHECKPOINT_MISSING';
  end if;

  if v_cp.status='DISABLED' or v_cp.scheduled_for is null then
    return jsonb_build_object('status',v_cp.status,'code','R5E_VACUUM_NOT_ARMED');
  end if;

  if clock_timestamp()<v_cp.scheduled_for then
    return jsonb_build_object(
      'status',v_cp.status,
      'code','R5E_VACUUM_WAITING_FOR_WINDOW',
      'scheduled_for',v_cp.scheduled_for
    );
  end if;

  select d.runid,d.status,d.start_time,d.end_time,d.return_message
    into v_run
  from cron.job_run_details d
  where d.jobid=v_cp.vacuum_job_id
    and d.start_time>=v_cp.scheduled_for-interval '1 minute'
  order by d.runid desc
  limit 1;

  if not found then
    if clock_timestamp()<=v_cp.scheduled_for+interval '10 minutes' then
      return jsonb_build_object('status','ARMED','code','R5E_VACUUM_RUN_NOT_VISIBLE_YET');
    end if;

    update private.lf_r5e_vacuum_checkpoint_v1
    set status='MISSED',
        last_error='R5E_VACUUM_RUN_NOT_OBSERVED_WITHIN_10_MINUTES',
        completed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where control_id=1;
  elsif v_run.status in ('running','starting') or v_run.end_time is null then
    update private.lf_r5e_vacuum_checkpoint_v1
    set status='RUNNING',
        vacuum_run_id=v_run.runid,
        vacuum_run_status=v_run.status,
        updated_at=clock_timestamp()
    where control_id=1;

    return jsonb_build_object(
      'status','RUNNING',
      'vacuum_run_id',v_run.runid,
      'started_at',v_run.start_time
    );
  else
    select c.reltoastrelid into v_toast
    from pg_class c
    where c.oid='programacion.input_family_assessments'::regclass;

    update private.lf_r5e_vacuum_checkpoint_v1
    set status=case when v_run.status='succeeded' then 'VERIFIED' else 'FAILED' end,
        vacuum_run_id=v_run.runid,
        vacuum_run_status=v_run.status,
        last_error=case when v_run.status='succeeded' then null else v_run.return_message end,
        post_relation_bytes=pg_total_relation_size('programacion.input_family_assessments'::regclass),
        post_heap_bytes=pg_relation_size('programacion.input_family_assessments'::regclass),
        post_index_bytes=pg_indexes_size('programacion.input_family_assessments'::regclass),
        post_toast_bytes=case when v_toast=0 then 0 else pg_total_relation_size(v_toast) end,
        post_database_bytes=pg_database_size(current_database()),
        completed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where control_id=1;
  end if;

  begin
    execute 'alter role postgres reset lock_timeout';
  exception when others then
    get stacked diagnostics v_cleanup_error=message_text;
    update private.lf_r5e_vacuum_checkpoint_v1
    set last_error=concat_ws(' | ',last_error,'LOCK_TIMEOUT_RESET_FAILED:'||v_cleanup_error),
        updated_at=clock_timestamp()
    where control_id=1;
  end;

  begin
    perform cron.unschedule('lf-r5e-vacuum-full-once-v1');
  exception when others then
    get stacked diagnostics v_cleanup_error=message_text;
    if exists(select 1 from cron.job where jobname='lf-r5e-vacuum-full-once-v1') then
      perform cron.alter_job(
        (select jobid from cron.job where jobname='lf-r5e-vacuum-full-once-v1'),
        active=>false
      );
    end if;
    update private.lf_r5e_vacuum_checkpoint_v1
    set last_error=concat_ws(' | ',last_error,'VACUUM_JOB_CLEANUP:'||v_cleanup_error),
        updated_at=clock_timestamp()
    where control_id=1;
  end;

  begin
    perform cron.unschedule('lf-r5e-vacuum-finalizer-v1');
  exception when others then
    get stacked diagnostics v_cleanup_error=message_text;
    if exists(select 1 from cron.job where jobname='lf-r5e-vacuum-finalizer-v1') then
      perform cron.alter_job(
        (select jobid from cron.job where jobname='lf-r5e-vacuum-finalizer-v1'),
        active=>false
      );
    end if;
    update private.lf_r5e_vacuum_checkpoint_v1
    set last_error=concat_ws(' | ',last_error,'FINALIZER_JOB_CLEANUP:'||v_cleanup_error),
        updated_at=clock_timestamp()
    where control_id=1;
  end;

  select * into v_cp
  from private.lf_r5e_vacuum_checkpoint_v1
  where control_id=1;

  return jsonb_build_object(
    'status',v_cp.status,
    'vacuum_run_id',v_cp.vacuum_run_id,
    'vacuum_run_status',v_cp.vacuum_run_status,
    'pre_relation_bytes',v_cp.pre_relation_bytes,
    'post_relation_bytes',v_cp.post_relation_bytes,
    'pre_database_bytes',v_cp.pre_database_bytes,
    'post_database_bytes',v_cp.post_database_bytes,
    'last_error',v_cp.last_error
  );
end;
$function$;

revoke all on function private.fn_r5e_vacuum_finalize_v1()
  from public,anon,authenticated;
grant execute on function private.fn_r5e_vacuum_finalize_v1()
  to postgres;

-- Placeholder schedules are never active. A later versioned activation migration
-- binds the exact Cristhian-approved date/time.
select cron.schedule(
  'lf-r5e-vacuum-full-once-v1',
  '0 0 1 1 *',
  'VACUUM (FULL, ANALYZE) programacion.input_family_assessments'
);

select cron.schedule(
  'lf-r5e-vacuum-finalizer-v1',
  '* * * * *',
  'select private.fn_r5e_vacuum_finalize_v1();'
);

select cron.alter_job(
  (select jobid from cron.job where jobname='lf-r5e-vacuum-full-once-v1'),
  active=>false
);

select cron.alter_job(
  (select jobid from cron.job where jobname='lf-r5e-vacuum-finalizer-v1'),
  active=>false
);

update private.lf_r5e_vacuum_checkpoint_v1
set vacuum_job_id=(select jobid from cron.job where jobname='lf-r5e-vacuum-full-once-v1'),
    finalizer_job_id=(select jobid from cron.job where jobname='lf-r5e-vacuum-finalizer-v1'),
    updated_at=clock_timestamp()
where control_id=1;

do $vac_postcheck$
declare
  v_cp private.lf_r5e_vacuum_checkpoint_v1%rowtype;
begin
  select * into v_cp
  from private.lf_r5e_vacuum_checkpoint_v1 where control_id=1;

  if v_cp.status<>'DISABLED' or v_cp.scheduled_for is not null then
    raise exception 'R5E_VACUUM_CONTROL_MUST_INSTALL_DISABLED';
  end if;

  if exists(
    select 1 from cron.job
    where jobname in ('lf-r5e-vacuum-full-once-v1','lf-r5e-vacuum-finalizer-v1')
      and active
  ) then
    raise exception 'R5E_VACUUM_JOBS_MUST_INSTALL_INACTIVE';
  end if;

  if (select command from cron.job where jobname='lf-r5e-vacuum-full-once-v1')
       is distinct from 'VACUUM (FULL, ANALYZE) programacion.input_family_assessments' then
    raise exception 'R5E_VACUUM_COMMAND_DRIFT';
  end if;
end;
$vac_postcheck$;
