-- EKB del núcleo de reglas, 2026-11-20 (bloque C): 4 registros. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261120235500_lf_ekb_nucleo_reglas_20261120d_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('LF-NUCLEO-CONDITION-AS-STRING-BYPASS-20261120-001','LF-NUCLEO-CLOCK-TIMESTAMP-VS-NOW-20261120-001','LF-AUTOTEST-MASKED-CONTROL-20261120-001','LF-LOCAL-STUB-SCHEMA-DRIFT-20261120-001')) THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261120D_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-NUCLEO-CONDITION-AS-STRING-BYPASS-20261120-001','ENGINEERING_VALIDATION','Condición entregada como texto JSON eludía los controles de la puerta y colgaba el evaluador','En la puerta del núcleo, una condición pasada como cadena JSON (no objeto) no exponía hojas: los controles de vocabulario, datos fijos y parámetros no encontraban nada y pasaban; el evaluador recursaba sin fin (stack depth limit exceeded).','Los controles recorrían el árbol suponiendo que la condición ya tenía forma válida; no existía un control de forma y el evaluador no rechazaba nodos que no fueran objetos.','UNVALIDATED_AST_SHAPE','Validar la forma completa del árbol (hoja única o operador conocido con operandos) antes de inspeccionar su contenido; el evaluador debe fallar de inmediato ante un nodo inválido u operador desconocido.','Control de forma añadido; autopruebas C19, C19b, C20 y C21; mutantes M23-M26 muertos. Aplicado en PR #4472.','HIGH',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4472','RESUELTO','Prueba con una propuesta realista en modo evaluación: 86400 fijo no fue detectado y el evaluador dio stack depth limit exceeded',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','SILENT',
  'Núcleo de reglas bloque C, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-NUCLEO-CLOCK-TIMESTAMP-VS-NOW-20261120-001','PROGRAMMING_GOVERNANCE','Versión publicada con clock_timestamp() invisible para el resolvedor en la misma transacción','La puerta publicaba versiones con clock_timestamp() mientras el resolvedor filtra por publicada_desde <= now() (inicio de la transacción): una regla creada y consultada en la misma transacción no aparecía como efectiva y el control de conflicto con FIJA superior no la veía.','Mezcla de dos relojes: now() es fijo por transacción y clock_timestamp() avanza; el resolvedor y el escritor usaban relojes distintos.','MIXED_TRANSACTION_CLOCKS','Usar un solo reloj por operación: now() para fechas de vigencia que lee el resolvedor; clock_timestamp() solo para trazas.','Autoprueba C15 falló con clock_timestamp() y pasó con now(); mutante M06 muerto. PR #4472.','MEDIUM',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4472','RESUELTO','Autoprueba C15 de la migración del bloque C',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R1_NO_SABE','LOUD_EARLY',
  'Núcleo de reglas bloque C, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-AUTOTEST-MASKED-CONTROL-20261120-001','Testing/Programming Quality','Autoprueba aprobaba aunque el control probado estuviera roto porque otro control también rechazaba','La prueba de código repetido solo exigía RECHAZADA; el control de duplicado también rechazaba la misma propuesta, así que una mutación que anulaba el control de código sobrevivía. Lo mismo con un nodo ambiguo que otro chequeo capturaba.','La aserción verificaba el resultado global en lugar del control específico que se quería probar.','ASSERTION_ON_AGGREGATE_NOT_TARGET','Cada autoprueba negativa debe verificar que falló el control específico (por número o nombre), no solo el resultado global; confirmar con pruebas de mutación por control.','4 mutantes sobrevivientes (M20, M22, M23, M25) corregidos; 26/26 muertos. PR #4472.','MEDIUM',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4472','RESUELTO','Prueba de mutación local del bloque C',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R4_NO_CUESTIONA','SILENT',
  'Núcleo de reglas bloque C, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES (gen_random_uuid(),'LF-LOCAL-STUB-SCHEMA-DRIFT-20261120-001','ENGINEERING_VALIDATION','Esquema local de prueba de lf_global_config distinto del de producción','El stub local de public.lf_global_config solo tenía 4 columnas; la migración del bloque C falló localmente por value_type inexistente y faltaban claves que sí existen en producción.','El stub se armó con las columnas usadas en bloques anteriores, no desde el catálogo vigente de producción.','LOCAL_STUB_DRIFT','Antes de probar localmente, leer columnas y restricciones reales en producción (solo lectura) y alinear el stub; copiar las claves de configuración que la migración usa.','Stub alineado con value_type, value_status, description y created_at con sus CHECK; migración aplicada localmente y en producción sin diferencias.','LOW',1,
  clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4472','RESUELTO','Aplicación local del bloque C',
  'TEST',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','LOUD_EARLY',
  'Núcleo de reglas bloque C, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
