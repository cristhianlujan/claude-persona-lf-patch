-- Single new EKB finding: A4 direct legacy reader regression control.
BEGIN;
DO $ekb$
DECLARE v_code constant text := 'LF-NUCLEO-A4-DIRECT-LEGACY-READER-CI-20261121-001'; v_id uuid := gen_random_uuid();
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN RAISE EXCEPTION 'LF_EKB_A4_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge (
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
 primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref,created_at,updated_at)
 VALUES (v_id,v_code,'RULE_GOVERNANCE',
 'Nuevas funciones podían introducir lectura directa de las reglas legadas LF',
 'La transición A4 requiere que los nuevos consumidores usen las puertas de lectura, sin recrudecer el acople a lf_ops.reglas.',
 'No existía un control de admisión de nuevas definiciones SQL lectoras en PASE.',
 'NEW_DIRECT_LEGACY_RULE_READER',
 'Inspeccionar las definiciones nuevas o modificadas en SQL de producción del diff exact-head, sin rechazar retrospectivamente las definiciones históricas sin cambio. Bloquear lectores directos, referencias ambiguas y SQL dinámico no resoluble por el control; usar la vista de compatibilidad o la puerta del núcleo. No confundir el análisis estático con prueba completa de ejecución de SQL generado fuera de las fuentes inspeccionadas.',
 'PASE 44875891351 positivo, 44875954913 negativo: de dos funciones de sonda solo el lector directo se bloqueó con DIRECT_LEGACY_READ, exit 1; recertificación 44875993789: 10 positivos y 14 negativos, núcleo PG17 15/15, fallo inducido y 15/15 tras rollback.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4511','RESUELTO',
 'Train 44876049350 SUCCESS; merge d65d9139ded49c75968d5cec59005bef65127604; readback de tres blobs idénticos en main; SELECT producción 0 funciones de sonda',
 'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY',
 'Criterio A4 del plan de núcleo LF/SALY','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4511',clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code AND id=v_id AND estado='RESUELTO' AND pr='#4511') <> 1 THEN
 RAISE EXCEPTION 'LF_EKB_A4_READBACK_FAILED';
 END IF;
END $ekb$;
COMMIT;
