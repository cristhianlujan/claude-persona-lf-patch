create or replace function private.fn_lf_p0_evidence_retention_guard_v1(
  p_apply boolean default false,
  p_now timestamptz default clock_timestamp()
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_candidate_count bigint := 0;
  v_candidate_bytes bigint := 0;
  v_deleted_count bigint := 0;
  v_deleted_bytes bigint := 0;
  v_candidate_batch_sha256 text;
  v_deleted_batch_sha256 text;
  v_execution_id text;
  v_event_id bigint;
begin
  with ranked as (
    select
      e.evidence_object_id,
      e.content_bytes,
      e.content_sha256,
      e.created_at,
      row_number() over (
        order by e.created_at desc, e.evidence_object_id desc
      ) as recency_rank,
      case
        when e.mime_type = 'application/json'
        then convert_from(e.content, 'UTF8')::jsonb ->> 'terminal_result'
        else null
      end as terminal_result
    from private.lf_p0_review_evidence_objects_v1 e
    where e.object_role = 'PACKET_MANIFEST'
      and e.object_name = 'p0-real-rerun-v4.json'
      and e.retention_policy = 'UNTIL_TERMINAL_REVIEW'
  ), candidates as (
    select *
    from ranked
    where recency_rank > 20
      and created_at < p_now - interval '3 days'
      and terminal_result = 'READY_FOR_HUMAN_REVIEW_RECHECK'
  )
  select
    count(*),
    coalesce(sum(content_bytes), 0),
    encode(
      extensions.digest(
        convert_to(
          coalesce(string_agg(content_sha256, ',' order by created_at, evidence_object_id), ''),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  into v_candidate_count, v_candidate_bytes, v_candidate_batch_sha256
  from candidates;

  if not p_apply then
    return jsonb_build_object(
      'mode', 'DRY_RUN',
      'policy', 'SUCCESS_RECEIPTS_3D_KEEP_LATEST_20',
      'candidate_rows', v_candidate_count,
      'candidate_logical_bytes', v_candidate_bytes,
      'candidate_batch_sha256', v_candidate_batch_sha256,
      'observed_at', p_now
    );
  end if;

  with ranked as (
    select
      e.evidence_object_id,
      e.content_bytes,
      e.content_sha256,
      e.created_at,
      row_number() over (
        order by e.created_at desc, e.evidence_object_id desc
      ) as recency_rank,
      case
        when e.mime_type = 'application/json'
        then convert_from(e.content, 'UTF8')::jsonb ->> 'terminal_result'
        else null
      end as terminal_result
    from private.lf_p0_review_evidence_objects_v1 e
    where e.object_role = 'PACKET_MANIFEST'
      and e.object_name = 'p0-real-rerun-v4.json'
      and e.retention_policy = 'UNTIL_TERMINAL_REVIEW'
  ), candidates as (
    select *
    from ranked
    where recency_rank > 20
      and created_at < p_now - interval '3 days'
      and terminal_result = 'READY_FOR_HUMAN_REVIEW_RECHECK'
  ), deleted as (
    delete from private.lf_p0_review_evidence_objects_v1 e
    using candidates c
    where e.evidence_object_id = c.evidence_object_id
    returning e.evidence_object_id, e.content_bytes, e.content_sha256, e.created_at
  )
  select
    count(*),
    coalesce(sum(content_bytes), 0),
    encode(
      extensions.digest(
        convert_to(
          coalesce(string_agg(content_sha256, ',' order by created_at, evidence_object_id), ''),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  into v_deleted_count, v_deleted_bytes, v_deleted_batch_sha256
  from deleted;

  if v_deleted_count > 0 then
    v_execution_id := 'EXEC-P0-EVIDENCE-RETENTION-' || to_char(p_now at time zone 'UTC', 'YYYYMMDDHH24MISS');

    insert into public.lf_eventos(
      evento_tipo,
      entidad_tipo,
      entidad_codigo,
      descripcion,
      severidad,
      payload,
      origen,
      created_by_execution_id
    ) values (
      'CONTROL_OPERATIVO',
      'LF_EVIDENCE_RETENTION',
      'P0_EVIDENCE_RETENTION_GUARD_V1',
      'Retención automática de evidencia P0 fuera de ventana operativa.',
      'INFO',
      jsonb_build_object(
        'evidence_schema_version', 'operational-event/v2',
        'execution_id', v_execution_id,
        'producer', 'DB_RETENTION_CRON',
        'purpose', 'Acotar evidencia P0 exitosa conservando ventana reciente y trazabilidad por hash.',
        'acceptance_declared', false,
        'occurred_at', to_char(p_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'policy', 'SUCCESS_RECEIPTS_3D_KEEP_LATEST_20',
        'deleted_rows', v_deleted_count,
        'deleted_logical_bytes', v_deleted_bytes,
        'deleted_batch_sha256', v_deleted_batch_sha256,
        'candidate_rows_predelete', v_candidate_count,
        'candidate_batch_sha256_predelete', v_candidate_batch_sha256,
        'target_relation', 'private.lf_p0_review_evidence_objects_v1'
      ),
      'DB_RETENTION_CRON',
      v_execution_id
    )
    returning id into v_event_id;
  end if;

  return jsonb_build_object(
    'mode', 'APPLY',
    'policy', 'SUCCESS_RECEIPTS_3D_KEEP_LATEST_20',
    'deleted_rows', v_deleted_count,
    'deleted_logical_bytes', v_deleted_bytes,
    'deleted_batch_sha256', v_deleted_batch_sha256,
    'closure_event_id', v_event_id,
    'observed_at', p_now
  );
end
$function$;

revoke all on function private.fn_lf_p0_evidence_retention_guard_v1(boolean,timestamptz) from public, anon, authenticated;
grant execute on function private.fn_lf_p0_evidence_retention_guard_v1(boolean,timestamptz) to service_role;

comment on function private.fn_lf_p0_evidence_retention_guard_v1(boolean,timestamptz) is
'Bounded retention for successful p0-real-rerun-v4 manifests: keep a rolling three-day window and always preserve the latest 20; failures are not deleted by this guard.';

do $block$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'lf-p0-evidence-retention-v1'
  order by jobid desc
  limit 1;

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;
end
$block$;

select cron.schedule(
  'lf-p0-evidence-retention-v1',
  '17 8 * * *',
  $cron$select private.fn_lf_p0_evidence_retention_guard_v1(true);$cron$
);
