-- M8.8 checkpoint #791 / PAULO-066. The prior readback mixed run and invocation ID/time.
-- Demonstrated runtime drift: IG now runs through direct SQL request id -> validator run id.
-- This changes ONLY the unresolved checkpoint's evidence queries and retains DONE history.
do $preflight$
begin
 if not exists(
   select 1 from programacion.engineering_plan_units u
   join programacion.engineering_work_items w on w.id=u.work_item_id
   join programacion.engineering_work_checkpoints c on c.work_item_id=w.id
   where u.plan_code='IG_CURATOR_VALIDATOR_REFACTOR_V2' and u.unit_code='M8.8'
     and w.work_code='PAULO-066' and c.id=791
     and c.checkpoint_code='CHUNK_MARGIN_READBACK'
     and c.status in ('PENDING','IN_PROGRESS')
 ) then raise exception 'IG_M88_CHECKPOINT_ID_OR_STATUS_DRIFT'; end if;
end;
$preflight$;

select programacion.fn_engineering_checkpoint_input_upsert_v1(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.8','CHUNK_MARGIN_READBACK',
  '["with chunk as (\n select count(*) chunks,count(distinct run_id) runs,max(duration_ms) max_chunk_ms,\n count(*) filter(where duration_ms>=82500) chunks_ge_75pct_budget\n from programacion.input_validator_chunk_timings\n where created_at>now()-interval ''30 days''\n), req as (\n select count(*) requests,\n count(*) filter(where q.last_run_id is not null and r.id is null) request_run_id_mismatches,\n count(*) filter(where q.status=''DONE'' and q.last_status=''BLOCKED'') terminal_blocked,\n count(*) filter(where q.status=''DONE'' and r.status=''COMPLETED'') terminal_validated\n from programacion.ig_direct_requests_v1 q\n left join programacion.input_readiness_runs r on r.id=q.last_run_id\n) select to_jsonb(chunk)||to_jsonb(req) as readback from chunk cross join req","select count(*) cron_runs_30d,\ncount(*) filter(where status<>''succeeded'') failed_30d,\ncount(*) filter(where extract(epoch from(end_time-start_time))>=95) over_95s_30d,\ncount(*) filter(where start_time>timestamptz ''2026-10-08T10:40:00Z'') post_fix_runs,\ncount(*) filter(where start_time>timestamptz ''2026-10-08T10:40:00Z'' and extract(epoch from(end_time-start_time))>=95) over_95s_post_fix,\nmax(extract(epoch from(end_time-start_time))) max_cron_s_30d\nfrom cron.job_run_details where jobid=(select jobid from cron.job where jobname=''ig-direct-sql-worker-v1'') and start_time>now()-interval ''30 days''"]'::jsonb,
  '["programacion.input_validator_chunk_timings","programacion.input_readiness_runs","programacion.ig_direct_requests_v1","cron.job_run_details","cron.job"]'::jsonb
) as source_pack_upsert;

do $guard$
declare v_spec jsonb;
begin
 v_spec:=programacion.fn_engineering_checkpoint_action_spec_v3(
  'IG_CURATOR_VALIDATOR_REFACTOR_V2','M8.8','CHUNK_MARGIN_READBACK');
 if v_spec->'verification_queries'->>0 not like '%input_validator_chunk_timings%'
    or v_spec->'verification_queries'->>0 not like '%last_run_id%'
    or v_spec->'verification_queries'->>1 not like '%cron.job_run_details%'
 then raise exception 'IG_M88_READBACK_WRONG_IDS_OR_STALE_QUERY'; end if;
 if (select count(*) from programacion.engineering_work_checkpoints c
     where c.work_item_id=262 and c.status='DONE')<>6
 then raise exception 'IG_M88_PREVIOUS_DONE_CHECKPOINTS_MUTATED';end if;
end;
$guard$;
