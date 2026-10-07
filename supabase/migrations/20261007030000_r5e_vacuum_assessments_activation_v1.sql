-- Phase C: owner-approved VACUUM FULL for programacion.input_family_assessments only.
-- Train-only activation. No DELETE, DISABLE TRIGGER or standalone REINDEX.
-- Lock acquisition failures retry after 15 minutes, at most 4 retries after the initial attempt.

do $pre$
declare
  v_cp record;
  v_live bigint[];
  v_active_queries integer;
  v_new_rows bigint;
  v_new_validations bigint;
  v_job record;
  v_ctl record;
begin
  select enabled,status,baseline_eligible_count,compacted_count,last_error_sqlstate,last_error_message
    into v_cp
  from programacion.input_validator_compaction_checkpoint_v1
  where control_id=1;

  if not found
     or v_cp.enabled
     or v_cp.status<>'VERIFIED'
     or v_cp.baseline_eligible_count<>10131
     or v_cp.compacted_count<>10131
     or v_cp.last_error_sqlstate is not null
     or v_cp.last_error_message is not null then
    raise exception 'R5E_C_VACUUM_REQUIRES_VERIFIED_COMPACTION';
  end if;

  select coalesce(array_agg(id order by id),'{}'::bigint[])
    into v_live
  from programacion.input_readiness_runs
  where status in ('CURATING','VALIDATING');

  if v_live is distinct from array[22,309]::bigint[] then
    raise exception 'R5E_C_ACTIVE_IG_RUNS_CHANGED:%',v_live;
  end if;

  select count(*) into v_active_queries
  from pg_stat_activity
  where datname=current_database()
    and pid<>pg_backend_pid()
    and state<>'idle'
    and (
      query ilike '%input_family_assessments%'
      or query ilike '%input_readiness_runs%'
      or query ilike '%input_validator%'
    );

  if v_active_queries<>0 then
    raise exception 'R5E_C_ACTIVE_IG_QUERIES:%',v_active_queries;
  end if;

  select count(*) filter(where created_at>=timestamptz '2026-10-05 00:00:00-05'),
         count(*) filter(where validator_assessed_at>=timestamptz '2026-10-05 00:00:00-05')
    into v_new_rows,v_new_validations
  from programacion.input_family_assessments;

  if v_new_rows<>0 or v_new_validations<>0 then
    raise exception 'R5E_C_ASSESSMENT_BUSINESS_WRITES_CHANGED inserts=% validator_writes=%',
      v_new_rows,v_new_validations;
  end if;

  select jobid,active,command into v_job
  from cron.job
  where jobname='lf-r5e-vacuum-assessments-v1';

  if not found
     or v_job.active
     or v_job.command is distinct from
        'VACUUM (FULL, ANALYZE) programacion.input_family_assessments' then
    raise exception 'R5E_C_JOB30_NOT_CLEAN';
  end if;

  if exists(
    select 1 from cron.job
    where jobname in ('lf-r5e-vacuum-finalizer-v1','lf-r5e-vacuum-safety-reset-v1')
  ) then
    raise exception 'R5E_C_FINALIZER_OR_SAFETY_ALREADY_SCHEDULED';
  end if;

  select status,lock_timeout_clean into v_ctl
  from private.lf_r5e_vacuum_control_v1
  where control_id=1;

  if not found or v_ctl.status<>'VERIFIED'
     or not private.fn_r5e_postgres_lock_timeout_clean_v1() then
    raise exception 'R5E_C_VACUUM_CONTROL_NOT_CLEAN';
  end if;
end;
$pre$;

alter table private.lf_r5e_vacuum_table_receipts_v1
  add column if not exists retry_count integer not null default 0,
  add column if not exists max_retries integer not null default 4;

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
  v_next_at timestamptz;
  v_schedule text;
  v_is_lock_failure boolean;
  v_clean boolean;
begin
  select * into v_ctl
  from private.lf_r5e_vacuum_control_v1
  where control_id=1
  for update;

  if v_ctl.status in ('DISABLED','VERIFIED','FAILED') then
    return jsonb_build_object('status',v_ctl.status,'code','R5E_C_FINALIZER_NO_ACTION');
  end if;

  select * into v_target
  from private.lf_r5e_vacuum_table_receipts_v1
  where target_order=1
    and relation_name='programacion.input_family_assessments'
    and status in ('ARMED','RUNNING')
  for update;

  if not found then
    update private.lf_r5e_vacuum_control_v1
    set status='FAILED',
        last_error='R5E_C_TARGET_NOT_ARMED',
        updated_at=clock_timestamp()
    where control_id=1;
    execute 'alter role postgres reset lock_timeout';
    perform private.fn_r5e_vacuum_disable_jobs_v1();
    return jsonb_build_object('status','FAILED','code','R5E_C_TARGET_NOT_ARMED');
  end if;

  select d.runid,d.status,d.start_time,d.end_time,d.return_message
    into v_run
  from cron.job_run_details d
  where d.jobid=v_target.job_id
    and d.start_time>=v_target.armed_at
  order by d.runid desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'status',v_target.status,
      'code','R5E_C_TARGET_RUN_NOT_VISIBLE',
      'retry_count',v_target.retry_count
    );
  end if;

  if v_run.status in ('running','starting') or v_run.end_time is null then
    update private.lf_r5e_vacuum_table_receipts_v1
    set status='RUNNING',
        run_id=v_run.runid,
        run_status=v_run.status,
        run_started_at=v_run.start_time,
        updated_at=clock_timestamp()
    where target_order=1;

    update private.lf_r5e_vacuum_control_v1
    set status='RUNNING',updated_at=clock_timestamp()
    where control_id=1;

    return jsonb_build_object(
      'status','RUNNING','run_id',v_run.runid,'retry_count',v_target.retry_count
    );
  end if;

  if v_run.status='succeeded' then
    v_size:=private.fn_r5e_vacuum_capture_size_v1(
      'programacion.input_family_assessments'::regclass
    );

    update private.lf_r5e_vacuum_table_receipts_v1
    set status='VERIFIED',
        run_id=v_run.runid,
        run_status=v_run.status,
        run_started_at=v_run.start_time,
        run_ended_at=v_run.end_time,
        run_message=v_run.return_message,
        post_total_bytes=(v_size->>'total_bytes')::bigint,
        post_heap_bytes=(v_size->>'heap_bytes')::bigint,
        post_index_bytes=(v_size->>'index_bytes')::bigint,
        post_toast_aux_bytes=(v_size->>'toast_aux_bytes')::bigint,
        post_database_bytes=(v_size->>'database_bytes')::bigint,
        updated_at=clock_timestamp()
    where target_order=1;

    execute 'alter role postgres reset lock_timeout';
    v_clean:=private.fn_r5e_postgres_lock_timeout_clean_v1();

    update private.lf_r5e_vacuum_control_v1
    set status=case when v_clean then 'VERIFIED' else 'FAILED' end,
        last_error=case when v_clean then null else 'R5E_C_LOCK_TIMEOUT_RESET_READBACK_FAILED' end,
        lock_timeout_clean=v_clean,
        completed_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where control_id=1;

    perform private.fn_r5e_vacuum_disable_jobs_v1();

    return jsonb_build_object(
      'status',case when v_clean then 'VERIFIED' else 'FAILED' end,
      'run_id',v_run.runid,
      'retry_count',v_target.retry_count,
      'lock_timeout_clean',v_clean,
      'post_total_bytes',(v_size->>'total_bytes')::bigint,
      'post_database_bytes',(v_size->>'database_bytes')::bigint
    );
  end if;

  v_is_lock_failure:=
       lower(coalesce(v_run.return_message,'')) like '%lock timeout%'
    or lower(coalesce(v_run.return_message,'')) like '%could not obtain lock%'
    or lower(coalesce(v_run.return_message,'')) like '%lock not available%';

  if v_is_lock_failure and v_target.retry_count<v_target.max_retries then
    v_next_at:=date_trunc('minute',clock_timestamp())+interval '15 minutes';
    v_schedule:=format(
      '%s %s %s %s *',
      extract(minute from v_next_at)::int,
      extract(hour from v_next_at)::int,
      extract(day from v_next_at)::int,
      extract(month from v_next_at)::int
    );

    perform cron.alter_job(v_target.job_id,schedule=>v_schedule,active=>true);

    update private.lf_r5e_vacuum_table_receipts_v1
    set status='ARMED',
        retry_count=retry_count+1,
        armed_at=v_next_at,
        run_id=v_run.runid,
        run_status=v_run.status,
        run_started_at=v_run.start_time,
        run_ended_at=v_run.end_time,
        run_message=v_run.return_message,
        updated_at=clock_timestamp()
    where target_order=1
    returning * into v_target;

    update private.lf_r5e_vacuum_control_v1
    set status='ARMED',
        scheduled_for=v_next_at,
        last_error='R5E_C_LOCK_RETRY_'||v_target.retry_count||'_OF_'||v_target.max_retries,
        updated_at=clock_timestamp()
    where control_id=1;

    return jsonb_build_object(
      'status','RETRY_ARMED',
      'retry_count',v_target.retry_count,
      'max_retries',v_target.max_retries,
      'next_at',v_next_at,
      'message',v_run.return_message
    );
  end if;

  update private.lf_r5e_vacuum_table_receipts_v1
  set status='FAILED',
      run_id=v_run.runid,
      run_status=v_run.status,
      run_started_at=v_run.start_time,
      run_ended_at=v_run.end_time,
      run_message=v_run.return_message,
      updated_at=clock_timestamp()
  where target_order=1;

  execute 'alter role postgres reset lock_timeout';
  v_clean:=private.fn_r5e_postgres_lock_timeout_clean_v1();

  update private.lf_r5e_vacuum_control_v1
  set status='FAILED',
      last_error=case
        when v_is_lock_failure then
          'R5E_C_LOCK_RETRIES_EXHAUSTED retries='||v_target.retry_count||
          ' message='||coalesce(v_run.return_message,'<NULL>')
        else
          'R5E_C_VACUUM_FAILED:'||coalesce(v_run.return_message,'<NULL>')
      end,
      lock_timeout_clean=v_clean,
      completed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where control_id=1;

  perform private.fn_r5e_vacuum_disable_jobs_v1();

  return jsonb_build_object(
    'status','FAILED',
    'code',case when v_is_lock_failure then 'R5E_C_LOCK_RETRIES_EXHAUSTED'
                else 'R5E_C_VACUUM_FAILED' end,
    'retry_count',v_target.retry_count,
    'message',v_run.return_message,
    'lock_timeout_clean',v_clean
  );
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
  select * into v_ctl
  from private.lf_r5e_vacuum_control_v1
  where control_id=1
  for update;

  if v_ctl.status in ('DISABLED','VERIFIED','FAILED') then
    return jsonb_build_object('status',v_ctl.status,'code','R5E_C_SAFETY_NO_ACTION');
  end if;

  if v_ctl.safety_deadline is null or clock_timestamp()<v_ctl.safety_deadline then
    return jsonb_build_object(
      'status',v_ctl.status,'code','R5E_C_SAFETY_WAITING','deadline',v_ctl.safety_deadline
    );
  end if;

  execute 'alter role postgres reset lock_timeout';
  v_clean:=private.fn_r5e_postgres_lock_timeout_clean_v1();

  update private.lf_r5e_vacuum_table_receipts_v1
  set status='FAILED',
      run_message=coalesce(run_message,'')||' | R5E_C_SAFETY_DEADLINE',
      updated_at=clock_timestamp()
  where target_order=1 and status in ('ARMED','RUNNING');

  update private.lf_r5e_vacuum_control_v1
  set status='FAILED',
      last_error=case when v_clean
        then 'R5E_C_SAFETY_RESET_AT_90_MINUTES'
        else 'R5E_C_SAFETY_RESET_READBACK_FAILED'
      end,
      lock_timeout_clean=v_clean,
      completed_at=clock_timestamp(),
      updated_at=clock_timestamp()
  where control_id=1;

  perform private.fn_r5e_vacuum_disable_jobs_v1();

  return jsonb_build_object(
    'status','FAILED',
    'code','R5E_C_SAFETY_RESET_AT_90_MINUTES',
    'lock_timeout_clean',v_clean
  );
end;
$function$;

revoke all on function private.fn_r5e_vacuum_disable_jobs_v1() from public,anon,authenticated;
revoke all on function private.fn_r5e_vacuum_finalize_v1() from public,anon,authenticated;
revoke all on function private.fn_r5e_vacuum_safety_reset_v1() from public,anon,authenticated;
grant execute on function private.fn_r5e_vacuum_disable_jobs_v1() to postgres;
grant execute on function private.fn_r5e_vacuum_finalize_v1() to postgres;
grant execute on function private.fn_r5e_vacuum_safety_reset_v1() to postgres;

alter role postgres set lock_timeout='5s';

do $activate$
declare
  v_first_at timestamptz;
  v_schedule text;
  v_size jsonb;
  v_job30 bigint;
begin
  select jobid into strict v_job30
  from cron.job
  where jobname='lf-r5e-vacuum-assessments-v1';

  v_size:=private.fn_r5e_vacuum_capture_size_v1(
    'programacion.input_family_assessments'::regclass
  );

  v_first_at:=date_trunc('minute',clock_timestamp())+interval '1 minute';
  v_schedule:=format(
    '%s %s %s %s *',
    extract(minute from v_first_at)::int,
    extract(hour from v_first_at)::int,
    extract(day from v_first_at)::int,
    extract(month from v_first_at)::int
  );

  update private.lf_r5e_vacuum_table_receipts_v1
  set status='ARMED',
      armed_at=v_first_at,
      retry_count=0,
      max_retries=4,
      run_id=null,
      run_status=null,
      run_started_at=null,
      run_ended_at=null,
      run_message=null,
      pre_total_bytes=(v_size->>'total_bytes')::bigint,
      pre_heap_bytes=(v_size->>'heap_bytes')::bigint,
      pre_index_bytes=(v_size->>'index_bytes')::bigint,
      pre_toast_aux_bytes=(v_size->>'toast_aux_bytes')::bigint,
      pre_database_bytes=(v_size->>'database_bytes')::bigint,
      post_total_bytes=null,
      post_heap_bytes=null,
      post_index_bytes=null,
      post_toast_aux_bytes=null,
      post_database_bytes=null,
      updated_at=clock_timestamp()
  where target_order=1
    and relation_name='programacion.input_family_assessments'
    and job_id=v_job30;

  if not found then
    raise exception 'R5E_C_TARGET_RECEIPT_BINDING_MISSING';
  end if;

  update private.lf_r5e_vacuum_control_v1
  set status='ARMED',
      scheduled_for=v_first_at,
      safety_deadline=clock_timestamp()+interval '90 minutes',
      last_error=null,
      lock_timeout_clean=false,
      armed_at=clock_timestamp(),
      completed_at=null,
      updated_at=clock_timestamp()
  where control_id=1;

  perform cron.schedule(
    'lf-r5e-vacuum-finalizer-v1',
    '* * * * *',
    'select private.fn_r5e_vacuum_finalize_v1();'
  );

  perform cron.schedule(
    'lf-r5e-vacuum-safety-reset-v1',
    '* * * * *',
    'select private.fn_r5e_vacuum_safety_reset_v1();'
  );

  perform cron.alter_job(v_job30,schedule=>v_schedule,active=>true);
end;
$activate$;

do $post$
declare
  v_job30 record;
  v_finalizer record;
  v_safety record;
  v_receipt record;
begin
  select jobid,active,schedule into v_job30
  from cron.job where jobname='lf-r5e-vacuum-assessments-v1';

  select jobid,active into v_finalizer
  from cron.job where jobname='lf-r5e-vacuum-finalizer-v1';

  select jobid,active into v_safety
  from cron.job where jobname='lf-r5e-vacuum-safety-reset-v1';

  select status,retry_count,max_retries,pre_total_bytes,pre_database_bytes
    into v_receipt
  from private.lf_r5e_vacuum_table_receipts_v1
  where target_order=1;

  if v_job30.active is distinct from true
     or v_finalizer.active is distinct from true
     or v_safety.active is distinct from true
     or v_receipt.status<>'ARMED'
     or v_receipt.retry_count<>0
     or v_receipt.max_retries<>4
     or v_receipt.pre_total_bytes is null
     or v_receipt.pre_database_bytes is null then
    raise exception 'R5E_C_ACTIVATION_POSTCHECK_FAILED';
  end if;

  if private.fn_r5e_postgres_lock_timeout_clean_v1() then
    raise exception 'R5E_C_LOCK_TIMEOUT_NOT_ARMED';
  end if;
end;
$post$;
