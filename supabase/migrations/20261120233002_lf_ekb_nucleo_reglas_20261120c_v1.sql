-- EKB del núcleo de reglas, 2026-11-20 (bloque B): 1 registro. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261120235000_lf_ekb_nucleo_reglas_20261120c_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = 'LF-AUTOTEST-NULL-PASSES-AS-SUCCESS-20261120-001') THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261120C_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-AUTOTEST-NULL-PASSES-AS-SUCCESS-20261120-001','Testing/Programming Quality',
  'Autoprueba PL/pgSQL aceptaba NULL como éxito y tomaba solo la primera fila',
  'En el bloque B del núcleo, la autoprueba del cierre automático de versiones usaba IF NOT v_ok: con v_ok NULL no fallaba; y las pruebas de versión usaban SELECT INTO (primera fila). Una mutación que quitaba el cierre automático sobrevivió.',
  'Lógica de tres valores de SQL: NOT NULL es NULL y el IF lo trata como falso; SELECT INTO descarta filas adicionales.',
  'NULL_AS_SUCCESS_IN_ASSERTION',
  'En autopruebas usar IS NOT TRUE / IS DISTINCT FROM y exigir cardinalidad exacta (string_agg o count); validar cada autoprueba con pruebas de mutación antes de publicar.',
  '8/8 mutaciones detectadas tras la corrección; PR #4468 aplicado por el Train con 10/10 autopruebas.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4468','RESUELTO',
  'Prueba de mutación local: mutación sin cierre de versiones sobrevivió antes de la corrección',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R4_NO_CUESTIONA','SILENT',
  'Núcleo de reglas bloque B, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
