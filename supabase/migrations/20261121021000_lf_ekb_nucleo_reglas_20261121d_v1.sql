-- EKB del núcleo de reglas, 2026-11-21 (acople reversible): 1 hallazgo nuevo y 1 recurrencia. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261121021000_lf_ekb_nucleo_reglas_20261121d_v1.sql'; v_n integer;
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = 'LF-NUCLEO-LEGACY-RULES-NOT-EVALUABLE-20261121-001') THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121D_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-NUCLEO-LEGACY-RULES-NOT-EVALUABLE-20261121-001','GOVERNANCE',
  'Ninguna de las 586 reglas legadas es evaluable por la puerta del núcleo',
  'El modo sombra (lf_ops.lf_legado_sombra) evaluó las 586 reglas de lf_ops.reglas con la puerta del núcleo: 0 aceptables. Las 586 carecen de condición y efecto estructurados y de pruebas, y su origen (167 etiquetas distintas) no corresponde a ninguna autoridad registrada; 252 aplican a varias pantallas y necesitan derivar su alcance en el árbol. Todas tienen familia asignada.',
  'Las reglas se registraron como texto con metadatos en valor_config, sin un contrato que exigiera condición, pruebas ni autoridad.',
  'LEGACY_RULES_TEXT_ONLY',
  'Migrar con una ruta explícita: mapear las 167 etiquetas de origen a autoridades, estructurar condición, efecto y pruebas por familia, derivar el alcance común de las reglas de varias pantallas, y que cada regla pase la misma puerta que una nueva.',
  'Corrida de sombra del PR #4488 en producción: 586 evaluadas, 0 sin explicar, brechas SIN_ESTRUCTURA 586, SIN_PRUEBAS 586, SIN_AUTORIDAD_REGISTRADA 586, ALCANCE_POR_DERIVAR 252.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4488','ACTIVO',
  'lf_ops.lf_legado_sombra, corrida inicial de la migración 20261121020000',
  'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R5_EROSION_PROCESO','SILENT',
  'Núcleo de reglas, acople reversible, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
 UPDATE public.lf_error_knowledge
    SET frecuencia = frecuencia + 1, ultima_vez = clock_timestamp(), updated_at = clock_timestamp(),
        evidencia = evidencia || ' | Recurrencia 2026-11-21 (PR #4488): lf_ops.reglas local con columnas en otro orden que producción; una comparación EXCEPT por posición falló. Se reconstruyó el stub con el orden real y la prueba compara por nombre.'
  WHERE codigo = 'LF-LOCAL-STUB-SCHEMA-DRIFT-20261120-001';
 GET DIAGNOSTICS v_n = ROW_COUNT;
 IF v_n <> 1 THEN RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121D_RECURRENCIA_NO_ENCONTRADA'; END IF;
END $ekb$;
COMMIT;
