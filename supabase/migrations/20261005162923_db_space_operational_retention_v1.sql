-- DB-SPACE / PR-B1 — OPERATIONAL RETENTION v1
-- Prepared only. This migration must not be applied without owner approval.
-- Policy:
--   cron.job_run_details: keep 30d OR latest run per job
--   lf_architecture_monitor_runs_v4: keep 30d OR latest absolute run
--   lf_architecture_notification_outbox_v4: PG_NOTIFY only, older than 30d
--   lf_profile_runtime_queue_v1: SUCCEEDED older than 30d and no canonical EXEC-PROFILE-RUNTIME-<request_id>
-- Fail closed if any attempt/receipt references a PG_NOTIFY outbox row.

create or replace function private.fn_operational_retention_estimate_mb_v1(
  p_rel regclass,
  p_candidate_rows bigint,
  p_candidate_logical_bytes bigint,
  p_total_rows bigint,
  p_total_logical_bytes bigint
) returns numeric
language sql
stable
set search_path = pg_catalog
as $function$
  select round(
    (
      (
        (pg_total_relation_size(p_rel) - pg_indexes_size(p_rel))::numeric
        * case
            when coalesce(p_total_logical_bytes,0) > 0
              then p_candidate_logical_bytes::numeric / p_total_logical_bytes
            else 0
          end
      )
      +
      (
        pg_indexes_size(p_rel)::numeric
        * case
            when coalesce(p_total_rows,0) > 0
              then p_candidate_rows::numeric / p_total_rows
            else 0
          end
      )
    ) / 1048576.0,
    2
  );
$function$;

create or replace function private.fn_operational_retention_snapshot_v1(
  p_now timestamptz default clock_timestamp()
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, cron
as $function$
declare
  v_cron_total bigint;
  v_cron_total_bytes bigint;
  v_cron_candidates bigint;
  v_cron_candidate_bytes bigint;

  v_monitor_total bigint;
  v_monitor_total_bytes bigint;
  v_monitor_candidates bigint;
  v_monitor_candidate_bytes bigint;

  v_notify_total bigint;
  v_notify_total_bytes bigint;
  v_notify_candidates bigint;
  v_notify_candidate_bytes bigint;

  v_profile_total bigint;
  v_profile_total_bytes bigint;
  v_profile_candidates bigint;
  v_profile_candidate_bytes bigint;

  v_pg_notify_attempt_refs bigint;
  v_pg_notify_receipt_refs bigint;
begin
  with latest as (
    select distinct on (jobid) jobid, runid
    from cron.job_run_details
    order by jobid, runid desc
  ), rows_with_policy as (
    select d.*,
      (
        d.start_time < p_now - interval '30 days'
        and d.runid is distinct from l.runid
      ) as candidate
    from cron.job_run_details d
    left join latest l using (jobid)
  )
  select
    count(*),
    coalesce(sum(pg_column_size(x)),0),
    count(*) filter (where candidate),
    coalesce(sum(pg_column_size(x)) filter (where candidate),0)
  into
    v_cron_total,
    v_cron_total_bytes,
    v_cron_candidates,
    v_cron_candidate_bytes
  from rows_with_policy x;

  with latest as (
    select id
    from private.lf_architecture_monitor_runs_v4
    order by completed_at desc nulls last, id desc
    limit 1
  ), rows_with_policy as (
    select r.*,
      (
        r.started_at < p_now - interval '30 days'
        and r.id is distinct from (select id from latest)
      ) as candidate
    from private.lf_architecture_monitor_runs_v4 r
  )
  select
    count(*),
    coalesce(sum(pg_column_size(x)),0),
    count(*) filter (where candidate),
    coalesce(sum(pg_column_size(x)) filter (where candidate),0)
  into
    v_monitor_total,
    v_monitor_total_bytes,
    v_monitor_candidates,
    v_monitor_candidate_bytes
  from rows_with_policy x;

  with rows_with_policy as (
    select o.*,
      (
        o.channel = 'PG_NOTIFY'
        and o.created_at < p_now - interval '30 days'
      ) as candidate
    from private.lf_architecture_notification_outbox_v4 o
  )
  select
    count(*),
    coalesce(sum(pg_column_size(x)),0),
    count(*) filter (where candidate),
    coalesce(sum(pg_column_size(x)) filter (where candidate),0)
  into
    v_notify_total,
    v_notify_total_bytes,
    v_notify_candidates,
    v_notify_candidate_bytes
  from rows_with_policy x;

  with rows_with_policy as (
    select q.*,
      (
        q.status = 'SUCCEEDED'
        and q.created_at < p_now - interval '30 days'
        and not exists (
          select 1
          from public.lf_operation_execution e
          where e.execution_id = 'EXEC-PROFILE-RUNTIME-' || q.request_id::text
        )
      ) as candidate
    from private.lf_profile_runtime_queue_v1 q
  )
  select
    count(*),
    coalesce(sum(pg_column_size(x)),0),
    count(*) filter (where candidate),
    coalesce(sum(pg_column_size(x)) filter (where candidate),0)
  into
    v_profile_total,
    v_profile_total_bytes,
    v_profile_candidates,
    v_profile_candidate_bytes
  from rows_with_policy x;

  select
    count(distinct a.id),
    count(distinct r.id)
  into
    v_pg_notify_attempt_refs,
    v_pg_notify_receipt_refs
  from private.lf_architecture_notification_outbox_v4 o
  left join private.lf_architecture_notification_attempts_v4 a
    on a.outbox_id = o.id
  left join private.lf_architecture_notification_receipts_v4 r
    on r.outbox_id = o.id
  where o.channel = 'PG_NOTIFY';

  return jsonb_build_object(
    'mode','DRY_RUN',
    'observed_at',p_now,
    'retention_days',30,
    'pg_notify_preflight',jsonb_build_object(
      'attempt_refs',v_pg_notify_attempt_refs,
      'receipt_refs',v_pg_notify_receipt_refs,
      'safe',v_pg_notify_attempt_refs = 0 and v_pg_notify_receipt_refs = 0
    ),
    'tables',jsonb_build_object(
      'cron.job_run_details',jsonb_build_object(
        'candidate_rows',v_cron_candidates,
        'candidate_logical_bytes',v_cron_candidate_bytes,
        'estimated_reclaim_mb',private.fn_operational_retention_estimate_mb_v1(
          'cron.job_run_details'::regclass,
          v_cron_candidates,v_cron_candidate_bytes,
          v_cron_total,v_cron_total_bytes
        )
      ),
      'private.lf_architecture_monitor_runs_v4',jsonb_build_object(
        'candidate_rows',v_monitor_candidates,
        'candidate_logical_bytes',v_monitor_candidate_bytes,
        'estimated_reclaim_mb',private.fn_operational_retention_estimate_mb_v1(
          'private.lf_architecture_monitor_runs_v4'::regclass,
          v_monitor_candidates,v_monitor_candidate_bytes,
          v_monitor_total,v_monitor_total_bytes
        )
      ),
      'private.lf_architecture_notification_outbox_v4',jsonb_build_object(
        'candidate_rows',v_notify_candidates,
        'candidate_logical_bytes',v_notify_candidate_bytes,
        'estimated_reclaim_mb',private.fn_operational_retention_estimate_mb_v1(
          'private.lf_architecture_notification_outbox_v4'::regclass,
          v_notify_candidates,v_notify_candidate_bytes,
          v_notify_total,v_notify_total_bytes
        )
      ),
      'private.lf_profile_runtime_queue_v1',jsonb_build_object(
        'candidate_rows',v_profile_candidates,
        'candidate_logical_bytes',v_profile_candidate_bytes,
        'estimated_reclaim_mb',private.fn_operational_retention_estimate_mb_v1(
          'private.lf_profile_runtime_queue_v1'::regclass,
          v_profile_candidates,v_profile_candidate_bytes,
          v_profile_total,v_profile_total_bytes
        )
      )
    )
  );
end;
$function$;

create or replace function private.fn_operational_retention_v1(
  p_apply boolean default false,
  p_now timestamptz default clock_timestamp()
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, cron
as $function$
declare
  v_before jsonb;
  v_after jsonb;
  v_cron_deleted bigint := 0;
  v_monitor_deleted bigint := 0;
  v_notify_deleted bigint := 0;
  v_profile_deleted bigint := 0;
begin
  v_before := private.fn_operational_retention_snapshot_v1(p_now);

  if coalesce((v_before #>> '{pg_notify_preflight,attempt_refs}')::bigint,0) <> 0
     or coalesce((v_before #>> '{pg_notify_preflight,receipt_refs}')::bigint,0) <> 0 then
    raise exception using
      errcode = '23503',
      message = 'OPERATIONAL_RETENTION_PG_NOTIFY_REFERENCED';
  end if;

  if not p_apply then
    return v_before;
  end if;

  with latest as (
    select distinct on (jobid) jobid, runid
    from cron.job_run_details
    order by jobid, runid desc
  ), candidates as (
    select d.runid
    from cron.job_run_details d
    left join latest l using (jobid)
    where d.start_time < p_now - interval '30 days'
      and d.runid is distinct from l.runid
  )
  delete from cron.job_run_details d
  using candidates c
  where d.runid = c.runid;
  get diagnostics v_cron_deleted = row_count;

  with latest as (
    select id
    from private.lf_architecture_monitor_runs_v4
    order by completed_at desc nulls last, id desc
    limit 1
  ), candidates as (
    select r.id
    from private.lf_architecture_monitor_runs_v4 r
    where r.started_at < p_now - interval '30 days'
      and r.id is distinct from (select id from latest)
  )
  delete from private.lf_architecture_monitor_runs_v4 r
  using candidates c
  where r.id = c.id;
  get diagnostics v_monitor_deleted = row_count;

  delete from private.lf_architecture_notification_outbox_v4 o
  where o.channel = 'PG_NOTIFY'
    and o.created_at < p_now - interval '30 days';
  get diagnostics v_notify_deleted = row_count;

  delete from private.lf_profile_runtime_queue_v1 q
  where q.status = 'SUCCEEDED'
    and q.created_at < p_now - interval '30 days'
    and not exists (
      select 1
      from public.lf_operation_execution e
      where e.execution_id = 'EXEC-PROFILE-RUNTIME-' || q.request_id::text
    );
  get diagnostics v_profile_deleted = row_count;

  v_after := private.fn_operational_retention_snapshot_v1(p_now);

  return jsonb_build_object(
    'mode','APPLY',
    'observed_at',p_now,
    'before',v_before,
    'deleted_rows',jsonb_build_object(
      'cron.job_run_details',v_cron_deleted,
      'private.lf_architecture_monitor_runs_v4',v_monitor_deleted,
      'private.lf_architecture_notification_outbox_v4',v_notify_deleted,
      'private.lf_profile_runtime_queue_v1',v_profile_deleted
    ),
    'after',v_after
  );
end;
$function$;

revoke all on function private.fn_operational_retention_estimate_mb_v1(regclass,bigint,bigint,bigint,bigint)
  from public, anon, authenticated;
revoke all on function private.fn_operational_retention_snapshot_v1(timestamptz)
  from public, anon, authenticated;
revoke all on function private.fn_operational_retention_v1(boolean,timestamptz)
  from public, anon, authenticated;

grant execute on function private.fn_operational_retention_snapshot_v1(timestamptz) to service_role;
grant execute on function private.fn_operational_retention_v1(boolean,timestamptz) to service_role;

comment on function private.fn_operational_retention_v1(boolean,timestamptz) is
'DB-SPACE operational retention v1. Deletes only bounded operational history; fails closed if PG_NOTIFY outbox rows are referenced by attempts or receipts.';

do $job$
declare
  v_jobid bigint;
  v_jobs_before jsonb;
  v_jobs_after jsonb;
begin
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'jobid',jobid,
        'jobname',jobname,
        'schedule',schedule,
        'active',active,
        'command',command
      )
      order by jobid
    ),
    '[]'::jsonb
  )
  into v_jobs_before
  from cron.job
  where jobname <> 'lf-operational-retention-v1';

  for v_jobid in
    select jobid
    from cron.job
    where jobname = 'lf-operational-retention-v1'
    order by jobid
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'lf-operational-retention-v1',
    '43 8 * * *',
    $cron$select private.fn_operational_retention_v1(true);$cron$
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'jobid',jobid,
        'jobname',jobname,
        'schedule',schedule,
        'active',active,
        'command',command
      )
      order by jobid
    ),
    '[]'::jsonb
  )
  into v_jobs_after
  from cron.job
  where jobname <> 'lf-operational-retention-v1';

  if v_jobs_before is distinct from v_jobs_after then
    raise exception 'OPERATIONAL_RETENTION_EXISTING_CRON_DRIFT';
  end if;

  if not exists (
    select 1
    from cron.job
    where jobname = 'lf-operational-retention-v1'
      and schedule = '43 8 * * *'
      and active is true
      and command like '%fn_operational_retention_v1(true)%'
  ) then
    raise exception 'OPERATIONAL_RETENTION_CRON_POSTFLIGHT_FAILED';
  end if;
end;
$job$;
