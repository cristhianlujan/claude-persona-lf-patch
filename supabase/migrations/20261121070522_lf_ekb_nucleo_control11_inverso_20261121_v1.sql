-- One EKB record for F2 control 11 inverse. No other findings modified.
BEGIN;
DO $ekb$
DECLARE v_code constant text := 'LF-NUCLEO-CONTROL11-INVERSE-SCOPE-20261121-001'; v_id uuid := gen_random_uuid();
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN RAISE EXCEPTION 'LF_EKB_F2_INV_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge (
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
 primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref,created_at,updated_at)
 VALUES (v_id,v_code,'RULE_GOVERNANCE',
 'Control de alcance del núcleo sin sugerencia inversa de reducción',
 'El control 11 solo sugería elevar ante copias estructurales y no señalaba cuando las aplicaciones vigentes equivalentes se concentraban en un subárbol menor.',
 'El árbol y las aplicaciones vigentes no se recorrían para obtener un alcance descendiente común compatible con la clase.',
 'SCOPE_UPWARD_ONLY_NO_INVERSE_HINT',
 'En nucleo_regla_proponer_v1, usar únicamente aplicaciones de reglas vigentes con versiones publicadas actuales y misma clave, familia, naturaleza, condición y efecto. Sugerir el descendiente común más específico compatible con la clase; no sugerir sin evidencia, con aplicación al mismo alcance, con evidencia en ramas incompatibles ni en SOLO_AQUI. La señal es no bloqueante, no acredita exclusividad y no altera el alcance de la propuesta ni decide producto. Mantener paridad LF/SALY y prueba de mutación específica.',
 'PASE 44878036909 positivo: 10/10 por instancia, conjunto 17/17 y 17/17 tras rollback. PASE 44878084736 negativo: desactivar la sugerencia provoca F2_INV_I3_EXPECTED_SUGGESTION, exit 1. Recertificación tras renumerar 44878280646: 17/17, negativa detectada, 17/17 tras rollback. A4 PASS.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4515','RESUELTO',
 'Train 44878203952 SUCCESS, merge 6347fcdc522aeefdd874d1d2993562461d26ba8f, migración 20261121070125, blob 8aaa169deb6febd4af98b758a3a26a85adb05908; SELECT 4/4 cuerpos idénticos, ACL service_role, cero reglas en ambas instancias antes y después.',
 'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY',
 'Criterio F2 control 11 inverso, núcleo LF/SALY','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4515',clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code AND id=v_id AND estado='RESUELTO' AND pr='#4515') <> 1 THEN RAISE EXCEPTION 'LF_EKB_F2_INV_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
