-- EKB del núcleo de reglas, 2026-11-21 (alcance derivado): 1 hallazgo. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261121024000_lf_ekb_nucleo_reglas_20261121e_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = 'LF-LEGACY-RULE-SCREEN-LINKS-PARTIAL-COVERAGE-20261121-001') THEN RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121E_CODE_ALREADY_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-LEGACY-RULE-SCREEN-LINKS-PARTIAL-COVERAGE-20261121-001','GOVERNANCE',
  'Las reglas legadas de varias pantallas cubren solo una parte de su módulo común',
  'El alcance derivado (lf_ops.lf_legado_alcance) de las 251 reglas legadas con varias pantallas muestra que solo 2 cubren todas las pantallas de su ancestro común; 248 cubren una parte (3.714 enlaces, mediana 62,5 % de las pantallas bajo su ancestro) y 1 enlaza una pantalla fuera del árbol. No se sabe si el enlace parcial es intencional o una copia incompleta.',
  'Los enlaces regla-pantalla se copiaron pantalla por pantalla (6.177 filas) sin un alcance declarado del que derivarlos.',
  'COPIED_LINKS_WITHOUT_SCOPE',
  'Decidir por regla o por familia si aplica a todo el módulo (heredar en el ancestro) o solo a esas pantallas (aplicaciones puntuales); registrar el alcance en el núcleo y dejar de copiar enlaces.',
  'Corrida del PR #4490 en producción: TRANSVERSAL 201, UNA_PANTALLA 134, HEREDA_EN_ANCESTRO 2, APLICACIONES_POR_PANTALLA 248, SIN_PANTALLAS_EN_ARBOL 1.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4490','ACTIVO',
  'lf_ops.lf_legado_alcance, corrida de la migración 20261121023000',
  'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R5_EROSION_PROCESO','SILENT',
  'Núcleo de reglas, alcance derivado, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
