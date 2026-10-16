-- M10.7 selective snapshot reader candidate only. Router ACT-0001: registered owner
-- EDGE_FN_INPUT_GOVERNANCE_VALIDATOR_V1 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
-- This migration records EKB evidence; no runtime, grants or trigger mutation.
DO $ekb$
DECLARE v_code constant text := 'IG-M107-SELECTIVE-SNAPSHOT-READER-CANDIDATE-025';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code)
 THEN RAISE EXCEPTION 'IG_M107_SELECTIVE_READER_EKB_ALREADY_PRESENT'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge
                WHERE codigo='IG-M107-CONDITIONAL-SNAPSHOT-READER-CANDIDATE-024')
 THEN RAISE EXCEPTION 'IG_M107_SELECTIVE_READER_PREVIOUS_EKB_MISSING'; END IF;
 IF to_regprocedure('programacion.fn_input_governance_run_context_packet_v1(bigint)') IS NULL
 THEN RAISE EXCEPTION 'IG_M107_SELECTIVE_READER_PROVIDER_G1_MISSING'; END IF;
 INSERT INTO public.lf_error_knowledge
 (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
  validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,
  evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
  detectability,source_context,source_ref)
 VALUES
 (gen_random_uuid(),v_code,'GOVERNANCE',
 'M10.7 acceso selectivo a variables del snapshot por Curator y Validator',
 'Corrige el lector candidato previo: abre una vez por run y etapa, verifica SHA una sola vez, devuelve vistas por reglas/contratos/familias/paths del grafo; indices lazy sin copia completa en cada acceso.',
 'La version previa entregaba y clonaba el snapshot completo, incluso para un consumidor que necesita pocos campos.',
 'UNNECESSARY_FULL_SNAPSHOT_READER_COPY',
 'Reutilizar datos congelados en memoria y seleccionar solo secciones e IDs necesarios; no exigir leer todas las familias; preservar ausencia/fallback canonical y errores de integridad fail-closed.',
 'Suite selectiva 21 casos preparados en PR, positiva de referencias, negative identidad/tamper, independiente, secciones omitidas y lectura sin reconsulta; CI debe confirmar antes de fusion. No es integracion runtime ni benchmark de red.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),
 'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
 jsonb_build_object(
   'schema_version','IG_M107_SELECTIVE_SNAPSHOT_READER_V2',
   'previous_ekb','IG-M107-CONDITIONAL-SNAPSHOT-READER-CANDIDATE-024',
   'candidate_file','supabase/functions/_shared/ig_snapshot_reader_v1.mjs',
   'test_file','sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/test_m107_snapshot_reader_v1.mjs',
   'selectors',jsonb_build_array('rules_by_id','contracts_by_code','families_by_code','graph_by_path'),
   'lazy_per_section_indices',true,
   'sha_per_bound_snapshot',1,
   'full_clone_on_each_read',false,
   'full_snapshot_default_return',false,
   'requested_missing_section_fail_closed',true,
   'curator_wired',false,
   'validator_wired',false,
   'production_changed',false,
   'g3_active',false,
   'cp3_closed',false
 )::text,
 clock_timestamp(),clock_timestamp(),
 'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
 'Candidate-only selective reader, not runtime integration or measured speedup',
 'docs/ig/IG_M107_CONDITIONAL_SNAPSHOT_CONSUMER_ADAPTER_V1.md');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1
 THEN RAISE EXCEPTION 'IG_M107_SELECTIVE_READER_READBACK_FAILED'; END IF;
END $ekb$;
