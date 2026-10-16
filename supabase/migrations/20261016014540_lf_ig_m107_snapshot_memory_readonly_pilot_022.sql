-- IG M10.7: documented read-only snapshot pilot. No runtime changes.
DO $p$
DECLARE v_code text := 'IG-M107-INMEM-SNAPSHOT-PILOT-022';
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
 THEN RAISE EXCEPTION 'DUPLICATE_M107_PILOT_EKB'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM programacion.input_readiness_runs
 WHERE id=933 AND pantalla_id=43 AND version_id=19
 AND source_snapshot_sha256='0e542fbc90da9092ea20989bab49b746822286666b6c985d016ae4d04b1e3cce'
 ) THEN RAISE EXCEPTION 'SOURCE_IDENTITY_MISMATCH'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
 frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,created_at,updated_at,
 lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES(gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7: primera prueba de reutilizacion de snapshot en memoria',
 'Piloto de solo lectura: run 933, pantalla 43, 5 familias, 246 reglas, 2 contratos.',
 'Extracciones duplicadas de datos de entrada por familia.',
 'REPEATED_INPUT_EXTRACTION',
 'Una unica extraccion por ejecucion, snapshot inmutable, decisiones independientes y currentness vigente.',
 '3 pares baseline vs snapshot: 3032/627, 3638/452 y 2832/536 ms, 60/60 comparaciones exactas, 5 consultas vs 1. Microbenchmark, NO rendimiento del runtime.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','EKB-022','ACTIVO',
 '{"schema_version":"IG_M107_MEMORY_PILOT_V1","run_id":933,"rules":246,"contracts":2,"families":5,"baseline_ms":[3032,3638,2832],"optimized_ms":[627,452,536],"identical_checks":60,"checks_passed":60,"full_runtime_tested":false,"g3_active":false,"cp3_closed":false}',
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'Read-only input data microbenchmark, no runtime write',
 'docs/ig/IG_M107_SNAPSHOT_MEMORY_READONLY_PILOT_V1.md');
END $p$;
