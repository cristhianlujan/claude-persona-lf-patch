-- EKB del núcleo de reglas, 2026-11-21 (bloque D y promoción legada): 4 registros. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261121004000_lf_ekb_nucleo_reglas_20261121a_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('LF-SQL-WHERE-NOT-NULL-EXCLUDES-MISSING-20261121-001','LF-JSONB-OPERATOR-PRECEDENCE-20261121-001','LF-MUTANT-KILLED-BY-SYNTAX-NOT-EVIDENCE-20261121-001','LF-PROMOTION-SCORE-SECDEF-PUBLIC-EXECUTE-20261121-001')) THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121A_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-SQL-WHERE-NOT-NULL-EXCLUDES-MISSING-20261121-001','ENGINEERING_VALIDATION','Filtro WHERE NOT (...) dejaba pasar un criterio faltante de la rúbrica','Al registrar un juicio, la búsqueda de criterios faltantes usaba WHERE ... AND NOT (puntaje es número AND ...). Si el criterio no venía, la expresión interna era NULL, NOT NULL es NULL y la fila se excluía: el criterio faltante no se reportaba y el juicio incompleto se aceptaba.','Lógica de tres valores en un filtro: la misma causa que la autoprueba con NULL del bloque B, ahora en código de producción y en un WHERE en lugar de un IF.','NULL_EXCLUDED_BY_NEGATED_FILTER','Para buscar lo que no cumple, usar (condición) IS NOT TRUE en vez de NOT (condición); aplicarlo en WHERE, IF y CHECK cuando un operando puede faltar.','Autoprueba E3 falló antes de la corrección y pasa después; mutante D02 muerto. PR #4475.','HIGH',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4475','RESUELTO','Autoprueba E3 del bloque D',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','SILENT',
  'Núcleo de reglas bloque D, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-JSONB-OPERATOR-PRECEDENCE-20261121-001','PROGRAMMING_GOVERNANCE','Precedencia de operadores jsonb: base->pruebas - 2 se leyó como base -> (pruebas - 2)','En una autoprueba, base->pruebas - 2 (quitar el tercer elemento) falló con invalid input syntax for type integer: los operadores -> y - tienen la misma precedencia y se asocian de otra forma a la esperada.','Operadores jsonb sin paréntesis explícitos.','JSONB_OPERATOR_PRECEDENCE','Encerrar entre paréntesis cada acceso jsonb antes de combinarlo con otro operador: (base->pruebas) - 2.','Corrección aplicada; autopruebas E7 y E9 pasan. PR #4475.','LOW',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4475','RESUELTO','Aplicación local del bloque D',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R1_NO_SABE','LOUD_EARLY',
  'Núcleo de reglas bloque D, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-MUTANT-KILLED-BY-SYNTAX-NOT-EVIDENCE-20261121-001','Testing/Programming Quality','Mutantes contados como muertos por error de sintaxis, y mutantes incompletos contados como sobrevivientes','En la prueba de mutación del bloque D, dos mutantes murieron por error de sintaxis o por una construcción no soportada (no por una aserción). En la promoción legada, una mutación que solo anulaba un operando de un OR parecía sobrevivir, aunque el resto de la condición seguía detectando el caso.','Se contaba como muerto cualquier fallo de la migración, y la mutación no anulaba el comportamiento completo que se quería probar.','INVALID_MUTANT_COUNTED','Contar un mutante como muerto solo si falla con el mensaje de la aserción esperada (NUCLEO_AUTOTEST_FALLA o el código de verificación); diseñar cada mutación para anular el comportamiento completo (por ejemplo, el RAISE) y no un operando.','Mutantes rehechos: bloque D 25/25 muertos por aserción; promoción legada 5/5. PR #4475 y #4477.','MEDIUM',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4477','RESUELTO','Prueba de mutación de los bloques D y legado',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R4_NO_CUESTIONA','SILENT',
  'Núcleo de reglas bloque D, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-PROMOTION-SCORE-SECDEF-PUBLIC-EXECUTE-20261121-001','GOVERNANCE','lf_rule_promotion_score_v1 es SECURITY DEFINER con EXECUTE para PUBLIC','Al parametrizar la promoción legada se observó que la función corre con los permisos de su dueño y que cualquier rol puede ejecutarla (incluidos anon y authenticated): lee lf_ops.reglas y pasos de ejecución que esos roles no ven directamente.','Permiso por defecto de PostgreSQL (EXECUTE a PUBLIC) no revocado en una función SECURITY DEFINER.','SECDEF_PUBLIC_EXECUTE','En la etapa de seguridad, revocar EXECUTE de PUBLIC, anon y authenticated en funciones SECURITY DEFINER y otorgarlo solo a los roles que la llaman; auditar el resto de funciones con el mismo patrón.','Pendiente: no se cambió en el PR #4477 para no mezclar cambio de permisos con la parametrización.','MEDIUM',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4477','ACTIVO','Lectura de permisos de lf_rule_promotion_score_v1',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','SILENT',
  'Núcleo de reglas bloque D, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
