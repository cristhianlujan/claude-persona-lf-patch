-- Resolve the already recorded legacy coexistence hazard; register a distinct revision dead end.
-- No rule/version, approval, product decision, or old reader is changed by this EKB-only migration.
BEGIN;
DO $ekb$
DECLARE
 existing_code constant text := 'LF-NUCLEO-MIGRATION-CANDIDATE-LEGACY-COEXISTENCE-20261121-001';
 new_code constant text := 'LF-NUCLEO-INITIAL-CANDIDATE-REVISION-DEADEND-20261121-001';
 v_id uuid := gen_random_uuid(); v_n integer;
BEGIN
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=existing_code AND estado='ACTIVO' AND pr='#4517' AND md5(evidencia)='76fadd76277a98133df55d98aa216d63')<>1 THEN
  RAISE EXCEPTION 'AM_EKB_EXISTING_EVIDENCE_DRIFT'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=new_code) THEN RAISE EXCEPTION 'AM_EKB_DUPLICATE_REVISION'; END IF;
 UPDATE public.lf_error_knowledge
 SET estado='RESUELTO',ultima_vez=clock_timestamp(),updated_at=clock_timestamp(),
 prevencion=concat_ws(E'\n',prevencion,'Corrección #4524: vista de compatibilidad conserva cada legada sin condición; las reglas de núcleo ligadas por FK, código o referencia de origen MIGRACION lf_ops.reglas quedan solo en la superficie nativa. No equivale a cutover ni autorización de publicación.'),
 validacion=concat_ws(E'\n',validacion,'PG17 PASE 44883064124 positivo; 44883134661 negativo por AM_COEX_V6_ORIGIN_DUPLICATE; 44883228388 recertificado positivo, PUENTE 8/8 y 17/17 regresiones tras rollback.'),
 evidencia=concat_ws(E'\n',evidencia,'PR #4524, merge 65b1de5615abfb34505e8d617b9f3e9bbbb07075, Train 44883288508 SUCCESS; migración 20261121081500 blob 219791f1fdef20bf94a4f66994fc002c5d3e87e8. SELECT: 586 legadas, huella anterior y posterior 156c7faa4cf529d084c1cd808e75f1d5, vista 586, faltantes/distintas 0, extra con id 0, códigos duplicados 0, 10 candidatas v1, 0 nuevas versiones, 0 PUBLICADA. Resuelto ocultamiento prematuro/duplicación en vista legada, no publicación ni cambio de ruta de consumidores.')
 WHERE codigo=existing_code AND estado='ACTIVO';
 GET DIAGNOSTICS v_n=ROW_COUNT;
 IF v_n<>1 THEN RAISE EXCEPTION 'AM_EKB_UPDATE_CARDINALITY %',v_n; END IF;
 INSERT INTO public.lf_error_knowledge (
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
 primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref,created_at,updated_at)
 VALUES(v_id,new_code,'RULE_GOVERNANCE','La primera versión candidata devuelta no admite remediación por la puerta actual',
 'CAMBIO en nucleo_regla_proponer_v1 rechaza una versión candidata abierta. nucleo_version_descartar_v1 descarta la candidata y deja RETIRADA la regla que nunca se publicó; el control 0 de CAMBIO rechaza RETIRADA. Cambiar alcance tampoco está admitido por CAMBIO.',
 'La ruta de cambio fue probada para reglas con una versión publicada previa, pero no para remediar la primera candidata nunca publicada.',
 'INITIAL_CANDIDATE_REVISION_DEADEND',
 'No descartar ni publicar una primera candidata real como atajo. Diseñar revisión canónica atómica que conserve contenido, juicio, pruebas y hash de versión previa; crear otra CANDIDATA, enlazar motivo y autoridad real y reevaluar con nuevo hash. Definir expresamente cómo revisar alcance sin reasignar una regla vigente. No escribir filas directamente ni atribuir aprobación al productor.',
 'PASE 44883228388 PG17: PUENTE 8/8, V8 verifica el rechazo específico de CAMBIO con candidata abierta, luego el descarte de sonda no publicada produce RETIRADA y CAMBIO vuelve a rechazar; rollback conserva datos. No se descartó ni editó una versión real del piloto.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4524','ACTIVO',
 'PR #4524 merge 65b1de5615abfb34505e8d617b9f3e9bbbb07075, Train 44883288508 SUCCESS. SELECT producción: 10 CANDIDATA versión 1, 9 DEVUELTA y 1 AUTO, 10 juicios CONTEXTO_ACTUAL/revisor_es_productor=true/llamadas_modelo=0, 0 v2 y 0 PUBLICADA. Pendiente ruta de revisión gobernada; no inventar aprobación ni completar AM.',
 'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY',
 'AM piloto PAYMENTS_CHECKOUT, bloqueo de remediación primera candidata','https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4524',clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=existing_code AND estado='RESUELTO')<>1 OR
    (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=new_code AND id=v_id AND estado='ACTIVO')<>1 THEN
  RAISE EXCEPTION 'AM_EKB_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
