-- New EKB finding, open until safe publication/coexistence is governed.
BEGIN;
DO $ekb$
DECLARE v_code constant text := 'LF-NUCLEO-MIGRATION-CANDIDATE-LEGACY-COEXISTENCE-20261121-001'; v_id uuid := gen_random_uuid();
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN RAISE EXCEPTION 'LF_EKB_AM_COEXISTENCE_DUPLICATE'; END IF;
 INSERT INTO public.lf_error_knowledge (
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
 primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref,created_at,updated_at)
 VALUES (v_id,v_code,'RULE_GOVERNANCE',
 'La asociación FK de una candidata migrada puede ocultar la regla legada antes de publicar',
 'La vista lf_ops.v_reglas_compat_v1 excluye una regla legada si existe nucleo_reglas.regla_legacy_id asociado y estado CANDIDATA o VIGENTE. Sin FK, conserva ambas entradas; publicar el mismo código produciría dos filas VIGENTE. Un juicio AUTO no acredita por sí solo un corte seguro del lector.',
 'La vista de compatibilidad equipara asociación de candidata con reemplazo; no separa trazabilidad de origen, identidad legada y corte operativo.',
 'CANDIDATE_LEGACY_FK_PREMATURE_REPLACEMENT',
 'En una migración de prueba preservar legadas: entrar por nucleo_regla_proponer_v1, registrar origen MIGRACION con referencias exactas y juicio completo ligado al hash del paquete, sin asignar regla_legacy_id ni publicar hasta una transición de coexistencia validada. No fabricar APROBAR ni confundir pruebas deterministas con juicio semántico. Revisar duplicación visible por código y lectores antes de habilitar publicación; no cerrar puertas antiguas sin aprobación.',
 'PASE 44880886628 PG17: 10 candidatas, 10 juicios CONTEXTO_ACTUAL con siete criterios, 10 evaluaciones; 10 hashes falsos rechazados por NUCLEO_JUICIO_HASH_DISTINTO y 9 intentos de publicación rechazados por NUCLEO_PUBLICAR_SIN_PROMOCION; 17/17 regresiones y 17/17 después de rollback. Nueve DEVUELTA, REG_CHK_007 AUTO nota 97 sin publicar. La prueba existente del puente verifica ocultamiento al asignar FK. SELECT después del Train: diez candidatas, cero vigentes, cero FK, 586 legadas idénticas.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4517','ACTIVO',
 'Train 44880939661 SUCCESS; merge a323d4284cd5bccf351a2b615987933a52a6d1a7; migración 20261121074000; hash legado antes/después 156c7faa4cf529d084c1cd808e75f1d5; vista compatibilidad 586 a 596 filas (10 candidatas sin id). 70 puntajes documentados en sandbox/lf_contract_gate_test/nucleo_ci/checkout_am_juicios_v1.json. Pendiente solución técnica de coexistencia/publicación; tres decisiones de producto sin resolver.',
 'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY',
 'AM piloto PAYMENTS_CHECKOUT y corte seguro de lector legado','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4517',clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code AND id=v_id AND estado='ACTIVO' AND pr='#4517') <> 1 THEN RAISE EXCEPTION 'LF_EKB_AM_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
