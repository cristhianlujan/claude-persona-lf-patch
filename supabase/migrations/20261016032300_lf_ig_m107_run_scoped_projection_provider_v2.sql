-- M10.7 run-scoped selective provider candidate, EKB-only receipt.
-- Router ACT-0001 -> registered EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1
-- -> ACTUALIZACION_DB_LF / LF Migration Merge Train.
-- NO SQL runtime function, trigger, policy, grant or production activation changes.
DO $ekb$
DECLARE v_code CONSTANT text := 'IG-M107-RUN-PROJECTION-PROVIDER-026';
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
 THEN RAISE EXCEPTION 'M107_PROJECTION_EKB_DUPLICATE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_error_knowledge
               WHERE codigo='IG-M107-SELECTIVE-SNAPSHOT-READER-CANDIDATE-025')
 THEN RAISE EXCEPTION 'M107_PROJECTION_READER_DEPENDENCY_MISSING'; END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.input_readiness_runs
   WHERE id=933 AND pantalla_id=43 AND version_id=19
     AND source_snapshot_sha256='0e542fbc90da9092ea20989bab49b746822286666b6c985d016ae4d04b1e3cce')
 THEN RAISE EXCEPTION 'M107_PROJECTION_EVIDENCE_SOURCE_DRIFT'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
  frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
  lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES (
 gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7 proveedor por run y proyeccion selectiva, candidato sin runtime',
 'Nueva capa auxiliar que carga una vez el dato congelado desde proveedor confiable, conserva memoria por ejecucion y entrega solo IDs/rutas solicitados a consumidores independientes.',
 'El lector selectivo anterior no vinculaba el loader compartido ni preparaba un handoff seleccionable entre procesos.',
 'RUN_SCOPED_SNAPSHOT_PROJECTION',
 'Una carga backend por run, seleccionar secciones por necesidad, agrupar proyecciones y enviar su SHA; conservar guard y autoridad. No crear caché global ni modificar las decisiones.',
 'Suite de regresion aislada preparada de 16 casos; CI verificara antes de merge. Probe SQL real 242017 bytes full vs 71116 bytes seleccion; 70.6% menos volumen en esta muestra. NO benchmark de runtime. Sin activar consumidores.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
 jsonb_build_object(
 'schema_version','IG_M107_RUN_SCOPED_PROJECTION_PROVIDER_V2',
 'previous_ekb','IG-M107-SELECTIVE-SNAPSHOT-READER-CANDIDATE-025',
 'provider_file','supabase/functions/_shared/ig_snapshot_projection_provider_v2.mjs',
 'test_file','sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/test_m107_projection_provider_v2.mjs',
 'ci_workflow','.github/workflows/ig-m107-projection-candidate-ci.yml',
 'historical_run_id',933,'screen_id',43,
 'full_payload_bytes',242017,'selected_payload_bytes',71116,
 'full_rule_count',246,'selected_rule_count',5,
 'full_family_count',47,'selected_family_count',5,
 'trusted_loader_wired',false,
 'curator_wired',false,'validator_wired',false,
 'runtime_modified',false,'g3_active',false,'cp3_closed',false
 )::text,
 clock_timestamp(),clock_timestamp(),
 'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'Candidate-only source-loaded once per run; no trusted backend loader integrated',
 'docs/ig/IG_M107_RUN_SCOPED_PROJECTION_PROVIDER_V2.md'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'M107_PROJECTION_EKB_READBACK_FAILURE'; END IF;
END $ekb$;
