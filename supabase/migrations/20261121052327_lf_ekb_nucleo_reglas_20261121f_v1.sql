-- EKB del núcleo de reglas, 2026-11-21 (motor de cálculo, profundidad por forma y piloto PAYMENTS_CHECKOUT): 4 hallazgos. Solo EKB.
BEGIN;
DO $ekb$
DECLARE v_src text := 'supabase/migrations/20261121080000_lf_ekb_nucleo_reglas_20261121f_v1.sql';
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('LF-NUCLEO-DEPTH-REQUIRED-ALL-CASES-20261121-001','LF-LEGACY-CHECKOUT-COMMISSION-TEXT-VS-CONFIG-20261121-001','LF-LEGACY-RULE-REFERENCES-MISSING-FIELD-20261121-001','LF-LEGACY-CHECKOUT-RULES-DUPLICATED-20261121-001')) THEN RAISE EXCEPTION 'LF_EKB_NUCLEO_20261121F_CODE_ALREADY_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES
  (gen_random_uuid(),'LF-NUCLEO-DEPTH-REQUIRED-ALL-CASES-20261121-001','RULE_GOVERNANCE',
  'La evaluación del núcleo exigía a cada regla todas las casuísticas de su naturaleza',
  'Al evaluar el piloto PAYMENTS_CHECKOUT (11 reglas estructuradas), toda regla CONDUCTA debía cubrir EN/BAJO/SOBRE_EL_LIMITE aunque fuera sí/no, y cualquier casuística propia de la familia se exigía a todas las reglas de la familia: la profundidad quedaba en 3 a 4 sobre 100 sin que faltara ninguna prueba con sentido.',
  'El filtro de casuísticas requeridas solo usaba naturaleza y familia; no consideraba la forma de la condición.',
  'DEPTH_REQUIREMENT_IGNORES_CONDITION_SHAPE',
  'Derivar la exigencia de la condición: UMBRAL (compara contra un parámetro) exige los tres límites; CATEGORICA exige SE_CUMPLE y NO_SE_CUMPLE. No crear casuísticas por regla a nivel de familia.',
  'nucleo_autotest_profundidad_v1 13/13 en LF y SALY, mutación 9/9; piloto con ROLLBACK: las 11 reglas sin motivo de profundidad.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4500','RESUELTO',
  'lf_ops.nucleo_regla_evaluar_v1, lf_ops.nucleo_forma_condicion_v1',
  'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','LOUD_EARLY',
  'Núcleo de reglas, piloto PAYMENTS_CHECKOUT, 2026-11-21',v_src,clock_timestamp(),clock_timestamp()),
  (gen_random_uuid(),'LF-LEGACY-CHECKOUT-COMMISSION-TEXT-VS-CONFIG-20261121-001','RULE_GOVERNANCE',
  'Reglas de checkout fijan una comisión LF de 2 % que la configuración real del aliado no cobra',
  'REG_CHK_006 (texto) y REG_NIU_002 (valor_config 0.02) dicen comisión LF 2 % + Niubiz 3,5 %; public.lf_b2b_pricing_config tiene management_fee_type NONE y niubiz_fee_value 0.035. El porcentaje además está escrito con dos formatos (2 y 0.02).',
  'Los porcentajes se copiaron como datos fijos dentro de reglas en vez de leerse de la configuración de precios del aliado.',
  'FIXED_DATA_IN_RULE_DIVERGES_FROM_CONFIG',
  'La regla estructurada no lleva porcentajes: exige mostrar toda comisión configurada (tipo distinto de NONE) y lee los valores de lf_b2b_pricing_config. Decisión de producto pendiente sobre si la comisión LF existe.',
  'Consulta de solo lectura en producción del 2026-11-21 y piloto con ROLLBACK de la regla REG_CHK_006 estructurada (CANDIDATA, 0 bloqueos).',
  'HIGH',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4499','ACTIVO',
  'lf_ops.reglas 210 y 226; public.lf_b2b_pricing_config',
  'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R2_NO_VE','SILENT',
  'Núcleo de reglas, piloto PAYMENTS_CHECKOUT, 2026-11-21',v_src,clock_timestamp(),clock_timestamp()),
  (gen_random_uuid(),'LF-LEGACY-RULE-REFERENCES-MISSING-FIELD-20261121-001','RULE_GOVERNANCE',
  'Una regla legada se da por resuelta con un campo que no existe en ninguna tabla',
  'REG_CHK_CUO_003 dice RESUELTO con un campo configurable por aliado acepta_yape_en_cuotas; information_schema no tiene ninguna columna con ese nombre ni similar. La regla parece cerrada pero su mecanismo no existe.',
  'La resolución se registró como texto en la descripción sin crear ni enlazar el dato que la implementa.',
  'RESOLUTION_TEXT_WITHOUT_IMPLEMENTATION',
  'Al estructurar, cada hecho de la condición debe existir (columna o hecho registrado); registrar el faltante como decisión pendiente y no como resuelto.',
  'Consulta de solo lectura a information_schema.columns del 2026-11-21: 0 columnas con yape o acepta_cuota.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4499','ACTIVO',
  'lf_ops.reglas 286',
  'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R5_EROSION_PROCESO','SILENT',
  'Núcleo de reglas, piloto PAYMENTS_CHECKOUT, 2026-11-21',v_src,clock_timestamp(),clock_timestamp()),
  (gen_random_uuid(),'LF-LEGACY-CHECKOUT-RULES-DUPLICATED-20261121-001','RULE_GOVERNANCE',
  'La familia de checkout repite la misma regla en dos o tres versiones',
  'Al estructurar PAYMENTS_CHECKOUT, 22 reglas legadas se reducen a 11 reglas del núcleo; además 25 de las 61 son textos o diseño de pantalla sin condición evaluable (copys, modales, logos, pantalla de éxito).',
  'Distintas olas de captura (CHK, CHK_CUO, NIU, SUC, CLIENT_*) registraron la misma decisión sin buscar la existente, y la tabla de reglas también recibió especificaciones de pantalla.',
  'DUPLICATED_RULES_ACROSS_CAPTURE_WAVES',
  'Al migrar, consolidar en una regla del núcleo con el enlace a todas sus legadas; separar los textos de pantalla de las reglas evaluables.',
  'Piloto con ROLLBACK del 2026-11-21: 11 reglas estructuradas que absorben 22 legadas, todas CANDIDATA sin bloqueos.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261121','#4499','ACTIVO',
  'lf_ops.reglas de la familia PAYMENTS_CHECKOUT (61)',
  'VALIDATION',ARRAY['CLAUDE_NATIVE','PROGRAMADOR','INPUT_GOVERNANCE']::text[],'R5_EROSION_PROCESO','SILENT',
  'Núcleo de reglas, piloto PAYMENTS_CHECKOUT, 2026-11-21',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
