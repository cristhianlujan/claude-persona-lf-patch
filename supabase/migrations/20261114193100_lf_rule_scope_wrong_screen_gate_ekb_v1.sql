-- EKB single source-first lesson: screens are not a universal RULE promotion gate.
-- Depends on 20261114193000 scope V2; no rule/owner/policy writes.
BEGIN;
DO $ekb$
BEGIN
 IF to_regprocedure('programacion.fn_t_remed_rule_promotion_verdicts_v2(bigint)') IS NULL
 THEN RAISE EXCEPTION 'LF_SCOPE_EKB_V2_NOT_INSTALLED'; END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge
   WHERE codigo='LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001')
 THEN RAISE EXCEPTION 'LF_SCOPE_EKB_ALREADY_RECORDED'; END IF;
 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
 created_at,updated_at,lifecycle_phase,consumer_role,root_cause_family,
 detectability,source_context,source_ref)
 VALUES (
 gen_random_uuid(),
 'LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001',
 'RULE_GOVERNANCE',
 'Umbral de cinco pantallas mal ubicado en puerta de vigencia',
 'SELECT 2026-11-14: 124/412 VIGENTE tienen menos de cinco pantallas; 34/412 cero. 148/166 CANDIDATO bajo cinco. V1 usa USED_BY_ENOUGH_SCREENS y mezcla calidad con amplitud de politica. Regla backend sin pantalla no debe quedar descartada por falta de pantalla.',
 'El mapeo regla-pantalla lo realiza Curator y es circular exigir cinco vinculaciones previas. La amplitud transversal y backend exige evidencia de alcance, no cantidad de pantallas.',
 'SCREEN_COUNT_CIRCULAR_DEPENDENCY_AND_POLICY_SCOPE_CONFLATION',
 'Separar VIGENTE: calidad+SCOPE_EVIDENCE (1 pantalla, alcance transversal declarado, objeto backend catalogado, o REVIEW_SCOPE sin veto de flujo). Separar POLITICA: 5+ o es_transversal. Conservar paso70 juez independiente e identidad humana. No relabel legacy 262+8 ni cambiar V1.',
 'SELECT lf_ops.reglas/reglas_pantallas; pg_get_functiondef V1 MD5=92e8025b70d17e3de7da7206795ed73d; V2 source-first; PG17/18 ROLLBACK; #3854 es promocion de politicas 19/22, no habilita bypass de la ruta regla->politica.',
 'HIGH',1,clock_timestamp(),clock_timestamp(),
 'LF_PROMOTION_SCOPE_EVIDENCE_DUAL_GATE_20261114','PR_GOVERNED','ACTIVO',
 'SELECT 166 + 412; no promotion requested/applied',
 clock_timestamp(),clock_timestamp(),'RULE_GOVERNANCE',
 ARRAY['PRODUCT_DIRECTOR','INPUT_GOVERNANCE_CURATOR','ENGINEERING','UI_ARCHITECT'],
 'R5_EROSION_PROCESO','LOUD_EARLY',
 'Owner instruction 2026-11-14. Preserve all historic rule states and policy bindings',
 'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3854'
 );
 IF (SELECT count(*) FROM public.lf_error_knowledge
 WHERE codigo='LF-PROMO-SCREEN-CRITERION-MISPLACED-20261114-001'
  AND estado='ACTIVO')<>1
 THEN RAISE EXCEPTION 'LF_SCOPE_EKB_READBACK_MISSING'; END IF;
END $ekb$;
COMMIT;
