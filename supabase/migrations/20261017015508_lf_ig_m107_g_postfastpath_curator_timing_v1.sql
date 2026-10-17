-- M10.7/G post-fastpath same-source Curator timing with forced REBIND.
-- One migration; rollback TEMP run; no production runtime, schema, rules, trigger changes.
-- This is NOT an end-to-end or same-strategy Curator comparison with run 944.
DO $measure$
DECLARE
 v_id bigint; v_identity text; v_out jsonb; v_spans jsonb;
 v_baseline_deterministic_ms numeric; v_curator_ms numeric;
 v_deterministic_ms numeric; v_semantic_ms numeric;
 v_source_sha text; v_parent_sha text;
 v_before_count int; v_family_count int; v_positive int;
 v_t0 timestamptz; v_wall_ms numeric;
 v_rollback boolean:=false;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge
  WHERE codigo='IG-M107-G-POSTFASTPATH-CURATOR-TIMING-042') THEN
  RAISE EXCEPTION 'IG_M107_G_POSTBENCH_ALREADY_RECORDED'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
  ('IG-M107-G-NATIVE-SNAPSHOT-DIGEST-COST-040',
   'IG-M107-G-CURATOR-SQL-FASTPATH-041',
   'IG-M107-POST-BCD-FULLRUN-TIMING-039'))<>3
 THEN RAISE EXCEPTION 'IG_M107_G_EKB_PRECHECK_FAILED'; END IF;
 IF position('pg_trigger_depth()>0' in pg_get_functiondef(
    'programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)'::regprocedure))=0
 THEN RAISE EXCEPTION 'IG_M107_G_FASTPATH_NOT_INSTALLED'; END IF;
 IF (programacion.fn_input_run_source_currentness_v1(944)->>'source_current') IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'IG_M107_G_BASELINE_SOURCE_NOT_CURRENT'; END IF;
 SELECT source_snapshot_sha256 INTO STRICT v_parent_sha
  FROM programacion.input_readiness_runs WHERE id=944 AND status='COMPLETED'
  AND pantalla_id=43;
 IF EXISTS(SELECT 1 FROM programacion.ig_direct_requests_v1 WHERE status='QUEUED')
  OR EXISTS (SELECT 1 FROM programacion.input_readiness_runs
   WHERE pantalla_id=43 AND status IN ('CURATING','VALIDATING'))
 THEN RAISE EXCEPTION 'IG_M107_G_WORKER_NOT_IDLE'; END IF;
 SELECT count(*) INTO v_before_count FROM programacion.input_readiness_runs WHERE pantalla_id=43;
 SELECT sum((payload->>'elapsed_ms')::numeric) INTO v_baseline_deterministic_ms
  FROM programacion.provenance_receipts
  WHERE subject_ref='input-readiness-run:944'
   AND subject_type='IG_PERFORMANCE_TIMING'
   AND payload->>'phase'='RESOLVER'
   AND payload->>'resolver_code'='programacion.fn_input_deterministic_assess(jsonb,text,jsonb,jsonb)';
 IF v_baseline_deterministic_ms IS NULL OR v_baseline_deterministic_ms<=0
 THEN RAISE EXCEPTION 'IG_M107_G_BASELINE_DETERMINISTIC_TELEMETRY_MISSING'; END IF;
 BEGIN
  v_identity:='INPUT_CURATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
  v_t0:=clock_timestamp();
  v_out:=programacion.fn_input_governance_curator_materialize_v1(
   43,'MANUAL',v_identity,true);
  v_wall_ms:=round(extract(epoch from (clock_timestamp()-v_t0))*1000,3);
  v_id:=(v_out->>'run_id')::bigint;
  IF v_out->>'status' IS DISTINCT FROM 'VALIDATOR_RUNTIME_REQUIRED'
   OR v_out->>'run_status' IS DISTINCT FROM 'CURATING'
   OR (v_out->>'parent_run_id')::bigint IS DISTINCT FROM 944
   OR v_out#>>'{request_context_summary,graph_build_exactly_once}' IS DISTINCT FROM 'true'
   OR v_out#>>'{performance_observation,capture_status}' IS DISTINCT FROM 'OBSERVED'
   OR v_out#>>'{performance_observation,strategy}' IS DISTINCT FROM 'REBIND'
  THEN RAISE EXCEPTION 'IG_M107_G_POSTBENCH_CURATOR_CONTRACT_MISMATCH'; END IF;
  v_spans:=v_out#>'{performance_observation,per_family_resolver_spans}';
  IF jsonb_typeof(v_spans) IS DISTINCT FROM 'array' OR jsonb_array_length(v_spans)<>47
  THEN RAISE EXCEPTION 'IG_M107_G_POSTBENCH_SPAN_COUNT_INVALID'; END IF;
  SELECT sum((s->>'deterministic_elapsed_ms')::numeric),
         sum((s->>'semantic_elapsed_ms')::numeric)
   INTO v_deterministic_ms,v_semantic_ms
   FROM jsonb_array_elements(v_spans) s;
  v_curator_ms:=(v_out#>>'{performance_observation,sql_total_elapsed_ms}')::numeric;
  IF v_deterministic_ms IS NULL OR v_deterministic_ms<=0
   OR v_curator_ms<=0 OR v_wall_ms<=0
  THEN RAISE EXCEPTION 'IG_M107_G_POSTBENCH_MEASUREMENT_MISSING'; END IF;
  SELECT count(*),count(*) FILTER (
    WHERE a.curator_evidence->'core_invocation'->>'contract'='M5_4_DETERMINISTIC_ASSESS_BRIDGE_V1'
    AND a.curator_evidence->'core_invocation'->>'result_sha256' ~ '^[0-9a-f]{64}$')
   INTO v_family_count,v_positive FROM programacion.input_family_assessments a
   WHERE a.run_id=v_id;
  IF v_family_count<>47 OR v_positive<>47 THEN
    RAISE EXCEPTION 'IG_M107_G_POSTBENCH_FAMILY_PROOF_INCOMPLETE:%:%',
      v_family_count,v_positive; END IF;
  SELECT source_snapshot_sha256 INTO v_source_sha
   FROM programacion.input_readiness_runs WHERE id=v_id;
  -- A CURATING REBIND has not yet pinned its final Validator source manifest.
  -- Its parent is the current completed run. Do not falsely assert same source SHA
  -- if source_snapshot_sha256 remains unset here.
  IF (SELECT scope->>'mode' FROM programacion.input_readiness_runs WHERE id=v_id)
    IS DISTINCT FROM 'RUNTIME_ASSERTION_REBIND_SAFE_SUCCESSOR_V1'
  THEN RAISE EXCEPTION 'IG_M107_G_POSTBENCH_REBIND_MODE_MISSING'; END IF;

  RAISE EXCEPTION 'IG_M107_G_ROLLBACK_MEASUREMENT_ONLY' USING ERRCODE='PZ127';
 EXCEPTION WHEN SQLSTATE 'PZ127' THEN v_rollback:=true;
 END;
 IF NOT v_rollback
  OR v_family_count<>47 OR v_positive<>47
  OR (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_before_count
  OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_id)
  OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_id)
  OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_id)
  OR (programacion.fn_input_run_source_currentness_v1(944)->>'source_current') IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION 'IG_M107_G_POSTBENCH_ROLLBACK_OR_CURRENTNESS_FAILED'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
 validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
 source_context,source_ref)
 VALUES(
 gen_random_uuid(),'IG-M107-G-POSTFASTPATH-CURATOR-TIMING-042','GOVERNANCE',
 'M10.7 G: medición nativa Curator posterior al fastpath de grafo',
 'Una pantalla, fuente padre run944 CURRENT, 47 familias en autoprueba REBIND con rollback y telemetría real por familia. Comparación orientativa con RESOLVER de 944, ya que 944 fue SOURCE_STALE_RECURATE y este fixture es REBIND.',
 'El Curator evita reconstruir el grafo en la evaluación determinista dentro del trigger confiable. Antes de G solo había una cota de costo, sin corrida medible posterior.',
 'POST_FASTPATH_CURATOR_SAME_SCREEN_REBIND_TELEMETRY',
 'Comparar resolver de 47 familias, no extrapolar REBIND a SOURCE_STALE_RECURATE ni declarar reducción de solicitud completa. Conservar identidad, SHA, currentness, triggers y rollback.',
 'Train: 47 core receipts, 47 spans, estado CURATING, estrategia REBIND, una sola construcción de grafo, rollback 0 residuos, padre run944 CURRENT. Baseline determinista extraído de los receipts de 944. No cierra CP3 ni atribuye mejora integral.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/G',
 'ACTIVO',jsonb_build_object(
   'schema_version','IG_M107_G_POSTFASTPATH_CURATOR_FOCAL_V1',
   'screen_id',43,'parent_run_id',944,'rolled_back_run_id',v_id,
   'parent_source_snapshot_sha256',v_parent_sha,
   'rebinding_snapshot_sha256',v_source_sha,
   'base_strategy','SOURCE_STALE_RECURATE',
   'measurement_strategy','REBIND',
   'baseline_deterministic_ms',v_baseline_deterministic_ms,
   'post_deterministic_ms',v_deterministic_ms,
   'post_semantic_ms',v_semantic_ms,
   'post_curator_sql_total_ms',v_curator_ms,
   'post_curator_wall_ms',v_wall_ms,
   'deterministic_observed_delta_pct',
     round(100*(v_baseline_deterministic_ms-v_deterministic_ms)/v_baseline_deterministic_ms,2),
   'family_receipts_passed',v_positive,'family_spans_count',jsonb_array_length(v_spans),
   'graph_build_exactly_once',true,'rollback_clean',true,
   'validator_run',false,'full_e2e_gain_proven',false,'causal_gain_proven',false,
   'CP3_closed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'One-screen same-parent timed REBIND Curator, no endpoint activation',
 'supabase/migrations/lf_ig_m107_g_postfastpath_curator_timing_v1.sql');
END $measure$;