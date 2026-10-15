-- IG M10.7 CP3: live post-transport evidence; no assertion PASS.
DO $ekb$
DECLARE
  v_old record;
  v_new record;
  v_pass int;
  v_chunks int;
  v_compute bigint;
  v_wait bigint;
BEGIN
  SELECT * INTO STRICT v_old FROM programacion.input_readiness_runs WHERE id=832;
  SELECT * INTO STRICT v_new FROM programacion.input_readiness_runs WHERE id=933;
  SELECT count(*) FILTER(WHERE validator_outcome='PASS')
    INTO v_pass FROM programacion.input_family_assessments WHERE run_id=933;
  SELECT count(*),sum(duration_ms),sum(wait_resume_ms)
    INTO v_chunks,v_compute,v_wait FROM programacion.input_validator_chunk_timings WHERE run_id=933;
  IF v_old.pantalla_id<>43 OR v_new.pantalla_id<>43
    OR v_new.status<>'COMPLETED' OR v_pass<>47 OR v_chunks<>6
    OR v_new.validator_duration_ms<>229436
    OR v_compute<>205179 OR v_wait<>21231
    OR (SELECT schedule FROM cron.job WHERE jobid=45)<>'30 seconds'
    OR NOT EXISTS(SELECT 1 FROM programacion.ig_direct_requests_v1
      WHERE id=18 AND last_run_id=933 AND status='DONE' AND last_status='READY')
  THEN RAISE EXCEPTION 'M107_CP3_LIVE_OBSERVATION_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
    WHERE codigo='IG-M107-CP3-TRANSPORT-CPU-TRADEOFF-004')
  THEN RAISE EXCEPTION 'M107_CP3_EKB_DUPLICATE'; END IF;
  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref)
  VALUES(
    gen_random_uuid(),'IG-M107-CP3-TRANSPORT-CPU-TRADEOFF-004','GOVERNANCE',
    'Focal post cron 30s confirma mejora de transporte pero persiste presupuesto SQL incumplido',
    'Pantalla B2B-CARGA-001: antes run832 47/47 PASS, 6 chunks, compute 135147ms, wait 315181ms, final wall hasta ultimo chunk 453380ms. Despues run933 47/47 PASS, 6 chunks, compute 205179ms, wait 21231ms, final wall 229980ms, validator_duration_ms 229436. Solicitud 18 DONE/READY sin error y solo 1 pantalla. Las fuentes y 27 vs 20 propuestas cambiaron: comparacion orientativa, no benchmark exact-source ni certificado p90.',
    'La cadencia del mismo cron disminuyo la espera, pero el costo CPU/SQL por familia y el cierre de propuestas persisten. fn_input_governance_validate_v2 reevalua assertions y los triggers fn_guard_input_family_execution_update y fn_guard_input_family_assessment_update vuelven a evaluar, rehidratar y reconstruir manifest por fila. No se ha probado aun que ese trabajo redundante se pueda quitar sin afectar assurance.',
    'TRANSPORT_WAIT_IMPROVED_SQL_WORK_REMAINS_ABOVE_BUDGET',
    'No cerrar CP3, no ampliar timeout ni saltar Validator. Optimizar fuente exacta por fase conservando Q0-Q8, trigger guards, comprobacion de source currentness y oraculos independientes; probar rollback y negativos, benchmark comparable y p90. La marca terminal con clock_timestamp precede 545ms al ultimo chunk: medir con ambos relojes y no falsear el umbral.',
    'En DB run933 COMPLETED, 47 PASS de 47, 0 FAIL/BLOCKED/PENDING, duracion 229436ms >150000, hasta ultimo chunk 229980ms, wait=21231ms, compute=205179ms; CP3 permanece PENDING al 45%. No inferir equivalencia exact-source con 832.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
    'ACTIVO','supabase://programacion.input_readiness_runs/933;supabase://programacion.input_validator_chunk_timings/933;supabase://programacion.ig_direct_requests_v1/18',
    clock_timestamp(),clock_timestamp(),'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'M10.7 CP3 one-screen real post-transport benchmark diagnosis',
    'supabase://programacion.input_readiness_runs/933'
  );
END $ekb$;