-- IG M10.7 — Only EKB documentary receipt for read-only SQL efficiency benchmark.
-- Router ACT-0001 / ACTUALIZACION_DB_LF; no changes to product/runtime/functions/triggers.
DO $ekb$
DECLARE
  v_code constant text := 'IG-M107-SQL-MATERIALIZATION-BENCHMARK-023';
  v_evidence jsonb;
BEGIN
  IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
  THEN RAISE EXCEPTION 'IG_M107_SQL_BENCHMARK_ALREADY_RECORDED'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM programacion.input_readiness_runs
    WHERE id=933 AND pantalla_id=43 AND version_id=19
      AND source_snapshot_sha256='0e542fbc90da9092ea20989bab49b746822286666b6c985d016ae4d04b1e3cce'
  ) THEN RAISE EXCEPTION 'IG_M107_SQL_BENCHMARK_SOURCE_IDENTITY_MISMATCH'; END IF;

  v_evidence := jsonb_build_object(
    'schema_version','IG_M107_SQL_MATERIALIZATION_BENCHMARK_V1',
    'reference_run',933,'screen_id',43,'version_id',19,
    'rule_count',246,'contract_count',2,'family_sample_count',5,
    'sql_hot_median_ms',jsonb_build_object(
       'multi_materialized',38.856,
       'multi_default',40.936,
       'once_materialized',44.922,
       'multi_not_materialized',154.985,
       'once_default',159.576),
    'plan_function_scans',jsonb_build_object(
       'multi_materialized',1,'multi_default',1,
       'once_materialized',1,'multi_not_materialized',6,'once_default',6),
    'all_five_payload_digests_equal',true,
    'direct_jsonb_materialized_equal_not_materialized',true,
    'direct_jsonb_materialized_equal_default',true,
    'materialize_all_ctes_unconditionally',false,
    'production_query_changed',false,
    'curator_validator_runtime_benchmarked',false,
    'g3_active',false,
    'cp3_closed',false,
    'scope','READ_ONLY_SQL_PLAN_MICROBENCHMARK',
    'document','docs/ig/IG_M107_SQL_MATERIALIZED_BENCHMARK_V1.md'
  );

  INSERT INTO public.lf_error_knowledge
  (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
   frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
   lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
  VALUES
  (gen_random_uuid(),v_code,'GOVERNANCE',
   'M10.7: eficiencia SQL y materializacion selectiva con reutilizacion del snapshot',
   'Prueba de lectura: cinco variantes SQL para pantalla 43 y run 933, mismos 246 vinculos, dos contratos y cinco familias, igualdad JSONB verificada.',
   'El plan puede repetir ejecuciones de la misma funcion costosa aunque la extraccion externa sea una sola consulta.',
   'SQL_REPEATED_EXPENSIVE_SUBQUERY',
   'Elegir CTE MATERIALIZED selectivamente por EXPLAIN ANALYZE BUFFERS y equivalencia; reducir N+1, evaluar indices/filtros, reutilizar snapshot en memoria; no forzar MATERIALIZED global.',
   'Tres pruebas SQL calientes por variante: medianas 38.856/40.936/44.922/154.985/159.576 ms, 1 frente a 6 Function Scan; JSONB igual. No es benchmark de Curator ni Validator.',
   'MEDIUM',1,clock_timestamp(),clock_timestamp(),
   'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',v_evidence::text,
   clock_timestamp(),clock_timestamp(),
   'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
   'Read-only SQL optimization proof; no runtime, policy or trigger mutation',
   'docs/ig/IG_M107_SQL_MATERIALIZED_BENCHMARK_V1.md');

  IF (SELECT COUNT(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
  THEN RAISE EXCEPTION 'IG_M107_SQL_BENCHMARK_EKB_READBACK_FAILED'; END IF;
END $ekb$;
