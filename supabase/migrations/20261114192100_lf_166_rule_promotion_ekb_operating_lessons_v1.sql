-- LF promotion 166 operating lessons. EKB only, append by governed Train.
-- Never writes a rule, screen relation, owner identity proof or promotion.
BEGIN;
DO $ekb$
DECLARE v_n integer;
BEGIN
 IF to_regclass('public.lf_rule_promotion_documentary_owner_v1') IS NULL
    OR to_regclass('public.lf_rule_promotion_screen_diagnostic_v1') IS NULL
 THEN RAISE EXCEPTION 'LF_PROMO_EKB_READONLY_SOURCE_NOT_INSTALLED'; END IF;
 IF (SELECT count(*) FROM public.lf_rule_promotion_documentary_owner_v1
     WHERE rule_id IN (235,438,439,440,532,577)
       AND source_identity_assertion='false'
       AND identity_verified_effective=false)<>6
 THEN RAISE EXCEPTION 'LF_PROMO_EKB_B08_SIX_UNVERIFIED_READBACK_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_rule_promotion_screen_diagnostic_v1
     WHERE linked_screens<5)<>148
 THEN RAISE EXCEPTION 'LF_PROMO_EKB_148_RULES_READBACK_DRIFT'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN ('LF-PROMO-B08-SAME-OWNER-SIX-20261114-001','LF-PROMO-148-EVIDENCE-FIRST-SCREENS-20261114-001','LF-PROMO-MASSIVE-PROCEDURE-SKILL-20261114-001'))
 THEN RAISE EXCEPTION 'LF_PROMO_EKB_CODE_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
  validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
  pr,estado,evidencia,created_at,updated_at,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref)
 SELECT gen_random_uuid(),v.codigo,v.categoria,v.titulo,v.descripcion,
  v.causa_raiz,v.patron,v.prevencion,v.validacion,
  'HIGH',1,clock_timestamp(),clock_timestamp(),
  'LF_PROMOTION_166_OWNER_SCREENS_BATCH_20261114','PR_GOVERNED',
  'ACTIVO','SELECT B08 six identities; 148 screens; no promotions',
  clock_timestamp(),clock_timestamp(),'RULE_GOVERNANCE',
  ARRAY['PRODUCT_DIRECTOR','INPUT_GOVERNANCE_CURATOR','UI_ARCHITECT','ENGINEERING'],
  'R5_EROSION_PROCESO','LOUD_EARLY',
  'B08 documentary identity only; 0 evidence-supported missing explicit links; batch tests fixture only',
  'https://github.com/cristhianlujan/claude-persona-lf-patch/tree/main/docs/rule-promotion'
 FROM (VALUES ('LF-PROMO-B08-SAME-OWNER-SIX-20261114-001','RULE_GOVERNANCE','B08 documental único para seis reglas y futuro','Owner LF es el mismo decisor documental; SELECT 6 reglas con owner_decision_identity_verified=false: 235,438,439,440,532,577. La fuente B08 prohíbe convertir placeholder o frase en IAM.','Confundir misma persona declarada con prueba de autenticación individual transforma evidencia insuficiente en firma inventada.','B08_DOCUMENTARY_OWNER_NOT_AUTHENTICATED','Mantener owner_name documental, identity_mode UNVERIFIED_CHAT_DECLARATION, identity_verified=false y evidencias de frase/SHA; vista retro/futura. Requerir IdP sub autenticado, permiso, timestamp, nonce y receipt para firma real.','audits/rule-quality-lote28/12_criterios_cierre_motor_7.md; SELECT lf_ig_project_owner_v2 y 6 lf_ops.reglas; vista read-only.'),
('LF-PROMO-148-EVIDENCE-FIRST-SCREENS-20261114-001','INPUT_GOVERNANCE','Cinco pantallas exige vínculo con evidencia, no relleno','SELECT 148 reglas menos de cinco pantallas: 0 referencias explícitas sin vínculo, 59 revisión UI/E2E, 65 alcance bajo provisional y 24 cero enlaces sin fuente suficiente.','El umbral de cinco usado como cuota induce relaciones ficticias o promoción inmotivada.','PROMOTION_5_SCREEN_QUOTA_WITHOUT_SOURCE_EVIDENCE','Curator/IG propone solo enlaces sustentados por fuente y pantalla real mediante RULE_LINK_APPLY→VINCULACION_REGLA_PANTALLA_LF; perfil UI aporta E2E cuando visual. Recontar por SELECT; no bajar umbral ni fabricar enlaces.','SELECT lf_ops.reglas,reglas_pantallas,pantallas; view lf_rule_promotion_screen_diagnostic_v1; no links created.'),
('LF-PROMO-MASSIVE-PROCEDURE-SKILL-20261114-001','RULE_GOVERNANCE','Promoción masiva gobernada reusable sin juez o firma simulados','Funciones decide_batch y apply_batch instaladas; recorren IDs y reportan ok/blocked por fila; PR #3898 PASS fixtures PG17.6/18.7 con ROLLBACK; 0 solicitudes reales y 0 promociones. Batch actual permite parcial por elemento.','Prueba sintética de HUMAN y Step70 no aporta identidad autenticada ni un segundo juez real; batch parcial no es aprobación atómica de conjunto.','PROMOTION_BATCH_SYNTHETIC_RECEIPTS_NOT_REAL_AUTHORITY','Procedimiento: diagnóstico de cinco criterios → Step40/50/60/70 realmente independiente → request y SHA por regla → firma owner verificada → dryrun solo lectura → decide_batch→apply_batch→readback; conservar blocked por fila. Nunca asumir atomicidad global ni eliminar hallazgos.','pg_get_functiondef decide_batch/apply_batch y PR #3898; skill/procedimiento docs/rule-promotion/SKILL_PROMOCION_MASIVA_LF_V1.md.')) v(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion);
 SELECT count(*) INTO v_n FROM public.lf_error_knowledge
 WHERE codigo IN ('LF-PROMO-B08-SAME-OWNER-SIX-20261114-001','LF-PROMO-148-EVIDENCE-FIRST-SCREENS-20261114-001','LF-PROMO-MASSIVE-PROCEDURE-SKILL-20261114-001') AND estado='ACTIVO';
 IF v_n<>3 THEN RAISE EXCEPTION 'LF_PROMO_EKB_EXPECTED_THREE_GOT_%',v_n; END IF;
END $ekb$;
COMMIT;
