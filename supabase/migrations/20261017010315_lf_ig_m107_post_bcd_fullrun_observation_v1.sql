-- M10.7 post-B/C/D full runtime observation. EKB ONLY; no functional DDL.
-- Cross-source before/after is descriptive, NOT same-source causality or p90.
DO $obs$
DECLARE
 v_old_req programacion.ig_direct_requests_v1%rowtype;
 v_new_req programacion.ig_direct_requests_v1%rowtype;
 v_old_run programacion.input_readiness_runs%rowtype;
 v_new_run programacion.input_readiness_runs%rowtype;
 v_old_chunks record; v_new_chunks record;
 v_old_full_ms numeric; v_new_full_ms numeric;
 v_old_curator_ms numeric; v_new_curator_ms numeric;
 v_old_queue_ms numeric; v_new_queue_ms numeric;
 v_old_tail_ms numeric; v_new_tail_ms numeric;
 v_old_families integer; v_new_families integer;
 v_old_proposals integer; v_new_proposals integer;
 v_fresh jsonb;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
     WHERE codigo='IG-M107-POST-BCD-FULLRUN-TIMING-039')
 THEN RAISE EXCEPTION 'IG_M107_FULLRUN_OBSERVATION_ALREADY_REGISTERED'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
   ('IG-M107-B-ACTIVE-GUARD-ONEPASS-033',
    'IG-M107-C-SEMANTIC-GRAPH-CONDITIONAL-035',
    'IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036',
    'IG-M107-E-INDEX-QUERY-REVIEW-038'))<>4
 THEN RAISE EXCEPTION 'IG_M107_BCD_EKB_DEPENDENCIES_INCOMPLETE'; END IF;

 SELECT * INTO STRICT v_old_req FROM programacion.ig_direct_requests_v1 WHERE id=18;
 SELECT * INTO STRICT v_new_req FROM programacion.ig_direct_requests_v1 WHERE id=19;
 SELECT * INTO STRICT v_old_run FROM programacion.input_readiness_runs WHERE id=933;
 SELECT * INTO STRICT v_new_run FROM programacion.input_readiness_runs WHERE id=944;

 IF v_old_req.status<>'DONE' OR v_new_req.status<>'DONE'
   OR v_old_req.last_status<>'READY' OR v_new_req.last_status<>'READY'
   OR v_old_req.error_code IS NOT NULL OR v_new_req.error_code IS NOT NULL
   OR v_old_req.last_run_id<>933 OR v_new_req.last_run_id<>944
   OR v_old_run.status<>'COMPLETED' OR v_new_run.status<>'COMPLETED'
   OR v_old_run.pantalla_id<>43 OR v_new_run.pantalla_id<>43
   OR v_old_run.version_id IS DISTINCT FROM v_new_run.version_id
   OR v_old_req.step_count<>8 OR v_new_req.step_count<>8
 THEN RAISE EXCEPTION 'IG_M107_FULLRUN_REQUEST_OR_ROUTE_DIFFERENCE'; END IF;

 SELECT count(*),sum(duration_ms) compute_ms,sum(coalesce(assertions_ms,0)) assertions_ms,
  sum(coalesce(db_write_ms,0)) db_write_ms,
  sum(coalesce(gap_proposals_ms,0)) proposals_ms,
  sum(coalesce(wait_resume_ms,0)) wait_ms,sum(families_processed) families_processed
 INTO v_old_chunks FROM programacion.input_validator_chunk_timings WHERE run_id=933;
 SELECT count(*),sum(duration_ms) compute_ms,sum(coalesce(assertions_ms,0)) assertions_ms,
  sum(coalesce(db_write_ms,0)) db_write_ms,
  sum(coalesce(gap_proposals_ms,0)) proposals_ms,
  sum(coalesce(wait_resume_ms,0)) wait_ms,sum(families_processed) families_processed
 INTO v_new_chunks FROM programacion.input_validator_chunk_timings WHERE run_id=944;
 SELECT count(*),count(*) FILTER (WHERE validator_outcome='PASS')
 INTO v_old_families,v_new_families FROM programacion.input_family_assessments WHERE run_id=933;
 IF v_old_families<>47 OR v_new_families<>47 THEN
   RAISE EXCEPTION 'IG_M107_BASELINE_47_FAMILY_PASS_INCOMPLETE'; END IF;
 SELECT count(*),count(*) FILTER (WHERE validator_outcome='PASS')
 INTO v_old_families,v_new_families FROM programacion.input_family_assessments WHERE run_id=944;
 IF v_old_families<>47 OR v_new_families<>47 THEN
   RAISE EXCEPTION 'IG_M107_CANDIDATE_47_FAMILY_PASS_INCOMPLETE'; END IF;
 SELECT count(*) INTO v_old_proposals FROM programacion.input_gap_proposals
 WHERE run_id=933 AND validator_outcome='PASS';
 SELECT count(*) INTO v_new_proposals FROM programacion.input_gap_proposals
 WHERE run_id=944 AND validator_outcome='PASS';
 IF v_old_proposals<>20 OR v_new_proposals<>20
   OR v_old_chunks.count<>6 OR v_new_chunks.count<>6
   OR v_old_chunks.families_processed<>47 OR v_new_chunks.families_processed<>47
 THEN RAISE EXCEPTION 'IG_M107_20_PROPOSAL_OR_SIX_CHUNK_PARITY_FAILURE'; END IF;

 v_fresh:=programacion.fn_input_run_source_currentness_v1(944);
 IF v_fresh->>'source_current'<>'true'
  OR v_old_run.source_snapshot_sha256 IS NOT DISTINCT FROM v_new_run.source_snapshot_sha256
 THEN RAISE EXCEPTION 'IG_M107_NEW_SOURCE_FRESHNESS_OR_DRIFT_NOT_PROVEN'; END IF;
 v_old_full_ms:=round(extract(epoch from(v_old_req.finished_at-v_old_req.requested_at))*1000,3);
 v_new_full_ms:=round(extract(epoch from(v_new_req.finished_at-v_new_req.requested_at))*1000,3);
 v_old_queue_ms:=round(extract(epoch from(v_old_run.created_at-v_old_req.requested_at))*1000,3);
 v_new_queue_ms:=round(extract(epoch from(v_new_run.created_at-v_new_req.requested_at))*1000,3);
 v_old_curator_ms:=round(extract(epoch from(v_old_run.curator_completed_at-v_old_run.created_at))*1000,3);
 v_new_curator_ms:=round(extract(epoch from(v_new_run.curator_completed_at-v_new_run.created_at))*1000,3);
 v_old_tail_ms:=round(extract(epoch from(v_old_req.finished_at-v_old_run.validator_completed_at))*1000,3);
 v_new_tail_ms:=round(extract(epoch from(v_new_req.finished_at-v_new_run.validator_completed_at))*1000,3);
 IF v_old_full_ms<=0 OR v_new_full_ms<=0 OR
    v_old_run.validator_duration_ms<=0 OR v_new_run.validator_duration_ms<=0
 THEN RAISE EXCEPTION 'IG_M107_FULLRUN_CLOCK_METRICS_UNAVAILABLE'; END IF;

 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
 source_context,source_ref)
 VALUES (
 gen_random_uuid(),'IG-M107-POST-BCD-FULLRUN-TIMING-039','GOVERNANCE',
 'M10.7 rendimiento post B/C/D: 1 pantalla, Validator y solicitud completos',
 'Run 944 en ruta SQL activa, 47 familias y 20 propuestas PASS sin error, después de integrar B/C/D; readback de la solicitud #19 y de seis chunks, contrastados con run 933 de solicitud #18. Fuentes distintas: comparación observacional, no causal.',
 'Las optimizaciones locales demostraron equivalencia funcional pero no demostraban ahorro integral. La muestra posterior permite localizar el nuevo costo dominante; la variación de fuentes impide atribuir causalidad exacta.',
 'FULL_RUNTIME_CLOCKED_BEFORE_AFTER_WITH_SOURCE_DRIFT',
 'Medir por separado cola, Curator, Validator, assertions, escrituras/triggers, propuestas y esperas; usar identidad y SHA de ambas fuentes. Exigir mismo origen y réplicas para prueba causal/p90. No cerrar CP3 ni confundir el 45% de soak con ahorro.',
 'Solicitud #18/run 933 y solicitud #19/run 944 terminadas DONE/READY sin error; 47/47 familias, 20/20 propuestas, 6 chunks cada una. Duración total, por fase y source SHA verificados desde DB. Una muestra posterior no acredita p90.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/PERFORMANCE',
 'ACTIVO',jsonb_build_object(
  'schema_version','IG_M107_FULLRUN_POST_BCD_OBSERVATION_V1',
  'historical_request_id',18,'post_change_request_id',19,
  'historical_run_id',933,'post_change_run_id',944,'screen_id',43,
  'baseline_source_sha256',v_old_run.source_snapshot_sha256,
  'post_source_sha256',v_new_run.source_snapshot_sha256,
  'comparison_kind','CROSS_SOURCE_OBSERVATIONAL_NOT_EXACT_CAUSAL',
  'original_runtime',jsonb_build_object(
    'e2e_ms',v_old_full_ms,'queue_wait_ms',v_old_queue_ms,
    'curator_ms',v_old_curator_ms,'validator_ms',v_old_run.validator_duration_ms,
    'after_validator_ms',v_old_tail_ms,'chunks',v_old_chunks.count,
    'compute_ms',v_old_chunks.compute_ms,
    'assertions_ms',v_old_chunks.assertions_ms,
    'db_write_ms',v_old_chunks.db_write_ms,
    'proposal_ms',v_old_chunks.proposals_ms,'wait_ms',v_old_chunks.wait_ms),
  'post_bcd_runtime',jsonb_build_object(
    'e2e_ms',v_new_full_ms,'queue_wait_ms',v_new_queue_ms,
    'curator_ms',v_new_curator_ms,'validator_ms',v_new_run.validator_duration_ms,
    'after_validator_ms',v_new_tail_ms,'chunks',v_new_chunks.count,
    'compute_ms',v_new_chunks.compute_ms,
    'assertions_ms',v_new_chunks.assertions_ms,
    'db_write_ms',v_new_chunks.db_write_ms,
    'proposal_ms',v_new_chunks.proposals_ms,'wait_ms',v_new_chunks.wait_ms),
  'observed_e2e_reduction_pct',round(100*(v_old_full_ms-v_new_full_ms)/v_old_full_ms,2),
  'observed_validator_reduction_pct',round(100*(v_old_run.validator_duration_ms-v_new_run.validator_duration_ms)/v_old_run.validator_duration_ms,2),
  'families_passed',47,'proposals_passed',20,'request_steps',8,
  'negative_oracle_reexecuted',false,
  'causal_gain_proven',false,'p90_measured',false,'CP3_closed',false,
  'runtime_or_triggers_changed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO',
 'LOUD_EARLY','Two executed SQL queue runs with different authority source SHA',
 'supabase/migrations/lf_ig_m107_post_bcd_fullrun_observation_v1.sql');
END $obs$;