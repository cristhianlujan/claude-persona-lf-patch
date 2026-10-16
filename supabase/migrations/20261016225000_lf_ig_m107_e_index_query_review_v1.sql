-- IG M10.7 / E: observational SQL plan audit. No index, schema, function or trigger change.
-- Read-only EXPLAIN ANALYZE of four existing queries, EKB evidence only.
DO $audit$
DECLARE
 v_codes text[]:=ARRAY[
   'proposals_by_run','proposal_distinct_sources','families_by_run','screen_rule_links'];
 v_queries text[]:=ARRAY[
  'SELECT id,proposal_kind,source_refs FROM programacion.input_gap_proposals WHERE run_id=933 AND validator_outcome=''PASS'' ORDER BY id',
  'SELECT DISTINCT r.ref FROM programacion.input_gap_proposals p CROSS JOIN LATERAL jsonb_array_elements(p.source_refs) r(ref) WHERE p.run_id=933 AND p.validator_outcome=''PASS''',
  'SELECT id,family_code,source_refs FROM programacion.input_family_assessments WHERE run_id=933 ORDER BY family_code',
  'SELECT rp.regla_id,r.codigo,r.estado FROM lf_ops.reglas_pantallas rp JOIN lf_ops.reglas r ON r.id=rp.regla_id WHERE rp.pantalla_id=43'
 ];
 v_index_names text[]:=ARRAY[
  'idx_input_gap_proposals_run','input_family_assessments_run_id_family_code_key',
  'idx_reglas_pantallas_screen','reglas_pkey'];
 v_existing integer; v_index text; v_plan jsonb; v_item jsonb;
 v_observations jsonb:='[]'::jsonb;
 v_i integer;
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='IG-M107-E-INDEX-QUERY-REVIEW-038')
 THEN RAISE EXCEPTION 'IG_M107_E_AUDIT_ALREADY_RECORDED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036')
 THEN RAISE EXCEPTION 'IG_M107_E_D_PROOF_MISSING'; END IF;
 IF (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
 THEN RAISE EXCEPTION 'IG_M107_E_BASELINE_RUN_MISSING'; END IF;
 FOREACH v_index IN ARRAY v_index_names LOOP
  SELECT count(*) INTO v_existing FROM pg_indexes
  WHERE schemaname IN ('programacion','lf_ops') AND indexname=v_index;
  IF v_existing<>1 THEN
   RAISE EXCEPTION 'IG_M107_E_EXPECTED_INDEX_MISSING:%',v_index;
  END IF;
 END LOOP;
 FOR v_i IN 1..4 LOOP
  EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '||v_queries[v_i] INTO v_plan;
  IF jsonb_typeof(v_plan)<>'array'
   OR v_plan->0->>'Execution Time' IS NULL
   OR v_plan->0->>'Planning Time' IS NULL
  THEN RAISE EXCEPTION 'IG_M107_E_SQL_PLAN_NOT_OBSERVED:%',v_codes[v_i]; END IF;
  v_item:=jsonb_build_object(
    'query',v_codes[v_i],
    'execution_ms',(v_plan->0->>'Execution Time')::numeric,
    'planning_ms',(v_plan->0->>'Planning Time')::numeric,
    'rows',(v_plan#>>'{0,Plan,Actual Rows}')::bigint,
    'shared_hit_buffers',(v_plan#>>'{0,Plan,Shared Hit Blocks}')::bigint,
    'root_node',v_plan#>>'{0,Plan,Node Type}',
    'actual_plan',v_plan->0->'Plan');
  v_observations:=v_observations||jsonb_build_array(v_item);
 END LOOP;
 IF jsonb_array_length(v_observations)<>4
 THEN RAISE EXCEPTION 'IG_M107_E_AUDIT_INCOMPLETE'; END IF;

 INSERT INTO public.lf_error_knowledge(
   id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
   validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
   created_at,updated_at,lifecycle_phase,root_cause_family,detectability,
   source_context,source_ref)
 VALUES(
  gen_random_uuid(),'IG-M107-E-INDEX-QUERY-REVIEW-038','GOVERNANCE',
  'M10.7 E: comprobar indices y planes antes de proponer cambios',
  'Auditoría de SELECT sin cambios de estructura para propuestas, referencias distintas, familias y vínculos de reglas sobre pantalla 43/run 933. Todos los planes y métricas se obtienen con EXPLAIN ANALYZE BUFFERS en Migration Train.',
  'El costo dominante observado proviene del grafo/manifiesto y llamadas repetidas, no de ausencia demostrada de índices en las consultas pequeñas examinadas.',
  'INDEX_CHANGE_ONLY_AFTER_REAL_PLAN_PROOF',
  'No crear índices adicionales sobre rutas ya indexadas por run/pantalla sin medir ganancia y write overhead. Comparar fuente idéntica; no inferir SLO o p90 de planes SELECT.',
  'Cuatro EXPLAIN ANALYZE FORMAT JSON completados, índices relevantes existentes; sin DDL, triggers ni cambios en Validator. La auditoría por sí sola no acredita optimización global ni CP3.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),
  'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_E','ACTIVO',
  jsonb_build_object(
   'schema_version','IG_M107_E_INDEX_PLAN_AUDIT_V1',
   'screen_id',43,'historical_run_id',933,
   'observations',v_observations,
   'index_names',to_jsonb(v_index_names),
   'queries_audited',4,
   'new_indexes_created',0,
   'runtime_or_triggers_changed',false,
   'microbench_only',true,'CP3_closed',false,
   'source_age_warning','RUN933_COMPLETED_SOURCE_MAY_BE_STALE')::text,
  clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO',
  'LOUD_EARLY','Migration Train read-only explain audit on historical sample',
  'supabase/migrations/lf_ig_m107_e_index_query_review_v1.sql'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge
    WHERE codigo='IG-M107-E-INDEX-QUERY-REVIEW-038')<>1
 THEN RAISE EXCEPTION 'IG_M107_E_EKB_REGISTRATION_FAILED'; END IF;
END $audit$;