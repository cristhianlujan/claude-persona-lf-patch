-- IG M10.7: independently instrument read-only source resolution.
-- This is a bounded historical diagnostic, NOT a Validator run or performance admission.
-- No runtime/contract/trigger/index/permission/scheduler changes.
-- Repeat 3 times per read-only operation. Readback must be interpreted
-- as live-source MICROBENCHMARK, not per-trigger time or exact-source proof.
DO $diag$
DECLARE
 v_run programacion.input_readiness_runs%rowtype;
 v_phase text;
 v_sample integer;
 v_started timestamptz;
 v_ms bigint;
 v_result jsonb;
 v_samples jsonb:='[]'::jsonb;
 v_total_samples int:=0;
 v_status jsonb;
 v_first_sha text;
 v_sha text;
 v_trial int;
 v_code constant text:='IG-M107-ATOMIC-SOURCE-MICROBENCH-006';
BEGIN
 SELECT * INTO STRICT v_run
 FROM programacion.input_readiness_runs WHERE id=933;
 IF v_run.pantalla_id<>43 OR v_run.version_id<>19 OR v_run.status<>'COMPLETED'
 OR (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
 THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_INPUT_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
 THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_ALREADY_PERSISTED'; END IF;
 IF md5(pg_get_functiondef('programacion.fn_input_build_source_manifest_safe_v1(bigint)'::regprocedure))
   <> 'cbe9282a0fe72628cc3e0b707973fd02'
 THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_SOURCE_FUNCTION_DRIFT'; END IF;
 v_status:=programacion.fn_input_governance_continuation_currentness_v1(933);
 IF v_status->>'code'<>'COMPLETED_STALE_OR_UNKNOWN'
 OR v_status#>>'{authority_readback,dimensions,source_manifest,current}'<>'false'
 THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_CURRENTNESS_EXPECTATION_DRIFT'; END IF;

 FOREACH v_phase IN ARRAY ARRAY[
  'SCREEN_CONTRACT','SCREEN_CANONICAL_GRAPH','SOURCE_MANIFEST',
  'CONTINUATION_CURRENTNESS','RESOLVE_SCREEN_GRAPH','RESOLVE_SCREEN_STATES',
  'MANIFEST_IDENTITY'
 ] LOOP
  v_first_sha:=NULL;
  FOR v_sample IN 1..3 LOOP
   v_started:=clock_timestamp();
   CASE v_phase
    WHEN 'SCREEN_CONTRACT' THEN
     SELECT f.contract-'metadata' INTO v_result
     FROM lf_ops.fn_screen_contract_v1('B2B_APP_SHELL','B2B_CARGAS','B2B-CARGA-001') f LIMIT 1;
    WHEN 'SCREEN_CANONICAL_GRAPH' THEN
     SELECT programacion.fn_input_screen_canonical_graph(v_run.pantalla_id,v_run.version_id) INTO v_result;
    WHEN 'SOURCE_MANIFEST' THEN
     SELECT programacion.fn_input_build_source_manifest_safe_v1(v_run.id) INTO v_result;
    WHEN 'CONTINUATION_CURRENTNESS' THEN
     SELECT programacion.fn_input_governance_continuation_currentness_v1(v_run.id) INTO v_result;
    WHEN 'RESOLVE_SCREEN_GRAPH' THEN
     SELECT programacion.fn_input_resolve_source_ref(
      jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',v_run.pantalla_id),
      v_run.pantalla_id,v_run.version_id) INTO v_result;
    WHEN 'RESOLVE_SCREEN_STATES' THEN
     SELECT programacion.fn_input_resolve_source_ref(
      jsonb_build_object('kind','SCREEN_STATE_SET','pantalla_id',v_run.pantalla_id),
      v_run.pantalla_id,v_run.version_id) INTO v_result;
    WHEN 'MANIFEST_IDENTITY' THEN
     SELECT programacion.fn_input_source_manifest_identity_v1(v_run.source_manifest) INTO v_result;
   END CASE;
   v_ms:=round(extract(epoch from(clock_timestamp()-v_started))*1000)::bigint;
   IF v_result IS NULL OR v_ms<0 THEN
     RAISE EXCEPTION 'IG_M107_MICROBENCH_NULL_OR_INVALID:%',v_phase; END IF;
   v_sha:=programacion.fn_v09_sha256_jsonb(v_result);
   IF v_first_sha IS NOT NULL AND v_first_sha IS DISTINCT FROM v_sha THEN
     RAISE EXCEPTION 'IG_M107_MICROBENCH_NONREPEATABLE_SOURCE:%',v_phase;
   END IF;
   v_first_sha:=v_sha;
   v_samples:=v_samples||jsonb_build_array(jsonb_build_object(
    'phase',v_phase,'sample_no',v_sample,'elapsed_ms',v_ms,
    'result_sha256',v_sha,'measurement_kind','LIVE_READ_ONLY_FUNCTION'));
   v_total_samples:=v_total_samples+1;
  END LOOP;
 END LOOP;
 IF v_total_samples<>21 OR jsonb_array_length(v_samples)<>21
 THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_SAMPLE_COUNT_MISMATCH'; END IF;

 FOR v_trial IN 1..2 LOOP
  BEGIN
   INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref
   ) VALUES (
    gen_random_uuid(),v_code,'GOVERNANCE',
    'Medicion granular de 7 operaciones SQL sin alterar Validator ni sus triggers',
    'Microbenchmark read-only focal de run933 sobre fuente live actual: 7 operaciones por 3 repeticiones (21 muestras). Incluye contrato, grafo, manifiesto, autoridad currentness, resolucion grafo, resolucion estados e identidad de manifiesto. Las duraciones individuales y huellas de resultado estan en evidencia. Se instrumentan funciones, NO el tiempo de cada trigger en UPDATE.',
    'Los 134 recalculos previstos por rutas de triggers se habian derivado del codigo, pero no eran contador runtime. Medir el costo de cada funcion componente sin introducir un run nuevo ni modificar los triggers permite separar costos de grafo, manifiesto y resolucion frente al total de 122115ms de actualizaciones de run933. La fuente live actual es STALE respecto a run933; no es benchmark exact-source ni se permite reutilizarla como prueba de PASS.',
    'ATOMIC_READ_ONLY_SOURCE_PROFILE',
    'Conservar 21 timings con source y SHA vinculados, repetir sobre fuente congelada si se habilita diagnóstico en un futuro Validator. Para medir triggers reales usar EXPLAIN ANALYZE en un UPDATE autorizado y reversible sobre un run de prueba PENDING, nunca sobre recibos terminales. No ampliar presupuestos ni eliminar controles; prevenir falsa atribucion de tiempo de trigger por multiplicacion de microbenchmarks.',
    '21/21 llamadas read-only medidas. Pantalla 43 run 933 COMPLETED pero CONTINUATION=COMPLETED_STALE_OR_UNKNOWN; no modifica run ni CP3, presupuestos, seguridad o contratos. 3 muestras por operacion con resultados identicos dentro de transaccion. No demuestra ahorro, no autentica assert FAIL/PASS, no instrumenta UPDATE/trigger.',
    'MEDIUM',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
    'ACTIVO',jsonb_build_object(
     'schema_version','IG_ATOMIC_SOURCE_MICROBENCH_V1',
     'run_id',933,'pantalla_id',43,
     'source_current_at_probe',false,
     'sample_count',v_total_samples,'samples',v_samples,
     'limitations',jsonb_build_array('HISTORICAL_STALE_SOURCE','NOT_PER_TRIGGER','NOT_EXACT_SOURCE','NO_BUDGET_ADMISSION'))::text,
    clock_timestamp(),clock_timestamp(),'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'Input Governance independent read-only bounded performance probe',
    'supabase://programacion.input_readiness_runs/933'
   );
   IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
   THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_WRITE_READBACK_MISMATCH'; END IF;
   IF v_trial=1 THEN
    RAISE EXCEPTION 'IG_M107_MICROBENCH_ROLLBACK_PROBE' USING ERRCODE='PZ125';
   END IF;
  EXCEPTION WHEN SQLSTATE 'PZ125' THEN
   IF v_trial<>1 THEN RAISE; END IF;
  END;
  IF v_trial=1 AND EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
  THEN RAISE EXCEPTION 'IG_M107_MICROBENCH_ROLLBACK_RESIDUE'; END IF;
 END LOOP;
END $diag$;
