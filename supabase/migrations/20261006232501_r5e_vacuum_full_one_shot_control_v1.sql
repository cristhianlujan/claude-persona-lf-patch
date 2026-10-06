-- R5-E VACUUM FULL transport v2.
-- INSTALLATION ONLY: all jobs are created inactive.
-- A later owner-approved activation migration arms the maintenance window.

do $pre$
declare
  v_cron text;
begin
  select extversion into v_cron from pg_extension where extname='pg_cron';
  if v_cron is distinct from '1.6.4' then
    raise exception 'R5E_VACUUM_PG_CRON_VERSION_UNEXPECTED:%',coalesce(v_cron,'<NULL>');
  end if;

  if coalesce(current_setting('cron.use_background_workers',true),'')<>'off' then
    raise exception 'R5E_VACUUM_CRON_MODE_CHANGED:%',
      coalesce(current_setting('cron.use_background_workers',true),'<NULL>');
  end if;

  if exists(select 1 from cron.job where jobname in (
    'lf-r5e-vacuum-assessments-v1',
    'lf-r5e-vacuum-inventory-objects-v1',
    'lf-r5e-vacuum-inventory-search-index-v1',
    'lf-r5e-vacuum-finalizer-v1',
    'lf-r5e-vacuum-safety-reset-v1'
  )) then
    raise exception 'R5E_VACUUM_JOB_ALREADY_EXISTS';
  end if;

  if to_regclass('private.lf_r5e_vacuum_control_v1') is not null
     or to_regclass('private.lf_r5e_vacuum_table_receipts_v1') is not null
     or to_regprocedure('private.fn_r5e_vacuum_finalize_v1()') is not null
     or to_regprocedure('private.fn_r5e_vacuum_safety_reset_v1()') is not null then
    raise exception 'R5E_VACUUM_CONTROL_ALREADY_EXISTS';
  end if;
end;
$pre$;

create table private.lf_r5e_vacuum_control_v1(
  control_id smallint primary key check(control_id=1),
  status text not null check(status in ('DISABLED','ARMED','RUNNING','VERIFIED','FAILED')),
  scheduled_for timestamptz,
  safety_deadline timestamptz,
  last_error text,
  lock_timeout_clean boolean,
  armed_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);

insert into private.lf_r5e_vacuum_control_v1(control_id,status,lock_timeout_clean)
values(1,'DISABLED',true);

create table private.lf_r5e_vacuum_table_receipts_v1(
  target_order smallint primary key check(target_order between 1 and 3),
  relation_name text not null unique,
  job_name text not null unique,
  job_id bigint,
  status text not null check(status in ('DISABLED','ARMED','RUNNING','VERIFIED','FAILED')),
  armed_at timestamptz,
  run_id bigint,
  run_status text,
  run_started_at timestamptz,
  run_ended_at timestamptz,
  run_message text,
  pre_total_bytes bigint,
  pre_heap_bytes bigint,
  pre_index_bytes bigint,
  pre_toast_aux_bytes bigint,
  pre_database_bytes bigint,
  post_total_bytes bigint,
  post_heap_bytes bigint,
  post_index_bytes bigint,
  post_toast_aux_bytes bigint,
  post_database_bytes bigint,
  updated_at timestamptz not null default clock_timestamp()
);

insert into private.lf_r5e_vacuum_table_receipts_v1(
  target_order,relation_name,job_name,status
) values
(1,'programacion.input_family_assessments','lf-r5e-vacuum-assessments-v1','DISABLED'),
(2,'inventory.objects','lf-r5e-vacuum-inventory-objects-v1','DISABLED'),
(3,'inventory.search_index','lf-r5e-vacuum-inventory-search-index-v1','DISABLED');

revoke all on private.lf_r5e_vacuum_control_v1 from public,anon,authenticated;
revoke all on private.lf_r5e_vacuum_table_receipts_v1 from public,anon,authenticated;
grant select,insert,update on private.lf_r5e_vacuum_control_v1 to postgres;
grant select,insert,update on private.lf_r5e_vacuum_table_receipts_v1 to postgres;

create or replace function private.fn_r5e_postgres_lock_timeout_clean_v1()
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select not exists (
    select 1
    from pg_db_role_setting s
    join pg_roles r on r.oid=s.setrole
    cross join lateral unnest(s.setconfig) cfg
    where r.rolname='postgres'
      and s.setdatabase=0
      and cfg like 'lock_timeout=%'
  );
$function$;

create or replace function private.fn_r5e_vacuum_capture_size_v1(p_relation regclass)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_toast oid;
begin
  select reltoastrelid into v_toast from pg_class where oid=p_relation;
  return jsonb_build_object(
    'total_bytes',pg_total_relation_size(p_relation),
    'heap_bytes',pg_relation_size(p_relation),
    'index_bytes',pg_indexes_size(p_relation),
    'toast_aux_bytes',case when coalesce(v_toast,0)=0 then 0 else pg_total_relation_size(v_toast) end,
    'database_bytes',pg_database_size(current_database())
  );
end;
$function$;

create or replace function private.fn_r5e_vacuum_disable_jobs_v1()
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','cron'
as $function$
declare
  v record;
begin
  for v in
    select jobid
    from cron.job
    where jobname in (
      'lf-r5e-vacuum-assessments-v1',
      'lf-r5e-vacuum-inventory-objects-v1',
      'lf-r5e-vacuum-inventory-search-index-v1',
      'lf-r5e-vacuum-finalizer-v1',
      'lf-r5e-vacuum-safety-reset-v1'
    )
  loop
    perform cron.alter_job(v.jobid,active=>false);
    perform cron.unschedule(v.jobid);
  end loop;
end;
$function$;

create or replace function private.fn_r5e_vacuum_finalize_v1()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','cron'
as $function$
declare
  v_ctl private.lf_r5e_vacuum_control_v1%rowtype;
  v_target private.lf_r5e_vacuum_table_receipts_v1%rowtype;
  v_run record;
  v_size jsonb;
  v_next private.lf_r5e_vacuum_table_receipts_v1%rowtype;
  v_next_at timestamptz;
  v_schedule text;
begin
  select * into v_ctl from private.lf_r5e_vacuum_control_v1
  where control_id=1 for update;

  if v_ctl.status='DISABLED' then
    return jsonb_build_object('status','DISABLED');
  end if;

  select * into v_target
  from private.lf_r5e_vacuum_table_receipts_v1
  where status in ('ARMED','RUNNING')
  order by target_order
  limit 1
  for update;

  if not found then
    if not exists(
      select 1 from private.lf_r5e_vacuum_table_receipts_v1 where status<>'VERIFIED'
    ) then
      execute 'alter role postgres reset lock_timeout';

      if not private.fn_r5e_postgres_lock_timeout_clean_v1() then
        update private.lf_r5e_vacuum_control_v1
        set status='FAILED',
            last_error='R5E_LOCK_TIMEOUT_RESET_READBACK_FAILED',
            lock_timeout_clean=false,
            completed_at=clock_timestamp(),
            updated_at=clock_timestamp()
        where control_id=1;
        perform private.fn_r5e_vacuum_disable_jobs_v1();
        return jsonb_build_object('status','FAILED','code','R5E_LOCK_TIMEOUT_RESET_READBACK_FAILED');
      end if;

      update private.lf_r5e_vacuum_control_v1
      set status='VERIFIED',
          lock_timeout_clean=true,
          completed_at=clock_timestamp(),
          updated_at=clock_timestamp()
      where control_id=1;

      perform private.fn_r5e_vacuum_disable_jobs_v1();
      return jsonb_build_object('status','VERIFIED','lock_timeout_clean',true);
    end if;

    return jsonb_build_object('status',v_ctl.status,'code','R5E_NO_ARMED_TARGET');
  end if;

  select d.runid,d.status,d.start_time,d.end_time,d.return_message
    into v_run
  from cron.job_run_details d
  where d.jobid=v_target.job_id
    and d.start_time>=coalesce(v_target.armed_at,v_ctl.armed_at)
  order by d.runid desc
  limit 1;

  if not found then
    return jsonb_build_object('status',v_target.status,'code','R5E_TARGET_RUN_NOT_VISIBLE');
  end if;

  if v_run.status in ('running','starting') or v_run.end_time is null then
    update private.lf_r5e_vacuum_table_receipts_v1
    set status='RUNNING',run_id=v_run.runid,run_status=v_run.status,
        run_started_at=v_run.start_time,updated_at=clock_timestamp()
    where target_order=v_target.target_order;

    update private.lf_r5e_vacuum_control_v1
    set status='RUNNING',updated_at=clock_timestamp()
    where control_id=1;

    return jsonb_build_object(
      'status','RUNNING','relation',v_target.relation_name,'run_id',v_run.runid
    );
  end if;

  v_size:=private.fn_r5e_vacuum_capture_size_v1(v_target.relation_name::regclass);

  update private.lf_r5e_vacuum_table_receipts_v1
  set status=case when v_run.status='succeeded' then 'VERIFIED' else 'FAILED' end,
      run_id=v_run.runid,run_status=v_run.status,
      run_started_at=v_run.start_time,run_ended_at=v_run.end_time,
      run_message=v_run.return_message,
      post_total_bytes=(v_size->>'total_bytes')::bigint,
      post_heap_bytes=(v_size->>'heap_bytes')::bigint,
      post_index_bytes=(v_size->>'index_bytes')::bigint,
      post_toast_aux_bytes=(v_size->>'toast_aux_bytes')::bigint,
      post_database_bytes=(v_size->>'database_bytes')::bigint,
      updated_at=clock_timestamp()
  where target_order=v_target.target_order;

  perform cron.alter_job(v_target.job_id,active=>false);

  if v_run.status<>'succeeded' then
    execute 'alter role postgres reset lock_timeout';

    update private.lf_r5e_vacuum_control_v1
    set status='FAILED',
        last_error='R5E_VACUUM_FAILED:'||v_target.relation_name||':'||coalesce(v_run.return_message,'<NULL>'),
        lock_timeout_clean=private.fn_r5e_postgres_lock_timeout_clean_v1(),
        completed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where control_id=1;

    perform private.fn_r5e_vacuum_disable_jobs_v1();

    return jsonb_build_object(
      'status','FAILED','relation',v_target.relation_name,
      'run_status',v_run.status,'message',v_run.return_message,
      'lock_timeout_clean',private.fn_r5e_postgres_lock_timeout_clean_v1()
    );
  end if;

  select * into v_next
  from private.lf_r5e_vacuum_table_receipts_v1
  where target_order=v_target.target_order+1
  for update;

  if found then
    v_next_at:=date_trunc('minute',clock_timestamp())+interval '1 minute';
    v_schedule:=format(
      '%s %s %s %s *',
      extract(minute from v_next_at)::int,
      extract(hour from v_next_at)::int,
      extract(day from v_next_at)::int,
      extract(month from v_next_at)::int
    );

    perform cron.alter_job(v_next.job_id,schedule=>v_schedule,active=>true);

    update private.lf_r5e_vacuum_table_receipts_v1
    set status='ARMED',armed_at=v_next_at,updated_at=clock_timestamp()
    where target_order=v_next.target_order;

    return jsonb_build_object(
      'status','NEXT_ARMED',
      'completed_relation',v_target.relation_name,
      'next_relation',v_next.relation_name,
      'next_at',v_next_at
    );
  end if;

  -- Last target succeeded. The next finalizer tick closes the control and
  -- verifies that the role-level setting was fully reset.
  return jsonb_build_object('status','TARGETS_COMPLETE_PENDING_FINAL_READBACK');
end;
$function$;

create or replace function private.fn_r5e_vacuum_safety_reset_v1()
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','private','cron'
as $function$
declare
  v_ctl private.lf_r5e_vacuum_control_v1%rowtype;
  v_clean boolean;
begin
  select * into v_ctl from private.lf_r5e_vacuum_control_v1
  where control_id=1 for update;

  if v_ctl.status in ('DISABLED','VERIFIED','FAILED') then
    return jsonb_build_object('status',v_ctl.status,'code','R5E_SAFETY_NO_ACTION');
  end if;

  if v_ctl.safety_deadline is null or clock_timestamp()<v_ctl.safety_deadline then
    return jsonb_build_object(
      'status',v_ctl.status,'code','R5E_SAFETY_WAITING',
      'deadline',v_ctl.safety_deadline
    );
  end if;

  execute 'alter role postgres reset lock_timeout';
  v_clean:=private.fn_r5e_postgres_lock_timeout_clean_v1();

  perform private.fn_r5e_vacuum_disable_jobs_v1();

  update private.lf_r5e_vacuum_control_v1
  set status='FAILED',
      last_error=case
        when v_clean then 'R5E_SAFETY_RESET_AT_30_MINUTES'
        else 'R5E_SAFETY_RESET_READBACK_FAILED'
      end,
      lock_timeout_clean=v_clean,
      completed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where control_id=1;

  return jsonb_build_object(
    'status','FAILED','code','R5E_SAFETY_RESET_AT_30_MINUTES',
    'lock_timeout_clean',v_clean
  );
end;
$function$;

revoke all on function private.fn_r5e_postgres_lock_timeout_clean_v1() from public,anon,authenticated;
revoke all on function private.fn_r5e_vacuum_capture_size_v1(regclass) from public,anon,authenticated;
revoke all on function private.fn_r5e_vacuum_disable_jobs_v1() from public,anon,authenticated;
revoke all on function private.fn_r5e_vacuum_finalize_v1() from public,anon,authenticated;
revoke all on function private.fn_r5e_vacuum_safety_reset_v1() from public,anon,authenticated;

grant execute on function private.fn_r5e_postgres_lock_timeout_clean_v1() to postgres;
grant execute on function private.fn_r5e_vacuum_capture_size_v1(regclass) to postgres;
grant execute on function private.fn_r5e_vacuum_disable_jobs_v1() to postgres;
grant execute on function private.fn_r5e_vacuum_finalize_v1() to postgres;
grant execute on function private.fn_r5e_vacuum_safety_reset_v1() to postgres;

-- Each VACUUM is one top-level statement. Placeholder schedules are inactive.
select cron.schedule(
  'lf-r5e-vacuum-assessments-v1','0 0 1 1 *',
  'VACUUM (FULL, ANALYZE) programacion.input_family_assessments'
);
select cron.schedule(
  'lf-r5e-vacuum-inventory-objects-v1','0 0 1 1 *',
  'VACUUM (FULL, ANALYZE) inventory.objects'
);
select cron.schedule(
  'lf-r5e-vacuum-inventory-search-index-v1','0 0 1 1 *',
  'VACUUM (FULL, ANALYZE) inventory.search_index'
);
select cron.schedule(
  'lf-r5e-vacuum-finalizer-v1','* * * * *',
  'select private.fn_r5e_vacuum_finalize_v1();'
);
select cron.schedule(
  'lf-r5e-vacuum-safety-reset-v1','* * * * *',
  'select private.fn_r5e_vacuum_safety_reset_v1();'
);

update private.lf_r5e_vacuum_table_receipts_v1 r
set job_id=j.jobid,updated_at=clock_timestamp()
from cron.job j
where j.jobname=r.job_name;

select cron.alter_job(jobid,active=>false)
from cron.job
where jobname in (
  'lf-r5e-vacuum-assessments-v1',
  'lf-r5e-vacuum-inventory-objects-v1',
  'lf-r5e-vacuum-inventory-search-index-v1',
  'lf-r5e-vacuum-finalizer-v1',
  'lf-r5e-vacuum-safety-reset-v1'
);

do $post$
begin
  if exists(
    select 1 from cron.job
    where jobname in (
      'lf-r5e-vacuum-assessments-v1',
      'lf-r5e-vacuum-inventory-objects-v1',
      'lf-r5e-vacuum-inventory-search-index-v1',
      'lf-r5e-vacuum-finalizer-v1',
      'lf-r5e-vacuum-safety-reset-v1'
    )
    and active
  ) then
    raise exception 'R5E_VACUUM_JOBS_MUST_INSTALL_INACTIVE';
  end if;

  if (select count(*) from private.lf_r5e_vacuum_table_receipts_v1 where job_id is not null)<>3 then
    raise exception 'R5E_VACUUM_TARGET_JOB_BINDING_INCOMPLETE';
  end if;

  if not private.fn_r5e_postgres_lock_timeout_clean_v1() then
    raise exception 'R5E_VACUUM_INSTALL_REQUIRES_CLEAN_POSTGRES_LOCK_TIMEOUT';
  end if;
end;
$post$;
