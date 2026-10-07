-- Inventory-only R5-E VACUUM activation.
-- Owner explicitly excludes programacion.input_family_assessments / job 30.
-- No DELETE, DISABLE TRIGGER or REINDEX.

do $pre$
declare
  v_ctl private.lf_r5e_vacuum_control_v1%rowtype;
  v_count integer;
begin
  select * into v_ctl
  from private.lf_r5e_vacuum_control_v1
  where control_id=1
  for update;

  if not found or v_ctl.status<>'DISABLED' then
    raise exception 'R5E_INV_ACTIVATION_CONTROL_NOT_DISABLED:%',coalesce(v_ctl.status,'<MISSING>');
  end if;

  if not private.fn_r5e_postgres_lock_timeout_clean_v1() then
    raise exception 'R5E_INV_ACTIVATION_REQUIRES_CLEAN_LOCK_TIMEOUT';
  end if;

  select count(*) into v_count
  from cron.job
  where jobname in (
    'lf-r5e-vacuum-assessments-v1',
    'lf-r5e-vacuum-inventory-objects-v1',
    'lf-r5e-vacuum-inventory-search-index-v1',
    'lf-r5e-vacuum-finalizer-v1',
    'lf-r5e-vacuum-safety-reset-v1'
  );

  if v_count<>5 then
    raise exception 'R5E_INV_ACTIVATION_JOB_SET_INCOMPLETE:%',v_count;
  end if;

  if exists(
    select 1 from cron.job
    where jobname in (
      'lf-r5e-vacuum-assessments-v1',
      'lf-r5e-vacuum-inventory-objects-v1',
      'lf-r5e-vacuum-inventory-search-index-v1',
      'lf-r5e-vacuum-finalizer-v1',
      'lf-r5e-vacuum-safety-reset-v1'
    ) and active
  ) then
    raise exception 'R5E_INV_ACTIVATION_REQUIRES_ALL_JOBS_INACTIVE';
  end if;
end;
$pre$;

create or replace function private.fn_r5e_vacuum_disable_jobs_v1()
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','cron'
as $function$
declare
  v record;
  v_job30 bigint;
begin
  select jobid into v_job30
  from cron.job
  where jobname='lf-r5e-vacuum-assessments-v1';

  if v_job30 is not null then
    perform cron.alter_job(v_job30,active=>false);
  end if;

  for v in
    select jobid
    from cron.job
    where jobname in (
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
      select 1 from private.lf_r5e_vacuum_table_receipts_v1 where target_order in (2,3) and status<>'VERIFIED'
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
    while extract(minute from v_next_at)::int in (17,22,27,32,37) loop
      v_next_at:=v_next_at+interval '1 minute';
    end loop;
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



alter role postgres set lock_timeout='5s';

do $activate$
declare
  v_first_at timestamptz;
  v_schedule text;
  v_obj jsonb;
  v_search jsonb;
  v_job30 bigint;
  v_job31 bigint;
  v_job32 bigint;
  v_finalizer bigint;
  v_safety bigint;
begin
  select jobid into strict v_job30 from cron.job where jobname='lf-r5e-vacuum-assessments-v1';
  select jobid into strict v_job31 from cron.job where jobname='lf-r5e-vacuum-inventory-objects-v1';
  select jobid into strict v_job32 from cron.job where jobname='lf-r5e-vacuum-inventory-search-index-v1';
  select jobid into strict v_finalizer from cron.job where jobname='lf-r5e-vacuum-finalizer-v1';
  select jobid into strict v_safety from cron.job where jobname='lf-r5e-vacuum-safety-reset-v1';

  v_obj:=private.fn_r5e_vacuum_capture_size_v1('inventory.objects'::regclass);
  v_search:=private.fn_r5e_vacuum_capture_size_v1('inventory.search_index'::regclass);

  v_first_at:=date_trunc('minute',clock_timestamp())+interval '1 minute';
  while extract(minute from v_first_at)::int in (17,22,27,32,37) loop
    v_first_at:=v_first_at+interval '1 minute';
  end loop;

  v_schedule:=format(
    '%s %s %s %s *',
    extract(minute from v_first_at)::int,
    extract(hour from v_first_at)::int,
    extract(day from v_first_at)::int,
    extract(month from v_first_at)::int
  );

  update private.lf_r5e_vacuum_table_receipts_v1
  set status='DISABLED',
      armed_at=null,
      run_id=null,
      run_status='OWNER_EXCLUDED',
      run_started_at=null,
      run_ended_at=null,
      run_message='JOB30_EXCLUDED_BY_OWNER_NO_VACUUM',
      updated_at=clock_timestamp()
  where target_order=1 and job_id=v_job30;

  update private.lf_r5e_vacuum_table_receipts_v1
  set status='ARMED',
      armed_at=v_first_at,
      run_id=null,
      run_status=null,
      run_started_at=null,
      run_ended_at=null,
      run_message=null,
      pre_total_bytes=(v_obj->>'total_bytes')::bigint,
      pre_heap_bytes=(v_obj->>'heap_bytes')::bigint,
      pre_index_bytes=(v_obj->>'index_bytes')::bigint,
      pre_toast_aux_bytes=(v_obj->>'toast_aux_bytes')::bigint,
      pre_database_bytes=(v_obj->>'database_bytes')::bigint,
      post_total_bytes=null,
      post_heap_bytes=null,
      post_index_bytes=null,
      post_toast_aux_bytes=null,
      post_database_bytes=null,
      updated_at=clock_timestamp()
  where target_order=2 and job_id=v_job31;

  update private.lf_r5e_vacuum_table_receipts_v1
  set status='DISABLED',
      armed_at=null,
      run_id=null,
      run_status=null,
      run_started_at=null,
      run_ended_at=null,
      run_message=null,
      pre_total_bytes=(v_search->>'total_bytes')::bigint,
      pre_heap_bytes=(v_search->>'heap_bytes')::bigint,
      pre_index_bytes=(v_search->>'index_bytes')::bigint,
      pre_toast_aux_bytes=(v_search->>'toast_aux_bytes')::bigint,
      pre_database_bytes=(v_search->>'database_bytes')::bigint,
      post_total_bytes=null,
      post_heap_bytes=null,
      post_index_bytes=null,
      post_toast_aux_bytes=null,
      post_database_bytes=null,
      updated_at=clock_timestamp()
  where target_order=3 and job_id=v_job32;

  update private.lf_r5e_vacuum_control_v1
  set status='ARMED',
      scheduled_for=v_first_at,
      safety_deadline=clock_timestamp()+interval '30 minutes',
      last_error=null,
      lock_timeout_clean=false,
      armed_at=clock_timestamp(),
      completed_at=null,
      updated_at=clock_timestamp()
  where control_id=1;

  perform cron.alter_job(v_job30,active=>false);
  perform cron.alter_job(v_job31,schedule=>v_schedule,active=>true);
  perform cron.alter_job(v_job32,active=>false);
  perform cron.alter_job(v_finalizer,schedule=>'* * * * *',active=>true);
  perform cron.alter_job(v_safety,schedule=>'* * * * *',active=>true);
end;
$activate$;

do $post$
declare
  v_job30 boolean;
  v_job31 record;
  v_job32 boolean;
  v_finalizer boolean;
  v_safety boolean;
  v_timeout_ok boolean;
  v_bad integer;
begin
  select active into v_job30 from cron.job where jobname='lf-r5e-vacuum-assessments-v1';
  select active,schedule into v_job31 from cron.job where jobname='lf-r5e-vacuum-inventory-objects-v1';
  select active into v_job32 from cron.job where jobname='lf-r5e-vacuum-inventory-search-index-v1';
  select active into v_finalizer from cron.job where jobname='lf-r5e-vacuum-finalizer-v1';
  select active into v_safety from cron.job where jobname='lf-r5e-vacuum-safety-reset-v1';

  if v_job30 is distinct from false
     or v_job31.active is distinct from true
     or v_job32 is distinct from false
     or v_finalizer is distinct from true
     or v_safety is distinct from true then
    raise exception 'R5E_INV_ACTIVATION_JOB_STATE_FAILED';
  end if;

  if split_part(v_job31.schedule,' ',1)::int in (17,22,27,32,37) then
    raise exception 'R5E_INV_ACTIVATION_REFRESH_MINUTE_COLLISION:%',v_job31.schedule;
  end if;

  select exists(
    select 1
    from pg_db_role_setting s
    join pg_roles r on r.oid=s.setrole
    cross join lateral unnest(s.setconfig) cfg
    where r.rolname='postgres'
      and s.setdatabase=0
      and cfg='lock_timeout=5s'
  ) into v_timeout_ok;

  if not v_timeout_ok then
    raise exception 'R5E_INV_ACTIVATION_LOCK_TIMEOUT_NOT_PERSISTED';
  end if;

  select count(*) into v_bad
  from private.lf_r5e_vacuum_table_receipts_v1
  where (target_order=1 and (status<>'DISABLED' or run_status<>'OWNER_EXCLUDED'))
     or (target_order=2 and status<>'ARMED')
     or (target_order=3 and status<>'DISABLED');

  if v_bad<>0 then
    raise exception 'R5E_INV_ACTIVATION_RECEIPT_STATE_FAILED rows=%',v_bad;
  end if;
end;
$post$;
