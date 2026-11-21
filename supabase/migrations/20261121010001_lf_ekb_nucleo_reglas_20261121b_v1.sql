-- EKB del núcleo de reglas, 2026-11-21 (bloque E): 1 registro. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261121011000_lf_ekb_nucleo_reglas_20261121b_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = 'LF-NUCLEO-VERSION-INSERT-EQUALS-PUBLISH-20261121-001') THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121B_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-NUCLEO-VERSION-INSERT-EQUALS-PUBLISH-20261121-001','ARCHITECTURE_GOVERNANCE',
  'Registrar una versión la publicaba: un cambio a una regla vigente entraba en efecto sin juicio',
  'En el bloque B del núcleo, insertar una versión la numeraba, cerraba la anterior y la dejaba vigente en el mismo momento. Con solo versiones 1 no se notaba; al diseñar la ruta de cambio (F3) se vio que una versión 2 de una regla VIGENTE habría entrado en efecto sin evaluación, juicio ni promoción.',
  'Se modeló el ciclo de vida en la regla y no en la versión; las fases F1 (versiones) y F2b (promoción) se diseñaron por separado.',
  'REGISTRATION_EQUALS_PUBLICATION',
  'Separar registro de publicación: cada versión nace CANDIDATA sin fechas y solo se publica con una evaluación AUTO o una aprobación sobre su contenido; revisar cada fase nueva contra el ciclo completo (registrar, evaluar, publicar, implementar).',
  'Corregido en PR #4479 antes de que existieran datos: autopruebas K6 (la candidata no entra en efecto) y K3 (no se publica sin promoción); mutantes E05 y E22 muertos.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4479','RESUELTO',
  'Revisión de diseño de la ruta de cambio del bloque E; tablas del núcleo vacías en producción al corregir',
  'DESIGN',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','SILENT',
  'Núcleo de reglas bloque E, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
