-- EKB del núcleo de reglas, 2026-11-20 (ciclo 17:47): 2 registros. Solo EKB.
BEGIN;
DO $ekb$
DECLARE
 v_src text := 'supabase/migrations/20261120230500_lf_ekb_nucleo_reglas_20261120b_v1.sql';
 v_codes text[] := ARRAY['LF-MIGRATION-NO-TRANSACTION-PARTIAL-APPLY-20261120-001','LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001']::text[];
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo = ANY(v_codes)) THEN
   RAISE EXCEPTION 'LF_EKB_NUCLEO_20261120B_CODE_ALREADY_EXISTS';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
  primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,root_cause_family,
  detectability,source_context,source_ref,created_at,updated_at)
 VALUES
 (gen_random_uuid(),'LF-MIGRATION-NO-TRANSACTION-PARTIAL-APPLY-20261120-001','SQL',
  'Migración con validación fail-closed sin BEGIN/COMMIT deja objetos creados a medias',
  'En la prueba local del PR #4463, el DO que aborta por reglas sin familia falló pero la tabla creada antes quedó persistida, porque cada sentencia se confirmaba por separado.',
  'La validación fail-closed estaba dentro de la migración pero no toda la migración estaba en una única transacción.',
  'FAIL_CLOSED_WITHOUT_ATOMICITY',
  'Toda migración con validaciones que pueden abortar va envuelta en BEGIN/COMMIT; probar el caso de fallo y verificar que no queda ningún objeto.',
  'Postgres local: con BEGIN/COMMIT el fallo deja la tabla inexistente (rollback completo). PR #4463 fusionado.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4463','RESUELTO',
  'Prueba local: tabla existía tras NUCLEO_REGLA_SIN_FAMILIA antes de la corrección',
  'MIGRATION_PREFLIGHT',ARRAY['CLAUDE_NATIVE','PROGRAMADOR']::text[],'R2_NO_VE','SILENT',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp()),
 (gen_random_uuid(),'LF-NUCLEO-IG-FAMILIES-WITHOUT-RULES-20261120-001','RULE_GOVERNANCE',
  '18 familias de IG no tienen ninguna regla asignada',
  'Tras asignar familia a las 586 reglas (PR #4463), 18 de las 47 familias de IG quedan sin reglas: IDEMPOTENCY_CONCURRENCY, DEPENDENCIES, NEGATIVE_REQUIREMENTS, FRESHNESS_INVALIDATION, APPLICABILITY_READINESS, OBJECTIVE_OUTCOMES, PROFILES, VISUAL_EVIDENCE, ROLLOUT_PRODUCTION_GATES, REDUCED_MOTION, SCREEN_IDENTITY, I18N_FORMATS, SOURCE_AUTHORITY_PROVENANCE, CONTEXT_BUDGET_RETRIEVAL_POLICY, EKB, ACTIONS, FORCED_COLORS_CONTRAST, CONFLICT_PRECEDENCE.',
  'IG evalúa estas familias por pantalla (input_family_assessments) pero el catálogo de reglas nunca recibió reglas para ellas.',
  'FAMILY_WITHOUT_RULES',
  'Toda familia activa debe tener su set mínimo de reglas o quedar EN_FORMACION; completar por IG/T_REMED.',
  'SELECT sobre lf_ops.nucleo_regla_familia y lf_ops.nucleo_familias (solo lectura).',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'LF_NUCLEO_REGLAS_20261120','#4463','ACTIVO',
  'Medición en Supabase tras el Train del PR #4463',
  'RULE_GOVERNANCE',ARRAY['CLAUDE_NATIVE','INPUT_GOVERNANCE']::text[],'R3_NO_PRIORIZA','SILENT',
  'Núcleo de reglas F0, 2026-11-20',v_src,clock_timestamp(),clock_timestamp());
END $ekb$;
COMMIT;
