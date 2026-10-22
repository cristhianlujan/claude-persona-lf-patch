-- Read-only status operation: what is running now (strategy executions) and which work plans are
-- in progress, including the Router architecture wave. No writes; marks stale items instead of
-- hiding them. Applied only through ACTUALIZACION_DB_LF / LF Migration Merge Train.
BEGIN;

CREATE OR REPLACE FUNCTION public.lf_estado_en_curso_v1(p_stale_after_days integer DEFAULT 14)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog','public','programacion'
AS $f$
  SELECT jsonb_build_object(
    'schema_version','LF_ESTADO_EN_CURSO_V1',
    'as_of',to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'stale_after_days',p_stale_after_days,
    'read_only',true,
    'planes_en_curso',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'work_code',w.work_code,'workstream',w.stream_code,'titulo',w.title,
               'estado',w.status,'avance_pct',w.progress_pct,
               'checkpoints',w.done_checkpoint_count||'/'||w.checkpoint_count,
               'bloqueos_abiertos',w.open_blockers,
               'ultima_actualizacion',to_char(w.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD'),
               'sin_movimiento',(w.updated_at < now()-make_interval(days=>p_stale_after_days)))
             ORDER BY (w.work_code ILIKE 'ROUTER-W1-%') DESC, w.updated_at DESC),'[]'::jsonb)
      FROM programacion.v_engineering_work_progress w
      WHERE w.status IN ('IN_PROGRESS','READY')),
    'plan_router',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'work_code',w.work_code,'titulo',w.title,'estado',w.status,
               'avance_pct',w.progress_pct,'checkpoints',w.done_checkpoint_count||'/'||w.checkpoint_count)
             ORDER BY w.work_code),'[]'::jsonb)
      FROM programacion.v_engineering_work_progress w
      WHERE w.work_code ILIKE 'ROUTER-W1-%'),
    'estrategias_en_ejecucion',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
               'operacion',e.operation_code,'execution_id',e.execution_id,
               'ultima_actualizacion',to_char(e.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD'),
               'dias_sin_movimiento',floor(extract(epoch from (now()-e.updated_at))/86400)::int,
               'sin_movimiento',(e.updated_at < now()-make_interval(days=>p_stale_after_days)))
             ORDER BY e.updated_at DESC),'[]'::jsonb)
      FROM public.lf_operation_execution e
      WHERE e.status='IN_PROGRESS' AND e.operation_code ILIKE '%ESTRATEGIA%')
  )
$f$;

REVOKE ALL ON FUNCTION public.lf_estado_en_curso_v1(integer) FROM PUBLIC;
DO $g$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('REVOKE ALL ON FUNCTION public.lf_estado_en_curso_v1(integer) FROM %I',v_role); END IF;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['service_role','supabase_read_only_user'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=v_role) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION public.lf_estado_en_curso_v1(integer) TO %I',v_role); END IF;
  END LOOP;
END
$g$;

DO $rw$
DECLARE v_r jsonb; v_n_plan int; v_n_exec int;
BEGIN
  v_r := public.lf_estado_en_curso_v1();
  SELECT count(*) INTO v_n_plan FROM programacion.v_engineering_work_progress WHERE status IN ('IN_PROGRESS','READY');
  SELECT count(*) INTO v_n_exec FROM public.lf_operation_execution WHERE status='IN_PROGRESS' AND operation_code ILIKE '%ESTRATEGIA%';
  IF (v_r->>'read_only')::boolean IS DISTINCT FROM true
     OR jsonb_array_length(v_r->'planes_en_curso') <> v_n_plan
     OR jsonb_array_length(v_r->'estrategias_en_ejecucion') <> v_n_exec
     OR jsonb_array_length(v_r->'plan_router') < 1
  THEN RAISE EXCEPTION 'ESTADO_EN_CURSO_REHEARSAL_%', v_r; END IF;
END
$rw$;
COMMIT;
