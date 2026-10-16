-- IG M10.7 Lote A: consolidated read-only profiling and prior EKB readback.
-- EKB ONLY: no changes to runtime, functions, triggers, permissions, checkpoints or production.
-- Existing reference run 933 is COMPLETED and its source is historically stale:
-- no exact-source runtime performance or new p90 is claimed.
DO $ekb$
DECLARE
 v_code CONSTANT text := 'IG-M107-LOT-A-PROFILE-027';
 v_run record;
 v_families integer;
 v_compacted integer;
 v_distinct_sets integer;
 v_proposals integer;
 v_proposal_ref_sets integer;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'M107_LOT_A_EKB_ALREADY_EXISTS';
 END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M107-TRIGGER-ROLLBACK-PROFILE-008','IG-M107-TRANSVERSAL-EXECUTION-TELEMETRY-012',
  'IG-M107-ALL-STAGES-QUERY-INVENTORY-007'))<>3 THEN
   RAISE EXCEPTION 'M107_LOT_A_PREVIOUS_EKB_MISSING';
 END IF;
 SELECT id,pantalla_id,version_id,status,validator_duration_ms,source_snapshot_sha256
 INTO v_run FROM programacion.input_readiness_runs WHERE id=933;
 IF NOT FOUND OR v_run.pantalla_id<>43 OR v_run.version_id<>19
 OR v_run.status<>'COMPLETED' OR v_run.validator_duration_ms<>229436
 OR v_run.source_snapshot_sha256<>'0e542fbc90da9092ea20989bab49b746822286666b6c985d016ae4d04b1e3cce'
 THEN RAISE EXCEPTION 'M107_LOT_A_BASELINE_DRIFT'; END IF;
 SELECT count(*),count(*) FILTER(WHERE validator_evidence ? 'assertion_set_sha256'),
 count(DISTINCT validator_evidence->>'assertion_set_sha256')
 INTO v_families,v_compacted,v_distinct_sets
 FROM programacion.input_family_assessments WHERE run_id=933;
 SELECT count(*),count(DISTINCT source_refs::text)
 INTO v_proposals,v_proposal_ref_sets
 FROM programacion.input_gap_proposals WHERE run_id=933;
 IF v_families<>47 OR v_compacted<>47 OR v_distinct_sets<>19
 OR v_proposals<>20 OR v_proposal_ref_sets<>2
 THEN RAISE EXCEPTION 'M107_LOT_A_OBSERVATION_DRIFT'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES (
 gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7 lote A: mapa focal de costos y redundancia medido sin nueva corrida',
 'Se consolida el costo del Validator por fase y de los triggers familiares/propuestas a partir de EKB anterior y readback actual; no se requiere repetir la campana de medicion para priorizar B-E.',
 'Las escrituras y triggers absorben 122115ms de un Validator 229436ms. Una muestra rollback mide los guards individuales de familia y propuesta. Hay 47 evidencias compactadas pero 19 assertion sets distintos, y 20 propuestas con solo 2 conjuntos distintos de source_refs; esto indica potencial de reutilizacion, no ahorro demostrado.',
 'IG_M107_PER_RUN_FOCAL_COST_PROFILE',
 'Priorizar manifiesto y currentness repetidos (B), evaluaciones, grafo y rehidratacion (C), fuentes de propuestas (D) y consultas indexadas solo si se demuestra ganancia (E). Preservar Q0-Q8, currentness, 21 triggers, oraculos independientes, identidad y limite de 150s. No extrapolar muestra a runtime.',
 'EKB 008: EXPLAIN real con rollback, 1 UPDATE familia y 1 propuesta. Readback run933 6 chunks: db_write=122115ms, assertions=48773ms, proposals=34041ms, wait=21231ms. Readback SQL: 47/47 compactadas, 19 assertion sets distintos; 20 propuestas, 2 conjuntos distintos de refs. No fue posible ejecutar medicion focal de rehidratacion por ACL 42501; no simular sus tiempos. Lote A observacion completada, no optimizacion runtime.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_A','ACTIVO',
 jsonb_build_object(
 'schema_version','IG_M107_LOT_A_OBSERVATION_V1',
 'baseline_run_id',933,'baseline_screen_id',43,'baseline_historical_source_current',false,
 'validator_wall_ms',229436,'validator_db_write_ms',122115,
 'validator_assertions_ms',48773,'validator_gap_proposals_ms',34041,
 'validator_wait_resume_ms',21231,
 'family_guard_assessment_update_ms',894.075,
 'family_guard_execution_update_ms',426.558,
 'family_guard_currentness_update_ms',469.365,
 'family_guard_semantic_coherence_ms',223.794,
 'proposal_guard_validation_update_ms',1109.905,
 'proposal_guard_currentness_ms',504.385,
 'sample_family_update_count',1,'sample_proposal_update_count',1,
 'compacted_family_count',v_compacted,'distinct_assertion_sets',v_distinct_sets,
 'proposal_count',v_proposals,'distinct_proposal_ref_sets',v_proposal_ref_sets,
 'rehydration_direct_probe','DENIED_42501',
 'source_measurement_ekb','IG-M107-TRIGGER-ROLLBACK-PROFILE-008',
 'source_telemetry_ekb','IG-M107-TRANSVERSAL-EXECUTION-TELEMETRY-012',
 'source_inventory_ekb','IG-M107-ALL-STAGES-QUERY-INVENTORY-007',
 'optimization_wired',false,'runtime_changed',false,'cp3_closed',false
 )::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'Read-only historical run and prior isolated rollback trigger sample; no direct function execute rights',
 'supabase://public.lf_error_knowledge/IG-M107-TRIGGER-ROLLBACK-PROFILE-008'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'M107_LOT_A_EKB_READBACK_FAILED'; END IF;
END $ekb$;
