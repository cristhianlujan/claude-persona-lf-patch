-- IG M10.7 A1: transversal read-only observation over existing canonical metrics.
-- Scope: docs/ig/IG_M107_TRANSVERSAL_EXECUTION_TELEMETRY_V1.md
-- One additive function; not a Validator or trigger change, no CP3 transition.
DO $pre$
BEGIN
 IF to_regprocedure('programacion.fn_ig_validator_execution_metrics_v1(bigint)') IS NOT NULL
 THEN RAISE EXCEPTION 'IG_M107_A1_METRICS_ALREADY_EXISTS'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo='IG-M107-TRANSVERSAL-EXECUTION-TELEMETRY-012')
 THEN RAISE EXCEPTION 'IG_M107_A1_EKB_ALREADY_EXISTS'; END IF;
END $pre$;

CREATE FUNCTION programacion.fn_ig_validator_execution_metrics_v1(p_run_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path='pg_catalog','programacion'
AS $metrics$
DECLARE
  r programacion.input_readiness_runs%rowtype;
  t record;
  v_phase_sum bigint;
  v_observed_window_ms bigint;
  v_missing boolean;
BEGIN
  SELECT * INTO r FROM programacion.input_readiness_runs WHERE id=p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'IG_EXECUTION_METRICS_RUN_NOT_FOUND:%',p_run_id; END IF;
  SELECT count(*)::int AS chunk_count,
         coalesce(sum(duration_ms),0)::bigint AS compute_ms,
         coalesce(sum(coalesce(wait_resume_ms,0)),0)::bigint AS wait_resume_ms,
         coalesce(sum(coalesce(classification_ms,0)),0)::bigint AS classification_ms,
         coalesce(sum(coalesce(assertions_ms,0)),0)::bigint AS assertions_ms,
         coalesce(sum(coalesce(ekb_ms,0)),0)::bigint AS ekb_ms,
         coalesce(sum(coalesce(gap_proposals_ms,0)),0)::bigint AS gap_proposals_ms,
         coalesce(sum(coalesce(db_write_ms,0)),0)::bigint AS db_write_ms,
         coalesce(sum(coalesce(families_processed,0)),0)::integer AS families_processed,
         count(*) filter(where duration_ms IS NULL OR duration_ms<=0)::integer AS invalid_chunk_durations,
         count(*) filter(where classification_ms IS NULL OR assertions_ms IS NULL
             OR ekb_ms IS NULL OR gap_proposals_ms IS NULL OR db_write_ms IS NULL
             OR wait_resume_ms IS NULL OR families_processed IS NULL)::integer AS incomplete_phase_rows,
         min(started_at) AS first_chunk_at,
         max(completed_at) AS last_chunk_at
    INTO t FROM programacion.input_validator_chunk_timings WHERE run_id=p_run_id;
  v_phase_sum:=t.classification_ms+t.assertions_ms+t.ekb_ms+
      t.gap_proposals_ms+t.db_write_ms;
  v_observed_window_ms:=CASE WHEN t.first_chunk_at IS NOT NULL
    AND t.last_chunk_at IS NOT NULL
    THEN round(extract(epoch FROM (t.last_chunk_at-t.first_chunk_at))*1000)::bigint
    ELSE NULL END;
  v_missing := r.validator_duration_ms IS NULL OR r.validator_duration_ms<=0
    OR t.chunk_count=0 OR t.invalid_chunk_durations<>0
    OR t.incomplete_phase_rows<>0
    OR (r.status='COMPLETED' AND t.families_processed IS DISTINCT FROM r.family_count);
  RETURN jsonb_build_object(
    'schema_version','IG_VALIDATOR_EXECUTION_METRICS_V1',
    'run_id',p_run_id,'pantalla_id',r.pantalla_id,
    'run_status',r.status,'family_count',r.family_count,
    'source_snapshot_sha256',r.source_snapshot_sha256,
    'measurement_mode','OBSERVATION_ONLY',
    'checkpoint_pass',false,
    'validator_duration_ms',r.validator_duration_ms,
    'duration_unknown',v_missing,
    'over_150s',CASE WHEN r.validator_duration_ms>150000 THEN true
       WHEN r.validator_duration_ms IS NULL OR r.validator_duration_ms<=0 THEN null
       ELSE false END,
    'chunk_count',t.chunk_count,
    'families_processed',t.families_processed,
    'compute_ms',t.compute_ms,
    'wait_resume_ms',t.wait_resume_ms,
    'observed_validator_window_ms',v_observed_window_ms,
    'elapsed_clock_difference_ms',CASE WHEN v_observed_window_ms IS NOT NULL
       AND r.validator_duration_ms IS NOT NULL
       THEN r.validator_duration_ms-v_observed_window_ms ELSE null END,
    'phase_ms',jsonb_build_object(
       'classification',t.classification_ms,
       'assertions',t.assertions_ms,
       'ekb',t.ekb_ms,
       'gap_proposals',t.gap_proposals_ms,
       'db_write_including_triggers',t.db_write_ms,
       'accounted_compute',v_phase_sum,
       'unattributed_compute',t.compute_ms-v_phase_sum),
    'integrity',jsonb_build_object(
       'invalid_chunk_durations',t.invalid_chunk_durations,
       'incomplete_phase_rows',t.incomplete_phase_rows,
       'chunk_compute_exceeds_validator_wall',CASE
          WHEN r.validator_duration_ms IS NULL THEN null
          ELSE t.compute_ms>r.validator_duration_ms END),
    'limitations',jsonb_build_array(
       'DB_WRITE_INCLUDES_TRIGGERS_NOT_PER_TRIGGER',
       'NO_CP3_ASSERTION','NO_CROSS_CALL_CACHE',
       'NO_DERIVED_P50_OR_P90_FROM_ONE_RUN'));
END;
$metrics$;

REVOKE ALL ON FUNCTION programacion.fn_ig_validator_execution_metrics_v1(bigint) FROM PUBLIC;
COMMENT ON FUNCTION programacion.fn_ig_validator_execution_metrics_v1(bigint)
IS 'Nondecisional read-only report over existing per-chunk timings for any Input Governance run. No currentness or CP3 verdict.';

DO $test$
DECLARE
  v_code CONSTANT text:='IG-M107-TRANSVERSAL-EXECUTION-TELEMETRY-012';
  v_sample jsonb;
  v_bad text;
  v_payload jsonb;
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    WHERE n.nspname='programacion' AND p.proname='fn_ig_validator_execution_metrics_v1'
      AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
  ) THEN RAISE EXCEPTION 'IG_M107_A1_PUBLIC_EXECUTE_NOT_REVOKED'; END IF;
  v_bad:=null;
  BEGIN
    PERFORM programacion.fn_ig_validator_execution_metrics_v1(-1);
  EXCEPTION WHEN OTHERS THEN v_bad:=SQLERRM; END;
  IF v_bad NOT LIKE 'IG_EXECUTION_METRICS_RUN_NOT_FOUND:%'
  THEN RAISE EXCEPTION 'IG_M107_A1_MISSING_RUN_NOT_REJECTED'; END IF;
  v_sample:=programacion.fn_ig_validator_execution_metrics_v1(933);
  IF v_sample->>'schema_version'<>'IG_VALIDATOR_EXECUTION_METRICS_V1'
    OR (v_sample->>'run_id')::bigint<>933
    OR (v_sample->>'pantalla_id')::int<>43
    OR v_sample->>'run_status'<>'COMPLETED'
    OR (v_sample->>'family_count')::int<>47
    OR (v_sample->>'chunk_count')::int<>6
    OR (v_sample->>'families_processed')::int<>47
    OR (v_sample->>'validator_duration_ms')::bigint<>229436
    OR (v_sample->>'compute_ms')::bigint<>205179
    OR (v_sample->>'wait_resume_ms')::bigint<>21231
    OR (v_sample#>>'{phase_ms,assertions}')::bigint<>48773
    OR (v_sample#>>'{phase_ms,db_write_including_triggers}')::bigint<>122115
    OR (v_sample#>>'{phase_ms,gap_proposals}')::bigint<>34041
    OR (v_sample->>'duration_unknown')::boolean IS DISTINCT FROM false
    OR (v_sample->>'over_150s')::boolean IS DISTINCT FROM true
    OR (v_sample->>'checkpoint_pass')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'IG_M107_A1_SAMPLE_READBACK_DRIFT:%',left(v_sample::text,1300); END IF;
  -- Verify the measured source table agrees with the aggregated output.
  IF (v_sample->>'compute_ms')::bigint IS DISTINCT FROM
        (SELECT sum(duration_ms) FROM programacion.input_validator_chunk_timings WHERE run_id=933)
  THEN RAISE EXCEPTION 'IG_M107_A1_INDEPENDENT_CHUNK_READBACK_MISMATCH'; END IF;
  v_payload:=jsonb_build_object(
    'schema_version','IG_M107_TRANSVERSAL_EXECUTION_TELEMETRY_V1',
    'sample_run_id',933,
    'sample_screen_id',43,
    'recorded_metrics',v_sample,
    'negative_missing_run',true,
    'public_execute',false,
    'validator_runtime_changed',false,
    'cp3_closed',false);
  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref
  ) VALUES(
    gen_random_uuid(),v_code,'GOVERNANCE',
    'Reutilización de telemetría de fases del Validator, readback por run',
    'Función aditiva de observación no decisional por run_id sobre registros ya existentes. Agrega cómputo, esperas, fases y diferencias de reloj; no altera Validator, triggers, contratos, reglas ni la política CP3.',
    'Las métricas ya existían en registros de chunks y recibos de tiempos; faltaba reporte transversal de una ejecución, con desconocidos tratados fail-closed.',
    'REUSE_EXISTING_VALIDATOR_TIMING_AND_PHASES',
    'No inventar nuevas tablas de métricas; preservar separadas la duración total, sumas de chunks, esperas, agregados DB_WRITE y medición por trigger. Nunca declarar PASS CP3 con este reporte. Instrumentación de cada trigger requiere ensayo opt-in separado.',
    'Caso real run 933, 47 familias y 6 chunks; fases y reloj coinciden con tabla base; negativo inexistente rechazado; sin permisos de ejecución pública. No es prueba de ahorro ni modificación de producción.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    v_payload::text,clock_timestamp(),clock_timestamp(),
    'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'M10.7 transverse measurement uses existing chunk timings, no new telemetry engine',
    'programacion.fn_ig_validator_execution_metrics_v1(bigint)'
  );
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
  THEN RAISE EXCEPTION 'IG_M107_A1_EKB_READBACK_FAILED'; END IF;
END $test$;