-- IG M10.7 / Validator clock correctness / isolated Train migration.
-- Change ONLY the terminal marker of the already governed validator function.
-- PostgreSQL now() timestamps TRANSACTION START, not end of a long-running
-- VALIDATE_V2 call. clock_timestamp() is the correct wall-clock measurement.
-- No historical evidence rewrite, no timeout increase, no chunk reduction,
-- no trigger disabling, no semantic validator bypass, no CP3 closure.
DO $ig_m107_timing$
DECLARE
  v_procedure constant regprocedure := 'programacion.fn_input_governance_validate_v2(bigint,text)'::regprocedure;
  v_old text;
  v_new text;
  v_readback text;
  v_marker_old constant text := 'validator_completed_at=now()';
  v_marker_new constant text := 'validator_completed_at=clock_timestamp()';
  v_md5 constant text := 'd18bd26c33083017fbdf5a90bcf6d165';
  v_old_occurrences integer;
  v_trial integer;
  v_affected integer;
  v_missing integer;
  v_baseline_state jsonb;
BEGIN
  SELECT pg_get_functiondef(v_procedure) INTO STRICT v_old;
  IF md5(v_old) IS DISTINCT FROM v_md5
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_BASELINE_DRIFT'; END IF;
  v_old_occurrences:=(length(v_old)-length(replace(v_old,v_marker_old,'')))/length(v_marker_old);
  IF v_old_occurrences<>1
    OR position('set status=''COMPLETED'',validator_completed_at=now() where id=p_run_id;' in v_old)=0
    OR position('v_completed:=clock_timestamp();' in v_old)=0
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_EXPECTED_MARKER_UNRESOLVED'; END IF;
  v_new:=replace(v_old,v_marker_old,v_marker_new);
  IF v_new IS NOT DISTINCT FROM v_old
     OR replace(v_new,v_marker_new,v_marker_old) IS DISTINCT FROM v_old
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_ONE_TOKEN_PATCH_FAILED'; END IF;

  SELECT count(*),count(*) FILTER(WHERE r.validator_duration_ms=0)
    INTO v_affected,v_missing
  FROM programacion.input_readiness_runs r
  WHERE r.id IN (656,825,826,828,829,931,932)
    AND r.status='COMPLETED'
    AND EXISTS(
      SELECT 1 FROM programacion.input_validator_chunk_timings t
      WHERE t.run_id=r.id AND t.completed_at>r.validator_completed_at
    );
  IF v_affected<>7 OR v_missing<>5
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_HISTORICAL_SOURCE_CHANGED: %, %',v_affected,v_missing; END IF;

  SELECT jsonb_build_object('status',w.status,'done',count(*) FILTER(WHERE c.status='DONE'),
      'pending',count(*) FILTER(WHERE c.status='PENDING')) INTO v_baseline_state
  FROM programacion.engineering_work_items w
  JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=w.id
  WHERE w.id=478
  GROUP BY w.status;
  IF v_baseline_state IS DISTINCT FROM '{"status":"IN_PROGRESS","done":2,"pending":3}'::jsonb
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_UNEXPECTED_UNIT_STATE'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE name='lf_ig_m107_cp3_budget_guard_contract_v1')
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_CP3_GUARD_MISSING'; END IF;

  FOR v_trial IN 1..2 LOOP
    BEGIN
      -- CREATE OR REPLACE preserves the existing signature, privileges,
      -- security-definer metadata and complete validator semantics.
      EXECUTE v_new;
      SELECT pg_get_functiondef(v_procedure) INTO STRICT v_readback;
      IF v_readback IS DISTINCT FROM v_new
         OR position(v_marker_old in v_readback)<>0
         OR position(v_marker_new in v_readback)=0
      THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_SOURCE_READBACK_MISMATCH'; END IF;
      IF (SELECT count(*) FROM programacion.engineering_work_checkpoints
          WHERE work_item_id=478 AND status='DONE')<>2
      THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_DO_NOT_CLOSE_CP3'; END IF;
      IF v_trial=1 THEN
        RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_ROLLBACK_SENTINEL' USING ERRCODE='PZ117';
      END IF;
    EXCEPTION WHEN SQLSTATE 'PZ117' THEN
      IF v_trial<>1 THEN RAISE; END IF;
    END;
    IF v_trial=1 AND
       (SELECT pg_get_functiondef(v_procedure)) IS DISTINCT FROM v_old
    THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_ROLLBACK_RESIDUE'; END IF;
  END LOOP;

  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
            WHERE codigo='IG-M107-VALIDATOR-TX-START-TIMING-002')
  THEN RAISE EXCEPTION 'M107_VALIDATOR_CLOCK_EKB_ALREADY_EXISTS'; END IF;
  INSERT INTO public.lf_error_knowledge(
    id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref)
  VALUES(
    gen_random_uuid(),'IG-M107-VALIDATOR-TX-START-TIMING-002','GOVERNANCE',
    'Validator cerraba con now() de inicio de transaccion y subestimaba tiempo real',
    'M10.7 run 932 reportaba 180105 ms, pero el ultimo chunk ocurrio 237494 ms tras Curator; run 931 reportaba 120015 ms vs 168882 ms. Cinco corridas tenian 0 ms porque created_at, curator_completed_at y validator_completed_at conservaban inicio transaccional. Los chunks usan clock_timestamp().',
    'El marcador terminal validator_completed_at=now() usaba transaction_timestamp() en vez de reloj real. El gap era de 15 a 57 segundos y algunos registros eran cero pese a existir seis chunks.',
    'TRANSACTION_START_TIME_USED_FOR_RUNTIME_ELAPSED',
    'Al completar Validator medir wall-clock mediante clock_timestamp(). Usar tiempos de chunks y receipts independientes como auditoria; nunca atribuir duration=0 a rendimiento, ni reescribir historia. Preservar invariantes Q0-Q8, guards, timeout y no cerrar CP3 sin benchmark material.',
    'El contrato SQL altera una sola expresion con pin MD5 de fuente, prueba rollback sentinel, readback exacto, y conserva avance M10.7=45%. Comparacion RO 931/932 y cinco ceros. La prueba futura focal debe confirmar nuevo timing en un run material.',
    'HIGH',1,now(),now(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7',
    'VALIDATED_TESTED','supabase://programacion.input_readiness_runs/932;supabase://programacion.input_validator_chunk_timings/932',
    now(),now(),'PREFLIGHT','R4_NO_CUESTIONA','LOUD_EARLY',
    'M10.7 validator timestamp correction on the existing governed validate_v2 SQL function',
    'supabase://programacion.fn_input_governance_validate_v2'
  );
END
$ig_m107_timing$;
