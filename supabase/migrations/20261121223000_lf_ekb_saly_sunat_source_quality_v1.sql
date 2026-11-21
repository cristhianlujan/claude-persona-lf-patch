BEGIN;
DO $ekb$
DECLARE
 k constant text := 'SALY-SUNAT-REDUCED-RUC-INVALID-20261121-001';
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(k,0));
 IF NOT EXISTS (SELECT FROM public.lf_error_knowledge WHERE codigo=k) THEN
 INSERT INTO public.lf_error_knowledge(id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,created_at,updated_at)
 VALUES(gen_random_uuid(),k,'DATA_QUALITY','Una fila con RUC inválido abortó el cruce SUNAT','La sonda terminó con REDUCED_RUC_INVALID antes de emitir conteos.','Validación fatal de registro individual durante lectura de archivo íntegro.','INVALID_RECORD_ABORTS_SOURCE_JOIN','Contar rechazos por causa, excluir claves ambiguas y reconciliar. Conservar barreras de esquema, límites, SHA y CRC.','Job 137006725849: 1 RUC inválido, 5 filas de ancho incorrecto, 478657 coincidencias únicas con nombre y CRC verificado.','MEDIUM',1,now(),now(),'SALY_U07_SUNAT_JOIN','#4576','RESUELTO','Fallo 136998586470. Recuperación 137006725849.','DESIGN',ARRAY['PROGRAMADOR'],'R2_NO_VE','LOUD_EARLY','SALY Ventas, sondeo de cruce de padrones','https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44956839604/job/137006725849',now(),now());
 END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=k AND pr='#4576' AND estado='RESUELTO')<>1
 THEN RAISE EXCEPTION 'SUNAT_EKB_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
