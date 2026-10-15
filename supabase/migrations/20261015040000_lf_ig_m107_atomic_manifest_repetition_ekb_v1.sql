-- IG M10.7 CP3: atomized read-only performance diagnosis as EKB.
-- This migration inserts one evidence record only. No Validator, contract,
-- policy, index, timing, trigger, scheduler or checkpoint mutations.
DO $m107$
DECLARE
  n_f int;
  n_p int;
  n_pass int;
  v_chunks int;
  v_compute bigint;
  v_wait bigint;
  v_t int;
  v_trial int;
  v_code constant text:='IG-M107-ATOMIC-MANIFEST-REPEAT-005';
BEGIN
  SELECT count(*),count(*) FILTER (WHERE validator_outcome='PASS')
    INTO n_f,n_pass FROM programacion.input_family_assessments WHERE run_id=933;
  SELECT count(*) INTO n_p FROM programacion.input_gap_proposals WHERE run_id=933;
  SELECT count(*),sum(duration_ms),sum(wait_resume_ms)
    INTO v_chunks,v_compute,v_wait
  FROM programacion.input_validator_chunk_timings WHERE run_id=933;
  IF n_f<>47 OR n_pass<>47 OR n_p<>20 OR v_chunks<>6
    OR v_compute<>205179 OR v_wait<>21231
    OR (SELECT validator_duration_ms FROM programacion.input_readiness_runs WHERE id=933)<>229436
  THEN RAISE EXCEPTION 'M107_ATOMIC_EKB_RUN933_BASELINE_DRIFT'; END IF;

  SELECT count(*) INTO v_t
  FROM pg_trigger
  WHERE tgenabled IN ('O','A') AND
    tgname IN (
     'trg_input_family_assessment_update',
     'trg_input_family_assessment_00a_continuation_currentness_update',
     'trg_input_gap_proposal_update_v512',
     'trg_input_gap_proposal_00_continuation_currentness_update');
  IF v_t<>4 THEN RAISE EXCEPTION 'M107_ATOMIC_EKB_TRIGGER_TOPOLOGY_DRIFT'; END IF;
  IF md5(pg_get_functiondef('programacion.fn_input_build_source_manifest_safe_v1(bigint)'::regprocedure))
      <>'cbe9282a0fe72628cc3e0b707973fd02'
  THEN RAISE EXCEPTION 'M107_ATOMIC_EKB_MANIFEST_SOURCE_DRIFT'; END IF;
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
  THEN RAISE EXCEPTION 'M107_ATOMIC_EKB_ALREADY_EXISTS'; END IF;

  FOR v_trial IN 1..2 LOOP
    BEGIN
      INSERT INTO public.lf_error_knowledge(
        id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
        validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
        estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
        detectability,source_context,source_ref)
      VALUES (
        gen_random_uuid(),v_code,'GOVERNANCE',
        'Atomizacion M10.7: reconstruccion de manifiesto reiterada por familia y propuesta',
        'Run933 pantalla B2B-CARGA-001: Validator 229436 ms, seis chunks 205179 ms de calculo y 21231 ms de espera. Subfases registradas: assert construction 48773 ms, grupo evidencia+UPDATE+triggers 122115 ms, gap proposals 34041 ms. 47 familias y 20 propuestas; 38/47 assertions usan SCREEN_CANONICAL_GRAPH. EXPLAIN ANALYZE de fn_input_build_source_manifest_safe_v1(933) en tres mediciones separadas: 1283.678, 631.002, 523.804 ms. Contrato lf_ops.fn_screen_contract_v1 en dos muestras: 262.494 y 62.180 ms.',
        'Dos triggers habilitados sobre cada UPDATE de familia y otros dos sobre cada UPDATE de propuesta re-ejecutan currentness y verificacion del source manifest. En las rutas examinadas esto da 47*2+20*2=134 recomputaciones estructuralmente previstas, sin contar evaluaciones de asercion/Curator. Conteo derivado de codigo, no contador runtime. Las consultas simples de run_id y propuestas usan indices y devuelven resultados en ~0.35 a 5.33 ms. No hay llamadas web observadas en la ruta revisada de resolucion de fuente; son lecturas SQL/JSONB en Supabase.',
        'REDUNDANT_FULL_MANIFEST_RECONSTRUCTION_ON_ROW_UPDATE',
        'Atomizar sin inventar SLO: (1) transporte/espera; (2) construccion assertions: rebind/source resolution/hash; (3) evidencia+escritura: source readback/rehydration/evaluation; (4) triggers individuales: continuidad/currentness, version/manifest, semantica y hash; (5) propuestas: referencia distinta/resolucion y coste por UPDATE; (6) Curator. Medir con relojes monotonic de pared, counters por llamada, buffers, plan/indices y fingerprints exactos. Conservar oraculos fail-closed y no aceptar cache stale: agrupar solo con equivalencia de fuente dentro de transaccion que invalide al cambiar la autoridad. No inferir ahorro 134 x muestra por variacion de cache/carga. Preferir instrumentacion opt-in por run en diagnostico independiente, no parches por pantalla ni eliminar triggers.',
        'Read-only SQL: EXPLAIN ANALYZE full manifest 1283.678/631.002/523.804 ms, contract 262.494/62.180 ms; idx_input_family_assessments_run y idx_input_gap_proposals_run presentes, scans indice en <=5.33 ms. Identificada topologia 4/4 triggers. No se modifico contrato ni CP3, sigue PENDING y unidad 45%; ahorro no demostrado.',
        'HIGH',1,clock_timestamp(),clock_timestamp(),
        'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
        'ACTIVO','supabase://programacion.input_readiness_runs/933;supabase://programacion.input_validator_chunk_timings/933;supabase://pg_trigger;supabase://pg_indexes',
        clock_timestamp(),clock_timestamp(),'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
        'M10.7 atomic performance read-only RCA, one screen, no runtime changes',
        'supabase://programacion.fn_input_build_source_manifest_safe_v1'
      );
      IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
      THEN RAISE EXCEPTION 'M107_ATOMIC_EKB_READBACK_FAILED'; END IF;
      IF v_trial=1 THEN
        RAISE EXCEPTION 'M107_ATOMIC_EKB_ROLLBACK_SENTINEL' USING ERRCODE='PZ124';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ124' THEN
      IF v_trial<>1 THEN RAISE; END IF;
    END;
    IF v_trial=1 AND EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
    THEN RAISE EXCEPTION 'M107_ATOMIC_EKB_ROLLBACK_RESIDUE'; END IF;
  END LOOP;
END $m107$;
