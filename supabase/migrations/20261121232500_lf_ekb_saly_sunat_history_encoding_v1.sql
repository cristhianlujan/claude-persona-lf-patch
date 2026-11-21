BEGIN;
DO $ekb$
DECLARE
 k constant text := 'SALY-SUNAT-HISTORY-ENCODING-20261121-001';
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(k,0));
 IF NOT EXISTS (SELECT FROM public.lf_error_knowledge WHERE codigo=k) THEN
 INSERT INTO public.lf_error_knowledge(id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,created_at,updated_at)
 VALUES(gen_random_uuid(),k,'DATA_QUALITY','La lectura histórica del RUC falló al decodificar texto ajeno a la clave','El job 137018552394 descargó el archivo 202310 y falló con UnicodeDecodeError en un byte 0xD1.','El lector exigía UTF-8 a todas las columnas para comparar una clave ASCII.','UNRELATED_TEXT_ENCODING_ABORTS_KEY_LOOKUP','Preservar bytes al analizar la sintaxis CSV y comparar solo el RUC ASCII; verificar cabecera, SHA y CRC.','Prueba con Ñ de un byte y coma entrecomillada, más relectura de la fuente nacional en el job 137019577941.','MEDIUM',1,now(),now(),'SALY_U07_SUNAT_HISTORY','#4589','RESUELTO','Fallo 137018552394. Calificación 137019577941.','DESIGN',ARRAY['PROGRAMADOR'],'R2_NO_VE','LOUD_EARLY','SALY Ventas, lector histórico de RUC','https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/44961006766/job/137019577941',now(),now());
 END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=k AND pr='#4589' AND estado='RESUELTO')<>1
 THEN RAISE EXCEPTION 'SUNAT_EKB_READBACK_FAILED'; END IF;
END $ekb$;
COMMIT;
