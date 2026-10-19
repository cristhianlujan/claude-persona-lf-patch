-- IG M10.7 — record conditional data-only consumer candidate. No runtime mutation.
-- Router ACT-0001 -> ACTUALIZACION_DB_LF -> LF Migration Merge Train.
DO $ekb$
DECLARE v_code CONSTANT text:='IG-M107-CONDITIONAL-SNAPSHOT-READER-CANDIDATE-024';
BEGIN
  IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
    RAISE EXCEPTION 'IG_M107_CANDIDATE_EKB_ALREADY_EXISTS';
  END IF;
  IF to_regprocedure('programacion.fn_input_governance_run_context_packet_v1(bigint)') IS NULL THEN
    RAISE EXCEPTION 'IG_M107_CURRENT_PACKET_PROVIDER_MISSING';
  END IF;
  INSERT INTO public.lf_error_knowledge
  (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,
   frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,created_at,updated_at,
   lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
  VALUES(
    gen_random_uuid(),v_code,'GOVERNANCE',
    'M10.7 lector transversal condicional de snapshot, preparado sin activar consumidores',
    'Un lector data-only permite elegir entre un snapshot V2 integro y lectura canonica segun consumidor, etapa, identidad e integridad. El proveedor G1 real tiene referencias, no snapshot completo.',
    'No conectar Curator o Validator a metadatos de run G1 como si fueran el paquete completo.',
    'SNAPSHOT_CONSUMER_STAGE_AND_COMPLETENESS_GATE',
    'No consumir G1 como V2; no admitir cruce de run/etapa, identidad de Validator no independiente ni SHA adulterado. Cargar solo desde proveedor interno autorizado; mantener runtime existente hasta G3.',
    '11/11 casos unitarios locales PASS de lector candidato: positivo Curator/Validator con V2 simulado, G1 parcial/falta de paquete/etapa no aplicable, negativos de identidad, contenido, completitud e independencia. NO prueba integrada en runtime.',
    'MEDIUM',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    jsonb_build_object(
      'schema','IG_M107_CONDITIONAL_SNAPSHOT_READER_CANDIDATE_V1',
      'tests_local',11,'tests_passed',11,
      'current_g1_metadata_only',true,'current_g1_validating_only',true,
      'real_complete_v2_provider_available',false,
      'curator_runtime_consumer_wired',false,'validator_runtime_consumer_wired',false,
      'runtime_changed',false,'g3_active',false,'cp3_closed',false,
      'source','supabase/functions/_shared/ig_snapshot_reader_v1.mjs',
      'test','sandbox/lf_contract_gate_test/input_governance_runtime_candidate_judge/test_m107_snapshot_reader_v1.mjs',
      'design','docs/ig/IG_M107_CONDITIONAL_SNAPSHOT_CONSUMER_ADAPTER_V1.md'
    )::text,
    clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO','LOUD_EARLY',
    'Shared reader candidate, complete provider and runtime integration pending',
    'docs/ig/IG_M107_CONDITIONAL_SNAPSHOT_CONSUMER_ADAPTER_V1.md'
  );
  IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1 THEN
     RAISE EXCEPTION 'IG_M107_CANDIDATE_EKB_READBACK_FAILED';
  END IF;
END $ekb$;
