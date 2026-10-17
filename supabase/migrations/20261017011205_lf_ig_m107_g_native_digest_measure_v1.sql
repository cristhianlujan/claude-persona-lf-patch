-- M10.7 G: read-only work inside one SQL migration to size a SQL-native
-- transport opportunity. No behavior, guard, trigger, permissions or runtime changes.
-- A/B/C is diagnostic, NOT an authorization to replace per-family readbacks.
DO $g$
DECLARE
 v_graph jsonb; v_contract jsonb; v_ctx jsonb; v_ref jsonb;
 v_resolved jsonb; v_graph_sha text; v_contract_sha text;
 v_computed_sha text; v_expected_graph text;
 v_t0 timestamptz; v_ms numeric;
 v_a jsonb:='[]'::jsonb; v_b jsonb:='[]'::jsonb;
 v_c jsonb:='[]'::jsonb; v_negative text;
 v_i int; v_round int; v_actual text; v_phase text;
 v_evals int:=12; v_n int:=0; v_prior_context text;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='IG-M107-G-NATIVE-SNAPSHOT-DIGEST-COST-040')
 THEN RAISE EXCEPTION 'IG_M107_G_METRIC_ALREADY_PRESENT'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN (
  'IG-M107-F-TRUSTED-BACKEND-LOADER-028',
  'IG-M107-POST-BCD-FULLRUN-TIMING-039',
  'IG-M107-RUN-PROJECTION-PROVIDER-026'))<>3
 THEN RAISE EXCEPTION 'IG_M107_G_EKB_PRECEDENTS_MISSING'; END IF;
 IF (SELECT status FROM programacion.input_readiness_runs WHERE id=944)<>'COMPLETED'
    OR (programacion.fn_input_run_source_currentness_v1(944)->>'source_current')<>'true'
 THEN RAISE EXCEPTION 'IG_M107_G_SOURCE_NOT_CURRENT'; END IF;
 IF (SELECT count(*) FROM programacion.input_family_assessments WHERE run_id=944)<>47
 THEN RAISE EXCEPTION 'IG_M107_G_FAMILY_COHORT_UNEXPECTED'; END IF;
 v_prior_context:=current_setting('lf.input_request_context_v1',true);
 IF coalesce(v_prior_context,'')<>'' THEN
   RAISE EXCEPTION 'IG_M107_G_PREEXISTING_GRAPH_CONTEXT'; END IF;
 BEGIN
  SELECT c.especificacion INTO STRICT v_contract
   FROM programacion.contratos c WHERE c.version_id=19
     AND c.contrato_codigo='INPUT_READINESS_CONTRACT'
     AND c.estado='defined' AND c.fail_closed
   ORDER BY c.id DESC LIMIT 1;
  v_graph:=programacion.fn_input_screen_canonical_graph(43,19);
  v_graph_sha:=programacion.fn_v09_sha256_jsonb(v_graph);
  v_contract_sha:=programacion.fn_v09_sha256_jsonb(v_contract);
  v_ref:='{"kind":"SCREEN_CANONICAL_GRAPH","pantalla_id":43}'::jsonb;
  v_ctx:=jsonb_build_object(
    'schema_version','INPUT_GOVERNANCE_REQUEST_CONTEXT_V1',
    'pantalla_id',43,'version_id',19,'graph',v_graph,
    'graph_sha256',v_graph_sha);
  PERFORM set_config('lf.input_request_context_v1',v_ctx::text,true);
  -- Warm the same SQL cached-graph path outside the timers.
  v_resolved:=programacion.fn_input_resolve_source_ref(v_ref,43,19);
  IF v_resolved->>'observed_sha256' IS DISTINCT FROM v_graph_sha
  THEN RAISE EXCEPTION 'IG_M107_G_CANONICAL_SOURCE_DISAGREEMENT'; END IF;

  -- Each arm is one exact SQL input, same transaction/source. A is the current
  -- deterministic assess's digest/readback subexpression, B omits only the
  -- resolver but retains graph+contract digest, C is a cached-value ceiling.
  -- Arm order rotates to reduce directional warming effects.
  FOR v_round IN 1..3 LOOP
   FOR v_i IN 1..3 LOOP
    v_phase:=(ARRAY['A','B','C'])[(v_i+v_round-2)%3+1];
    v_t0:=clock_timestamp();
    FOR v_n IN 1..v_evals LOOP
      IF v_phase='A' THEN
        v_resolved:=programacion.fn_input_resolve_source_ref(v_ref,43,19);
        v_computed_sha:=programacion.fn_v09_sha256_jsonb(v_graph);
        v_actual:=programacion.fn_v09_sha256_jsonb(v_contract);
      ELSIF v_phase='B' THEN
        v_computed_sha:=programacion.fn_v09_sha256_jsonb(v_graph);
        v_actual:=programacion.fn_v09_sha256_jsonb(v_contract);
      ELSE
        v_computed_sha:=v_graph_sha;
        v_actual:=v_contract_sha;
      END IF;
      IF v_computed_sha IS DISTINCT FROM v_graph_sha
        OR v_actual IS DISTINCT FROM v_contract_sha
        OR (v_phase='A' AND v_resolved->>'observed_sha256' IS DISTINCT FROM v_graph_sha)
      THEN RAISE EXCEPTION 'IG_M107_G_GRAPH_DIGEST_PARITY_FAILED:%',v_phase; END IF;
    END LOOP;
    v_ms:=round(extract(epoch FROM clock_timestamp()-v_t0)*1000,3);
    IF v_phase='A' THEN v_a:=v_a||to_jsonb(v_ms);
    ELSIF v_phase='B' THEN v_b:=v_b||to_jsonb(v_ms);
    ELSE v_c:=v_c||to_jsonb(v_ms); END IF;
   END LOOP;
  END LOOP;

  -- Existing fail-closed SHA guard MUST reject a corrupted context.
  PERFORM set_config('lf.input_request_context_v1',
    jsonb_set(v_ctx,'{graph_sha256}',to_jsonb(repeat('0',64)),true)::text,true);
  BEGIN
    PERFORM programacion.fn_input_screen_canonical_graph(43,19);
  EXCEPTION WHEN OTHERS THEN v_negative:=SQLERRM; END;
  IF position('INPUT_REQUEST_CONTEXT_GRAPH_SHA_MISMATCH' in coalesce(v_negative,''))=0
  THEN RAISE EXCEPTION 'IG_M107_G_NEGATIVE_SHA_NOT_REJECTED:%',v_negative; END IF;
  PERFORM set_config('lf.input_request_context_v1',v_ctx::text,true);

  IF (programacion.fn_input_run_source_currentness_v1(944)->>'source_current')<>'true'
  THEN RAISE EXCEPTION 'IG_M107_G_SOURCE_CHANGED_DURING_PROBE'; END IF;
  PERFORM set_config('lf.input_request_context_v1',coalesce(v_prior_context,''),true);
 EXCEPTION WHEN OTHERS THEN
   PERFORM set_config('lf.input_request_context_v1',coalesce(v_prior_context,''),true);
   RAISE;
 END;
 IF jsonb_array_length(v_a)<>3 OR jsonb_array_length(v_b)<>3
    OR jsonb_array_length(v_c)<>3 THEN
   RAISE EXCEPTION 'IG_M107_G_BENCHMARK_INCOMPLETE'; END IF;

 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
 source_context,source_ref)
 VALUES(gen_random_uuid(),'IG-M107-G-NATIVE-SNAPSHOT-DIGEST-COST-040','GOVERNANCE',
 'M10.7 G: medir digest/relectura de Curator SQL sin activar otro transporte',
 'Tres rondas rotadas de 12 operaciones comparan las expresiones actuales de SHA y readback del Curator contra variantes diagnósticas con el mismo grafo, contrato y transacción. No modifica runtime.',
 'En 47 evaluaciones deterministas, el contexto ya aporta el grafo en memoria pero la función vuelve a ejecutar resolución y SHA por familia. El provider JavaScript F exige otra transacción READ ONLY y no es acoplable directamente al worker escritor.',
 'NATIVE_WORKER_CONTEXT_AND_DIGEST_COST_PROBE',
 'Conservar separación y currentness de autoridad; no saltar validadores Q0-Q8, trigger ni SHA. Hacer piloto de equivalencia con negativos y medir tiempo total antes de proponer sustitución. No atribuir ahorro real a variante C (caché hipotética).',
 'A: resolver actual+SHA de grafo+SHA contrato. B: SHA grafo+SHA contrato. C: hashes precomputados (techo hipotético, no opción aprobada). Misma transacción, 3 rondas, 12 repeticiones/ronda, digest idéntico y contexto alterado rechazado.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/G','ACTIVO',
 jsonb_build_object('schema_version','IG_M107_G_NATIVE_DIGEST_MEASURE_V1',
 'run_id',944,'screen_id',43,'source_current',true,
 'samples_per_arm',3,'repetitions_per_sample',12,
 'current_subpath_ms',v_a,'without_source_resolver_ms',v_b,
 'cached_sha_ceiling_ms',v_c,
 'same_graph_sha256',v_graph_sha,'same_contract_sha256',v_contract_sha,
 'tampered_context_rejected',true,'negative_error',v_negative,
 'read_only_source_ops',true,'runtime_function_changes',false,
 'claimed_full_curator_savings',false,'provider_activated',false,
 'p90_measured',false,'CP3_closed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO',
 'LOUD_EARLY','Same-transaction readback and digest microbenchmark',
 'supabase/migrations/lf_ig_m107_g_native_digest_measure_v1.sql');
END $g$;